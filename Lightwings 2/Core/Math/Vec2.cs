using System;

namespace Lightship.Core
{
    /// <summary>
    /// Engine-free 2D vector. Core must not reference Godot, so it carries its
    /// own minimal vector type. Axes follow Godot 2D: +X right, +Y down, and a
    /// ship's local forward is (0, -1).
    /// </summary>
    public struct Vec2 : IEquatable<Vec2>
    {
        public float X;
        public float Y;

        public Vec2(float x, float y)
        {
            X = x;
            Y = y;
        }

        public static readonly Vec2 Zero = new Vec2(0f, 0f);
        public static readonly Vec2 Forward = new Vec2(0f, -1f);

        public static Vec2 operator +(Vec2 a, Vec2 b) => new Vec2(a.X + b.X, a.Y + b.Y);
        public static Vec2 operator -(Vec2 a, Vec2 b) => new Vec2(a.X - b.X, a.Y - b.Y);
        public static Vec2 operator -(Vec2 a) => new Vec2(-a.X, -a.Y);
        public static Vec2 operator *(Vec2 a, float s) => new Vec2(a.X * s, a.Y * s);
        public static Vec2 operator *(float s, Vec2 a) => new Vec2(a.X * s, a.Y * s);
        public static Vec2 operator /(Vec2 a, float s) => new Vec2(a.X / s, a.Y / s);

        public float Length() => MathF.Sqrt(X * X + Y * Y);
        public float LengthSquared() => X * X + Y * Y;

        public static float Distance(Vec2 a, Vec2 b) => (a - b).Length();
        public static float DistanceSquared(Vec2 a, Vec2 b) => (a - b).LengthSquared();
        public static float Dot(Vec2 a, Vec2 b) => a.X * b.X + a.Y * b.Y;
        /// <summary>2D cross product (z of the 3D cross): positive when b is clockwise from a on screen.</summary>
        public static float Cross(Vec2 a, Vec2 b) => a.X * b.Y - a.Y * b.X;

        public Vec2 Normalized()
        {
            float len = Length();
            return len > 1e-12f ? new Vec2(X / len, Y / len) : Zero;
        }

        /// <summary>Perpendicular, rotated a quarter turn (screen-clockwise).</summary>
        public Vec2 Perp() => new Vec2(-Y, X);

        /// <summary>Rotate by an angle in radians (positive = screen-clockwise, Godot convention).</summary>
        public Vec2 Rotated(float radians)
        {
            float c = MathF.Cos(radians), s = MathF.Sin(radians);
            return new Vec2(X * c - Y * s, X * s + Y * c);
        }

        /// <summary>Angle in radians, atan2(Y, X).</summary>
        public float Angle() => MathF.Atan2(Y, X);

        public static Vec2 FromAngle(float radians) => new Vec2(MathF.Cos(radians), MathF.Sin(radians));

        public static Vec2 Lerp(Vec2 a, Vec2 b, float t) =>
            new Vec2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t);

        public bool Equals(Vec2 other) => X == other.X && Y == other.Y;
        public override bool Equals(object obj) => obj is Vec2 v && Equals(v);
        public override int GetHashCode() => X.GetHashCode() * 397 ^ Y.GetHashCode();
        public override string ToString() => "(" + X + ", " + Y + ")";
    }
}
