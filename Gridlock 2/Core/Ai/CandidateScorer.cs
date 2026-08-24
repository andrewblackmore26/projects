using System;
using System.Collections.Generic;
using Gridlock.Core.Config;

namespace Gridlock.Core.Ai
{
    /// <summary>One scored (source, wire) send option.</summary>
    public class Candidate
    {
        public int SourceNodeId;
        public int WireId;
        public int TargetNodeId;
        /// <summary>Hold duration that realizes the chosen send fraction (OverchargeTicks = burst).</summary>
        public int HoldTicks;
        public bool Burst;
        public float ProjectedPower;
        public float Speed;
        /// <summary>True when the send is sized to capture the target (used for release-time revalidation).</summary>
        public bool IsCaptureAttempt;
        /// <summary>Post-noise utility score.</summary>
        public float Score;
    }

    /// <summary>
    /// Utility scoring per spec §9.3. Pure evaluation over public sim state —
    /// the AI sees exactly what the player sees (spec §9.1).
    ///
    /// Informed additions beyond the spec letter, flagged here once:
    ///  - HARD feasibility filter: a candidate whose power (plus friendly power
    ///    already in flight on that wire) cannot beat the opposing in-flight
    ///    power is DISCARDED before noise. Spec's acceptance rule is "never send
    ///    into an unwinnable contest unless noise caused it"; we go stronger —
    ///    noise cannot resurrect a suicide send at any tier.
    ///  - Interception credit: W_DEFEND also applies to sending from a threatened
    ///    node along the threatened wire (meeting the incoming beam mid-wire).
    ///    Without this the AI would never voluntarily contest on the wire — the
    ///    game's signature move.
    ///  - Defensive transfers (friendly-target sends) exist ONLY when they can
    ///    land in time to matter; undirected transfers are skipped entirely
    ///    (prevents transfer-loop pathologies the literal formula allows).
    ///  - Capture-ratio denominator floored / capped (Tuning.AiMinDefenseForRatio,
    ///    AiCaptureRatioCap) so a zero-defense target does not produce an
    ///    infinite score.
    /// </summary>
    public static class CandidateScorer
    {
        private struct Threat
        {
            public float BeamPower;
            public long TicksUntilArrival;
            public int WireId;
        }

        public static Candidate PickBest(Simulation sim, Owner side, AiDifficulty diff,
            DeterministicRandom rng, out int unwinnableRejected)
        {
            unwinnableRejected = 0;
            Tuning tuning = sim.Tuning;
            Owner enemy = side == Owner.Player ? Owner.Ai : Owner.Player;

            // Per-wire in-flight power (beams + contest sides).
            var friendlyInFlight = new Dictionary<int, float>();
            var enemyInFlight = new Dictionary<int, float>();
            foreach (Beam b in sim.Beams)
            {
                var map = b.Owner == side ? friendlyInFlight : enemyInFlight;
                map.TryGetValue(b.WireId, out float p);
                map[b.WireId] = p + b.Power;
            }
            var contestByWire = new Dictionary<int, Contest>();
            foreach (Contest c in sim.Contests)
            {
                contestByWire[c.WireId] = c;
                float mine = c.PowerOf(side);
                float theirs = c.PowerOf(enemy);
                friendlyInFlight.TryGetValue(c.WireId, out float fp);
                friendlyInFlight[c.WireId] = fp + mine;
                enemyInFlight.TryGetValue(c.WireId, out float ep);
                enemyInFlight[c.WireId] = ep + theirs;
            }

            // Threat map: enemy beams inbound to nodes we own that would capture.
            // Keep the earliest-arriving such beam per node.
            var threats = new Dictionary<int, Threat>();
            if (diff.ThreatResponse)
            {
                foreach (Beam b in sim.Beams)
                {
                    if (b.Owner != enemy) continue;
                    Wire w = sim.WireById(b.WireId);
                    GameNode dest = sim.NodeById(w.DestinationNode(b.Dir));
                    if (dest.Owner != side) continue;
                    if (b.Power <= dest.Charge) continue;
                    float remainingT = b.Dir > 0 ? 1f - b.T : b.T;
                    long ticks = (long)Math.Ceiling(remainingT * w.Length / b.Speed * tuning.TickRate);
                    if (!threats.TryGetValue(dest.Id, out Threat existing) || ticks < existing.TicksUntilArrival)
                        threats[dest.Id] = new Threat { BeamPower = b.Power, TicksUntilArrival = ticks, WireId = w.Id };
                }
            }

            // Overcharging enemy nodes (anticipate read, spec §9.3 tier ≥ 6).
            List<GameNode> overchargingEnemies = null;
            if (diff.Anticipate)
            {
                foreach (GameNode n in sim.Nodes)
                {
                    if (n.Owner == enemy && n.State == NodeState.Overcharging)
                    {
                        overchargingEnemies ??= new List<GameNode>();
                        overchargingEnemies.Add(n);
                    }
                }
            }

            int overchargeTicks = tuning.OverchargeTicks;
            float maxNonBurstFraction = SendFraction(tuning, overchargeTicks - 1);

            Candidate best = null;
            foreach (GameNode source in sim.Nodes)
            {
                if (source.Owner != side || source.State != NodeState.Idle) continue;
                if (source.Charge < tuning.MinSendCharge) continue;

                bool sourceBordersEnemy = BordersEnemy(sim, source, enemy);

                foreach (int wireId in source.WireIds)
                {
                    Wire wire = sim.WireById(wireId);
                    GameNode target = sim.NodeById(wire.OtherNode(source.Id));
                    contestByWire.TryGetValue(wireId, out Contest contest);

                    if (target.Owner == side)
                    {
                        // Friendly target: only a timed defensive deposit qualifies.
                        if (!diff.ThreatResponse || !threats.TryGetValue(target.Id, out Threat threat)) continue;
                        float needed = (threat.BeamPower - target.Charge) * tuning.AiCaptureMargin;
                        if (needed <= 0f) continue;
                        int holdTicks = HoldTicksForPower(tuning, source.Charge, needed, overchargeTicks, maxNonBurstFraction);
                        if (holdTicks < 0) continue; // cannot raise enough without bursting
                        float projected = source.Charge * SendFraction(tuning, holdTicks);
                        long travelTicks = (long)Math.Ceiling(wire.Length / tuning.BaseBeamSpeed * tuning.TickRate);
                        if (holdTicks + travelTicks >= threat.TicksUntilArrival) continue; // would land too late
                        // Against the CAPPED charge: a deposit into a nearly full
                        // node overflows and is lost, so the uncapped sum would
                        // green-light a rescue that provably cannot hold — while
                        // stripping the source, since W_DEFEND usually wins the argmax.
                        float defended = Math.Min(target.Charge + projected, target.MaxCharge(tuning));
                        if (defended <= threat.BeamPower) continue;
                        Evaluate(sim, side, enemy, diff, rng, source, wire, target, contest,
                            friendlyInFlight, enemyInFlight, threats, overchargingEnemies,
                            holdTicks, projected, tuning.BaseBeamSpeed, isBurst: false, isCapture: false,
                            sourceBordersEnemy, ref best, ref unwinnableRejected);
                        continue;
                    }

                    // Enemy or neutral target: normal send sized for capture; when
                    // capture is out of reach, a chip is sized to ZERO the remaining
                    // defense (a zeroed neutral makes the next tap a capture — the
                    // intended chip-then-take sequencing), never an all-in dump.
                    float defense = target.Owner == Owner.Neutral ? target.NeutralDefense : target.Charge;
                    float neededPower = defense * tuning.AiCaptureMargin + tuning.PowerEpsilon;
                    int normalHold = HoldTicksForPower(tuning, source.Charge, neededPower, overchargeTicks, maxNonBurstFraction);
                    bool isCapture = normalHold >= 0;
                    if (normalHold < 0)
                    {
                        // Chip sized to ZERO the defense if we can (the next tap
                        // then captures)...
                        normalHold = HoldTicksForPower(tuning, source.Charge, defense, overchargeTicks, maxNonBurstFraction);
                        // ...else a progress chip (multi-send hub work, spec §5.7)
                        // — but ONLY from a nearly-full bank. Low-charge all-in
                        // chips measured as tiers stripping themselves (0-capture
                        // losses); near cap, accrual overflow makes the chip the
                        // correct play (Tuning.AiChipMinBankFraction).
                        if (normalHold < 0 &&
                            source.Charge >= source.MaxCharge(tuning) * tuning.AiChipMinBankFraction)
                        {
                            normalHold = overchargeTicks - 1;
                        }
                    }
                    if (normalHold >= 0)
                    {
                        float normalPower = source.Charge * SendFraction(tuning, normalHold);
                        Evaluate(sim, side, enemy, diff, rng, source, wire, target, contest,
                            friendlyInFlight, enemyInFlight, threats, overchargingEnemies,
                            normalHold, normalPower, tuning.BaseBeamSpeed, isBurst: false, isCapture,
                            sourceBordersEnemy, ref best, ref unwinnableRejected);
                    }

                    if (diff.BurstEnabled)
                    {
                        Evaluate(sim, side, enemy, diff, rng, source, wire, target, contest,
                            friendlyInFlight, enemyInFlight, threats, overchargingEnemies,
                            overchargeTicks, source.Charge, tuning.BaseBeamSpeed * tuning.BurstSpeedMultiplier,
                            isBurst: true, isCapture: source.Charge > defense,
                            sourceBordersEnemy, ref best, ref unwinnableRejected);
                    }
                }
            }
            return best;
        }

        private static void Evaluate(Simulation sim, Owner side, Owner enemy, AiDifficulty diff,
            DeterministicRandom rng, GameNode source, Wire wire, GameNode target, Contest contest,
            Dictionary<int, float> friendlyInFlight, Dictionary<int, float> enemyInFlight,
            Dictionary<int, CandidateScorer.Threat> threats, List<GameNode> overchargingEnemies,
            int holdTicks, float projected, float speed, bool isBurst, bool isCapture,
            bool sourceBordersEnemy, ref Candidate best, ref int unwinnableRejected)
        {
            Tuning tuning = sim.Tuning;

            // Hard feasibility filter (see class remarks).
            enemyInFlight.TryGetValue(wire.Id, out float opposing);
            if (opposing > 0f)
            {
                friendlyInFlight.TryGetValue(wire.Id, out float friendly);
                if (projected + friendly <= opposing)
                {
                    unwinnableRejected++;
                    return;
                }
            }

            float score = 0f;

            // Capture feasibility — dominant term (spec §9.3).
            if (target.Owner != side)
            {
                float defense = target.Owner == Owner.Neutral ? target.NeutralDefense : target.Charge;
                float ratio = projected / Math.Max(defense, tuning.AiMinDefenseForRatio);
                if (projected > defense)
                    score += tuning.WCapture * Math.Min(ratio, tuning.AiCaptureRatioCap);
                else
                    score += tuning.WChip * ratio;
            }

            // Target value — hubs are worth more. A send that cannot take the
            // prize only scores a fraction of it (see Tuning.AiChipValueScale).
            bool takesTarget = isCapture || target.Owner == side;
            float valueScale = takesTarget ? 1f : tuning.AiChipValueScale;
            score += tuning.WDegree * target.Degree * valueScale;

            // Travel time penalty (long wires telegraph and can be intercepted).
            score -= tuning.WTravel * (wire.Length / speed);

            // Reinforcement: feed a losing-but-flippable contest on this wire.
            if (contest != null)
            {
                float mine = contest.PowerOf(side);
                float theirs = contest.PowerOf(enemy);
                if (mine < theirs && mine + projected > theirs)
                    score += tuning.WReinforce;
            }

            if (diff.ThreatResponse)
            {
                // Defend a threatened friendly node by depositing into it
                // (timing already validated at enumeration for friendly targets).
                if (target.Owner == side && threats.ContainsKey(target.Id))
                    score += tuning.WDefend * target.Degree;

                // Interception: launch from the threatened node into the incoming
                // beam's wire before it lands (informed addition).
                //
                // The margin is two ticks, not one. The threat resolves at
                // tick N + m - 1 (it still moves during the deciding tick), while
                // the interceptor only exists at N + H + 1 (BeginHold drains at
                // N+1, the release at N+H+1). H = m-1 therefore buys a beam that
                // spawns one tick AFTER the node has already fallen.
                if (threats.TryGetValue(source.Id, out Threat selfThreat) &&
                    selfThreat.WireId == wire.Id && holdTicks + 1 < selfThreat.TicksUntilArrival)
                    score += tuning.WDefend * source.Degree;
            }

            // Overcharge read: a brightening enemy node telegraphs where it can reach.
            if (overchargingEnemies != null)
            {
                foreach (GameNode e in overchargingEnemies)
                {
                    foreach (int wid in e.WireIds)
                    {
                        if (sim.WireById(wid).OtherNode(e.Id) != target.Id) continue;
                        score += tuning.WAnticipate * e.OverchargeProgress(sim.Tick, tuning);
                        break;
                    }
                }
            }

            // Frontier bias: prefer contested space over safe interior.
            if (BordersEnemyOrContested(sim, target, enemy)) score += tuning.WFrontier * valueScale;

            // Overextension: don't strip a node that is itself on the front line.
            if (sourceBordersEnemy)
                score -= tuning.WOverextend * (source.Charge / source.MaxCharge(tuning));

            // Burst risk: the disable window is a real cost (see Tuning.WBurstRisk).
            if (isBurst) score -= tuning.WBurstRisk;

            // Evaluation noise (spec §9.2 step 3).
            score *= 1f + rng.Range(-diff.NoiseFactor, diff.NoiseFactor);

            if (best == null || score > best.Score)
            {
                best = new Candidate
                {
                    SourceNodeId = source.Id,
                    WireId = wire.Id,
                    TargetNodeId = target.Id,
                    HoldTicks = holdTicks,
                    Burst = isBurst,
                    ProjectedPower = projected,
                    Speed = speed,
                    IsCaptureAttempt = isCapture,
                    Score = score,
                };
            }
        }

        /// <summary>sendFraction = lerp(MIN_SEND_FRACTION, 1, holdTicks / OverchargeTicks) (spec §5.3).</summary>
        private static float SendFraction(Tuning tuning, int holdTicks)
        {
            float progress = holdTicks / (float)tuning.OverchargeTicks;
            if (progress > 1f) progress = 1f;
            return tuning.MinSendFraction + (1f - tuning.MinSendFraction) * progress;
        }

        /// <summary>
        /// Smallest non-burst hold that sends at least `needed` power from `charge`,
        /// or -1 if even the maximum non-burst hold falls short.
        /// </summary>
        private static int HoldTicksForPower(Tuning tuning, float charge, float needed,
            int overchargeTicks, float maxNonBurstFraction)
        {
            if (charge <= 0f) return -1;
            float neededFraction = needed / charge;
            if (neededFraction > maxNonBurstFraction) return -1;
            if (neededFraction <= tuning.MinSendFraction) return 0;
            float progress = (neededFraction - tuning.MinSendFraction) / (1f - tuning.MinSendFraction);
            int hold = (int)Math.Ceiling(progress * overchargeTicks);
            if (hold > overchargeTicks - 1) hold = overchargeTicks - 1;
            return hold;
        }

        private static bool BordersEnemy(Simulation sim, GameNode node, Owner enemy)
        {
            foreach (int wid in node.WireIds)
            {
                if (sim.NodeById(sim.WireById(wid).OtherNode(node.Id)).Owner == enemy) return true;
            }
            return false;
        }

        private static bool BordersEnemyOrContested(Simulation sim, GameNode node, Owner enemy)
        {
            foreach (int wid in node.WireIds)
            {
                if (sim.NodeById(sim.WireById(wid).OtherNode(node.Id)).Owner == enemy) return true;
                foreach (Contest c in sim.Contests)
                {
                    if (c.WireId == wid) return true;
                }
                foreach (Beam b in sim.Beams)
                {
                    if (b.WireId == wid && b.Owner == enemy) return true;
                }
            }
            return false;
        }
    }
}
