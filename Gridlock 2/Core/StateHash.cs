using System;

namespace Gridlock.Core
{
    /// <summary>
    /// FNV-1a 64-bit fingerprint of the full simulation state. Two runs of the
    /// same level + same intent sequence must produce identical hashes at every
    /// tick (determinism acceptance criterion), and the hash must be identical
    /// across engines (the M2 Godot-vs-console gate). Floats are hashed by raw
    /// bit pattern — no tolerance, ever.
    /// </summary>
    public static class StateHash
    {
        private const ulong FnvOffset = 14695981039346656037UL;
        private const ulong FnvPrime = 1099511628211UL;

        public static ulong Compute(Simulation sim)
        {
            ulong h = FnvOffset;
            h = Mix(h, sim.Tick);
            h = Mix(h, (long)sim.Result);

            foreach (GameNode n in sim.Nodes)
            {
                h = Mix(h, n.Id);
                h = Mix(h, (long)n.Owner);
                h = Mix(h, (long)n.State);
                h = MixFloat(h, n.Charge);
                h = MixFloat(h, n.NeutralDefense);
                h = Mix(h, n.HoldStartTick);
                h = Mix(h, n.State == NodeState.Disabled ? n.DisabledUntilTick : 0);
                h = Mix(h, n.State == NodeState.CaptureLocked ? n.LockUntilTick : 0);
            }
            foreach (Beam b in sim.Beams)
            {
                h = Mix(h, b.Id);
                h = Mix(h, b.WireId);
                h = Mix(h, (long)b.Owner);
                h = MixFloat(h, b.Power);
                h = MixFloat(h, b.Speed);
                h = MixFloat(h, b.T);
                h = Mix(h, b.Dir);
            }
            foreach (Contest c in sim.Contests)
            {
                h = Mix(h, c.Id);
                h = Mix(h, c.WireId);
                h = MixFloat(h, c.ContactT);
                h = MixFloat(h, c.PowerPlayer);
                h = MixFloat(h, c.PowerAi);
                h = MixFloat(h, c.SpeedPlayer);
                h = MixFloat(h, c.SpeedAi);
                h = Mix(h, c.DirPlayer);
            }
            return h;
        }

        private static ulong Mix(ulong h, long value)
        {
            ulong v = (ulong)value;
            for (int i = 0; i < 8; i++)
            {
                h ^= (v >> (i * 8)) & 0xFF;
                h *= FnvPrime;
            }
            return h;
        }

        private static ulong MixFloat(ulong h, float value) =>
            Mix(h, BitConverter.SingleToInt32Bits(value));
    }
}
