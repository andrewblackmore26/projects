using System;
using System.Collections.Generic;

namespace Gridlock.Core.Levels
{
    /// <summary>
    /// Hand-defined boards for tests and headless tooling. Campaign levels live
    /// in /Levels as JSON; these exist so tests and probes have known-geometry
    /// boards without touching the filesystem. Everything here still round-trips
    /// through LevelLoader.Build — DevBoards get no validation exemptions.
    /// </summary>
    public static class DevBoards
    {
        /// <summary>
        /// Two nodes, one 4-edge wire: player (0,0) ↔ ai (2,0).
        /// Wire 0 leaves the player's E face and enters the ai's W face.
        /// Length 4 → 1.0 s traversal at BASE_BEAM_SPEED 4.
        /// </summary>
        public static LevelData TwoNodeStrip(float playerCharge = 0f, float aiCharge = 0f)
        {
            var level = new LevelData { Id = "dev_two_node_strip", Name = "Dev Strip" };
            level.Nodes.Add(new LevelNodeData { Id = 0, Q = 0, R = 0, Owner = "player", Charge = playerCharge });
            level.Nodes.Add(new LevelNodeData { Id = 1, Q = 2, R = 0, Owner = "ai", Charge = aiCharge });
            level.Wires.Add(new LevelWireData
            {
                Id = 0,
                A = 0,
                B = 1,
                Path = new List<VertexCoord>
                {
                    new VertexCoord(1, -1), new VertexCoord(1, 1), new VertexCoord(2, 2),
                    new VertexCoord(3, 1), new VertexCoord(3, -1),
                },
            });
            return level;
        }

        /// <summary>
        /// Player (0,0) — neutral (2,0) — ai (4,0), two 4-edge wires in a line.
        /// The classic race-for-the-middle board.
        /// </summary>
        public static LevelData Chain3(float playerCharge = 0f, float aiCharge = 0f)
        {
            var level = new LevelData { Id = "dev_chain3", Name = "Dev Chain" };
            level.Nodes.Add(new LevelNodeData { Id = 0, Q = 0, R = 0, Owner = "player", Charge = playerCharge });
            level.Nodes.Add(new LevelNodeData { Id = 1, Q = 2, R = 0, Owner = "neutral" });
            level.Nodes.Add(new LevelNodeData { Id = 2, Q = 4, R = 0, Owner = "ai", Charge = aiCharge });
            level.Wires.Add(new LevelWireData
            {
                Id = 0,
                A = 0,
                B = 1,
                Path = new List<VertexCoord>
                {
                    new VertexCoord(1, -1), new VertexCoord(1, 1), new VertexCoord(2, 2),
                    new VertexCoord(3, 1), new VertexCoord(3, -1),
                },
            });
            level.Wires.Add(new LevelWireData
            {
                Id = 1,
                A = 1,
                B = 2,
                Path = new List<VertexCoord>
                {
                    new VertexCoord(5, -1), new VertexCoord(5, 1), new VertexCoord(6, 2),
                    new VertexCoord(7, 1), new VertexCoord(7, -1),
                },
            });
            return level;
        }

        /// <summary>
        /// Rotationally symmetric (180°) duel board for AI-vs-AI balance work:
        /// two homes, a centre hub, two satellites, and a deliberately LONG
        /// winding route on one axis (unequal travel times prevent the mirrored
        /// simultaneous-arrival grind — lessons.md). Routed with PathBuilder and
        /// mirrored, so the two sides' geometry is exactly point-symmetric.
        /// </summary>
        public static LevelData Duel()
        {
            var home = new HexCoord(-3, 0);      // player
            var centre = new HexCoord(0, 0);     // neutral hub
            var north = new HexCoord(1, -2);     // neutral satellite
            var allCells = new List<HexCoord>
            {
                home, Mirror(home), centre, north, Mirror(north),
            };

            var level = new LevelData { Id = "dev_duel", Name = "Dev Duel" };
            level.Nodes.Add(new LevelNodeData { Id = 0, Q = home.Q, R = home.R, Owner = "player" });
            level.Nodes.Add(new LevelNodeData { Id = 1, Q = -home.Q, R = -home.R, Owner = "ai" });
            level.Nodes.Add(new LevelNodeData { Id = 2, Q = centre.Q, R = centre.R, Owner = "neutral" });
            level.Nodes.Add(new LevelNodeData { Id = 3, Q = north.Q, R = north.R, Owner = "neutral" });
            level.Nodes.Add(new LevelNodeData { Id = 4, Q = -north.Q, R = -north.R, Owner = "neutral" });

            var used = new HashSet<EdgeKey>();
            int wireId = 0;

            // home—centre (both sides), then satellite—centre, then home—satellite
            // SHORT side, then the long winding cross wire.
            AddMirroredPair(level, ref wireId, used, allCells, home, 0, centre, 2, Mirror(home), 1, null);
            AddMirroredPair(level, ref wireId, used, allCells, north, 3, centre, 2, Mirror(north), 4, null);
            AddMirroredPair(level, ref wireId, used, allCells, Mirror(home), 1, north, 3, home, 0, null);
            // Long route: player home to the far (north) satellite, forced through
            // a distant waypoint so it genuinely winds (visual distance lies —
            // design pillar 1). Its mirror gives the ai the matching long route.
            AddMirroredPair(level, ref wireId, used, allCells, home, 0, north, 3, Mirror(home), 1,
                new List<VertexCoord> { new VertexCoord(-6, -8) });

            return level;
        }

        private static HexCoord Mirror(HexCoord c) => new HexCoord(-c.Q, -c.R);

        private static VertexCoord Mirror(VertexCoord v) => new VertexCoord(-v.N, -v.M);

        /// <summary>
        /// Route cellA(idA) → cellB(idB), then add the point-mirrored wire
        /// mirrorA(idMirrorA) → mirror(cellB). cellB is expected to be either the
        /// self-symmetric centre or a cell whose mirror carries idMirrorB — the
        /// caller passes the mirrored endpoint ids explicitly.
        /// </summary>
        private static void AddMirroredPair(LevelData level, ref int wireId, HashSet<EdgeKey> used,
            List<HexCoord> allCells, HexCoord cellA, int idA, HexCoord cellB, int idB,
            HexCoord mirrorCellA, int idMirrorA, List<VertexCoord> waypoints)
        {
            VertexCoord[] path = RouteAnyFace(cellA, cellB, allCells, used, waypoints);
            if (path == null)
                throw new InvalidOperationException(
                    "DevBoards.Duel: no route " + cellA + " -> " + cellB);
            PathBuilder.MarkUsed(path, used);
            level.Wires.Add(MakeWire(wireId++, idA, idB, path));

            var mirrored = new VertexCoord[path.Length];
            for (int i = 0; i < path.Length; i++) mirrored[i] = Mirror(path[i]);
            var mirroredList = new List<VertexCoord>(mirrored);
            for (int i = 0; i + 1 < mirrored.Length; i++)
            {
                if (used.Contains(new EdgeKey(mirrored[i], mirrored[i + 1])))
                    throw new InvalidOperationException(
                        "DevBoards.Duel: mirrored route collides with its original (" + cellA + " -> " + cellB + ")");
            }
            PathBuilder.MarkUsed(mirroredList, used);
            int idMirrorB = MirrorNodeId(level, cellB, idB);
            level.Wires.Add(MakeWire(wireId++, idMirrorA, idMirrorB, mirrored));
        }

        private static int MirrorNodeId(LevelData level, HexCoord cellB, int idB)
        {
            HexCoord mirror = Mirror(cellB);
            foreach (LevelNodeData n in level.Nodes)
            {
                if (n.Q == mirror.Q && n.R == mirror.R) return n.Id;
            }
            return idB; // self-symmetric (the centre)
        }

        private static LevelWireData MakeWire(int id, int a, int b, VertexCoord[] path)
        {
            var wire = new LevelWireData { Id = id, A = a, B = b };
            wire.Path.AddRange(path);
            return wire;
        }

        /// <summary>Try every face pair, keep the shortest legal route. Deterministic (fixed loop order).</summary>
        private static VertexCoord[] RouteAnyFace(HexCoord cellA, HexCoord cellB,
            List<HexCoord> allCells, HashSet<EdgeKey> used, List<VertexCoord> waypoints)
        {
            VertexCoord[] best = null;
            for (int fa = 0; fa < 6; fa++)
            {
                for (int fb = 0; fb < 6; fb++)
                {
                    VertexCoord[] path = PathBuilder.Route(cellA, fa, cellB, fb, allCells, used, waypoints);
                    if (path != null && (best == null || path.Length < best.Length)) best = path;
                }
            }
            return best;
        }
    }
}
