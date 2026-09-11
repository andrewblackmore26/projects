using System;
using System.Diagnostics;
using Lightship.Core.Sim;
using Xunit;
using Xunit.Abstractions;

namespace Lightship.Core.Tests
{
    public class DeterminismTests
    {
        [Fact]
        public void SameSeedSameHash()
        {
            Game a = SimTestHelpers.BotGame(7), b = SimTestHelpers.BotGame(7);
            SimTestHelpers.StepN(a, 3600);
            SimTestHelpers.StepN(b, 3600);
            Assert.Equal(StateHash.Compute(a), StateHash.Compute(b));
            Assert.True(a.Events.Total > 10, "a 60 s bot run should produce events");
        }

        [Fact]
        public void DifferentSeedDifferentHash()
        {
            Game a = SimTestHelpers.BotGame(7), b = SimTestHelpers.BotGame(8);
            SimTestHelpers.StepN(a, 3600);
            SimTestHelpers.StepN(b, 3600);
            Assert.NotEqual(StateHash.Compute(a), StateHash.Compute(b));
        }

        [Fact]
        public void HashChangesEveryTick()
        {
            Game a = SimTestHelpers.BotGame(7);
            ulong prev = StateHash.Compute(a);
            for (int i = 0; i < 10; i++)
            {
                a.Step(default);
                ulong h = StateHash.Compute(a);
                Assert.NotEqual(prev, h);
                prev = h;
            }
        }
    }

    [Trait("Category", "Perf")]
    public class PerfTests
    {
        private readonly ITestOutputHelper _out;
        public PerfTests(ITestOutputHelper output) { _out = output; }

        [Theory]
        [InlineData(1000)]
        [InlineData(2000)]
        public void StepBulletsUnderBudget(int bullets)
        {
            Game game = SimTestHelpers.BotGame(1);
            game.Arena.SpawnEnemies = false;
            game.Arena.DebugSpawnBullets(bullets);
            for (int i = 0; i < 60; i++) game.Step(default);   // warm up
            const int ticks = 600;
            var samples = new double[ticks];
            var sw = new Stopwatch();
            for (int i = 0; i < ticks; i++)
            {
                sw.Restart();
                game.Step(default);
                sw.Stop();
                samples[i] = sw.Elapsed.TotalMilliseconds;
            }
            Array.Sort(samples);
            double mean = 0; foreach (double d in samples) mean += d; mean /= ticks;
            _out.WriteLine("bullets " + bullets + " live " + game.Arena.Bullets.Live + ": mean " + mean.ToString("F3") + " ms, p50 " +
                           samples[ticks / 2].ToString("F3") + " ms, p99 " + samples[(int)(ticks * 0.99)].ToString("F3") + " ms");
            Assert.True(game.Arena.Bullets.Live >= bullets * 0.9f, "bullets did not stay alive: " + game.Arena.Bullets.Live);
            Assert.True(mean < 2.0, "mean " + mean + " ms per tick");
        }
    }
}
