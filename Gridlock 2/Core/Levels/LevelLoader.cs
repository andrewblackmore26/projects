using System;
using System.Collections.Generic;
using Gridlock.Core.Config;

namespace Gridlock.Core.Levels
{
    /// <summary>Thrown for any structurally invalid level. Message names the level, wire, and vertex.</summary>
    public class LevelValidationException : Exception
    {
        public LevelValidationException(string message) : base(message) { }
    }

    /// <summary>Runtime board built from validated level data.</summary>
    public class BuiltLevel
    {
        public LevelData Data;
        /// <summary>Nodes ordered by ascending id.</summary>
        public List<GameNode> Nodes = new List<GameNode>();
        /// <summary>Wires ordered by ascending id.</summary>
        public List<Wire> Wires = new List<Wire>();
        public List<string> Warnings = new List<string>();
    }

    /// <summary>
    /// Parses and validates level JSON. THE single validator: the editor, the
    /// generator, tests, and both engines all load boards through here, so every
    /// structural rule lives in exactly one place.
    ///
    /// Validation rules:
    ///  LR1  unique ids, valid wire endpoint refs, at least one player and one ai node
    ///  LR2  distinct node cells
    ///  LR3  path has ≥ 2 vertices, all valid lattice vertices, every consecutive
    ///       pair a lattice edge, no vertex repeated within a path
    ///  LR4  first/last segment IS a face edge of the endpoint node's hex
    ///       (exact lookup — this defines faceA/faceB)
    ///  LR5  no lattice edge used twice globally (implies one wire per face and
    ///       degree ≤ 6; explicit face/degree checks kept for clearer messages)
    ///  LR6  a vertex shared by 2+ wires must be a corner of a node that is an
    ///       endpoint of every sharing wire
    ///  LR7  no wire edge may lie on a node's rim except a wire's own first/last
    ///       (departure/arrival) segment
    ///  LR8  warn on wires shorter than 2 edges (a 1-edge wire is burst-undefendable)
    ///  LR9  objective parameters present for the chosen objective
    /// </summary>
    public static class LevelLoader
    {
        public static LevelData Parse(string json)
        {
            Dictionary<string, object> root;
            try
            {
                root = MiniJson.Parse(json) as Dictionary<string, object>;
            }
            catch (FormatException e)
            {
                throw new LevelValidationException("Malformed JSON: " + e.Message);
            }
            if (root == null) throw new LevelValidationException("Level root must be a JSON object");

            // A file with no 'version' is the spec §10.1 shape, which IS v1 —
            // the spec's own example JSON must load. An explicit wrong version
            // is still a hard error (no migration; re-export the level).
            int version = GetInt(root, "version", LevelData.FormatVersion);
            if (version != LevelData.FormatVersion)
                throw new LevelValidationException(
                    "Unsupported level version " + version + " (this build reads version " +
                    LevelData.FormatVersion + "; there is no migration — re-export the level)");

            var level = new LevelData
            {
                Id = GetString(root, "id", ""),
                Name = GetString(root, "name", ""),
                Difficulty = GetInt(root, "difficulty", 1),
                ParTime = GetFloat(root, "parTime", 0f),
                ObjectiveSeconds = GetFloat(root, "objectiveSeconds", 0f),
                ObjectiveMaxSends = GetInt(root, "objectiveMaxSends", 0),
                HexSize = GetFloat(root, "hexSize", 48f),
            };
            if (level.Id.Length == 0) throw new LevelValidationException("Level is missing 'id'");

            string objective = GetString(root, "objective", "eliminate");
            switch (objective)
            {
                case "eliminate": level.Objective = ObjectiveType.Eliminate; break;
                case "survive": level.Objective = ObjectiveType.Survive; break;
                case "capture": level.Objective = ObjectiveType.Capture; break;
                case "efficiency": level.Objective = ObjectiveType.Efficiency; break;
                default: throw new LevelValidationException(Prefix(level) + "unknown objective '" + objective + "'");
            }

            if (root.TryGetValue("objectiveNodeIds", out object idsObj) && idsObj is List<object> idsList)
            {
                foreach (object o in idsList) level.ObjectiveNodeIds.Add(ToInt(o, "objectiveNodeIds entry"));
            }

            if (!(root.TryGetValue("nodes", out object nodesObj) && nodesObj is List<object> nodesList))
                throw new LevelValidationException(Prefix(level) + "missing 'nodes' array");
            foreach (object o in nodesList)
            {
                var n = o as Dictionary<string, object>;
                if (n == null) throw new LevelValidationException(Prefix(level) + "node entry must be an object");
                level.Nodes.Add(new LevelNodeData
                {
                    Id = GetInt(n, "id", -1),
                    Q = GetInt(n, "q", 0),
                    R = GetInt(n, "r", 0),
                    Owner = GetString(n, "owner", "neutral"),
                    Charge = GetFloat(n, "charge", 0f),
                });
            }

            if (!(root.TryGetValue("wires", out object wiresObj) && wiresObj is List<object> wiresList))
                throw new LevelValidationException(Prefix(level) + "missing 'wires' array");
            foreach (object o in wiresList)
            {
                var w = o as Dictionary<string, object>;
                if (w == null) throw new LevelValidationException(Prefix(level) + "wire entry must be an object");
                var wire = new LevelWireData
                {
                    Id = GetInt(w, "id", -1),
                    A = GetInt(w, "a", -1),
                    B = GetInt(w, "b", -1),
                };
                if (!(w.TryGetValue("path", out object pathObj) && pathObj is List<object> pathList))
                    throw new LevelValidationException(Prefix(level) + "wire " + wire.Id + " is missing 'path'");
                foreach (object p in pathList)
                {
                    var pair = p as List<object>;
                    if (pair == null || pair.Count != 2)
                        throw new LevelValidationException(Prefix(level) + "wire " + wire.Id + " path entries must be [n, m] pairs");
                    wire.Path.Add(new VertexCoord(ToInt(pair[0], "path n"), ToInt(pair[1], "path m")));
                }
                level.Wires.Add(wire);
            }

            return level;
        }

        /// <summary>Validate and build the runtime board. Throws LevelValidationException on any rule violation.</summary>
        public static BuiltLevel Build(LevelData level, Tuning tuning)
        {
            var built = new BuiltLevel { Data = level };
            string prefix = Prefix(level);

            // LR1: unique node ids, side presence.
            var nodesById = new Dictionary<int, LevelNodeData>();
            bool hasPlayer = false, hasAi = false;
            foreach (LevelNodeData n in level.Nodes)
            {
                if (n.Id < 0) throw new LevelValidationException(prefix + "node id must be >= 0");
                if (nodesById.ContainsKey(n.Id))
                    throw new LevelValidationException(prefix + "duplicate node id " + n.Id);
                nodesById[n.Id] = n;
                Owner owner = ParseOwner(n.Owner, prefix + "node " + n.Id);
                if (owner == Owner.Player) hasPlayer = true;
                if (owner == Owner.Ai) hasAi = true;
            }
            if (!hasPlayer) throw new LevelValidationException(prefix + "no player-owned node");
            if (!hasAi) throw new LevelValidationException(prefix + "no ai-owned node");

            // LR2: distinct cells.
            var cells = new Dictionary<HexCoord, int>();
            foreach (LevelNodeData n in level.Nodes)
            {
                var cell = new HexCoord(n.Q, n.R);
                if (cells.TryGetValue(cell, out int otherId))
                    throw new LevelValidationException(prefix + "nodes " + otherId + " and " + n.Id + " share cell " + cell);
                cells[cell] = n.Id;
            }

            // Build GameNodes ordered by id.
            var sortedNodes = new List<LevelNodeData>(level.Nodes);
            sortedNodes.Sort((x, y) => x.Id.CompareTo(y.Id));
            var gameNodesById = new Dictionary<int, GameNode>();
            foreach (LevelNodeData n in sortedNodes)
            {
                Owner owner = ParseOwner(n.Owner, prefix + "node " + n.Id);
                var g = new GameNode
                {
                    Id = n.Id,
                    Coord = new HexCoord(n.Q, n.R),
                    Owner = owner,
                    State = NodeState.Idle,
                    Charge = owner == Owner.Neutral ? 0f : Math.Max(0f, n.Charge),
                };
                built.Nodes.Add(g);
                gameNodesById[n.Id] = g;
            }

            // Wires: LR3/LR4/LR5/LR7 per wire + global edge and vertex bookkeeping.
            var wireIdsSeen = new HashSet<int>();
            var usedEdges = new Dictionary<EdgeKey, int>();            // edge -> wireId
            var vertexUsers = new Dictionary<VertexCoord, List<int>>(); // vertex -> wireIds
            var sortedWires = new List<LevelWireData>(level.Wires);
            sortedWires.Sort((x, y) => x.Id.CompareTo(y.Id));

            foreach (LevelWireData w in sortedWires)
            {
                string wp = prefix + "wire " + w.Id + ": ";
                if (w.Id < 0) throw new LevelValidationException(wp + "wire id must be >= 0");
                if (!wireIdsSeen.Add(w.Id)) throw new LevelValidationException(prefix + "duplicate wire id " + w.Id);
                if (!nodesById.ContainsKey(w.A)) throw new LevelValidationException(wp + "endpoint a=" + w.A + " is not a node id");
                if (!nodesById.ContainsKey(w.B)) throw new LevelValidationException(wp + "endpoint b=" + w.B + " is not a node id");
                if (w.A == w.B) throw new LevelValidationException(wp + "endpoints must differ");

                // LR3.
                if (w.Path.Count < 2) throw new LevelValidationException(wp + "path needs at least 2 vertices");
                var seenVerts = new HashSet<VertexCoord>();
                foreach (VertexCoord v in w.Path)
                {
                    if (!v.IsValidVertex())
                        throw new LevelValidationException(wp + v + " is not a lattice vertex");
                    if (!seenVerts.Add(v))
                        throw new LevelValidationException(wp + "path revisits vertex " + v);
                }
                for (int i = 0; i + 1 < w.Path.Count; i++)
                {
                    if (!VertexCoord.IsLatticeEdge(w.Path[i], w.Path[i + 1]))
                        throw new LevelValidationException(wp + w.Path[i] + " -> " + w.Path[i + 1] + " is not a lattice edge");
                }

                // LR4: first/last segment is a face edge of the endpoint hex.
                GameNode nodeA = gameNodesById[w.A];
                GameNode nodeB = gameNodesById[w.B];
                int faceA = HexMath.FaceIndexOfEdge(nodeA.Coord, w.Path[0], w.Path[1]);
                if (faceA < 0)
                    throw new LevelValidationException(wp + "first segment " + w.Path[0] + " -> " + w.Path[1] +
                        " is not a face edge of node " + w.A + "'s hex " + nodeA.Coord);
                int last = w.Path.Count - 1;
                int faceB = HexMath.FaceIndexOfEdge(nodeB.Coord, w.Path[last - 1], w.Path[last]);
                if (faceB < 0)
                    throw new LevelValidationException(wp + "last segment " + w.Path[last - 1] + " -> " + w.Path[last] +
                        " is not a face edge of node " + w.B + "'s hex " + nodeB.Coord);

                // LR5 global edge uniqueness + LR7 rim discipline.
                for (int i = 0; i + 1 < w.Path.Count; i++)
                {
                    var key = new EdgeKey(w.Path[i], w.Path[i + 1]);
                    if (usedEdges.TryGetValue(key, out int otherWire))
                        throw new LevelValidationException(wp + "edge " + w.Path[i] + " -> " + w.Path[i + 1] +
                            " is already used by wire " + otherWire);
                    usedEdges[key] = w.Id;

                    // LR7: an interior segment may not lie on ANY node's rim; the
                    // first/last segment may lie only on its own endpoint's rim
                    // (guaranteed by LR4, but check it isn't also another node's rim —
                    // impossible geometrically since a face edge belongs to exactly
                    // two cells and the far cell holding a node is checked here).
                    foreach (LevelNodeData other in level.Nodes)
                    {
                        var cell = new HexCoord(other.Q, other.R);
                        if (HexMath.FaceIndexOfEdge(cell, w.Path[i], w.Path[i + 1]) < 0) continue;
                        bool isFirst = i == 0 && other.Id == w.A;
                        bool isLast = i == w.Path.Count - 2 && other.Id == w.B;
                        if (!isFirst && !isLast)
                            throw new LevelValidationException(wp + "segment " + w.Path[i] + " -> " + w.Path[i + 1] +
                                " runs along the rim of node " + other.Id + " (only a wire's own departure/arrival segment may)");
                    }
                }

                foreach (VertexCoord v in w.Path)
                {
                    if (!vertexUsers.TryGetValue(v, out List<int> users))
                    {
                        users = new List<int>();
                        vertexUsers[v] = users;
                    }
                    users.Add(w.Id);
                }

                // LR8.
                if (w.Path.Count - 1 < 2)
                    built.Warnings.Add(wp + "only " + (w.Path.Count - 1) +
                        " edge(s) long — a 1-edge wire is burst-undefendable at every tier");

                // Build runtime wire; attach to nodes (face conflicts checked here for clear messages).
                var wire = new Wire
                {
                    Id = w.Id,
                    NodeA = w.A,
                    NodeB = w.B,
                    Path = w.Path.ToArray(),
                    Length = w.Path.Count - 1,
                    FaceA = faceA,
                    FaceB = faceB,
                };
                wire.PixelPath = new Vec2[wire.Path.Length];
                for (int i = 0; i < wire.Path.Length; i++) wire.PixelPath[i] = wire.Path[i].ToPixel();
                built.Wires.Add(wire);

                AttachWire(nodeA, faceA, w.Id, wp + "node " + w.A);
                AttachWire(nodeB, faceB, w.Id, wp + "node " + w.B);
            }

            // LR6: shared vertices only at corners of a common endpoint node.
            var wiresById = new Dictionary<int, Wire>();
            foreach (Wire w in built.Wires) wiresById[w.Id] = w;
            foreach (KeyValuePair<VertexCoord, List<int>> kv in vertexUsers)
            {
                if (kv.Value.Count < 2) continue;
                bool ok = false;
                foreach (GameNode n in built.Nodes)
                {
                    if (!HexMath.IsCornerOf(n.Coord, kv.Key)) continue;
                    bool allShare = true;
                    foreach (int wireId in kv.Value)
                    {
                        Wire w = wiresById[wireId];
                        if (w.NodeA != n.Id && w.NodeB != n.Id) { allShare = false; break; }
                    }
                    if (allShare) { ok = true; break; }
                }
                if (!ok)
                    throw new LevelValidationException(prefix + "vertex " + kv.Key + " is shared by wires " +
                        string.Join(", ", kv.Value) + " away from a common endpoint node");
            }

            // Finalize degree-dependent fields.
            foreach (GameNode n in built.Nodes)
            {
                var ids = new List<int>();
                for (int f = 0; f < 6; f++)
                {
                    if (n.WireIdByFace[f] >= 0) ids.Add(n.WireIdByFace[f]);
                }
                n.WireIds = ids.ToArray();
                n.Degree = ids.Count;
                if (n.Owner == Owner.Neutral)
                    n.NeutralDefense = tuning.NeutralDefensePerDegree * n.Degree;
                if (n.Charge > n.MaxCharge(tuning)) n.Charge = n.MaxCharge(tuning);
            }

            // LR9: objective parameters.
            switch (level.Objective)
            {
                case ObjectiveType.Survive:
                    if (level.ObjectiveSeconds <= 0f)
                        throw new LevelValidationException(prefix + "survive objective needs objectiveSeconds > 0");
                    break;
                case ObjectiveType.Capture:
                    if (level.ObjectiveNodeIds.Count == 0)
                        throw new LevelValidationException(prefix + "capture objective needs objectiveNodeIds");
                    foreach (int id in level.ObjectiveNodeIds)
                    {
                        if (!nodesById.ContainsKey(id))
                            throw new LevelValidationException(prefix + "capture objective names unknown node " + id);
                    }
                    break;
                case ObjectiveType.Efficiency:
                    if (level.ObjectiveMaxSends <= 0)
                        throw new LevelValidationException(prefix + "efficiency objective needs objectiveMaxSends > 0");
                    break;
            }

            return built;
        }

        /// <summary>Parse + Build in one call (the normal load path).</summary>
        public static BuiltLevel LoadFromJson(string json, Tuning tuning) => Build(Parse(json), tuning);

        private static void AttachWire(GameNode node, int face, int wireId, string context)
        {
            if (node.WireIdByFace[face] >= 0)
                throw new LevelValidationException(context + " already has wire " + node.WireIdByFace[face] +
                    " on face " + face);
            node.WireIdByFace[face] = wireId;
        }

        private static Owner ParseOwner(string s, string context)
        {
            switch (s)
            {
                case "player": return Owner.Player;
                case "ai": return Owner.Ai;
                case "neutral": return Owner.Neutral;
                default: throw new LevelValidationException(context + ": unknown owner '" + s + "'");
            }
        }

        private static string Prefix(LevelData level) =>
            (level.Id.Length > 0 ? level.Id : "<level>") + ": ";

        // A present key with the wrong type is an authoring ERROR, never a
        // fallback: silently defaulting "q": "3" to 0 relocates a node and can
        // still pass every structural rule. Absent optional keys take the
        // fallback; present ones must be well typed. Integer keys additionally
        // reject non-integral numbers rather than truncating.

        private static string GetString(Dictionary<string, object> obj, string key, string fallback)
        {
            if (!obj.TryGetValue(key, out object v) || v == null) return fallback;
            if (v is string s) return s;
            throw new LevelValidationException("'" + key + "' must be a string");
        }

        private static int GetInt(Dictionary<string, object> obj, string key, int fallback)
        {
            if (!obj.TryGetValue(key, out object v) || v == null) return fallback;
            return ToInt(v, "'" + key + "'");
        }

        private static float GetFloat(Dictionary<string, object> obj, string key, float fallback)
        {
            if (!obj.TryGetValue(key, out object v) || v == null) return fallback;
            if (v is double d) return (float)d;
            throw new LevelValidationException("'" + key + "' must be a number");
        }

        private static int ToInt(object o, string context)
        {
            if (!(o is double d))
                throw new LevelValidationException(context + " must be a number");
            if (d != Math.Floor(d))
                throw new LevelValidationException(context + " must be a whole number, got " + d);
            return (int)d;
        }
    }
}
