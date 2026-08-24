using Godot;
using Gridlock.Core;
using Gridlock.Core.Levels;

namespace Gridlock.View
{
    /// <summary>
    /// Lattice units to screen pixels. The simulation works in lattice units with
    /// Y up; screens have Y down, so the mapping flips Y. The scale is chosen to
    /// fit the whole board on screen (a board is only readable if all of it is
    /// visible -- there is no fog and no camera to hunt with), capped by the
    /// level's authored hexSize.
    /// </summary>
    public class BoardTransform
    {
        public float Scale { get; private set; }
        public Vector2 Offset { get; private set; }

        public BoardTransform(BuiltLevel level, Vector2 viewportSize, float marginFraction = 0.09f)
        {
            float minX = float.MaxValue, maxX = float.MinValue;
            float minY = float.MaxValue, maxY = float.MinValue;

            void Include(Vec2 p)
            {
                if (p.X < minX) minX = p.X;
                if (p.X > maxX) maxX = p.X;
                if (p.Y < minY) minY = p.Y;
                if (p.Y > maxY) maxY = p.Y;
            }

            foreach (Wire w in level.Wires)
            {
                foreach (Vec2 p in w.PixelPath) Include(p);
            }
            foreach (GameNode n in level.Nodes)
            {
                // Include the whole hex, not just its centre, so outlines never clip.
                for (int i = 0; i < 6; i++) Include(HexMath.CellCorner(n.Coord, i));
            }
            if (minX > maxX) { minX = maxX = minY = maxY = 0f; }

            float boardW = Mathf.Max(maxX - minX, 0.001f);
            float boardH = Mathf.Max(maxY - minY, 0.001f);
            float usableW = viewportSize.X * (1f - marginFraction * 2f);
            float usableH = viewportSize.Y * (1f - marginFraction * 2f);

            Scale = Mathf.Min(usableW / boardW, usableH / boardH);
            if (level.Data.HexSize > 0f) Scale = Mathf.Min(Scale, level.Data.HexSize);

            var centre = new Vector2((minX + maxX) * 0.5f, (minY + maxY) * 0.5f);
            Offset = viewportSize * 0.5f - new Vector2(centre.X, -centre.Y) * Scale;
        }

        public Vector2 ToScreen(Vec2 p) => new Vector2(p.X, -p.Y) * Scale + Offset;

        public Vector2 ToScreen(Vector2 latticePoint) =>
            new Vector2(latticePoint.X, -latticePoint.Y) * Scale + Offset;

        /// <summary>Screen point back to lattice space (input picking).</summary>
        public Vec2 ToLattice(Vector2 screen)
        {
            Vector2 v = (screen - Offset) / Scale;
            return new Vec2(v.X, -v.Y);
        }
    }
}
