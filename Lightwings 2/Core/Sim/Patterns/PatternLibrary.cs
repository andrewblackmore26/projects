using Lightship.Core.Ships;

namespace Lightship.Core.Sim.Patterns
{
    /// <summary>
    /// The pattern identity of each element (spec 8): fire = cones, fans and
    /// lingering mines; lightning = fast bolts and chains; void = slow pulls;
    /// corruption = infection and drones. Bullet size and density scale with the
    /// enemy's tier (spec 8). Lightning and void land in M3.
    /// </summary>
    public static class PatternLibrary
    {
        /// <summary>Fire: a short-range cone, three bursts, then a pause. Higher tiers fire wider, denser, bigger cones.</summary>
        public static PatternDefinition FlameSpray(int tier = 1)
        {
            int up = System.Math.Max(0, tier - 1);
            // Reach = 220 u/s x 42 ticks = 154 units: the Ember closes to 110 and opens fire inside 170.
            var def = new PatternDefinition { Id = "flame_spray", Element = Element.Fire, Range = 170f, PreferredRange = 110f };
            def.Steps.Add(new PatternStep
            {
                Kind = StepKind.Cone, Count = 5 + 2 * up, SpreadDeg = 30f + 6f * up, Speed = 220f, Radius = 3f + 0.5f * up, Damage = 5f,
                TtlTicks = 42, IntervalTicks = 20, Repeat = 3, PauseTicks = 72, Aim = AimMode.AtPlayer,
            });
            return def;
        }

        /// <summary>
        /// Corruption: slow spores from the spore bud, led at the target, that infect what they
        /// touch (a short damage over time). Slower than fire and longer-ranged, so the two
        /// read differently before their colours do.
        /// </summary>
        public static PatternDefinition SporeBurst(int tier = 1)
        {
            int up = System.Math.Max(0, tier - 1);
            // Reach = 170 u/s x 90 ticks = 255 units; held at 190.
            var def = new PatternDefinition { Id = "infect", Element = Element.Corruption, Range = 260f, PreferredRange = 190f };
            def.Steps.Add(new PatternStep
            {
                Kind = StepKind.Cone, Count = 3 + up, SpreadDeg = 24f, Speed = 170f, Radius = 3.5f + 0.5f * up, Damage = 4f,
                TtlTicks = 90, IntervalTicks = 16, Repeat = 2 + up, PauseTicks = 100, Aim = AimMode.Lead, Flags = BulletFlags.Infect,
            });
            return def;
        }

        public static PatternDefinition ForEnemy(Element element, int tier)
        {
            switch (element)
            {
                case Element.Corruption: return SporeBurst(tier);
                default: return FlameSpray(tier);
            }
        }
    }
}
