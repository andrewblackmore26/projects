using System;
using Gridlock.Core.Ai;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;

namespace Gridlock.Core
{
    /// <summary>Everything a balance harness needs to know about one finished match.</summary>
    public class MatchStats
    {
        public MatchResult Result;
        public long Ticks;
        public float SimSeconds;
        public int PlayerSends;
        public int AiSends;
        public int PlayerCaptures;
        public int AiCaptures;
        public int ContestsStarted;
        public int ContestSideDeathResolutions;
        public int ContestMutualDeaths;
        public int ContestEndpointResolutions;
        public int UnwinnableRejectedPlayer;
        public int UnwinnableRejectedAi;
        public ulong FinalHash;
    }

    /// <summary>
    /// Runs a full AI-vs-AI match with no renderer attached (spec M1 exit bar).
    /// Used by tests, the Headless CLI, and both engines' attract/viewer modes.
    /// One controller drives the Player side, one the Ai side; the Simulation
    /// alternates their tick order by parity (side-bias defense).
    /// </summary>
    public static class HeadlessMatch
    {
        public const float DefaultMaxSeconds = 600f;

        /// <summary>
        /// THE way to seat two AI controllers on a simulation. Every caller must
        /// come through here — the headless CLI, the balance harness, and both
        /// engines' viewers. The cross-engine determinism gate compares state
        /// hashes, and that comparison only proves anything if both sides built
        /// the match identically; forking the seed by hand in two places is
        /// exactly how that guarantee rots (and it did, once).
        ///
        /// mirrorSeeds swaps which decision stream each side receives: running
        /// every seed both ways and aggregating cancels seed luck, and the delta
        /// between the two orientations measures structural side bias directly.
        /// </summary>
        public static void AttachControllers(Simulation sim, int playerTier, int aiTier, ulong seed,
            bool mirrorSeeds, out AiController playerAi, out AiController aiAi)
        {
            var root = new DeterministicRandom(seed);
            // Fork both streams FIRST, then assign — swapping salts inside the
            // Fork calls would not swap the streams (Fork advances root state).
            DeterministicRandom streamA = root.Fork(0x51DE0001UL);
            DeterministicRandom streamB = root.Fork(0x51DE0002UL);
            playerAi = new AiController(Owner.Player, AiDifficulty.FromTier(playerTier), mirrorSeeds ? streamB : streamA);
            aiAi = new AiController(Owner.Ai, AiDifficulty.FromTier(aiTier), mirrorSeeds ? streamA : streamB);
            sim.AddController(playerAi);
            sim.AddController(aiAi);
        }

        public static MatchStats Run(LevelData level, Tuning tuning, int playerTier, int aiTier,
            ulong seed, float maxSeconds = DefaultMaxSeconds, bool mirrorSeeds = false)
        {
            var sim = new Simulation(level, tuning);
            AttachControllers(sim, playerTier, aiTier, seed, mirrorSeeds, out AiController playerAi, out AiController aiAi);

            long maxTicks = (long)(maxSeconds * tuning.TickRate);
            while (sim.Result == MatchResult.None && sim.Tick < maxTicks)
                sim.Step();
            if (sim.Result == MatchResult.None) sim.ForceTimeout();

            return new MatchStats
            {
                Result = sim.Result,
                Ticks = sim.Tick,
                SimSeconds = sim.TimeSeconds,
                PlayerSends = sim.PlayerSends,
                AiSends = sim.AiSends,
                PlayerCaptures = sim.PlayerCaptures,
                AiCaptures = sim.AiCaptures,
                ContestsStarted = sim.ContestsStarted,
                ContestSideDeathResolutions = sim.ContestSideDeathResolutions,
                ContestMutualDeaths = sim.ContestMutualDeaths,
                ContestEndpointResolutions = sim.ContestEndpointResolutions,
                UnwinnableRejectedPlayer = playerAi.UnwinnableRejected,
                UnwinnableRejectedAi = aiAi.UnwinnableRejected,
                FinalHash = StateHash.Compute(sim),
            };
        }
    }
}
