using UnityEngine;
using Gridlock.Core;
using Gridlock.Core.Levels;

namespace Gridlock.View
{
    /// <summary>
    /// Board bounds in lattice units, and the orthographic size needed to fit
    /// them. Unity's world is Y-up like the simulation's, so unlike the Godot
    /// layer nothing has to flip: lattice units ARE world units here, and the
    /// camera does the scaling.
    /// </summary>
    public class UBoardTransform
    {
        public Vector2 Centre { get; private set; }
        public float OrthographicSize { get; private set; }

        /// <summary>World units per screen pixel, for keeping line cores pixel-sized.</summary>
        public float WorldPerPixel { get; private set; }

        public UBoardTransform(BuiltLevel level, int screenWidth, int screenHeight, float marginFraction = 0.10f)
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
                for (int i = 0; i < 6; i++) Include(HexMath.CellCorner(n.Coord, i));
            }
            if (minX > maxX) { minX = maxX = minY = maxY = 0f; }

            Centre = new Vector2((minX + maxX) * 0.5f, (minY + maxY) * 0.5f);

            float halfW = Mathf.Max((maxX - minX) * 0.5f, 0.001f);
            float halfH = Mathf.Max((maxY - minY) * 0.5f, 0.001f);
            float aspect = screenHeight > 0 ? (float)screenWidth / screenHeight : 1.777f;
            // Orthographic size is the half-HEIGHT, so a wide board is fitted
            // through the aspect ratio.
            OrthographicSize = Mathf.Max(halfH, halfW / Mathf.Max(aspect, 0.01f)) / (1f - marginFraction);
            WorldPerPixel = screenHeight > 0 ? (OrthographicSize * 2f) / screenHeight : 0.01f;
        }

        public static Vector2 ToWorld(Vec2 p) => new Vector2(p.X, p.Y);
    }
}
