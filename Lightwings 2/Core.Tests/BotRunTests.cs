using Lightship.Core.Ai;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Xunit;
using Xunit.Abstractions;

namespace Lightship.Core.Tests
{
    [Trait("Category", "Bot")]
    public class BotRunTests
    {
        private readonly ITestOutputHelper _out;
        public BotRunTests(ITestOutputHelper output) { _out = output; }

        [Fact]
        public void FirstEvolutionWithin120Seconds()
        {
            for (ulong seed = 1; seed <= 5; seed++)
            {
                Game game = SimTestHelpers.BotGame(seed);
                int ticks = SimTestHelpers.StepUntil(game, g => g.Events.Count(EventKind.Evolved) > 0, 7200);
                _out.WriteLine("seed " + seed + ": first evolution at " + (ticks >= 0 ? (ticks / 60f).ToString("F1") + " s" : "never") +
                               ", energy " + game.Run.Energy.ToString("F0") + ", kills " + game.Events.Count(EventKind.Kill) +
                               ", deaths " + game.Meta.Deaths);
                Assert.True(ticks >= 0 && ticks <= 7200, "seed " + seed + " did not evolve within 120 s (energy " + game.Run.Energy + ")");
            }
        }

        [Fact]
        public void EveryPlayerFormIsPilotable()
        {
            ShipCatalog catalog = SimTestHelpers.Catalog();
            foreach (ShipDefinition def in catalog.All)
            {
                var game = new Game(new Tuning(), catalog, 3, def.Id, new BotPilot());
                SimTestHelpers.StepN(game, 3600);
                _out.WriteLine(def.Id + ": 60 s piloted, energy " + game.Run.Energy.ToString("F0") + ", deaths " + game.Meta.Deaths);
                Assert.True(game.Tick == 3600);
            }
        }

        [Fact]
        public void BotDodgesMoreThanAStatue()
        {
            // Differential: the same seed with a statue (no input) takes more damage than the bot.
            var statue = new StaticPilot();
            var a = new Game(new Tuning(), SimTestHelpers.Catalog(), 11, Game.DefaultSeedShip, statue);
            var b = SimTestHelpers.BotGame(11);
            SimTestHelpers.StepN(a, 3600);
            SimTestHelpers.StepN(b, 3600);
            int statueHits = a.Events.Count(EventKind.PlayerDamaged);
            int botHits = b.Events.Count(EventKind.PlayerDamaged);
            _out.WriteLine("statue damaged " + statueHits + " times, bot " + botHits + " times in 60 s");
            Assert.True(botHits < statueHits, "bot " + botHits + " vs statue " + statueHits);
        }
    }
}
