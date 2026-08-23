using Gridlock.Core;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;

namespace Gridlock.Core.Tests
{
    public static class TestHelpers
    {
        /// <summary>Tuning with charge accrual OFF — most rule tests want frozen charges.</summary>
        public static Tuning FrozenTuning()
        {
            return new Tuning { BaseChargeRate = 0f };
        }

        public static Simulation NewSim(LevelData level, Tuning tuning = null) =>
            new Simulation(level, tuning ?? new Tuning());

        public static void StepN(Simulation sim, int n)
        {
            for (int i = 0; i < n; i++) sim.Step();
        }

        /// <summary>Steps until the predicate holds or maxTicks elapse; returns ticks stepped or -1.</summary>
        public static int StepUntil(Simulation sim, System.Func<Simulation, bool> done, int maxTicks)
        {
            for (int i = 0; i < maxTicks; i++)
            {
                if (done(sim)) return i;
                sim.Step();
            }
            return done(sim) ? maxTicks : -1;
        }
    }
}
