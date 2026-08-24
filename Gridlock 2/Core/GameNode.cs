using Gridlock.Core.Config;

namespace Gridlock.Core
{
    /// <summary>
    /// A node on the board (spec §4.2). Pure state — the rules that mutate it
    /// live in Simulation. Timers are ABSOLUTE tick indices, never countdowns
    /// (lessons.md: countdowns drift and cost a decrement per tick).
    /// </summary>
    public class GameNode
    {
        public int Id;
        public HexCoord Coord;
        public Owner Owner;
        public NodeState State;

        /// <summary>Stored charge. For owned nodes this IS the defense.</summary>
        public float Charge;

        /// <summary>One-time toll for neutral nodes; set at load, never regenerates (spec §5.7).</summary>
        public float NeutralDefense;

        /// <summary>Wire count, hard max 6 (one per hex face).</summary>
        public int Degree;

        /// <summary>Wire id per face 0..5, -1 = no wire on that face.</summary>
        public readonly int[] WireIdByFace = { -1, -1, -1, -1, -1, -1 };

        /// <summary>Attached wire ids in face order (compact, length == Degree).</summary>
        public int[] WireIds = System.Array.Empty<int>();

        /// <summary>Tick at which Disabled expires; meaningful only while State == Disabled.</summary>
        public long DisabledUntilTick;

        /// <summary>Tick at which CaptureLocked expires; meaningful only while State == CaptureLocked.</summary>
        public long LockUntilTick;

        /// <summary>Tick the current hold started, -1 when not holding. holdTicks = now − this.</summary>
        public long HoldStartTick = -1;

        /// <summary>
        /// Set once per hold, the first tick the hold reaches burst length —
        /// a latch, not an equality test, so the armed signal and the burst
        /// itself stay on the same predicate even if OverchargeTime is edited
        /// live from the debug panel mid-hold.
        /// </summary>
        public bool OverchargeArmed;

        public float MaxCharge(Tuning t) => t.MaxChargePerDegree * Degree;

        /// <summary>Hold ticks accumulated so far (0 when not holding).</summary>
        public long HoldTicks(long currentTick) =>
            HoldStartTick < 0 ? 0 : currentTick - HoldStartTick;

        /// <summary>0..1, drives node brightness while Overcharging (spec §4.2).</summary>
        public float OverchargeProgress(long currentTick, Tuning t)
        {
            if (HoldStartTick < 0) return 0f;
            float p = HoldTicks(currentTick) / (float)t.OverchargeTicks;
            return p < 0f ? 0f : (p > 1f ? 1f : p);
        }
    }
}
