using Lightship.Core;
using Lightship.Core.Ai;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.Sim;

namespace Lightship.Core.Tests
{
    /// <summary>A pilot that always returns the same intent.</summary>
    public sealed class StaticPilot : IPilot
    {
        public PlayerInput Input;
        public bool AimAtPlayer;

        public PlayerInput Decide(Arena arena, Ship self)
        {
            PlayerInput i = Input;
            if (AimAtPlayer && arena.Player != null) i.Aim = (arena.Player.Pos - self.Pos).Normalized();
            return i;
        }
    }

    public static class SimTestHelpers
    {
        private static ShipCatalog _catalog;

        public static ShipCatalog Catalog()
        {
            if (_catalog == null) _catalog = LoaderTests.Authored(out _);
            return _catalog;
        }

        /// <summary>A quiet arena: no enemy spawns, no ambient light, the player idle at the centre.</summary>
        public static Game QuietGame(ulong seed = 1, Tuning tuning = null)
        {
            var game = new Game(tuning ?? new Tuning(), Catalog(), seed, Game.DefaultSeedShip, new StaticPilot());
            game.Arena.SpawnEnemies = false;
            game.Arena.SpawnAmbientLight = false;
            return game;
        }

        public static Game BotGame(ulong seed = 1, Tuning tuning = null) =>
            new Game(tuning ?? new Tuning(), Catalog(), seed, Game.DefaultSeedShip, new BotPilot());

        public static void StepN(Game game, int n)
        {
            for (int i = 0; i < n; i++) game.Step(default);
        }

        public static int StepUntil(Game game, System.Func<Game, bool> done, int maxTicks)
        {
            for (int i = 0; i < maxTicks; i++)
            {
                if (done(game)) return i;
                game.Step(default);
            }
            return done(game) ? maxTicks : -1;
        }

        public static float SumPickupValues(Arena a)
        {
            float sum = 0f;
            for (int i = 0; i < a.Pickups.High; i++) if (a.Pickups.Alive[i]) sum += a.Pickups.Value[i];
            return sum;
        }
    }
}
