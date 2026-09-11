using System.Collections.Generic;

namespace Lightship.Core.Ships
{
    /// <summary>
    /// Spec 11.5 / Appendix B: every part's light runs at one lap per 2.0 s,
    /// every fourth part at 1.6 s, and phases are spread 0 / -0.7 / -1.3 s so
    /// the lights never move in sync. Applied only to parts that did not pin
    /// their own period/phase in the data.
    /// </summary>
    public static class LightSchedule
    {
        public static readonly float[] Periods = { 2.0f, 1.6f };
        public static readonly float[] Phases = { 0f, -0.7f, -1.3f };

        public static void Assign(List<PartDefinition> parts)
        {
            int i = 0;
            foreach (PartDefinition p in parts)
            {
                if (p.Dashed) continue;                      // reference rings carry no light
                if (p.PeriodIndex < 0) p.PeriodIndex = (i % 4 == 3) ? 1 : 0;
                if (p.PhaseIndex < 0) p.PhaseIndex = i % 3;
                i++;
            }
        }
    }
}
