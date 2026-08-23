using System;

namespace Gridlock.Core
{
    /// <summary>
    /// A wire between two nodes (spec §4.3): a polyline of lattice vertices from
    /// A to B. Every segment is one lattice edge of length exactly 1, so
    /// Length == Path.Length - 1. Length drives travel time — it is NOT the
    /// straight-line distance between endpoints (design pillar 1).
    /// </summary>
    public class Wire
    {
        public int Id;
        public int NodeA;
        public int NodeB;

        /// <summary>Lattice vertices from A to B, in order. Immutable after load.</summary>
        public VertexCoord[] Path;

        /// <summary>Precomputed pixel positions of Path (lattice units).</summary>
        public Vec2[] PixelPath;

        /// <summary>Polyline length in lattice units (= segment count).</summary>
        public float Length;

        /// <summary>Face 0..5 the wire occupies on node A / node B.</summary>
        public int FaceA;
        public int FaceB;

        /// <summary>Pixel position at parameter t ∈ [0,1] (t=0 at A, t=1 at B). For presentation and tooling.</summary>
        public Vec2 PositionAt(float t)
        {
            if (t <= 0f) return PixelPath[0];
            if (t >= 1f) return PixelPath[PixelPath.Length - 1];
            float d = t * Length;
            int seg = (int)d;
            if (seg >= PixelPath.Length - 1) seg = PixelPath.Length - 2;
            float frac = d - seg;
            return Vec2.Lerp(PixelPath[seg], PixelPath[seg + 1], frac);
        }

        /// <summary>The node id at the far end from the given node.</summary>
        public int OtherNode(int nodeId)
        {
            if (nodeId == NodeA) return NodeB;
            if (nodeId == NodeB) return NodeA;
            throw new ArgumentException("Node " + nodeId + " is not an endpoint of wire " + Id);
        }

        /// <summary>Travel direction (+1 = A→B, -1 = B→A) for a beam leaving the given node.</summary>
        public int DirectionFrom(int nodeId) => nodeId == NodeA ? 1 : -1;

        /// <summary>The endpoint node id a beam travelling in dir is heading toward.</summary>
        public int DestinationNode(int dir) => dir > 0 ? NodeB : NodeA;
    }
}
