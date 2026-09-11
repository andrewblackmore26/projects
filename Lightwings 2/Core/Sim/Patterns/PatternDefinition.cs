using System.Collections.Generic;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim.Patterns
{
    public enum StepKind
    {
        Cone,   // Count bullets at once, spread across SpreadDeg
        Fan,    // one bullet per interval sweeping across SpreadDeg
        Ring,   // Count bullets evenly around the ship
        Bolt,   // one fast bullet
        Mine,   // a stationary long-lived bullet
        Chain,  // M3: a bolt that jumps to a second target
        Pull,   // M3: void pull
    }

    public enum AimMode
    {
        AtPlayer,
        Forward,
        Lead,
    }

    /// <summary>One line of a bullet pattern; data, so elements differ by what they shoot (spec 8).</summary>
    public sealed class PatternStep
    {
        public StepKind Kind = StepKind.Cone;
        public int Count = 1;
        public float SpreadDeg = 0f;
        public float Speed = 200f;      // world units per second
        public float Radius = 3f;       // world units
        public float Damage = 8f;       // HP
        public int TtlTicks = 60;
        public int IntervalTicks = 20;  // ticks between repeats
        public int Repeat = 1;          // shots before the pause
        public int PauseTicks = 60;     // ticks after the last repeat
        public AimMode Aim = AimMode.AtPlayer;
        public byte Flags;              // BulletFlags carried by every bullet of this step (corruption spores infect)
    }

    public sealed class PatternDefinition
    {
        public string Id;
        public Element Element;
        public float Range = 320f;      // world units within which the ship fires
        /// <summary>
        /// World units the pilot tries to hold from its target. Must sit inside
        /// the bullets' reach (speed x ttl), or the pattern can never land: the
        /// first flame spray held 220 with a 154-unit reach and hit nothing.
        /// </summary>
        public float PreferredRange = 220f;

        /// <summary>The farthest any step's bullets travel before expiring.</summary>
        public float Reach
        {
            get
            {
                float r = 0f;
                foreach (PatternStep s in Steps) r = System.MathF.Max(r, s.Speed * s.TtlTicks / 60f);
                return r;
            }
        }
        public readonly List<PatternStep> Steps = new List<PatternStep>();
    }
}
