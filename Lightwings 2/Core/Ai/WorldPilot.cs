using System.Collections.Generic;
using Lightship.Core.Sim;
using Lightship.Core.World;

namespace Lightship.Core.Ai
{
    /// <summary>
    /// The scripted player in the world: fights with a BotPilot while a sector has
    /// work in it, then flies out of the edge that leads toward its next goal. Goals,
    /// in order: jump to the furthest checkpoint it can afford; the gate once energy
    /// meets its veil; otherwise the nearest rival sector this life has not cleared, least
    /// threatening first; and when none is left, graze the ambient light of its own
    /// territory. Only legal crossings are planned (WorldGrid.Route), so the bot never
    /// learns anything the map does not show.
    /// </summary>
    public sealed class WorldPilot : IPilot
    {
        public readonly BotPilot Fighter;
        private readonly Game _game;
        public SectorCoord Goal { get; private set; }
        public bool Travelling { get; private set; }

        public WorldPilot(Game game, BotPilot fighter = null)
        {
            _game = game;
            Fighter = fighter ?? new BotPilot();
        }

        public PlayerInput Decide(Arena arena, Ship self)
        {
            PlayerInput input = Fighter.Decide(arena, self);
            Run run = _game.Run;
            WorldGrid world = run.World;
            Travelling = false;
            if (world == null || run.LockedIn) return input;

            // Work here first: hostiles, enemies still to arrive, or light dropped by kills.
            if (arena.NearestHostile(self.Pos, self.Side) != null) return input;
            if (arena.EnemyBudget > 0 && arena.EnemiesSpawned < arena.EnemyBudget) return input;
            int drop = NearestDrop(arena, self.Pos, 700f);
            if (drop >= 0)
            {
                input.Move = (new Vec2(arena.Pickups.X[drop], arena.Pickups.Y[drop]) - self.Pos).Normalized();
                return input;
            }

            Meta meta = run.Meta;
            SectorCoord? jump = TeleportTarget(run);
            if (jump.HasValue)
            {
                input.Teleport = true;
                input.TeleportTarget = jump.Value;
                Goal = jump.Value;
                return input;
            }

            SectorCoord? goal = ChooseGoal(run);
            if (!goal.HasValue)
            {
                // Nothing left to fight within reach: graze. Light here first, else a sector that has some.
                int pk = arena.NearestPickup(self.Pos, arena.Width + arena.Height);
                if (pk >= 0)
                {
                    input.Move = (new Vec2(arena.Pickups.X[pk], arena.Pickups.Y[pk]) - self.Pos).Normalized();
                    return input;
                }
                // Stay while this sector's pool still has light to shed; once it runs dry, move on.
                if (arena.SectorElement != Ships.Element.None && arena.LightPool >= GrazeLeaveBelow) return input;
                goal = RichestGrazing(run);
                if (!goal.HasValue) return input;
            }
            Goal = goal.Value;
            List<SectorCoord> route = world.Route(run.Sector, goal.Value, run.Energy, meta);
            if (route.Count == 0) return input;
            Edge e = WorldGrid.EdgeToward(run.Sector, route[0]);
            Vec2 exit;
            switch (e)
            {
                case Edge.East: exit = new Vec2(arena.Width + 200f, self.Pos.Y); break;
                case Edge.West: exit = new Vec2(-200f, self.Pos.Y); break;
                case Edge.North: exit = new Vec2(self.Pos.X, -200f); break;
                default: exit = new Vec2(self.Pos.X, arena.Height + 200f); break;
            }
            input.Move = (exit - self.Pos).Normalized();
            Travelling = true;
            return input;
        }

        /// <summary>The furthest-out checkpoint the run can afford, if it is further out than here.</summary>
        private static SectorCoord? TeleportTarget(Run run)
        {
            SectorCoord? best = null;
            foreach (SectorCoord c in run.Meta.Checkpoints)
            {
                if (c.Layer <= run.Sector.Layer || !run.World.CanTeleport(c, run.Energy, run.Meta)) continue;
                if (!best.HasValue || c.Layer > best.Value.Layer) best = c;
            }
            return best;
        }

        private SectorCoord? ChooseGoal(Run run)
        {
            WorldGrid world = run.World;
            Meta meta = run.Meta;
            // The gate, once the veil allows it and it still stands.
            foreach (Sector s in world.SortedSectors())
                if (s.IsGate && !meta.BeatenGates.Contains(s.Coord) && run.Energy >= world.ThresholdToEnter(s.Coord)
                    && world.Route(run.Sector, s.Coord, run.Energy, meta).Count > 0)
                    return s.Coord;

            // Otherwise the nearest uncleared sector, least threatening first.
            SectorCoord? best = null;
            int bestGap = int.MaxValue, bestLen = int.MaxValue;
            foreach (Sector s in world.SortedSectors())
            {
                // Player territory is quiet for good: nothing to fight there.
                if (s.Layer == 0 || s.IsGate || run.Life(s.Coord).Cleared || meta.PlayerTerritory.Contains(s.Coord) || s.Coord == run.Sector) continue;
                int len = world.Route(run.Sector, s.Coord, run.Energy, meta).Count;
                if (len == 0) continue;
                int gap = System.Math.Max(0, s.ThreatTier(_game.Catalog) - run.Tier);
                if (gap < bestGap || (gap == bestGap && len < bestLen)) { best = s.Coord; bestGap = gap; bestLen = len; }
            }
            return best;
        }

        /// <summary>Below this much light left in its pool, a grazed sector is worth leaving.</summary>
        public const float GrazeLeaveBelow = 5f;

        /// <summary>The reachable sector with the most light left this life (the origin has none), nearest on a tie.</summary>
        private static SectorCoord? RichestGrazing(Run run)
        {
            SectorCoord? best = null;
            float bestPool = GrazeLeaveBelow;
            int bestLen = int.MaxValue;
            foreach (Sector s in run.World.SortedSectors())
            {
                if (s.Layer == 0 || s.Coord == run.Sector) continue;
                int len = run.World.Route(run.Sector, s.Coord, run.Energy, run.Meta).Count;
                if (len == 0) continue;
                float pool = run.Life(s.Coord).LightPool;
                if (pool > bestPool || (pool == bestPool && len < bestLen)) { best = s.Coord; bestPool = pool; bestLen = len; }
            }
            return best;
        }

        /// <summary>The nearest pickup that is not ambient light (a kill's or a hit's drop).</summary>
        private static int NearestDrop(Arena arena, Vec2 from, float within)
        {
            int best = -1;
            float bestD = within * within;
            PickupPool p = arena.Pickups;
            for (int i = 0; i < p.High; i++)
            {
                if (!p.Alive[i] || p.Ambient[i]) continue;
                float dx = p.X[i] - from.X, dy = p.Y[i] - from.Y;
                float d = dx * dx + dy * dy;
                if (d < bestD) { bestD = d; best = i; }
            }
            return best;
        }
    }
}
