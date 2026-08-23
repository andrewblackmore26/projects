using System;
using System.Collections.Generic;
using Gridlock.Core;
using Xunit;

namespace Gridlock.Core.Tests
{
    public class VertexLatticeTests
    {
        [Fact]
        public void Vertex_ValidityParityTable_MatchesCornerGroundTruth()
        {
            // Ground truth: every vertex is a corner of some hex. Generate all
            // corners over a hex range wide enough to cover the probe window.
            var truth = new HashSet<VertexCoord>();
            for (int q = -8; q <= 8; q++)
            {
                for (int r = -8; r <= 8; r++)
                {
                    for (int i = 0; i < 6; i++)
                        truth.Add(HexMath.CornerVertex(new HexCoord(q, r), i));
                }
            }
            for (int n = -12; n <= 12; n++)
            {
                for (int m = -12; m <= 12; m++)
                {
                    var v = new VertexCoord(n, m);
                    Assert.True(truth.Contains(v) == v.IsValidVertex(),
                        "validity mismatch at " + v + ": ground truth " + truth.Contains(v));
                }
            }
        }

        [Fact]
        public void Vertex_EveryValidVertexHasExactlyThreeNeighbours_AllAtDistanceOne()
        {
            for (int n = -9; n <= 9; n++)
            {
                for (int m = -9; m <= 9; m++)
                {
                    var v = new VertexCoord(n, m);
                    if (!v.IsValidVertex()) continue;
                    int neighbours = 0;
                    foreach (VertexCoord d in VertexCoord.EdgeDeltas)
                    {
                        var w = new VertexCoord(n + d.N, m + d.M);
                        if (!VertexCoord.IsLatticeEdge(v, w)) continue;
                        neighbours++;
                        float dist = Vec2.Distance(v.ToPixel(), w.ToPixel());
                        Assert.True(Math.Abs(dist - 1f) < 1e-5f,
                            "edge " + v + " -> " + w + " has length " + dist);
                    }
                    Assert.Equal(3, neighbours);
                }
            }
        }

        [Fact]
        public void Hex_CornerVertices_MatchFloatCorners()
        {
            for (int q = -3; q <= 3; q++)
            {
                for (int r = -3; r <= 3; r++)
                {
                    var h = new HexCoord(q, r);
                    for (int i = 0; i < 6; i++)
                    {
                        Vec2 exact = HexMath.CornerVertex(h, i).ToPixel();
                        Vec2 geometric = HexMath.CellCorner(h, i);
                        Assert.True(Vec2.Distance(exact, geometric) < 1e-4f,
                            "corner " + i + " of " + h + ": " + exact + " vs " + geometric);
                    }
                }
            }
        }

        [Fact]
        public void Hex_FaceEdge_IsSharedEdgeWithNeighbour()
        {
            for (int q = -3; q <= 3; q++)
            {
                for (int r = -3; r <= 3; r++)
                {
                    var h = new HexCoord(q, r);
                    for (int f = 0; f < 6; f++)
                    {
                        HexMath.FaceEdge(h, f, out VertexCoord a, out VertexCoord b);
                        Assert.True(VertexCoord.IsLatticeEdge(a, b));
                        HexCoord n = HexMath.Neighbour(h, f);
                        int oppositeFace = (f + 3) % 6;
                        HexMath.FaceEdge(n, oppositeFace, out VertexCoord na, out VertexCoord nb);
                        bool same = (a == na && b == nb) || (a == nb && b == na);
                        Assert.True(same, "face " + f + " of " + h + " is not the shared edge with " + n);
                    }
                }
            }
        }

        [Fact]
        public void Hex_FaceIndexOfEdge_RoundTrips()
        {
            var h = new HexCoord(2, -1);
            for (int f = 0; f < 6; f++)
            {
                HexMath.FaceEdge(h, f, out VertexCoord a, out VertexCoord b);
                Assert.Equal(f, HexMath.FaceIndexOfEdge(h, a, b));
                Assert.Equal(f, HexMath.FaceIndexOfEdge(h, b, a)); // unordered
            }
            // A radial (non-rim) edge is not a face edge.
            HexMath.FaceEdge(h, 0, out VertexCoord c0, out _);
            Assert.Equal(-1, HexMath.FaceIndexOfEdge(h, c0, new VertexCoord(c0.N + 1, c0.M - 1)));
        }

        [Fact]
        public void Vertex_EdgeTest_RejectsInvalidEndpoints()
        {
            // (0,0) is a hex-centre row entry, not a vertex.
            Assert.False(new VertexCoord(0, 0).IsValidVertex());
            Assert.False(VertexCoord.IsLatticeEdge(new VertexCoord(0, 0), new VertexCoord(0, 2)));
            // Valid endpoints but a non-edge delta.
            Assert.False(VertexCoord.IsLatticeEdge(new VertexCoord(0, 2), new VertexCoord(2, 2)));
        }
    }
}
