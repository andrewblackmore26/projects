using System.Collections.Generic;

namespace Lightship.Core.Ships
{
    /// <summary>
    /// The reshape (spec 5): parts with matching ids tween from old to new
    /// position and size; new parts grow out of the core; removed parts shrink
    /// into it. Tethers follow because geometry reads their endpoints. A pure
    /// function of (from, to, t), so it is testable and replayable.
    /// </summary>
    public static class ShipTween
    {
        public static ResolvedShip Resolve(ShipDefinition def) => ResolvedShip.From(def);

        public static ResolvedShip Blend(ShipDefinition from, ShipDefinition to, float t01)
        {
            float t = Easing.SmoothStep(t01);
            bool late = t >= 0.5f;
            ResolvedShip a = ResolvedShip.From(from);
            ResolvedShip b = ResolvedShip.From(to);
            var r = new ResolvedShip
            {
                Source = late ? to : from,
                ChassisColor = late ? to.ChassisColor : from.ChassisColor,
                CoreRole = late ? to.CoreColor : from.CoreColor,
                CoreRadius = Easing.Lerp(from.CoreRadius, to.CoreRadius, t),
                Breathes = late ? to.Breathes : from.Breathes,
            };

            var matched = new HashSet<string>();
            foreach (PartDefinition pb in b.Parts)
            {
                PartDefinition pa = a.FindPart(pb.Id);
                if (pa != null && pa.Shape == pb.Shape)
                {
                    matched.Add(pb.Id);
                    r.Parts.Add(Lerp(pa, pb, t, late));
                }
                else if (t > 0f)
                {
                    r.Parts.Add(Scaled(pb, t));          // grows out of the core
                }
            }
            if (t < 1f)
            {
                foreach (PartDefinition pa in a.Parts)
                {
                    if (matched.Contains(pa.Id)) continue;
                    PartDefinition shrinking = Scaled(pa, 1f - t);   // shrinks into the core
                    if (b.FindPart(pa.Id) != null) shrinking.Id = pa.Id + "~old";
                    r.Parts.Add(shrinking);
                }
            }
            return r;
        }

        private static PartDefinition Lerp(PartDefinition pa, PartDefinition pb, float t, bool late)
        {
            PartDefinition p = (late ? pb : pa).Clone();
            p.Pos = Vec2.Lerp(pa.Pos, pb.Pos, t);
            p.RotDeg = Easing.LerpAngleDeg(pa.RotDeg, pb.RotDeg, t);
            p.Params.Clear();
            foreach (string key in ShapeParams.Keys(pb.Shape))
            {
                bool inA = pa.Params.ContainsKey(key), inB = pb.Params.ContainsKey(key);
                if (!inA && !inB) continue;
                p.Params[key] = Easing.Lerp(pa.Param(key), pb.Param(key), t);
            }
            return p;
        }

        /// <summary>The part at a fraction of its size, pulled toward the core by the same fraction.</summary>
        private static PartDefinition Scaled(PartDefinition src, float s)
        {
            PartDefinition p = src.Clone();
            p.Pos = src.Pos * s;
            foreach (string key in ShapeParams.Keys(src.Shape))
            {
                if (!ShapeParams.IsSizeKey(key) || !src.Params.ContainsKey(key)) continue;
                p.Params[key] = src.Params[key] * s;
            }
            return p;
        }
    }
}
