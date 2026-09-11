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
            // Spec 8: every form must be pilotable by a bot. Each seed flies, fires, kills and keeps its tier.
            ShipCatalog catalog = SimTestHelpers.Catalog();
            foreach (ShipDefinition def in catalog.All)
            {
                var game = new Game(new Tuning(), catalog, 3, def.Id, new BotPilot());
                Vec2 last = game.Arena.Player.Pos;
                float travelled = 0f;
                int trigger = 0;
                for (int i = 0; i < 3600; i++)
                {
                    game.Step(default);
                    travelled += Vec2.Distance(last, game.Arena.Player.Pos);
                    last = game.Arena.Player.Pos;
                    if (game.Arena.Player.LastInput.Fire) trigger++;
                }
                _out.WriteLine(def.Id + ": tier " + game.Run.Tier + ", travelled " + travelled.ToString("F0") + ", trigger ticks " + trigger +
                               ", energy " + game.Run.Energy.ToString("F0") + ", kills " + game.Events.Count(EventKind.Kill) + ", deaths " + game.Meta.Deaths);
                Assert.True(travelled > 500f, def.Id + " barely moved");
                Assert.True(trigger > 600, def.Id + " barely fired");
                Assert.True(game.Events.Count(EventKind.Kill) > 0, def.Id + " killed nothing");
                Assert.True(game.Run.Tier >= def.Tier || game.Meta.Deaths > 0, def.Id + " lost tier without dying");
            }
        }

        [Fact]
        public void DodgingTakesFewerHitsThanNotDodging()
        {
            // Differential on the dodge code alone: same seeds, same fighting, dodge on versus off.
            int withDodge = 0, without = 0;
            for (ulong seed = 11; seed < 16; seed++)
            {
                var a = new Game(new Tuning(), SimTestHelpers.Catalog(), seed, Game.DefaultSeedShip, new BotPilot { Dodge = true });
                var b = new Game(new Tuning(), SimTestHelpers.Catalog(), seed, Game.DefaultSeedShip, new BotPilot { Dodge = false });
                SimTestHelpers.StepN(a, 7200);
                SimTestHelpers.StepN(b, 7200);
                withDodge += a.Events.Count(EventKind.PlayerDamaged);
                without += b.Events.Count(EventKind.PlayerDamaged);
            }
            _out.WriteLine("hits over 5 x 120 s: dodging " + withDodge + ", not dodging " + without);
            Assert.True(withDodge < without, "dodging " + withDodge + " vs not " + without);
        }

        [Fact]
        public void NoviceStillEvolvesWithinTwoMinutes()
        {
            // Spec 5: tune so a NEW player's first evolution lands within 2 minutes. The novice
            // profile (10 degree aim error, 60 % trigger, 250 ms late, no dodging) is the floor.
            for (ulong seed = 1; seed <= 5; seed++)
            {
                var game = new Game(new Tuning(), SimTestHelpers.Catalog(), seed, Game.DefaultSeedShip, new BotPilot(seed) { Skill = BotSkill.Novice() });
                int ticks = SimTestHelpers.StepUntil(game, g => g.Events.Count(EventKind.Evolved) > 0, 7200);
                _out.WriteLine("novice seed " + seed + ": first evolution at " + (ticks >= 0 ? (ticks / 60f).ToString("F1") + " s" : "never") +
                               ", deaths " + game.Meta.Deaths);
                Assert.True(ticks >= 0, "novice seed " + seed + " did not evolve within 120 s");
            }
        }
    }
}
