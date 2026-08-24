using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace Gridlock.Core
{
    /// <summary>
    /// Phases 6–7 of the tick: contest burn/push/resolution, then per-wire beam
    /// movement with a time-ordered event sweep (absorption into contests,
    /// crossings that spawn contests, same-owner merges, chase clashes, and
    /// endpoint arrivals), then all arrivals resolved globally in
    /// (τ, wireId, sourceId) order so same-tick multi-arrivals are deterministic
    /// and physically ordered (earlier τ resolves first and later arrivals see
    /// the node state it left).
    /// </summary>
    public partial class Simulation
    {
        private struct ArrivalEvent
        {
            public float Tau;
            public int WireId;
            public int SourceId; // beam id, or contest id + ContestSourceOffset
            public Owner Owner;
            public float Power;
            public int NodeId;
        }

        private const int ContestSourceOffset = 1_000_000;

        private readonly List<ArrivalEvent> _arrivals = new List<ArrivalEvent>();

        // ---- Phase 6: contests ----

        private void StepContests()
        {
            float dt = Tuning.Dt;
            float eps = Tuning.PowerEpsilon;

            for (int i = 0; i < _contests.Count; i++)
            {
                Contest c = _contests[i];
                c.StepBurnAndPush(Tuning, dt);
                float raw = c.ContactT;

                bool playerDead = c.PowerPlayer <= eps;
                bool aiDead = c.PowerAi <= eps;
                if (playerDead || aiDead)
                {
                    if (playerDead && aiDead)
                    {
                        // Evenly matched to the end: mutual annihilation (matrix #13).
                        c.ClampContact();
                        ContestMutualDeaths++;
                        ContestResolved?.Invoke(c.Id, c.WireId, Owner.Neutral, 0f);
                    }
                    else
                    {
                        // Survivor resumes as a beam from contactT with its remaining
                        // power and original speed/direction (spec §5.6). It holds
                        // position for the rest of this tick (still contactable).
                        Owner side = playerDead ? Owner.Ai : Owner.Player;
                        float power = playerDead ? c.PowerAi : c.PowerPlayer;
                        float speed = playerDead ? c.SpeedAi : c.SpeedPlayer;
                        int dir = playerDead ? c.DirAi : c.DirPlayer;

                        // If the front ALSO ran off the end this tick and the
                        // survivor is the side heading that way, it arrives
                        // rather than being parked on the boundary. Clamping
                        // first would erase the crossing fraction and stamp the
                        // arrival with tau 0, sorting it ahead of everything
                        // else that really did happen at the start of the tick.
                        bool offEnd = (raw <= 0f && dir < 0) || (raw >= 1f && dir > 0);
                        if (offEnd && power > eps)
                        {
                            float boundary = raw >= 1f ? 1f : 0f;
                            float moved = raw - c.PrevContactT;
                            float tau = moved == 0f ? 1f : Clamp01((boundary - c.PrevContactT) / moved);
                            Wire w = _wiresById[c.WireId];
                            _arrivals.Add(new ArrivalEvent
                            {
                                Tau = tau,
                                WireId = w.Id,
                                SourceId = c.Id + ContestSourceOffset,
                                Owner = side,
                                Power = power,
                                NodeId = w.DestinationNode(dir),
                            });
                        }
                        else
                        {
                            c.ClampContact();
                            if (power > eps)
                                SpawnBeam(_wiresById[c.WireId], side, power, speed, dir, c.ContactT, holdThisTick: true);
                        }
                        ContestSideDeathResolutions++;
                        ContestResolved?.Invoke(c.Id, c.WireId, side, power);
                    }
                    _contests.RemoveAt(i);
                    i--;
                    continue;
                }

                // Both alive: endpoint arrival only if the front MOVED into/past a
                // boundary this tick (a contest sitting exactly on a boundary with
                // zero push keeps grinding — matrix #11/#15).
                if (raw <= 0f && raw < c.PrevContactT)
                {
                    ResolveContestEndpoint(c, atNodeB: false, raw);
                    _contests.RemoveAt(i);
                    i--;
                }
                else if (raw >= 1f && raw > c.PrevContactT)
                {
                    ResolveContestEndpoint(c, atNodeB: true, raw);
                    _contests.RemoveAt(i);
                    i--;
                }
                else
                {
                    c.ClampContact();
                }
            }
        }

        /// <summary>
        /// The front reached a wire end with both sides alive: the side whose
        /// travel direction points at that endpoint arrives there with its
        /// remaining power; the shoved-out side's power is destroyed (matrix #14).
        /// </summary>
        private void ResolveContestEndpoint(Contest c, bool atNodeB, float raw)
        {
            Wire wire = _wiresById[c.WireId];
            int arrivingDir = atNodeB ? 1 : -1;
            Owner side = c.DirPlayer == arrivingDir ? Owner.Player : Owner.Ai;
            float power = c.PowerOf(side);
            int nodeId = atNodeB ? wire.NodeB : wire.NodeA;

            float boundary = atNodeB ? 1f : 0f;
            float moved = raw - c.PrevContactT;
            float tau = moved == 0f ? 1f : Clamp01((boundary - c.PrevContactT) / moved);

            _arrivals.Add(new ArrivalEvent
            {
                Tau = tau,
                WireId = wire.Id,
                SourceId = c.Id + ContestSourceOffset,
                Owner = side,
                Power = power,
                NodeId = nodeId,
            });
            ContestEndpointResolutions++;
            ContestResolved?.Invoke(c.Id, c.WireId, side, power);
        }

        // ---- Phase 7: beams ----

        private enum SweepKind { Arrival = 0, Absorb = 1, Merge = 2, Net = 3, Chase = 4, SpawnContest = 5 }

        private void StepBeams()
        {
            float dt = Tuning.Dt;

            // Move every beam to its tentative end-of-tick position. Beams spawned
            // by this tick's sends move (they existed at phase 2); contest
            // survivors hold (spawned mid-tick in phase 6).
            foreach (Beam b in _beams)
            {
                b.PrevT = b.T;
                if (!b.HoldThisTick)
                {
                    Wire w = _wiresById[b.WireId];
                    b.T += b.Dir * (b.Speed / w.Length) * dt;
                }
            }

            foreach (Wire wire in _wires)
                SweepWire(wire);

            // Global arrival ordering: physically earlier arrivals resolve first;
            // later same-tick arrivals see the node state the earlier one left.
            _arrivals.Sort(CompareArrivals);
            foreach (ArrivalEvent a in _arrivals)
                ResolveArrival(a.Owner, a.Power, a.NodeId, a.WireId);
            _arrivals.Clear();

            foreach (Beam b in _beams)
                b.HoldThisTick = false;
        }

        private static int CompareArrivals(ArrivalEvent x, ArrivalEvent y)
        {
            int c = x.Tau.CompareTo(y.Tau);
            if (c != 0) return c;
            c = x.WireId.CompareTo(y.WireId);
            if (c != 0) return c;
            return x.SourceId.CompareTo(y.SourceId);
        }

        private void SweepWire(Wire wire)
        {
            // Gather this wire's beams (ascending id — _beams preserves id order)
            // and its contest, if any (at most one by invariant).
            List<Beam> bucket = null;
            foreach (Beam b in _beams)
            {
                if (b.WireId != wire.Id) continue;
                bucket ??= new List<Beam>();
                bucket.Add(b);
            }
            if (bucket == null) return;

            Contest contest = null;
            foreach (Contest c in _contests)
            {
                if (c.WireId != wire.Id) continue;
                Debug.Assert(contest == null, "invariant violated: two contests on wire " + wire.Id);
                contest = c;
            }

            // Chronological event sweep over the tick. Every processed event
            // removes at least one beam, so the loop terminates.
            //
            // tauFloor is the time of the last event applied. All remaining
            // interactions are evaluated over [tauFloor, 1] only: without it, an
            // object CREATED mid-tick (a contest, a survivor beam) would be
            // tested against the part of a trajectory that happened before it
            // existed, and could for instance absorb a beam that passed its
            // position earlier in the same tick and is now moving away.
            float tauFloor = 0f;
            while (bucket.Count > 0)
            {
                float bestTau = float.MaxValue;
                SweepKind bestKind = SweepKind.Arrival;
                int bestI = -1, bestJ = -1;

                for (int i = 0; i < bucket.Count; i++)
                {
                    Beam b = bucket[i];
                    float bAtFloor = At(b.PrevT, b.T, tauFloor);

                    // Endpoint arrival.
                    if (b.Dir > 0 && b.T >= 1f)
                        ConsiderEvent(Remap(tauFloor, SafeTau(1f - bAtFloor, b.T - bAtFloor)), SweepKind.Arrival, i, -1,
                            bucket, ref bestTau, ref bestKind, ref bestI, ref bestJ);
                    else if (b.Dir < 0 && b.T <= 0f)
                        ConsiderEvent(Remap(tauFloor, SafeTau(bAtFloor, bAtFloor - b.T)), SweepKind.Arrival, i, -1,
                            bucket, ref bestTau, ref bestKind, ref bestI, ref bestJ);

                    // Absorption into the active contest (owner-based: covers
                    // reinforcement from either geometric side — matrix #5/#6/#7).
                    if (contest != null)
                    {
                        float d0 = bAtFloor - At(contest.PrevContactT, contest.ContactT, tauFloor);
                        float d1 = b.T - contest.ContactT;
                        if (Meets(d0, d1))
                            ConsiderEvent(Remap(tauFloor, CrossTau(d0, d1)), SweepKind.Absorb, i, -1,
                                bucket, ref bestTau, ref bestKind, ref bestI, ref bestJ);
                    }

                    // Pair interactions.
                    for (int j = i + 1; j < bucket.Count; j++)
                    {
                        Beam o = bucket[j];
                        SweepKind kind;
                        if (b.Owner == o.Owner)
                            kind = b.Dir == o.Dir ? SweepKind.Merge : SweepKind.Net;
                        else
                            kind = b.Dir != o.Dir ? SweepKind.SpawnContest : SweepKind.Chase;

                        float p0 = bAtFloor - At(o.PrevT, o.T, tauFloor);
                        float p1 = b.T - o.T;
                        if (!Meets(p0, p1)) continue;
                        ConsiderEvent(Remap(tauFloor, CrossTau(p0, p1)), kind, i, j,
                            bucket, ref bestTau, ref bestKind, ref bestI, ref bestJ);
                    }
                }

                if (bestI < 0) break;
                ProcessSweepEvent(wire, bucket, ref contest, bestKind, bestTau, bestI, bestJ);
                tauFloor = bestTau;
            }
        }

        /// <summary>Position along a tick trajectory at fraction tau.</summary>
        private static float At(float prev, float now, float tau) => prev + (now - prev) * tau;

        /// <summary>Map a fraction of the remaining sub-interval back onto the whole tick.</summary>
        private static float Remap(float floor, float tauWithin) => floor + tauWithin * (1f - floor);

        /// <summary>Two trajectories meet within the tick if their separation changes sign or touches zero.</summary>
        private static bool Meets(float d0, float d1) =>
            (d0 <= 0f && d1 >= 0f) || (d0 >= 0f && d1 <= 0f);

        /// <summary>Fraction of the tick at which separation d hits zero (d0 → d1 linear).</summary>
        private static float CrossTau(float d0, float d1)
        {
            float denom = d0 - d1;
            if (denom == 0f) return 0f; // static overlap: contact at once
            return Clamp01(d0 / denom);
        }

        private static float SafeTau(float num, float denom)
        {
            if (denom <= 0f) return 0f; // no motion but already at/over the boundary
            return Clamp01(num / denom);
        }

        private static float Clamp01(float v) => v < 0f ? 0f : (v > 1f ? 1f : v);

        private static void ConsiderEvent(float tau, SweepKind kind, int i, int j, List<Beam> bucket,
            ref float bestTau, ref SweepKind bestKind, ref int bestI, ref int bestJ)
        {
            // Total order: τ, then primary beam id, then secondary beam id, then kind.
            if (tau > bestTau) return;
            if (tau == bestTau)
            {
                int id = bucket[i].Id;
                int bestId = bestI >= 0 ? bucket[bestI].Id : int.MaxValue;
                if (id > bestId) return;
                if (id == bestId)
                {
                    int jd = j >= 0 ? bucket[j].Id : -1;
                    int bestJd = bestJ >= 0 ? bucket[bestJ].Id : -1;
                    if (jd > bestJd) return;
                    if (jd == bestJd && kind >= bestKind) return;
                }
            }
            bestTau = tau;
            bestKind = kind;
            bestI = i;
            bestJ = j;
        }

        /// <summary>
        /// Apply one sweep event. Every branch consumes at least one beam, which
        /// is what makes the sweep terminate — there is deliberately no "give up
        /// and stop" path, because abandoning a wire mid-tick would leave a
        /// crossing unresolved and silently break the rules.
        /// </summary>
        private void ProcessSweepEvent(Wire wire, List<Beam> bucket, ref Contest contest,
            SweepKind kind, float tau, int i, int j)
        {
            Beam a = bucket[i];
            switch (kind)
            {
                case SweepKind.Arrival:
                {
                    _arrivals.Add(new ArrivalEvent
                    {
                        Tau = tau,
                        WireId = wire.Id,
                        SourceId = a.Id,
                        Owner = a.Owner,
                        Power = a.Power,
                        NodeId = wire.DestinationNode(a.Dir),
                    });
                    RemoveBeam(bucket, i);
                    return;
                }

                case SweepKind.Absorb:
                {
                    AbsorbIntoContest(contest, a, wire);
                    RemoveBeam(bucket, i);
                    return;
                }

                case SweepKind.Merge:
                {
                    Beam o = bucket[j];
                    // The beam that was in front at tick start keeps its identity.
                    bool aFront = a.Dir > 0 ? a.PrevT >= o.PrevT : a.PrevT <= o.PrevT;
                    Beam kept = aFront ? a : o;
                    Beam gone = aFront ? o : a;
                    kept.Power += gone.Power;
                    if (gone.Speed > kept.Speed)
                    {
                        // Take the faster beam's speed AND its position: the
                        // merged packet travels at that speed for the rest of the
                        // tick, so leaving it at the slower front's position
                        // would quietly lose distance on every merge.
                        kept.Speed = gone.Speed;
                        kept.T = gone.T;
                        kept.PrevT = gone.PrevT;
                    }
                    BeamMerged?.Invoke(kept.Id, gone.Id);
                    RemoveBeam(bucket, bucket.IndexOf(gone));
                    return;
                }

                case SweepKind.Net:
                {
                    // Same owner, opposite directions: charge flowing both ways
                    // along one wire nets out, and the difference carries on in
                    // the direction of the larger send. The mirror of the chase
                    // rule, and load-bearing: letting these pass through each
                    // other is what lets a beam end up on the far side of a
                    // front, which in turn allows a SECOND opposing crossing on
                    // the same wire -- a configuration a single Contest cannot
                    // represent (its two sides would each need two directions).
                    Beam o = bucket[j];
                    float diff = a.Power - o.Power;
                    if (diff > Tuning.PowerEpsilon)
                    {
                        a.Power = diff;
                        BeamMerged?.Invoke(a.Id, o.Id);
                        RemoveBeam(bucket, bucket.IndexOf(o));
                    }
                    else if (diff < -Tuning.PowerEpsilon)
                    {
                        o.Power = -diff;
                        BeamMerged?.Invoke(o.Id, a.Id);
                        RemoveBeam(bucket, bucket.IndexOf(a));
                    }
                    else
                    {
                        BeamMerged?.Invoke(-1, a.Id);
                        int oi = bucket.IndexOf(o);
                        RemoveBeam(bucket, oi);
                        RemoveBeam(bucket, bucket.IndexOf(a));
                    }
                    return;
                }

                case SweepKind.Chase:
                {
                    // Opposing owners, same direction (possible after ownership
                    // flips): instant clash, no stationary tug-of-war (matrix #2).
                    Beam o = bucket[j];
                    float diff = a.Power - o.Power;
                    if (diff > Tuning.PowerEpsilon)
                    {
                        a.Power = diff;
                        BeamClashed?.Invoke(a.Id, wire.Id);
                        RemoveBeam(bucket, bucket.IndexOf(o));
                    }
                    else if (diff < -Tuning.PowerEpsilon)
                    {
                        o.Power = -diff;
                        BeamClashed?.Invoke(o.Id, wire.Id);
                        RemoveBeam(bucket, bucket.IndexOf(a));
                    }
                    else
                    {
                        BeamClashed?.Invoke(-1, wire.Id);
                        int oi = bucket.IndexOf(o);
                        RemoveBeam(bucket, oi);
                        RemoveBeam(bucket, bucket.IndexOf(a));
                    }
                    return;
                }

                case SweepKind.SpawnContest:
                {
                    Beam o = bucket[j];
                    if (contest != null)
                    {
                        // Should be unreachable: opposing beams cannot pass each
                        // other, and same-owner opposite-direction beams now net
                        // out rather than passing through, so a second disjoint
                        // crossing cannot form (matrix #9/#10).
                        //
                        // If it ever does, fold both beams into the existing
                        // front by owner. Never leave a crossing unresolved: the
                        // assert compiles out of Release builds, so bailing here
                        // would mean tests (Debug) and the balance harness
                        // (Release) silently running different physics, with the
                        // Release path letting opposing beams pass through each
                        // other forever.
                        Debug.Assert(false, "invariant violated: second contest on wire " + wire.Id);
                        AbsorbIntoContest(contest, a, wire);
                        AbsorbIntoContest(contest, o, wire);
                        int oi2 = bucket.IndexOf(o);
                        RemoveBeam(bucket, oi2);
                        RemoveBeam(bucket, bucket.IndexOf(a));
                        return;
                    }
                    float pos = Clamp01(a.PrevT + (a.T - a.PrevT) * tau);
                    Beam playerBeam = a.Owner == Owner.Player ? a : o;
                    Beam aiBeam = a.Owner == Owner.Player ? o : a;
                    contest = new Contest
                    {
                        Id = _nextContestId++,
                        WireId = wire.Id,
                        ContactT = pos,
                        PrevContactT = pos,
                        PowerPlayer = playerBeam.Power,
                        PowerAi = aiBeam.Power,
                        DirPlayer = playerBeam.Dir,
                        SpeedPlayer = playerBeam.Speed,
                        SpeedAi = aiBeam.Speed,
                    };
                    _contests.Add(contest);
                    ContestsStarted++;
                    ContestStarted?.Invoke(contest.Id, wire.Id, pos);
                    int oi = bucket.IndexOf(o);
                    RemoveBeam(bucket, oi);
                    RemoveBeam(bucket, bucket.IndexOf(a));
                    return;
                }
            }
        }

        /// <summary>
        /// Fold a beam into a contest side. Reinforcement transfers POWER ONLY
        /// (spec §5.6): the side keeps the speed it entered with, so the
        /// survivor later resumes at its "original speed" per the resolution
        /// rule. Speed and power are deliberately separate axes (§5.4) — a burst
        /// reinforcement lends its weight, not its momentum.
        /// </summary>
        private void AbsorbIntoContest(Contest contest, Beam beam, Wire wire)
        {
            if (beam.Owner == Owner.Player) contest.PowerPlayer += beam.Power;
            else contest.PowerAi += beam.Power;
            ContestReinforced?.Invoke(contest.Id, wire.Id, beam.Owner, beam.Power);
        }

        private void RemoveBeam(List<Beam> bucket, int index)
        {
            Beam b = bucket[index];
            bucket.RemoveAt(index);
            _beams.Remove(b);
        }
    }
}
