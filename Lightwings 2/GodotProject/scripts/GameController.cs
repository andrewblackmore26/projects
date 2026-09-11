using Lightship.Core.Ai;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Lightship.Core.World;

namespace Lightship.View
{
    /// <summary>
    /// Owns the game and steps it on a fixed 60 Hz timestep with its own
    /// accumulator, exposing the leftover fraction as Alpha so views can
    /// interpolate between ticks.
    ///
    /// Edge intents (evolve) are LATCHED until a tick consumes them: at 60 fps
    /// some frames run no tick at all, and a press that lands on one of those
    /// frames would otherwise be lost (the 1-tick intent lesson).
    /// </summary>
    public sealed class GameController
    {
        public readonly Game Game;
        public readonly Tuning Tuning;
        public float Alpha { get; private set; }

        private double _accumulator;
        private bool _evolveLatched;
        private int _evolveChoice;
        private bool _teleportLatched;
        private SectorCoord _teleportTarget;

        /// <summary>
        /// The world is the game; the sandbox (the M1 arena) serves the loop probes and the
        /// bench. Both are built by the same Core calls the CLI and the tests use.
        /// </summary>
        public GameController(Tuning tuning, ShipCatalog catalog, ulong seed, string seedShip, bool bot, GameMode mode = GameMode.World)
        {
            Tuning = tuning;
            string ship = seedShip ?? Game.DefaultSeedShip;
            Game = mode == GameMode.World
                ? Game.NewWorld(tuning, catalog, seed, bot ? BotSkill.Perfect() : null, ship)
                : new Game(tuning, catalog, seed, ship, bot ? new BotPilot() : null);
        }

        public float SimTime => Game.Arena.Time + Alpha * Tuning.Dt;

        public void RequestEvolve(int choice)
        {
            _evolveLatched = true;
            _evolveChoice = choice;
        }

        /// <summary>Spec 7: a jump chosen on the map, applied by the next tick (the run checks the rules).</summary>
        public void RequestTeleport(SectorCoord to)
        {
            _teleportLatched = true;
            _teleportTarget = to;
        }

        /// <summary>Advance by wall-clock time (play mode).</summary>
        public int Advance(double deltaSeconds, PlayerInput live)
        {
            double dt = Tuning.Dt;
            _accumulator += deltaSeconds;
            // Cap catch-up so a stalled frame cannot spiral.
            if (_accumulator > 0.25) _accumulator = 0.25;
            int steps = 0;
            while (_accumulator >= dt)
            {
                StepOnce(live);
                _accumulator -= dt;
                steps++;
            }
            Alpha = (float)(_accumulator / dt);
            return steps;
        }

        public void StepOnce(PlayerInput live)
        {
            PlayerInput input = live;
            if (_evolveLatched)
            {
                input.Evolve = true;
                input.EvolveChoice = _evolveChoice;
                _evolveLatched = false;   // one press, one attempt (ignored below the threshold)
            }
            if (_teleportLatched)
            {
                input.Teleport = true;
                input.TeleportTarget = _teleportTarget;
                _teleportLatched = false;
            }
            Game.Step(input);
        }

        /// <summary>Capture probes only: draw the frozen frame part-way between ticks.</summary>
        public void SetAlphaForProbe(float alpha) => Alpha = alpha;

        /// <summary>Advance an exact number of ticks (deterministic capture and gates).</summary>
        public void AdvanceTicks(long ticks)
        {
            for (long i = 0; i < ticks; i++) StepOnce(default);
            Alpha = 0f;
        }
    }
}
