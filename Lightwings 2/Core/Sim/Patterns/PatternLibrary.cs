using Lightship.Core.Ships;

namespace Lightship.Core.Sim.Patterns
{
    /// <summary>
    /// The pattern identity of each element (spec 8): fire = cones, fans and
    /// lingering mines; lightning = fast bolts and chains; void = slow pulls;
    /// corruption = infection and drones. M1 ships fire; the rest land in M3.
    /// </summary>
    public static class PatternLibrary
    {
        /// <summary>Fire T1 Ember: a short-range cone of five, three bursts, then a pause.</summary>
        public static PatternDefinition FlameSpray()
        {
            // Reach = 220 u/s x 42 ticks = 154 units: the Ember closes to 110 and opens fire inside 170.
            var def = new PatternDefinition { Id = "flame_spray", Element = Element.Fire, Range = 170f, PreferredRange = 110f };
            def.Steps.Add(new PatternStep
            {
                Kind = StepKind.Cone, Count = 5, SpreadDeg = 30f, Speed = 220f, Radius = 3f, Damage = 8f,
                TtlTicks = 42, IntervalTicks = 20, Repeat = 3, PauseTicks = 72, Aim = AimMode.AtPlayer,
            });
            return def;
        }

        public static PatternDefinition ForEnemy(Element element, int tier)
        {
            switch (element)
            {
                default: return FlameSpray();
            }
        }
    }
}
