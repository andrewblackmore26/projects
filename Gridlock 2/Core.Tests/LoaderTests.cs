using System.Collections.Generic;
using Gridlock.Core;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;
using Xunit;

namespace Gridlock.Core.Tests
{
    public class LoaderTests
    {
        private static BuiltLevel Build(LevelData level) =>
            LevelLoader.Build(level, new Tuning());

        private static void AssertRejected(LevelData level, string messageFragment)
        {
            var ex = Assert.Throws<LevelValidationException>(() => Build(level));
            Assert.Contains(messageFragment, ex.Message);
        }

        [Fact]
        public void Loader_Accepts_Strip_ComputesLengthFacesDegree()
        {
            BuiltLevel built = Build(DevBoards.TwoNodeStrip());
            Assert.Equal(2, built.Nodes.Count);
            Wire w = built.Wires[0];
            Assert.Equal(4f, w.Length);
            Assert.Equal(0, w.FaceA); // leaves player's E face
            Assert.Equal(3, w.FaceB); // enters ai's W face
            Assert.Equal(1, built.Nodes[0].Degree);
            Assert.Equal(1, built.Nodes[1].Degree);
            Assert.Equal(0f, built.Nodes[0].NeutralDefense); // owned nodes have no neutral toll
        }

        [Fact]
        public void Loader_Chain3_NeutralDefenseScalesWithDegree()
        {
            BuiltLevel built = Build(DevBoards.Chain3());
            GameNode mid = built.Nodes[1];
            Assert.Equal(Owner.Neutral, mid.Owner);
            Assert.Equal(2, mid.Degree);
            Assert.Equal(new Tuning().NeutralDefensePerDegree * 2, mid.NeutralDefense);
        }

        [Fact]
        public void Loader_Reject_UnsupportedVersion()
        {
            var ex = Assert.Throws<LevelValidationException>(() =>
                LevelLoader.Parse("{\"version\": 3, \"id\": \"x\", \"nodes\": [], \"wires\": []}"));
            Assert.Contains("version", ex.Message);
        }

        [Fact]
        public void Loader_Reject_DuplicateNodeId()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            level.Nodes.Add(new LevelNodeData { Id = 0, Q = 5, R = 5, Owner = "neutral" });
            AssertRejected(level, "duplicate node id");
        }

        [Fact]
        public void Loader_Reject_MissingSide()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            level.Nodes[1].Owner = "neutral"; // no ai node left
            AssertRejected(level, "no ai-owned node");
        }

        [Fact]
        public void Loader_Reject_NodeCellCollision()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            level.Nodes.Add(new LevelNodeData { Id = 2, Q = 0, R = 0, Owner = "neutral" });
            AssertRejected(level, "share cell");
        }

        [Fact]
        public void Loader_Reject_UnknownNodeRef()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            level.Wires[0].B = 99;
            AssertRejected(level, "not a node id");
        }

        [Fact]
        public void Loader_Reject_InvalidVertexInPath()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            level.Wires[0].Path[2] = new VertexCoord(2, 3); // m % 3 == 0 row: not a vertex
            AssertRejected(level, "not a lattice vertex");
        }

        [Fact]
        public void Loader_Reject_NonLatticeEdgeStep()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            // Replace (2,2) with (2,4): valid vertex but (1,1)->(2,4) is no edge.
            level.Wires[0].Path[2] = new VertexCoord(2, 4);
            AssertRejected(level, "not a lattice edge");
        }

        [Fact]
        public void Loader_Reject_PathRevisitsVertex()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            level.Wires[0].Path = new List<VertexCoord>
            {
                new VertexCoord(1, -1), new VertexCoord(1, 1), new VertexCoord(2, 2),
                new VertexCoord(1, 1), new VertexCoord(2, 2), // bounce back and forth
                new VertexCoord(3, 1), new VertexCoord(3, -1),
            };
            AssertRejected(level, "revisits");
        }

        [Fact]
        public void Loader_Reject_FirstSegmentNotFaceEdge()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            level.Wires[0].Path.RemoveAt(0); // now starts (1,1)->(2,2): a rim edge of hex(1,0), not of the node
            AssertRejected(level, "not a face edge");
        }

        [Fact]
        public void Loader_Reject_DuplicateEdgeUse_AcrossWires()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            var copy = new LevelWireData { Id = 1, A = 0, B = 1 };
            copy.Path.AddRange(level.Wires[0].Path);
            level.Wires.Add(copy);
            AssertRejected(level, "already used by wire 0");
        }

        [Fact]
        public void Loader_Reject_WireOnForeignNodeRim()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            // Put a node in cell (1,0): the strip's middle segments run along its rim.
            level.Nodes.Add(new LevelNodeData { Id = 2, Q = 1, R = 0, Owner = "neutral" });
            AssertRejected(level, "rim of node 2");
        }

        [Fact]
        public void Loader_Accepts_AdjacentFaceWires_SharedRimCorner()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            level.Nodes.Add(new LevelNodeData { Id = 2, Q = 0, R = 2, Owner = "neutral" });
            var wire = new LevelWireData { Id = 1, A = 0, B = 2 };
            wire.Path.AddRange(new[]
            {
                new VertexCoord(1, 1), new VertexCoord(0, 2), new VertexCoord(0, 4),
                new VertexCoord(1, 5), new VertexCoord(1, 7),
            });
            level.Wires.Add(wire);

            BuiltLevel built = Build(level); // shares corner (1,1) with wire 0 — legal, same endpoint node
            Assert.Equal(2, built.Nodes[0].Degree);
            Assert.Equal(0, built.Wires[0].FaceA);
            Assert.Equal(1, built.Wires[1].FaceA);
        }

        [Fact]
        public void Loader_Warns_WireShorterThan2()
        {
            // Adjacent nodes joined across their shared face: a legal 1-edge wire.
            var level = new LevelData { Id = "dev_short" };
            level.Nodes.Add(new LevelNodeData { Id = 0, Q = 0, R = 0, Owner = "player" });
            level.Nodes.Add(new LevelNodeData { Id = 1, Q = 1, R = 0, Owner = "ai" });
            var wire = new LevelWireData { Id = 0, A = 0, B = 1 };
            wire.Path.AddRange(new[] { new VertexCoord(1, -1), new VertexCoord(1, 1) });
            level.Wires.Add(wire);

            BuiltLevel built = Build(level);
            Assert.Single(built.Warnings);
            Assert.Contains("burst-undefendable", built.Warnings[0]);
            Assert.Equal(1f, built.Wires[0].Length);
        }

        [Fact]
        public void Loader_Reject_ObjectiveParamsMissing()
        {
            LevelData level = DevBoards.TwoNodeStrip();
            level.Objective = ObjectiveType.Survive;
            AssertRejected(level, "objectiveSeconds");

            level = DevBoards.TwoNodeStrip();
            level.Objective = ObjectiveType.Capture;
            AssertRejected(level, "objectiveNodeIds");

            level = DevBoards.TwoNodeStrip();
            level.Objective = ObjectiveType.Efficiency;
            AssertRejected(level, "objectiveMaxSends");
        }

        [Fact]
        public void LevelWriter_RoundTripsThroughLoader()
        {
            LevelData original = DevBoards.Chain3(playerCharge: 5f);
            original.Difficulty = 3;
            original.ParTime = 120f;
            string json = LevelWriter.Write(original);
            BuiltLevel reloaded = LevelLoader.LoadFromJson(json, new Tuning());
            Assert.Equal(3, reloaded.Nodes.Count);
            Assert.Equal(2, reloaded.Wires.Count);
            Assert.Equal(5f, reloaded.Nodes[0].Charge);
            Assert.Equal(3, reloaded.Data.Difficulty);
            Assert.Equal(4f, reloaded.Wires[1].Length);
        }

        [Fact]
        public void PathBuilder_RoutesStripEquivalent()
        {
            var cells = new List<HexCoord> { new HexCoord(0, 0), new HexCoord(2, 0) };
            VertexCoord[] path = PathBuilder.Route(
                new HexCoord(0, 0), 0, new HexCoord(2, 0), 3, cells);
            Assert.NotNull(path);

            var level = DevBoards.TwoNodeStrip();
            level.Wires[0].Path = new List<VertexCoord>(path);
            BuiltLevel built = Build(level); // router output must satisfy the loader
            Assert.True(built.Wires[0].Length >= 3f);
        }

        [Fact]
        public void DevBoards_Duel_BuildsAndValidates()
        {
            BuiltLevel built = Build(DevBoards.Duel());
            Assert.Equal(5, built.Nodes.Count);
            Assert.Equal(8, built.Wires.Count);
            // Point symmetry: each mirrored wire pair has identical length.
            for (int i = 0; i < built.Wires.Count; i += 2)
                Assert.Equal(built.Wires[i].Length, built.Wires[i + 1].Length);
            // The deliberate long route is meaningfully longer than the direct ones.
            Assert.True(built.Wires[6].Length > built.Wires[0].Length + 3,
                "long route (" + built.Wires[6].Length + ") should exceed home-centre (" + built.Wires[0].Length + ") by 3+");
        }
    }
}
