using System;

namespace Lightship.Core.Sim
{
    /// <summary>
    /// FNV-1a fingerprint of everything that matters: the Godot player and the
    /// headless CLI must print the same value for the same seed and inputs, or
    /// the simulation is not deterministic and nothing downstream can be trusted.
    /// </summary>
    public static class StateHash
    {
        private const ulong Offset = 14695981039346656037UL;
        private const ulong Prime = 1099511628211UL;

        public static ulong Compute(Game game)
        {
            ulong h = Offset;
            Run run = game.Run;
            Arena a = run.Arena;
            h = Mix(h, (ulong)game.Tick);
            h = Mix(h, (ulong)a.Tick);
            h = Mix(h, Bits(run.Energy));
            h = Mix(h, (ulong)run.Tier);
            h = Mix(h, (ulong)game.Meta.Deaths);
            h = Mix(h, game.Rng.State);
            h = Mix(h, a.Rng.State);
            foreach (Ship s in a.Ships)
            {
                h = Mix(h, (ulong)s.Id);
                h = Mix(h, Bits(s.Pos.X)); h = Mix(h, Bits(s.Pos.Y));
                h = Mix(h, Bits(s.Vel.X)); h = Mix(h, Bits(s.Vel.Y));
                h = Mix(h, Bits(s.Hp));
                h = Mix(h, (ulong)s.Tier);
                h = Mix(h, s.Alive ? 1UL : 0UL);
            }
            BulletPool b = a.Bullets;
            for (int i = 0; i < b.High; i++)
            {
                if (!b.Alive[i]) continue;
                h = Mix(h, (ulong)i);
                h = Mix(h, Bits(b.X[i])); h = Mix(h, Bits(b.Y[i]));
                h = Mix(h, Bits(b.VX[i])); h = Mix(h, Bits(b.VY[i]));
                h = Mix(h, (ulong)b.Ttl[i]);
            }
            PickupPool p = a.Pickups;
            for (int i = 0; i < p.High; i++)
            {
                if (!p.Alive[i]) continue;
                h = Mix(h, (ulong)i);
                h = Mix(h, Bits(p.X[i])); h = Mix(h, Bits(p.Y[i]));
                h = Mix(h, Bits(p.Value[i]));
            }
            h = Mix(h, (ulong)game.Events.Total);
            return h;
        }

        private static ulong Bits(float f) => (ulong)(uint)BitConverter.SingleToInt32Bits(f);

        private static ulong Mix(ulong h, ulong v)
        {
            for (int i = 0; i < 8; i++)
            {
                h ^= (v >> (i * 8)) & 0xFF;
                h *= Prime;
            }
            return h;
        }
    }
}
