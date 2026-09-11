using System.Collections.Generic;

namespace Lightship.Core.Ships
{
    /// <summary>
    /// Spec 11.5 / Appendix B: a part's light runs at one lap per 2.0 s, about
    /// one part in four at 1.6 s, and phases are spread over 0 / -0.7 / -1.3 s
    /// so the lights never move in sync.
    ///
    /// The schedule is a function of the part's ID, not its position in the
    /// list: a part carried from one tier to the next keeps its period and
    /// phase, so its running light travels on continuously through the
    /// reshape. (Assigning by list index made every carried part's light jump
    /// at the tween's halfway snap, because each tier orders its parts
    /// differently.) Parts that pin light_period / light_phase in the data keep
    /// their pinned values.
    /// </summary>
    public static class LightSchedule
    {
        public static readonly float[] Periods = { 2.0f, 1.6f };
        public static readonly float[] Phases = { 0f, -0.7f, -1.3f };

        /// <summary>FNV-1a over the id's UTF-16 units: identical on every runtime (string.GetHashCode is not).</summary>
        public static uint IdHash(string id)
        {
            uint h = 2166136261u;
            foreach (char c in id ?? "")
            {
                h ^= c;
                h *= 16777619u;
            }
            // Final avalanche so ids that differ in one trailing character spread across buckets.
            h ^= h >> 15; h *= 0x2C1B3C6Du; h ^= h >> 12; h *= 0x297A2D39u; h ^= h >> 15;
            return h;
        }

        public static int PeriodIndexFor(string id) => (IdHash(id) & 3) == 3 ? 1 : 0;
        public static int PhaseIndexFor(string id) => (int)((IdHash(id) >> 2) % 3);

        public static void Assign(List<PartDefinition> parts)
        {
            foreach (PartDefinition p in parts)
            {
                if (p.Dashed) continue;                      // reference rings carry no light
                // A crossfading old part ("id~old") keeps the schedule of the id it came from.
                string key = p.Id != null && p.Id.EndsWith("~old") ? p.Id.Substring(0, p.Id.Length - 4) : p.Id;
                if (p.PeriodIndex < 0) p.PeriodIndex = PeriodIndexFor(key);
                if (p.PhaseIndex < 0) p.PhaseIndex = PhaseIndexFor(key);
            }
        }
    }
}
