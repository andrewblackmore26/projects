namespace Gridlock.Core
{
    /// <summary>
    /// A packet of charge in flight along a wire (spec §5.5).
    /// t ∈ [0,1] along the wire (0 = node A, 1 = node B); per tick
    /// t += dir · (speed / wire.Length) · dt.
    /// </summary>
    public class Beam
    {
        public int Id;
        public int WireId;
        public Owner Owner;

        /// <summary>Decides collisions and captures. Unit: charge.</summary>
        public float Power;

        /// <summary>Decides arrival order. Unit: lattice units/second.</summary>
        public float Speed;

        /// <summary>Position along the wire, 0..1.</summary>
        public float T;

        /// <summary>Position at the previous tick (presentation interpolation + sweep tests).</summary>
        public float PrevT;

        /// <summary>+1 = travelling A→B, -1 = B→A.</summary>
        public int Dir;

        /// <summary>
        /// Set on beams spawned mid-tick by contest resolution: they hold position
        /// for the remainder of the spawn tick (still contactable) and move from
        /// the next tick.
        /// </summary>
        public bool HoldThisTick;

        /// <summary>t travelled per second on the given wire.</summary>
        public float RatePerSecond(Wire w) => Speed / w.Length;
    }
}
