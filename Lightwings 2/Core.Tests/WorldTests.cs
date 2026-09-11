using System.Collections.Generic;
using System.Linq;
using Lightship.Core;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Lightship.Core.World;
using Xunit;

namespace Lightship.Core.Tests
{
    /// <summary>Spec 7 and 19 (M2): the grid, layers, veils, the gate's lock-in, territory, death and teleport.</summary>
    public class WorldTests
    {
        private static readonly SectorCoord Gate = new SectorCoord(2, 0);

        /// <summary>A world game flown by a pilot that always returns the same intent (idle by default).</summary>
        private static (Game game, StaticPilot pilot) WorldGame(ulong seed = 1, Tuning t = null)
        {
            var pilot = new StaticPilot();
            var game = new Game(t ?? new Tuning(), SimTestHelpers.Catalog(), seed, Game.DefaultSeedShip, pilot, GameMode.World);
            return (game, pilot);
        }

        private static List<GameEvent> EventsOf(Game game, EventKind kind)
        {
            var all = new List<GameEvent>();
            game.Events.Since(0, all);
            return all.Where(e => e.Kind == kind).ToList();
        }

        [Fact]
        public void LayerIsChebyshevDistanceFromTheOrigin()
        {
            Assert.Equal(0, new SectorCoord(0, 0).Layer);
            Assert.Equal(1, new SectorCoord(1, -1).Layer);
            Assert.Equal(1, new SectorCoord(0, 1).Layer);
            Assert.Equal(2, new SectorCoord(2, -1).Layer);
            Assert.Equal(2, new SectorCoord(-2, 2).Layer);
        }

        [Fact]
        public void TheM2WorldIsFiveByFiveWithOneGateAndTwoContiguousRivals()
        {
            WorldGrid w = WorldGrid.Build(new Tuning());
            Assert.Equal(25, w.Sectors.Count);
            Assert.Equal(Element.None, w[WorldGrid.Origin].Owner);
            Assert.Equal(0, w[WorldGrid.Origin].EnemyCount);
            Sector[] gates = w.All.Where(s => s.IsGate).ToArray();
            Assert.Single(gates);
            Assert.Equal(Gate, gates[0].Coord);
            Assert.Equal("fire_t3_scorch", gates[0].GatekeeperShip);
            Assert.Equal(3, gates[0].ThreatTier(SimTestHelpers.Catalog()));
            Assert.Contains(w.All, s => s.Owner == Element.Fire);
            Assert.Contains(w.All, s => s.Owner == Element.Corruption);
            Assert.True(w.RegionsContiguous(new Meta()));
            // Difficulty scales by layer (spec 7/8): layer n holds tier-n enemies, more of them further out.
            foreach (Sector s in w.All.Where(s => s.Layer > 0 && !s.IsGate))
            {
                Assert.Equal(s.Layer, s.EnemyTier);
                Assert.Equal(4 + 2 * s.Layer, s.EnemyCount);
            }
        }

        [Fact]
        public void TheVeilNeedsItsThresholdAndOnlyTheGateCrossesIt()
        {
            WorldGrid w = WorldGrid.Build(new Tuning());
            var meta = new Meta();
            Assert.Equal(CrossResult.VeilNeedsEnergy, w.CanCross(new SectorCoord(1, 0), Gate, 299f, false, meta));
            Assert.Equal(CrossResult.Ok, w.CanCross(new SectorCoord(1, 0), Gate, 300f, false, meta));
            Assert.Equal(CrossResult.VeilOnlyGates, w.CanCross(new SectorCoord(1, 1), new SectorCoord(2, 1), 5000f, false, meta));
            // Layer 0 to 1 is open; sideways and inward moves are always free; the grid has an edge.
            Assert.Equal(CrossResult.Ok, w.CanCross(WorldGrid.Origin, new SectorCoord(0, 1), 0f, false, meta));
            Assert.Equal(CrossResult.Ok, w.CanCross(new SectorCoord(1, 0), new SectorCoord(1, 1), 0f, false, meta));
            Assert.Equal(CrossResult.Ok, w.CanCross(new SectorCoord(2, 1), new SectorCoord(1, 1), 0f, false, meta));
            Assert.Equal(CrossResult.WorldEdge, w.CanCross(Gate, new SectorCoord(3, 0), 5000f, false, meta));
            Assert.Equal(CrossResult.LockedIn, w.CanCross(Gate, new SectorCoord(1, 0), 5000f, true, meta));
        }

        [Fact]
        public void FlyingIntoAnEdgeCrossesAfterTheDwellButABrushDoesNot()
        {
            var (game, pilot) = WorldGame();
            Tuning t = game.T;
            // A brush: touch the north edge for fewer ticks than the dwell, then let go.
            game.Arena.Player.Pos = new Vec2(1200f, 1f);
            pilot.Input.Move = new Vec2(0f, -1f);
            SimTestHelpers.StepN(game, t.CrossDwellTicks - 2);
            pilot.Input.Move = Vec2.Zero;
            SimTestHelpers.StepN(game, 5);
            Assert.Equal(WorldGrid.Origin, game.Run.Sector);

            // A push: fly east until the edge, then keep pushing.
            pilot.Input.Move = new Vec2(1f, 0f);
            long atEdge = -1, crossed = -1;
            for (int i = 0; i < 60 * 12 && crossed < 0; i++)
            {
                game.Step(default);
                if (atEdge < 0 && game.Run.Sector == WorldGrid.Origin && game.Arena.Player.Pos.X >= game.Arena.Width) atEdge = game.Tick;
                if (game.Run.Sector != WorldGrid.Origin) crossed = game.Tick;
            }
            Assert.True(atEdge > 0 && crossed > 0, "never reached or crossed the edge");
            Assert.Equal(t.CrossDwellTicks - 1, crossed - atEdge);
            Assert.Equal(new SectorCoord(1, 0), game.Run.Sector);
            Assert.Equal(t.SectorEntryInset, game.Arena.Player.Pos.X, 3);
            Assert.Contains(new SectorCoord(1, 0), game.Meta.Explored);
        }

        [Fact]
        public void TheVeilHoldsBelowItsThresholdAndSaysWhy()
        {
            var (game, pilot) = WorldGame();
            game.Run.Warp(new SectorCoord(1, 0));
            game.Arena.SpawnEnemies = false;
            game.Arena.Player.Pos = new Vec2(game.Arena.Width - 2f, 675f);
            pilot.Input.Move = new Vec2(1f, 0f);
            SimTestHelpers.StepN(game, 120);
            Assert.Equal(new SectorCoord(1, 0), game.Run.Sector);
            List<GameEvent> blocked = EventsOf(game, EventKind.CrossBlocked);
            Assert.NotEmpty(blocked);
            Assert.All(blocked, e => Assert.Equal((float)(int)CrossResult.VeilNeedsEnergy, e.Value));
            Assert.Equal(CrossResult.VeilNeedsEnergy, game.Run.EdgeResult(Edge.East));
            Assert.True(game.Run.EdgeIntoGate(Edge.East));

            // With the threshold met the same push goes through, into the gate.
            game.Run.Energy = 300f;
            SimTestHelpers.StepN(game, game.T.CrossDwellTicks + 2);
            Assert.Equal(Gate, game.Run.Sector);
        }

        [Fact]
        public void TheGateLocksEveryExitUntilItsGatekeeperFalls()
        {
            var (game, pilot) = WorldGame();
            game.Run.Warp(Gate);
            Run run = game.Run;
            Assert.True(run.LockedIn);
            Ship keeper = run.Arena.Gatekeeper;
            Assert.NotNull(keeper);
            Assert.Equal(Faction.Rival, keeper.Faction);
            Assert.Equal("fire_t3_scorch", keeper.Def.Id);
            foreach (Edge e in Edges.All)
                Assert.True(run.EdgeResult(e) == CrossResult.LockedIn || run.EdgeResult(e) == CrossResult.WorldEdge);

            // Push the inward edge: it holds.
            run.Arena.Player.Pos = new Vec2(1f, 675f);
            pilot.Input.Move = new Vec2(-1f, 0f);
            SimTestHelpers.StepN(game, 60);
            Assert.Equal(Gate, run.Sector);
            Assert.Contains(EventsOf(game, EventKind.CrossBlocked), e => e.Value == (int)CrossResult.LockedIn);

            // The gatekeeper falls: the gate opens for good and becomes a checkpoint.
            run.Arena.Damage(keeper, 1e6f, Sides.Player, keeper.Pos, true);
            game.Step(default);
            Assert.False(run.LockedIn);
            Assert.Contains(Gate, game.Meta.BeatenGates);
            Assert.Contains(Gate, game.Meta.Checkpoints);
            Assert.Contains(Gate, game.Meta.PlayerTerritory);
            Assert.Single(EventsOf(game, EventKind.GateBeaten));
            SimTestHelpers.StepN(game, game.T.CrossDwellTicks + 2);
            Assert.Equal(new SectorCoord(1, 0), game.Run.Sector);
        }

        [Fact]
        public void TheGateWarnsBeforeEntryNotAfter()
        {
            var (game, pilot) = WorldGame();
            game.Run.Warp(new SectorCoord(1, 0));
            game.Arena.SpawnEnemies = false;
            game.Run.Energy = 300f;
            pilot.Input.Move = new Vec2(1f, 0f);
            SimTestHelpers.StepUntil(game, g => g.Run.Sector == Gate, 60 * 20);
            GameEvent warning = EventsOf(game, EventKind.GateWarning).Single();
            GameEvent locked = EventsOf(game, EventKind.GateLocked).Single();
            Assert.Equal(new Vec2(Gate.X, Gate.Y), warning.To);
            // At least a second of warning while flying straight at it (420 units at 260 u/s, plus the dwell).
            Assert.True(locked.Tick - warning.Tick >= 60, "warned only " + (locked.Tick - warning.Tick) + " ticks before the lock-in");
        }

        [Fact]
        public void ClearingASectorMakesItPlayerTerritoryForGood()
        {
            var (game, _) = WorldGame();
            var at = new SectorCoord(-1, 0);
            game.Run.Warp(at);
            int budget = game.Arena.EnemyBudget;
            Assert.Equal(game.World[at].EnemyCount, budget);
            for (int i = 0; i < 60 * 90 && !game.Run.Life(at).Cleared; i++)
            {
                game.Step(default);
                foreach (Ship s in game.Arena.Ships.ToList())
                    if (s.Alive && s.Faction == Faction.Enemy) game.Arena.Damage(s, 1e6f, Sides.Player, s.Pos, true);
            }
            Assert.True(game.Run.Life(at).Cleared);
            Assert.Equal(budget, game.Arena.EnemiesSpawned);
            Assert.Contains(at, game.Meta.PlayerTerritory);
            GameEvent cleared = EventsOf(game, EventKind.SectorCleared).Single();
            Assert.Equal(1f, cleared.Value);

            // It stays the player's through death, and drift never takes it. The next life finds it
            // quiet (no garrison comes back) with its ambient light still flowing (regrowth ground).
            game.Die();
            Assert.Contains(at, game.Meta.PlayerTerritory);
            Assert.Equal(Element.Corruption, game.World[at].Owner);
            SectorSetup next = game.Run.SetupFor(at);
            Assert.Equal(0, next.EnemyBudget);
            Assert.Equal(Element.Corruption, next.Light);
            Assert.True(next.LightPool > 0f);
            Assert.DoesNotContain(game.World.RadiationNear(WorldGrid.Origin, 1, SimTestHelpers.Catalog(), game.Meta), r => r.Coord == at);
        }

        [Fact]
        public void ASectorRemembersItsDeadWithinOneLife()
        {
            var (game, _) = WorldGame();
            var at = new SectorCoord(-1, 0);
            game.Run.Warp(at);
            SimTestHelpers.StepUntil(game, g => g.Arena.AliveRegulars() >= 2, 60 * 10);
            int killed = 0;
            foreach (Ship s in game.Arena.Ships.ToList())
                if (s.Alive && s.Faction == Faction.Enemy && killed < 2) { game.Arena.Damage(s, 1e6f, Sides.Player, s.Pos, true); killed++; }
            game.Run.Warp(WorldGrid.Origin);
            game.Run.Warp(at);
            Assert.Equal(game.World[at].EnemyCount - 2, game.Arena.EnemyBudget);
            // A new life forgets it.
            game.Die();
            Assert.Equal(game.World[at].EnemyCount, game.Run.SetupFor(at).EnemyBudget);
        }

        [Fact]
        public void TheOriginIsSafeAndDark()
        {
            var (game, _) = WorldGame();
            SimTestHelpers.StepN(game, 60 * 60);
            Assert.Equal(WorldGrid.Origin, game.Run.Sector);
            Assert.Equal(0, game.Arena.EnemiesSpawned);
            Assert.Equal(0, game.Arena.Pickups.Live);
            Assert.Equal(0, game.Meta.Deaths);
        }

        [Fact]
        public void DeathKeepsTheMetaAndResetsTheRun()
        {
            var (game, _) = WorldGame();
            game.Run.Warp(Gate);
            Ship keeper = game.Arena.Gatekeeper;
            game.Arena.Damage(keeper, 1e6f, Sides.Player, keeper.Pos, true);
            game.Step(default);
            game.Run.Energy = 900f;
            long tickBefore = game.Arena.Tick;
            int explored = game.Meta.Explored.Count;

            game.Arena.DamagePlayer(1e6f, game.Arena.Player.Pos);
            game.Step(default);

            Run run = game.Run;
            Assert.Equal(1, game.Meta.Deaths);
            Assert.Equal(0f, run.Energy);
            Assert.Equal(1, run.Tier);
            Assert.Equal(WorldGrid.Origin, run.Sector);
            Assert.Equal(Game.DefaultSeedShip + "_player", run.Ship.Id);
            Assert.False(run.LockedIn);
            Assert.Contains(Gate, game.Meta.Checkpoints);
            Assert.Contains(Gate, game.Meta.BeatenGates);
            Assert.Contains(Gate, game.Meta.PlayerTerritory);
            Assert.Equal(explored, game.Meta.Explored.Count);
            // The clock carries on through death: no absolute-tick timer outlives it.
            Assert.True(run.Arena.Tick >= tickBefore, "arena tick went back from " + tickBefore + " to " + run.Arena.Tick);
        }

        [Fact]
        public void TeleportNeedsACheckpointItsThresholdAndNoLockIn()
        {
            var (game, _) = WorldGame();
            Run run = game.Run;
            run.Energy = 1000f;
            Assert.False(run.TryTeleport(Gate));                    // not a checkpoint yet
            game.Meta.Checkpoints.Add(Gate);
            game.Meta.BeatenGates.Add(Gate);
            run.Energy = 299f;
            Assert.False(run.TryTeleport(Gate));                    // below the layer's veil
            run.Energy = 300f;
            Assert.True(run.TryTeleport(Gate));
            Assert.Equal(Gate, run.Sector);
            Assert.False(run.LockedIn);                             // a beaten gate does not lock
            Assert.Single(EventsOf(game, EventKind.Teleported));

            // Never out of a lock-in.
            var (g2, _) = WorldGame(2);
            g2.Run.Warp(Gate);
            g2.Meta.Checkpoints.Add(new SectorCoord(1, 0));
            g2.Run.Energy = 1000f;
            Assert.False(g2.Run.TryTeleport(new SectorCoord(1, 0)));
        }

        [Fact]
        public void TeleportIsAnIntentThePilotCanSend()
        {
            var (game, pilot) = WorldGame();
            game.Meta.Checkpoints.Add(Gate);
            game.Meta.BeatenGates.Add(Gate);
            game.Run.Energy = 300f;
            pilot.Input.Teleport = true;
            pilot.Input.TeleportTarget = Gate;
            game.Step(default);
            Assert.Equal(Gate, game.Run.Sector);
        }

        [Fact]
        public void BordersDriftButNeverTerritoryGatesOrTheOriginAndRegionsStayWhole()
        {
            int flips = 0;
            for (ulong seed = 1; seed <= 200; seed++)
            {
                WorldGrid w = WorldGrid.Build(new Tuning());
                var meta = new Meta();
                meta.PlayerTerritory.Add(new SectorCoord(0, -1));
                meta.PlayerTerritory.Add(new SectorCoord(-1, 1));
                var owners = w.All.ToDictionary(s => s.Coord, s => s.Owner);
                var rng = new DeterministicRandom(seed);
                for (int life = 0; life < 6; life++)
                {
                    var before = w.All.ToDictionary(s => s.Coord, s => s.Owner);
                    List<SectorCoord> changed = w.DriftBorders(rng, meta, 3);
                    flips += changed.Count;
                    // Every reported flip is a different sector that really changed hands.
                    Assert.Equal(changed.Count, changed.Distinct().Count());
                    Assert.All(changed, c => Assert.NotEqual(before[c], w[c].Owner));
                    Assert.Equal(changed.Count, w.All.Count(s => before[s.Coord] != s.Owner));
                    Assert.True(w.RegionsContiguous(meta), "seed " + seed + " split a region");
                    // A rival only wins land next to land it holds at that moment, never across the
                    // player's territory (checked one flip at a time: a later flip may take the neighbour).
                    List<SectorCoord> one = w.DriftBorders(rng, meta, 1);
                    flips += one.Count;
                    Assert.All(one, c => Assert.Contains(Edges.All, e => w[c.Step(e)] is Sector n &&
                        WorldGrid.IsRivalLand(n, meta) && n.Owner == w[c].Owner));
                    Assert.True(w.RegionsContiguous(meta), "seed " + seed + " split a region");
                    foreach (SectorCoord c in meta.PlayerTerritory) Assert.Equal(owners[c], w[c].Owner);
                    Assert.Equal(owners[Gate], w[Gate].Owner);
                    Assert.Equal(Element.None, w[WorldGrid.Origin].Owner);
                    Assert.Contains(w.All, s => s.Owner == Element.Fire);
                    Assert.Contains(w.All, s => s.Owner == Element.Corruption);
                }
            }
            Assert.True(flips > 200, "borders barely moved: " + flips + " flips in 1200 lives");
        }

        [Fact]
        public void RadiationMarksSectorsAboveThePlayersTierWithinThree()
        {
            WorldGrid w = WorldGrid.Build(new Tuning());
            var meta = new Meta();
            List<Radiation> r = w.RadiationNear(WorldGrid.Origin, 1, SimTestHelpers.Catalog(), meta);
            Assert.Equal(16, r.Count);                               // every layer-2 sector: tier 2 (+1), the gate tier 3 (+2)
            Assert.Equal(2, r.Single(x => x.Coord == Gate).Gap);
            Assert.All(r.Where(x => x.Coord != Gate), x => Assert.Equal(1, x.Gap));
            Assert.All(r, x => Assert.Equal(w[x.Coord].Owner, x.Light));
            // Within three sectors only.
            Assert.DoesNotContain(w.RadiationNear(new SectorCoord(-2, 0), 1, SimTestHelpers.Catalog(), meta), x => x.Coord == new SectorCoord(2, 0));
            // A beaten gate and player territory radiate nothing; a tier-3 player sees no gap.
            meta.BeatenGates.Add(Gate);
            meta.PlayerTerritory.Add(new SectorCoord(2, 1));
            List<Radiation> after = w.RadiationNear(WorldGrid.Origin, 1, SimTestHelpers.Catalog(), meta);
            Assert.DoesNotContain(after, x => x.Coord == Gate || x.Coord == new SectorCoord(2, 1));
            Assert.Empty(w.RadiationNear(WorldGrid.Origin, 3, SimTestHelpers.Catalog(), new Meta()));
        }

        [Fact]
        public void RoutesUseOnlyLegalCrossings()
        {
            WorldGrid w = WorldGrid.Build(new Tuning());
            var meta = new Meta();
            Assert.Empty(w.Route(WorldGrid.Origin, Gate, 299f, meta));
            List<SectorCoord> route = w.Route(WorldGrid.Origin, Gate, 300f, meta);
            Assert.Equal(new[] { new SectorCoord(1, 0), Gate }, route);
            // Beyond the veil only through the gate: (2,2) is reached via (2,0).
            List<SectorCoord> far = w.Route(WorldGrid.Origin, new SectorCoord(2, 2), 300f, meta);
            Assert.Contains(Gate, far);
        }

        [Fact]
        public void WorldGamesAreDeterministic()
        {
            Game a = Game.NewWorld(new Tuning(), SimTestHelpers.Catalog(), 7, Ai.BotSkill.Perfect());
            Game b = Game.NewWorld(new Tuning(), SimTestHelpers.Catalog(), 7, Ai.BotSkill.Perfect());
            Game c = Game.NewWorld(new Tuning(), SimTestHelpers.Catalog(), 8, Ai.BotSkill.Perfect());
            for (int i = 0; i < 60 * 90; i++) { a.Step(default); b.Step(default); c.Step(default); }
            Assert.True(a.Meta.Explored.Count > 2, "the bot explored " + a.Meta.Explored.Count + " sectors");
            Assert.Equal(StateHash.Compute(a), StateHash.Compute(b));
            Assert.NotEqual(StateHash.Compute(a), StateHash.Compute(c));
        }
    }
}
