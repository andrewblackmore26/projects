using System.Collections.Generic;

namespace Lightship.Core.Ships
{
    /// <summary>
    /// One primitive of a lightship, as authored (spec 14). Positions are in
    /// ship-local world units (1 unit = 1 px at base zoom), +Y down, forward
    /// = -Y. Shape parameters are kept by name so the tween can lerp every
    /// shared key without knowing the shape.
    /// </summary>
    public sealed class PartDefinition
    {
        public string Id;
        public Shape Shape;
        public Vec2 Pos;
        public float RotDeg;
        public ColorRole Color;
        public Dictionary<string, float> Params = new Dictionary<string, float>();

        /// <summary>Tethers only: ids of the parts joined.</summary>
        public string From;
        public string To;

        /// <summary>0 = 2.0 s, 1 = 1.6 s; -1 = assign by LightSchedule.</summary>
        public int PeriodIndex = -1;
        /// <summary>0 = 0 s, 1 = -0.7 s, 2 = -1.3 s; -1 = assign by LightSchedule.</summary>
        public int PhaseIndex = -1;

        /// <summary>The ability this part carries (spec 11.7). Null for pure chassis.</summary>
        public string Component;
        /// <summary>Explicit draw layer; null = inferred (tether, dashed ring, component, else body).</summary>
        public PartLayer? Layer;
        /// <summary>Reference/reach ring: 1 px dashed, 40-60 % opacity, no fill, no running light.</summary>
        public bool Dashed;
        /// <summary>
        /// The previous tier's part this one supersedes (spec 12: fire T3 "body
        /// becomes a hexagon chassis"). Growth by addition (spec 11.8) requires
        /// every part id of tier n-1 to remain in tier n or be named here.
        /// </summary>
        public string Replaces;

        public bool IsTether => Shape == Shape.Tether;

        public float Param(string key, float fallback) =>
            Params.TryGetValue(key, out float v) ? v : fallback;

        public float Param(string key) => Param(key, ShapeParams.Default(Shape, key));

        public PartDefinition Clone()
        {
            var c = new PartDefinition
            {
                Id = Id, Shape = Shape, Pos = Pos, RotDeg = RotDeg, Color = Color,
                From = From, To = To, PeriodIndex = PeriodIndex, PhaseIndex = PhaseIndex,
                Component = Component, Layer = Layer, Dashed = Dashed, Replaces = Replaces,
            };
            foreach (var kv in Params) c.Params[kv.Key] = kv.Value;
            return c;
        }
    }

    /// <summary>The parameter vocabulary of every primitive.</summary>
    public static class ShapeParams
    {
        private static readonly string[] None = new string[0];

        public static string[] Keys(Shape s)
        {
            switch (s)
            {
                case Shape.Circle: return new[] { "radius" };
                case Shape.Ellipse: return new[] { "rx", "ry" };
                case Shape.Triangle: return new[] { "base", "height" };
                case Shape.Prong: return new[] { "base", "length" };
                case Shape.Diamond: return new[] { "width", "height" };
                case Shape.Chevron: return new[] { "width", "height", "notch" };
                case Shape.Hexagon: return new[] { "radius" };
                case Shape.Crescent: return new[] { "radius", "cut_radius", "cut_dx", "cut_dy" };
                case Shape.Arc: return new[] { "radius", "thickness", "start_deg", "sweep_deg" };
                case Shape.Ring: return new[] { "radius", "thickness" };
                default: return None;
            }
        }

        /// <summary>Keys that scale with the size of the part (grow from zero in the tween, scale in the editor).</summary>
        public static bool IsSizeKey(string key) =>
            key != "notch" && key != "start_deg" && key != "sweep_deg";

        public static float Default(Shape s, string key)
        {
            switch (key)
            {
                case "notch": return 0.5f;
                case "sweep_deg": return 90f;
                case "thickness": return 2f;
                default: return 0f;
            }
        }

        /// <summary>Largest size parameter, used to detect a part tweened down to nothing.</summary>
        public static float Extent(PartDefinition p)
        {
            float best = 0f;
            foreach (string k in Keys(p.Shape))
            {
                if (!IsSizeKey(k)) continue;
                float v = System.MathF.Abs(p.Param(k));
                if (v > best) best = v;
            }
            return best;
        }
    }
}
