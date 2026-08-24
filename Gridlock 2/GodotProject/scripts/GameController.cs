using System;
using Godot;
using Gridlock.Core;
using Gridlock.Core.Ai;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;

namespace Gridlock.View
{
    /// <summary>
    /// Owns the simulation and steps it on a fixed timestep with its own
    /// accumulator, exposing the leftover fraction as Alpha so views can
    /// interpolate between ticks and stay smooth at any framerate.
    ///
    /// The presentation layer NEVER mutates simulation state: input arrives as
    /// intents, which drain on the following tick (a documented 1-tick latency).
    /// UI must therefore drive itself from its own input state, not from a
    /// read-back of the simulation, or every interaction cancels itself.
    /// </summary>
    public class GameController
    {
        public readonly Simulation Sim;
        public readonly Tuning Tuning;
        public readonly BuiltLevel Level;

        /// <summary>Fraction of the way into the next tick, 0..1, for interpolation.</summary>
        public float Alpha { get; private set; }

        private double _accumulator;

        public GameController(BuiltLevel level, Tuning tuning)
        {
            Level = level;
            Tuning = tuning;
            Sim = new Simulation(level, tuning);
        }

        /// <summary>
        /// Seat both AI sides exactly the way the headless CLI does. Routed
        /// through Core so the cross-engine hash gate compares the same match;
        /// building the controllers here by hand is what broke it once.
        /// </summary>
        public void AttachStandardAi(int playerTier, int aiTier, ulong seed) =>
            HeadlessMatch.AttachControllers(Sim, playerTier, aiTier, seed, false, out _, out _);

        /// <summary>Seat one AI opponent (the other side is a human).</summary>
        public void AddAi(Owner side, int tier, ulong seed) =>
            Sim.AddController(new AiController(side, AiDifficulty.FromTier(tier), new DeterministicRandom(seed)));

        /// <summary>Advance by wall-clock time (play and attract modes).</summary>
        public void Advance(double deltaSeconds)
        {
            double dt = Tuning.Dt;
            _accumulator += deltaSeconds;
            // Cap catch-up so a stalled frame cannot spiral (spec asks for
            // smooth motion, not for replaying a lost second all at once).
            if (_accumulator > 0.25) _accumulator = 0.25;
            while (_accumulator >= dt)
            {
                Sim.Step();
                _accumulator -= dt;
            }
            Alpha = (float)(_accumulator / dt);
        }

        /// <summary>Advance an exact number of ticks (deterministic capture and gates).</summary>
        public void AdvanceTicks(long ticks)
        {
            for (long i = 0; i < ticks; i++) Sim.Step();
            Alpha = 0f;
        }

        /// <summary>Interpolated position of a beam along its wire, in wire t.</summary>
        public float BeamT(Beam b) => Mathf.Lerp(b.PrevT, b.T, Alpha);

        /// <summary>Interpolated contest contact point, in wire t.</summary>
        public float ContactT(Contest c) => Mathf.Lerp(c.PrevContactT, c.ContactT, Alpha);
    }
}
