using System;

namespace Lightship.Core
{
    /// <summary>
    /// Own PRNG (splitmix64-based) so results are identical across .NET runtimes
    /// and across the Godot player and the headless CLI. System.Random's
    /// algorithm differs between runtimes, which would break the determinism
    /// gate. Never use System.Random anywhere in Core.
    /// </summary>
    public sealed class DeterministicRandom
    {
        private ulong _state;

        public DeterministicRandom(ulong seed)
        {
            // Avoid the all-zero state.
            _state = seed == 0 ? 0x9E3779B97F4A7C15UL : seed;
        }

        /// <summary>Raw state, for the state hash.</summary>
        public ulong State => _state;

        public ulong NextUlong()
        {
            _state += 0x9E3779B97F4A7C15UL;
            ulong z = _state;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            return z ^ (z >> 31);
        }

        /// <summary>Uniform float in [0, 1).</summary>
        public float NextFloat()
        {
            // 24 bits of mantissa for an exact float in [0,1).
            return (NextUlong() >> 40) * (1.0f / 16777216.0f);
        }

        /// <summary>Uniform float in [min, max).</summary>
        public float Range(float min, float max) => min + NextFloat() * (max - min);

        /// <summary>Uniform int in [min, max) (max exclusive).</summary>
        public int RangeInt(int min, int max)
        {
            if (max <= min) return min;
            return min + (int)(NextUlong() % (ulong)(max - min));
        }

        /// <summary>Derive an independent stream (e.g. for one AI) from this one.</summary>
        public DeterministicRandom Fork(ulong salt) =>
            new DeterministicRandom(NextUlong() ^ salt);
    }
}
