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

        // ---- M2: the world ----

        private static BotSkill Skill(bool novice) => novice ? BotSkill.Novice() : BotSkill.Perfect();

        /// <summary>Spec 5 in the real game: the origin is safe, so the first evolution now includes leaving it.</summary>
        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void FirstEvolutionInTheWorldWithin120Seconds(bool novice)
        {
            for (ulong seed = 1; seed <= 3; seed++)
            {
                Game game = Game.NewWorld(new Tuning(), SimTestHelpers.Catalog(), seed, Skill(novice));
                int ticks = SimTestHelpers.StepUntil(game, g => g.Events.Count(EventKind.Evolved) > 0, 7200);
                _out.WriteLine((novice ? "novice" : "perfect") + " seed " + seed + ": first evolution in the world at " + (ticks / 60f).ToString("F1") + " s");
                Assert.True(ticks >= 0, "seed " + seed + " did not evolve within 120 s in the world");
            }
        }

        /// <summary>
        /// Spec 19 M2: a player gets through the veil by beating the gate's rival. The perfect bot
        /// must win the first time on every seed (measured 134-140 s, no deaths). The novice (no
        /// dodging) is a distribution: over 20 seeds 11 won first time and one needed four tries
        /// (727 s), so the gate asserts the median and that every novice gets through eventually.
        /// </summary>
        [Fact]
        public void ThePerfectBotBeatsTheGateFirstTime()
        {
            for (ulong seed = 1; seed <= 5; seed++)
            {
                Game game = Game.NewWorld(new Tuning(), SimTestHelpers.Catalog(), seed, Skill(false));
                int ticks = SimTestHelpers.StepUntil(game, g => g.Meta.BeatenGates.Count > 0, 300 * 60);
                _out.WriteLine("perfect seed " + seed + ": gate beaten at " + (ticks / 60f).ToString("F1") + " s, deaths " + game.Meta.Deaths);
                Assert.True(ticks >= 0, "seed " + seed + " did not beat the gate within 300 s");
                Assert.Equal(0, game.Meta.Deaths);
                Assert.Contains(new World.SectorCoord(2, 0), game.Meta.Checkpoints);
            }
        }

        [Fact]
        public void EveryNoviceGetsThroughTheGateAndHalfWithinFiveMinutes()
        {
            var times = new System.Collections.Generic.List<float>();
            for (ulong seed = 1; seed <= 20; seed++)
            {
                Game game = Game.NewWorld(new Tuning(), SimTestHelpers.Catalog(), seed, Skill(true));
                int ticks = SimTestHelpers.StepUntil(game, g => g.Meta.BeatenGates.Count > 0, 1200 * 60);
                _out.WriteLine("novice seed " + seed + ": gate beaten at " + (ticks / 60f).ToString("F1") + " s, deaths " + game.Meta.Deaths);
                Assert.True(ticks >= 0, "novice seed " + seed + " never got through the gate in 20 minutes");
                times.Add(ticks / 60f);
            }
            times.Sort();
            float median = (times[9] + times[10]) / 2f;
            _out.WriteLine("novice gate median " + median.ToString("F1") + " s, max " + times[19].ToString("F1") + " s");
            Assert.True(median <= 300f, "novice median " + median + " s");
        }

        /// <summary>
        /// Spec 7 and 19 M2: "a death costs minutes, not the run". After the gate, the bot is
        /// killed; the time until it stands in the checkpoint again (regrow to its veil, teleport)
        /// must be a few minutes. Measured 76-83 s (perfect), 84-92 s (novice).
        /// </summary>
        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void DeathCostsMinutesNotTheRun(bool novice)
        {
            var gate = new World.SectorCoord(2, 0);
            for (ulong seed = 1; seed <= 3; seed++)
            {
                Game game = Game.NewWorld(new Tuning(), SimTestHelpers.Catalog(), seed, Skill(novice));
                Assert.True(SimTestHelpers.StepUntil(game, g => g.Meta.BeatenGates.Count > 0, 1200 * 60) >= 0, "no gate to return to");
                game.Die();
                long diedSeq = game.Events.Total;
                Assert.Equal(0f, game.Run.Energy);
                Assert.Contains(gate, game.Meta.Checkpoints);
                Assert.Contains(gate, game.Meta.BeatenGates);
                int ticks = SimTestHelpers.StepUntil(game, g => g.Run.Sector == gate, 240 * 60);
                _out.WriteLine((novice ? "novice" : "perfect") + " seed " + seed + ": back at the checkpoint " + (ticks / 60f).ToString("F1") +
                               " s after the death, energy " + game.Run.Energy.ToString("F0") + ", deaths " + game.Meta.Deaths);
                Assert.True(ticks >= 0, "seed " + seed + " was not back at the checkpoint within 240 s of dying");
                // Back by the kept checkpoint and a teleport, into an open gate: not a walk into a fresh lock-in.
                var since = new System.Collections.Generic.List<GameEvent>();
                game.Events.Since(diedSeq, since);
                Assert.Contains(since, e => e.Kind == EventKind.Teleported && (int)e.To.X == gate.X && (int)e.To.Y == gate.Y);
                Assert.False(game.Run.LockedIn);
                Assert.Null(game.Arena.Gatekeeper);
            }
        }
    }
}
