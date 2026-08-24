using UnityEngine;
using Gridlock.Core;
using Gridlock.Core.Ai;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// Owns the simulation and steps it on a fixed timestep with its own
    /// accumulator, exposing the leftover fraction as Alpha for interpolation.
    /// Mirrors the Godot GameController exactly, so the engines differ only in
    /// how they draw and feel.
    ///
    /// The presentation layer never mutates simulation state: input goes in as
    /// intents, which drain on the NEXT tick. UI must drive itself from its own
    /// input state rather than reading the simulation back, or every interaction
    /// cancels itself.
    /// </summary>
    public class UGameController
    {
        public readonly Simulation Sim;
        public readonly Tuning Tuning;
        public readonly BuiltLevel Level;

        public float Alpha { get; private set; }

        private double _accumulator;

        public UGameController(BuiltLevel level, Tuning tuning)
        {
            Level = level;
            Tuning = tuning;
            Sim = new Simulation(level, tuning);
        }

        /// <summary>
        /// Seat both AI sides the way the headless CLI does, so an attract match
        /// here is the same match the determinism gate compares.
        /// </summary>
        public void AttachStandardAi(int playerTier, int aiTier, ulong seed) =>
            HeadlessMatch.AttachControllers(Sim, playerTier, aiTier, seed, false, out _, out _);

        public void AddAi(CoreOwner side, int tier, ulong seed) =>
            Sim.AddController(new AiController(side, AiDifficulty.FromTier(tier), new DeterministicRandom(seed)));

        public void Advance(double deltaSeconds)
        {
            double dt = Tuning.Dt;
            _accumulator += deltaSeconds;
            if (_accumulator > 0.25) _accumulator = 0.25; // never replay a lost second at once
            while (_accumulator >= dt)
            {
                Sim.Step();
                _accumulator -= dt;
            }
            Alpha = (float)(_accumulator / dt);
        }

        public float BeamT(Beam b) => Mathf.Lerp(b.PrevT, b.T, Alpha);

        public float ContactT(Contest c) => Mathf.Lerp(c.PrevContactT, c.ContactT, Alpha);
    }
}
