using System.Collections.Generic;

namespace Gridlock.Core.Levels
{
    /// <summary>
    /// Offline wire authoring: routes a lattice-legal path from one node face to
    /// another with BFS, optionally through waypoint vertices (that is how a
    /// deliberately winding wire is authored — the router itself always takes the
    /// shortest legal route per leg). Used by tests, dev boards, and the Headless
    /// `gen` tool. Not shipped gameplay — procgen is out of scope (spec §10.1);
    /// this exists so humans never hand-write [n, m] arrays.
    ///
    /// Guarantees on success: the returned path starts with the fromFace edge of
    /// cellA, ends with the toFace edge of cellB, uses only valid lattice edges,
    /// repeats no vertex, avoids every corner of every OTHER node's hex (and the
    /// unused corners of its own endpoints), and avoids all edges in usedEdges.
    /// Returns null when no route exists under those constraints.
    /// </summary>
    public static class PathBuilder
    {
        public static VertexCoord[] Route(
            HexCoord cellA, int faceA,
            HexCoord cellB, int faceB,
            IEnumerable<HexCoord> allNodeCells,
            HashSet<EdgeKey> usedEdges = null,
            IList<VertexCoord> waypoints = null)
        {
            HexMath.FaceEdge(cellA, faceA, out VertexCoord a1, out VertexCoord a2);
            HexMath.FaceEdge(cellB, faceB, out VertexCoord b1, out VertexCoord b2);

            // Every node corner is forbidden except the four face-edge corners.
            var forbidden = new HashSet<VertexCoord>();
            foreach (HexCoord cell in allNodeCells)
            {
                for (int i = 0; i < 6; i++) forbidden.Add(HexMath.CornerVertex(cell, i));
            }
            forbidden.Remove(a1);
            forbidden.Remove(a2);
            forbidden.Remove(b1);
            forbidden.Remove(b2);

            var used = usedEdges ?? new HashSet<EdgeKey>();
            var faceEdgeA = new EdgeKey(a1, a2);
            var faceEdgeB = new EdgeKey(b1, b2);
            if (used.Contains(faceEdgeA) || used.Contains(faceEdgeB)) return null;

            // The lattice is infinite: BFS MUST be bounded or an enclosed goal
            // never terminates. Search box = everything relevant, padded.
            var bounds = new SearchBounds();
            foreach (HexCoord cell in allNodeCells)
            {
                for (int i = 0; i < 6; i++) bounds.Include(HexMath.CornerVertex(cell, i));
            }
            if (waypoints != null)
            {
                foreach (VertexCoord w in waypoints) bounds.Include(w);
            }
            bounds.Pad(10, 15);

            // Try both orientations of each anchor edge; keep the shortest result.
            VertexCoord[] best = null;
            foreach ((VertexCoord start0, VertexCoord start1) in new[] { (a1, a2), (a2, a1) })
            {
                foreach ((VertexCoord end0, VertexCoord end1) in new[] { (b1, b2), (b2, b1) })
                {
                    VertexCoord[] path = RouteOriented(start0, start1, end0, end1, forbidden, used, waypoints, bounds);
                    if (path != null && (best == null || path.Length < best.Length)) best = path;
                }
            }
            return best;
        }

        private class SearchBounds
        {
            private int _minN = int.MaxValue, _maxN = int.MinValue;
            private int _minM = int.MaxValue, _maxM = int.MinValue;

            public void Include(VertexCoord v)
            {
                if (v.N < _minN) _minN = v.N;
                if (v.N > _maxN) _maxN = v.N;
                if (v.M < _minM) _minM = v.M;
                if (v.M > _maxM) _maxM = v.M;
            }

            public void Pad(int n, int m)
            {
                _minN -= n; _maxN += n;
                _minM -= m; _maxM += m;
            }

            public bool Contains(VertexCoord v) =>
                v.N >= _minN && v.N <= _maxN && v.M >= _minM && v.M <= _maxM;
        }

        private static VertexCoord[] RouteOriented(
            VertexCoord start0, VertexCoord start1,
            VertexCoord end0, VertexCoord end1,
            HashSet<VertexCoord> forbidden,
            HashSet<EdgeKey> usedEdges,
            IList<VertexCoord> waypoints,
            SearchBounds bounds)
        {
            // Full path shape: start0, start1, ...BFS..., end0, end1.
            // The BFS legs run start1 -> (waypoints...) -> end0, never touching
            // start0/end1 (blocked below) and never reusing a vertex.
            var path = new List<VertexCoord> { start0, start1 };
            var blocked = new HashSet<VertexCoord>(forbidden) { start0, end1 };

            var targets = new List<VertexCoord>();
            if (waypoints != null) targets.AddRange(waypoints);
            targets.Add(end0);

            VertexCoord current = start1;
            foreach (VertexCoord target in targets)
            {
                blocked.Add(current);
                List<VertexCoord> leg = Bfs(current, target, blocked, usedEdges, bounds);
                if (leg == null) return null;
                foreach (VertexCoord v in leg)
                {
                    path.Add(v);
                    blocked.Add(v);
                }
                current = target;
            }
            path.Add(end1);

            // Final self-consistency: no repeats (BFS legs cannot revisit blocked
            // vertices, so this only guards programmer error).
            var seen = new HashSet<VertexCoord>();
            foreach (VertexCoord v in path)
            {
                if (!seen.Add(v)) return null;
            }
            return path.ToArray();
        }

        /// <summary>Shortest path from start (exclusive) to goal (inclusive) within bounds; null if unreachable.</summary>
        private static List<VertexCoord> Bfs(
            VertexCoord start, VertexCoord goal,
            HashSet<VertexCoord> blocked, HashSet<EdgeKey> usedEdges,
            SearchBounds bounds)
        {
            if (blocked.Contains(goal)) return null;
            if (!bounds.Contains(goal) || !bounds.Contains(start)) return null;
            var cameFrom = new Dictionary<VertexCoord, VertexCoord>();
            var queue = new Queue<VertexCoord>();
            var visited = new HashSet<VertexCoord> { start };
            queue.Enqueue(start);

            while (queue.Count > 0)
            {
                VertexCoord v = queue.Dequeue();
                foreach (VertexCoord d in VertexCoord.EdgeDeltas)
                {
                    var next = new VertexCoord(v.N + d.N, v.M + d.M);
                    if (!next.IsValidVertex()) continue;
                    if (!bounds.Contains(next)) continue;
                    if (visited.Contains(next)) continue;
                    if (blocked.Contains(next) && next != goal) continue;
                    if (usedEdges.Contains(new EdgeKey(v, next))) continue;
                    visited.Add(next);
                    cameFrom[next] = v;
                    if (next == goal)
                    {
                        var leg = new List<VertexCoord>();
                        VertexCoord walk = goal;
                        while (walk != start)
                        {
                            leg.Add(walk);
                            walk = cameFrom[walk];
                        }
                        leg.Reverse();
                        return leg;
                    }
                    queue.Enqueue(next);
                }
            }
            return null;
        }

        /// <summary>Register a finished path's edges into a used-edge set (for multi-wire boards).</summary>
        public static void MarkUsed(IList<VertexCoord> path, HashSet<EdgeKey> usedEdges)
        {
            for (int i = 0; i + 1 < path.Count; i++)
                usedEdges.Add(new EdgeKey(path[i], path[i + 1]));
        }
    }
}
