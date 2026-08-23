using System;
using System.Collections.Generic;
using Gridlock.Core;
using Gridlock.Core.Levels;

namespace Gridlock.Headless
{
    /// <summary>
    /// Authoring helper for campaign levels: place nodes, then route wires with
    /// PathBuilder (optionally through waypoints for deliberate winding), with
    /// exact path mirroring for symmetric boards. Humans never hand-write [n,m]
    /// arrays. Output must still pass LevelLoader — no exemptions.
    /// </summary>
    public class BoardBuilder
    {
        private readonly LevelData _level;
        private readonly List<HexCoord> _cells = new List<HexCoord>();
        private readonly HashSet<EdgeKey> _used = new HashSet<EdgeKey>();
        private bool _wiresStarted;

        public BoardBuilder(string id, string name, int difficulty, float parTime = 180f)
        {
            _level = new LevelData { Id = id, Name = name, Difficulty = difficulty, ParTime = parTime };
        }

        public LevelData Level => _level;

        /// <summary>All nodes must be placed before the first wire (the router forbids node corners).</summary>
        public int Node(int q, int r, string owner, float charge = 0f)
        {
            if (_wiresStarted)
                throw new InvalidOperationException(_level.Id + ": place all nodes before wires");
            int id = _level.Nodes.Count;
            _level.Nodes.Add(new LevelNodeData { Id = id, Q = q, R = r, Owner = owner, Charge = charge });
            _cells.Add(new HexCoord(q, r));
            return id;
        }

        /// <summary>Route a wire a→b; waypoints are flattened (n, m) vertex pairs forcing a winding route.</summary>
        public int Wire(int a, int b, params int[] waypointPairs)
        {
            _wiresStarted = true;
            List<VertexCoord> waypoints = null;
            if (waypointPairs.Length > 0)
            {
                if (waypointPairs.Length % 2 != 0)
                    throw new ArgumentException(_level.Id + ": waypoints must be (n, m) pairs");
                waypoints = new List<VertexCoord>();
                for (int i = 0; i < waypointPairs.Length; i += 2)
                {
                    var v = new VertexCoord(waypointPairs[i], waypointPairs[i + 1]);
                    if (!v.IsValidVertex())
                        throw new ArgumentException(_level.Id + ": waypoint " + v + " is not a lattice vertex");
                    waypoints.Add(v);
                }
            }

            VertexCoord[] path = RouteAnyFace(_cells[a], _cells[b], waypoints);
            if (path == null)
                throw new InvalidOperationException(_level.Id + ": no route for wire " + a + " -> " + b);
            PathBuilder.MarkUsed(path, _used);
            return AddWire(a, b, path);
        }

        /// <summary>
        /// Add the point-mirrored copy of an existing wire (vertex (n,m) → (-n,-m)),
        /// between the given endpoint ids. Guarantees the symmetric side has
        /// EXACTLY equal travel time — never re-route what fairness depends on.
        /// </summary>
        public int MirrorWire(int wireId, int a, int b)
        {
            LevelWireData source = _level.Wires[wireId];
            var mirrored = new VertexCoord[source.Path.Count];
            for (int i = 0; i < mirrored.Length; i++)
                mirrored[i] = new VertexCoord(-source.Path[i].N, -source.Path[i].M);
            for (int i = 0; i + 1 < mirrored.Length; i++)
            {
                if (_used.Contains(new EdgeKey(mirrored[i], mirrored[i + 1])))
                    throw new InvalidOperationException(
                        _level.Id + ": mirror of wire " + wireId + " collides with an existing wire");
            }
            PathBuilder.MarkUsed(new List<VertexCoord>(mirrored), _used);
            return AddWire(a, b, mirrored);
        }

        private int AddWire(int a, int b, VertexCoord[] path)
        {
            int id = _level.Wires.Count;
            var wire = new LevelWireData { Id = id, A = a, B = b };
            wire.Path.AddRange(path);
            _level.Wires.Add(wire);
            return id;
        }

        private VertexCoord[] RouteAnyFace(HexCoord cellA, HexCoord cellB, List<VertexCoord> waypoints)
        {
            VertexCoord[] best = null;
            for (int fa = 0; fa < 6; fa++)
            {
                for (int fb = 0; fb < 6; fb++)
                {
                    VertexCoord[] path = PathBuilder.Route(cellA, fa, cellB, fb, _cells, _used, waypoints);
                    if (path != null && (best == null || path.Length < best.Length)) best = path;
                }
            }
            return best;
        }
    }
}
