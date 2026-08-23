using System;
using Gridlock.Core.Config;

namespace Gridlock.Core.Ai
{
    /// <summary>
    /// The AI opponent (spec §9). Drives its side exclusively through the same
    /// public intent pipeline as the player — including the hold: an AI node
    /// visibly brightens (Overcharging) before it sends, so the telegraphing
    /// symmetry design pillar holds for both sides. One pending hold at a time
    /// (players have one pointer; the AI gets one "hand").
    ///
    /// All randomness lives here (decision jitter, score noise) in a forked
    /// DeterministicRandom — the Simulation itself is RNG-free.
    /// </summary>
    public class AiController : ISimController
    {
        public Owner Side { get; }

        private readonly AiDifficulty _difficulty;
        private readonly DeterministicRandom _rng;

        private long _nextDecisionTick;

        // Pending hold state machine.
        private int _pendingNode = -1;
        private int _pendingWire = -1;
        private int _pendingTarget = -1;
        private bool _pendingIsCapture;
        private long _beginTick;
        private long _releaseTick;

        /// <summary>Instrumentation: candidates discarded by the hard unwinnable-send filter.</summary>
        public int UnwinnableRejected { get; private set; }
        public int DecisionsMade { get; private set; }
        public int ActionsTaken { get; private set; }

        public AiController(Owner side, AiDifficulty difficulty, DeterministicRandom rng)
        {
            Side = side;
            _difficulty = difficulty;
            _rng = rng;
        }

        public AiController(Owner side, int tier, ulong seed)
            : this(side, AiDifficulty.FromTier(tier), new DeterministicRandom(seed))
        {
        }

        public void Tick(Simulation sim)
        {
            if (sim.Result != MatchResult.None) return;
            long tick = sim.Tick;

            if (_pendingNode >= 0)
            {
                TickPendingHold(sim, tick);
                return;
            }

            if (tick < _nextDecisionTick) return;

            // Schedule the next decision with ±20% jitter (spec §9.2) so the
            // cadence never feels metronomic.
            float jitter = 1f + _rng.Range(-0.2f, 0.2f);
            long interval = Math.Max(1L,
                (long)Math.Round(_difficulty.DecisionInterval * sim.Tuning.TickRate * jitter));
            _nextDecisionTick = tick + interval;
            DecisionsMade++;

            Candidate best = CandidateScorer.PickBest(sim, Side, _difficulty, _rng, out int rejected);
            UnwinnableRejected += rejected;
            if (best == null || best.Score <= _difficulty.ActionThreshold) return; // banking is a move

            ActionsTaken++;
            sim.EnqueueBeginHold(Side, best.SourceNodeId);
            if (best.HoldTicks <= 0)
            {
                // Instant tap-send: hold and release drain on the same tick.
                sim.EnqueueReleaseSend(Side, best.SourceNodeId, best.WireId);
                return;
            }

            _pendingNode = best.SourceNodeId;
            _pendingWire = best.WireId;
            _pendingTarget = best.TargetNodeId;
            _pendingIsCapture = best.IsCaptureAttempt;
            _beginTick = tick;
            // BeginHold drains at tick+1 (HoldStartTick = tick+1); releasing at
            // controller-tick (tick + H) drains at tick+H+1 → exactly H hold ticks.
            _releaseTick = tick + best.HoldTicks;
        }

        private void TickPendingHold(Simulation sim, long tick)
        {
            GameNode node = sim.NodeById(_pendingNode);
            if (node == null || node.Owner != Side)
            {
                ClearPending(); // lost the node mid-hold
                return;
            }

            if (tick < _releaseTick)
            {
                // After the 1-tick intent latency the node must be Overcharging;
                // if the BeginHold was rejected (state race), abandon.
                if (tick > _beginTick + 2 && node.State != NodeState.Overcharging) ClearPending();
                return;
            }

            if (node.State == NodeState.Overcharging)
            {
                // Release-time revalidation: a capture attempt whose target we now
                // own is moot — cancel instead (a visible feint, which is fine).
                bool moot = false;
                if (_pendingIsCapture)
                {
                    GameNode target = sim.NodeById(_pendingTarget);
                    if (target != null && target.Owner == Side) moot = true;
                }
                if (moot) sim.EnqueueCancelHold(Side, _pendingNode);
                else sim.EnqueueReleaseSend(Side, _pendingNode, _pendingWire);
            }
            ClearPending();
        }

        private void ClearPending()
        {
            _pendingNode = -1;
            _pendingWire = -1;
            _pendingTarget = -1;
            _pendingIsCapture = false;
        }
    }
}
