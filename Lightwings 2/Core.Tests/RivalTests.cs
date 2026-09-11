using System;
using System.Collections.Generic;
using System.Linq;
using Lightship.Core;
using Lightship.Core.Ai;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Xunit;

namespace Lightship.Core.Tests
{
    /// <summary>
    /// Spec 8 rivals: decisions, not patterns, within human-like limits (150-300 ms
    /// reaction, 2-5 degree aim error), with visible intent (aim lines, obvious retreat),
    /// grabbing light, preferring the biggest target, and fighting each other.
    /// </summary>
    public class RivalTests
    {
        private const string Scorch = "fire_t3_scorch";

        /// <summary>A quiet sandbox with the idle player at the centre and one rival to its right.</summary>
        private static (Game game, Ship rival, RivalPilot pilot) Duel(ulong pilotSeed = 3, float distance = 300f, Tuning t = null)
        {
            Game game = SimTestHelpers.QuietGame(1, t);
            var pilot = new RivalPilot(game.T, pilotSeed);
            Ship rival = game.Arena.SpawnRival(SimTestHelpers.Catalog().Get(Scorch), game.Arena.Centre + new Vec2(distance, 0f), pilot);
            return (game, rival, pilot);
        }

        [Fact]
        public void ReactionDelayIsWithin150To300Ms()
        {
            var t = new Tuning();
            var delays = Enumerable.Range(1, 300).Select(s => new RivalPilot(t, (ulong)s).DelayTicks).ToList();
            Assert.Equal(9, delays.Min());          // 150 ms
            Assert.Equal(18, delays.Max());         // 300 ms
            Assert.True(delays.Distinct().Count() >= 8, "delays barely vary");
        }

        /// <summary>
        /// Two identical duels; in one a bullet is fired at the rival from 250 units. The rivals
        /// must decide identically until the bullet is DelayTicks old (it does not exist for the
        /// rival yet), and the threatened one must then dodge. A zero-delay control dodges at once,
        /// which is what gives this test its teeth.
        /// </summary>
        [Fact]
        public void BulletsYoungerThanTheDelayAreInvisible()
        {
            int FirstDivergence(Tuning t, out int delay)
            {
                var (a, ra, pa) = Duel(5, 300f, t);
                var (b, rb, _) = Duel(5, 300f, t);
                delay = pa.DelayTicks;
                SimTestHelpers.StepN(a, 30);
                SimTestHelpers.StepN(b, 30);
                long t0 = b.Arena.Tick;
                // A row of bullets 250 units up, across where the rival will be when they arrive:
                // it moves ~100 units in that time, so one bullet at where it stood simply misses.
                Vec2 ahead = rb.Pos + rb.Vel * 0.45f;
                for (int k = -5; k <= 5; k++)
                    b.Arena.SpawnBullet(Sides.Player, Element.Corruption, ahead + new Vec2(k * 20f, -250f), new Vec2(0f, 520f), 2.5f, 10f, 120);
                for (int i = 1; i <= 40; i++)
                {
                    a.Step(default);
                    b.Step(default);
                    Vec2 ma = ra.LastInput.Move, mb = rb.LastInput.Move;
                    if (MathF.Abs(ma.X - mb.X) > 1e-5f || MathF.Abs(ma.Y - mb.Y) > 1e-5f) return (int)(b.Arena.Tick - t0);
                }
                return -1;
            }

            int seen = FirstDivergence(new Tuning(), out int d);
            Assert.True(seen >= d, "reacted after " + seen + " ticks with a " + d + "-tick delay");
            Assert.True(seen > 0 && seen <= d + 3, "never dodged (or far too late): " + seen);

            var instant = new Tuning { RivalDelayMinTicks = 0, RivalDelayMaxTicks = 0 };
            int control = FirstDivergence(instant, out int d0);
            Assert.Equal(0, d0);
            Assert.True(control >= 0 && control < seen, "the zero-delay control reacted at " + control + ", the delayed rival at " + seen);
        }

        /// <summary>Against a still target the only aim error is the burst's: its magnitude is 2-5 degrees and it changes between bursts.</summary>
        [Fact]
        public void AimErrorIsTwoToFiveDegreesPerBurst()
        {
            var (game, rival, pilot) = Duel(7, 150f);
            Ship target = game.Arena.Player;
            target.MaxHp = target.Hp = 1e6f;
            var errors = new List<float>();
            int lastBursts = 0;
            for (int i = 0; i < 60 * 40 && errors.Count < 12; i++)
            {
                game.Step(default);
                if (!rival.Alive || !target.Alive) break;
                if (pilot.Bursts == lastBursts || rival.Retreating) continue;
                lastBursts = pilot.Bursts;
                // Facing is this tick's aim, decided from the position before the move (PrevPos).
                Vec2 truth = (target.Pos - rival.PrevPos).Normalized();
                float err = MathF.Atan2(Vec2.Cross(truth, rival.Facing), Vec2.Dot(truth, rival.Facing)) * 180f / MathF.PI;
                Assert.Equal(pilot.AimErrorDeg, err, 1);
                errors.Add(MathF.Abs(err));
            }
            Assert.True(errors.Count >= 6, "only " + errors.Count + " bursts in 40 s");
            Assert.All(errors, e => Assert.InRange(e, 1.95f, 5.05f));
            Assert.True(errors.Max() - errors.Min() > 0.5f, "the error never changed between bursts");
        }

        /// <summary>
        /// Spec 8/9: every burst has its OWN aim line, shown at least RivalAimLineTicks (0.5 s)
        /// before its first shot and still showing while it fires; no weapon shot ever leaves
        /// without a line up. Bursts are counted where the pilot starts them, not by volleys.
        /// </summary>
        [Fact]
        public void EveryBurstHasItsOwnAimLineHalfASecondAhead()
        {
            var (game, rival, pilot) = Duel(9, 150f);
            Ship player = game.Arena.Player;
            player.MaxHp = player.Hp = 1e6f;   // the target must outlive the test
            var events = new List<GameEvent>();
            long lastLine = long.MinValue, seq = 0;
            int lastBursts = 0, checkedBursts = 0, shotsWithoutLine = 0;
            for (int i = 0; i < 60 * 40; i++)
            {
                game.Step(default);
                long now = game.Arena.Tick;
                game.Events.Since(seq, events);
                seq = game.Events.Total;
                foreach (GameEvent e in events)
                    if (e.Kind == EventKind.AimLine && e.ShipId == rival.Id) lastLine = e.Tick;
                if (pilot.Bursts > lastBursts)
                {
                    lastBursts = pilot.Bursts;
                    Assert.True(lastLine > long.MinValue, "burst " + pilot.Bursts + " had no aim line of its own");
                    Assert.True(now - lastLine >= game.T.RivalAimLineTicks, "burst " + pilot.Bursts + " only " + (now - lastLine) + " ticks after its line");
                    lastLine = long.MinValue;   // the next burst needs its own line
                    checkedBursts++;
                }
                // The weapon's shots (fast); the burning trail's embers (slow) are not "firing".
                BulletPool b = game.Arena.Bullets;
                for (int k = 0; k < b.High; k++)
                    if (b.Alive[k] && b.OwnerId[k] == rival.Id && b.Born[k] == now && b.VX[k] * b.VX[k] + b.VY[k] * b.VY[k] > 100f * 100f
                        && now >= rival.AimLineUntil)
                        shotsWithoutLine++;
            }
            Assert.Equal(0, shotsWithoutLine);
            Assert.True(checkedBursts >= 4, "only " + checkedBursts + " bursts");
        }

        /// <summary>Spec 8 "retreat to regenerate when low": in below RivalRetreatBelow, out only at RivalRecoverAbove (hysteresis), obviously.</summary>
        [Fact]
        public void RetreatsBelow35PercentStopsShootingAndComesBackAbove70()
        {
            var (game, rival, pilot) = Duel(11, 250f);
            Tuning t = game.T;
            SimTestHelpers.StepN(game, 20);
            void At(float frac)
            {
                rival.Hp = rival.MaxHp * frac;
                rival.LastDamageTick = game.Arena.Tick;   // no regen during the probe
                game.Step(default);
            }
            At(t.RivalRetreatBelow + 0.01f);
            Assert.False(rival.Retreating);
            At(t.RivalRetreatBelow - 0.01f);
            Assert.True(rival.Retreating);
            Assert.Equal(1, pilot.Retreats);
            Ship player = game.Arena.Player;
            for (int i = 0; i < 90; i++)
            {
                At(t.RivalRetreatBelow - 0.01f);
                Vec2 toPlayer = player.Pos - rival.PrevPos;
                Assert.True(Vec2.Dot(rival.LastInput.Move, toPlayer) <= 0f, "moved toward the player while retreating");
                Assert.False(rival.LastInput.Fire);
            }
            // The hysteresis: back above the trigger is not enough.
            At(0.5f);
            Assert.True(rival.Retreating);
            At(t.RivalRecoverAbove - 0.01f);
            Assert.True(rival.Retreating);
            At(t.RivalRecoverAbove);
            Assert.False(rival.Retreating);
            Assert.Equal(1, pilot.Retreats);
        }

        /// <summary>
        /// The reaction delay covers noticing: a target that comes into view is adopted only
        /// DelayTicks later. The zero-delay control adopts it on the first tick.
        /// </summary>
        [Fact]
        public void ANewTargetIsNoticedOnlyAfterTheDelay()
        {
            int Adopted(Tuning t, out int delay, out int playerId)
            {
                Game game = SimTestHelpers.QuietGame(1, t);
                game.Arena.Player.Pos = game.Arena.Player.PrevPos = new Vec2(100f, 100f);
                var pilot = new RivalPilot(game.T, 23);
                delay = pilot.DelayTicks;
                Ship rival = game.Arena.SpawnRival(SimTestHelpers.Catalog().Get(Scorch), new Vec2(1900f, 1000f), pilot);
                SimTestHelpers.StepN(game, 20);
                Assert.Equal(-1, pilot.TargetId);                      // beyond perception
                game.Arena.Player.Pos = game.Arena.Player.PrevPos = rival.Pos + new Vec2(-400f, 0f);
                playerId = game.Arena.Player.Id;
                for (int k = 1; k <= 40; k++)
                {
                    game.Step(default);
                    if (pilot.TargetId == playerId) return k;
                }
                return -1;
            }
            int seen = Adopted(new Tuning(), out int d, out _);
            Assert.Equal(d + 1, seen);
            int instant = Adopted(new Tuning { RivalDelayMinTicks = 0, RivalDelayMaxTicks = 0 }, out int d0, out _);
            Assert.Equal(0, d0);
            Assert.Equal(1, instant);
        }

        [Fact]
        public void RivalsRegenerateWhenLeftAlone()
        {
            var (game, rival, _) = Duel(13, 1000f);
            rival.Hp = rival.MaxHp * 0.5f;
            rival.LastDamageTick = game.Arena.Tick;
            SimTestHelpers.StepN(game, game.T.RegenDelayTicks - 5);
            Assert.Equal(rival.MaxHp * 0.5f, rival.Hp, 3);
            SimTestHelpers.StepN(game, 65);
            Assert.True(rival.Hp > rival.MaxHp * 0.55f, "hp " + rival.Hp);
        }

        [Fact]
        public void RivalsGrabLightAndItHealsThem()
        {
            var (game, rival, _) = Duel(15, 900f);
            rival.Hp = rival.MaxHp * 0.8f;
            rival.LastDamageTick = game.Arena.Tick;
            int pk = game.Arena.SpawnPickup(Element.Fire, 1, rival.Pos, false);
            // Fresh light is not on offer yet (not its own shed light): nothing for RivalGrabMinAgeTicks.
            game.Step(default);
            Assert.True(game.Arena.Pickups.Alive[pk]);
            game.Arena.Pickups.X[pk] = rival.Pos.X; game.Arena.Pickups.Y[pk] = rival.Pos.Y;
            float before = rival.Hp;
            SimTestHelpers.StepUntil(game, g => !g.Arena.Pickups.Alive[pk], game.T.RivalGrabMinAgeTicks + 30);
            Assert.False(game.Arena.Pickups.Alive[pk]);
            Assert.Equal(1, game.Events.Count(EventKind.RivalAbsorb));
            Assert.True(rival.Hp >= before + 5f * game.T.RivalHealPerEnergy - 0.01f, "healed " + (rival.Hp - before));
            Assert.Equal(0f, game.Run.Energy);
        }

        [Fact]
        public void RivalsPreferTheBiggestTargetNearThem()
        {
            Game game = SimTestHelpers.QuietGame();
            ShipCatalog cat = SimTestHelpers.Catalog();
            Arena a = game.Arena;
            game.Arena.Player.Pos = new Vec2(100f, 100f);           // far away (beyond perception)
            var pilot = new RivalPilot(game.T, 17);
            var at = new Vec2(1900f, 1000f);
            Ship rival = a.SpawnRival(cat.Get(Scorch), at, pilot);
            Ship small = a.SpawnEnemy(cat.Get("corruption_t1_glitch"), at + new Vec2(-150f, 0f), Sim.Patterns.PatternLibrary.SporeBurst(1));
            Ship big = a.SpawnEnemy(cat.Get("corruption_t3_trojan"), at + new Vec2(0f, -350f), Sim.Patterns.PatternLibrary.SporeBurst(3));
            // It notices after its reaction delay, and what it picks is the big one.
            SimTestHelpers.StepN(game, pilot.DelayTicks + 1);
            Assert.Equal(big.Id, pilot.TargetId);
            // Kill the big one: it settles for the small one (again after the delay).
            a.Damage(big, 1e6f, Sides.Player, big.Pos, true);
            SimTestHelpers.StepN(game, pilot.DelayTicks + 2);
            Assert.Equal(small.Id, pilot.TargetId);
        }

        /// <summary>
        /// Spec 8: rivals are hostile to each other and pick each other as targets. The corruption
        /// rival out-ranges the fire one (spores reach 624, flame 180) and kites it, so the damage
        /// in this duel flows one way; the player is idle and out of both rivals' perception.
        /// </summary>
        [Fact]
        public void RivalsTargetAndDamageEachOther()
        {
            Game game = SimTestHelpers.QuietGame();
            ShipCatalog cat = SimTestHelpers.Catalog();
            Arena a = game.Arena;
            game.Arena.Player.Pos = new Vec2(100f, 100f);
            var firePilot = new RivalPilot(game.T, 19);
            var corrPilot = new RivalPilot(game.T, 21);
            Ship fire = a.SpawnRival(cat.Get(Scorch), new Vec2(1700f, 900f), firePilot);
            Ship corr = a.SpawnRival(cat.Get("corruption_t3_trojan"), new Vec2(1950f, 900f), corrPilot);
            Assert.True(Sides.Hostile(fire.Side, corr.Side));
            SimTestHelpers.StepN(game, 60 * 12);
            Assert.Equal(corr.Id, firePilot.TargetId);
            Assert.Equal(fire.Id, corrPilot.TargetId);
            Assert.True(fire.Hp < fire.MaxHp * 0.9f || !fire.Alive, "the corruption rival never hurt the fire rival: hp " + fire.Hp);
            Assert.Equal(0f, game.Run.Energy);            // nobody's kills pay the player
        }
    }
}
