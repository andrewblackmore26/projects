using System;
using System.Collections.Generic;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;

namespace Gridlock.Core
{
    /// <summary>
    /// A controller drives one side by enqueueing intents (the AI, a replay, a
    /// network peer). Controllers are ticked INSIDE Step in alternating order by
    /// tick parity (side-bias defense — lessons.md), and their intents are
    /// drained on the NEXT Step: the 1-tick intent latency is a contract.
    /// </summary>
    public interface ISimController
    {
        Owner Side { get; }
        void Tick(Simulation sim);
    }

    /// <summary>
    /// The whole game. Fixed timestep 1/60 s, deterministic, engine-free.
    /// Presentation layers read state and subscribe to events; they never mutate —
    /// all input arrives through the intent queue. The Simulation itself contains
    /// ZERO randomness (controllers own their RNGs), so the state hash is
    /// RNG-independent.
    ///
    /// Tick phase order (fixed, load-bearing — see docs and tests):
    ///   1 timer expiry (Disabled/CaptureLocked, absolute tick indices)
    ///   2 drain intent queue (holds begin/cancel, sends execute)
    ///   3 controllers tick (enqueue intents for the NEXT tick; parity-alternating order)
    ///   4 charge accrual
    ///   5 hold-progress events
    ///   6 contest burn/push/resolution           (BeamPhase.cs)
    ///   7 beam movement + interaction sweep + arrivals (BeamPhase.cs)
    ///   8 win/objective evaluation
    /// </summary>
    public partial class Simulation
    {
        public readonly Tuning Tuning;
        public readonly LevelData Level;

        private readonly List<GameNode> _nodes = new List<GameNode>();
        private readonly List<Wire> _wires = new List<Wire>();
        private readonly Dictionary<int, GameNode> _nodesById = new Dictionary<int, GameNode>();
        private readonly Dictionary<int, Wire> _wiresById = new Dictionary<int, Wire>();
        private readonly List<Beam> _beams = new List<Beam>();
        private readonly List<Contest> _contests = new List<Contest>();
        private readonly List<ISimController> _controllers = new List<ISimController>();
        private readonly Queue<Intent> _intents = new Queue<Intent>();

        private long _tick;
        private int _nextBeamId;
        private int _nextContestId;
        private double _accumulator;
        private MatchResult _result = MatchResult.None;

        // Stats (balance instrumentation).
        public int PlayerSends { get; private set; }
        public int AiSends { get; private set; }
        public int PlayerCaptures { get; private set; }
        public int AiCaptures { get; private set; }
        public int ContestsStarted { get; private set; }
        public int ContestSideDeathResolutions { get; private set; }
        public int ContestMutualDeaths { get; private set; }
        public int ContestEndpointResolutions { get; private set; }

        public long Tick => _tick;
        public float TimeSeconds => _tick * Tuning.Dt;
        public MatchResult Result => _result;
        public IReadOnlyList<GameNode> Nodes => _nodes;
        public IReadOnlyList<Wire> Wires => _wires;
        public IReadOnlyList<Beam> Beams => _beams;
        public IReadOnlyList<Contest> Contests => _contests;

        public GameNode NodeById(int id) => _nodesById.TryGetValue(id, out GameNode n) ? n : null;
        public Wire WireById(int id) => _wiresById.TryGetValue(id, out Wire w) ? w : null;

        // ---- Events (primitive payloads only — presentation must not hold sim object refs) ----

        public event Action<int, Owner, Owner> NodeCaptured;          // nodeId, newOwner, prevOwner
        public event Action<int, Owner, float> NodeChipped;           // nodeId, attacker, amount
        public event Action<int, int, Owner, float, int> BeamSpawned; // beamId, wireId, owner, power, dir
        public event Action<int, int> BeamMerged;                     // keptBeamId, absorbedBeamId
        public event Action<int, int> BeamClashed;                    // survivorBeamId (-1 if mutual), wireId
        public event Action<int, int, float> ContestStarted;          // contestId, wireId, contactT
        public event Action<int, int, Owner, float> ContestReinforced;// contestId, wireId, side, addedPower
        public event Action<int, int, Owner, float> ContestResolved;  // contestId, wireId, winner (Neutral = mutual), survivorPower
        public event Action<int, int, Owner, float> BeamArrived;      // wireId, nodeId, owner, power
        public event Action<int> NodeOvercharging;                    // nodeId (hold began)
        public event Action<int> NodeOverchargeArmed;                 // nodeId (hold crossed the burst threshold)
        public event Action<int> NodeDisabled;                        // nodeId
        public event Action<int, NodeState, NodeState> NodeStateChanged; // nodeId, newState, prevState
        public event Action<MatchResult> MatchEnded;

        public Simulation(LevelData level, Tuning tuning)
            : this(LevelLoader.Build(level, tuning), tuning)
        {
        }

        public Simulation(BuiltLevel built, Tuning tuning)
        {
            Tuning = tuning;
            Level = built.Data;
            foreach (GameNode n in built.Nodes)
            {
                _nodes.Add(n);
                _nodesById[n.Id] = n;
            }
            foreach (Wire w in built.Wires)
            {
                _wires.Add(w);
                _wiresById[w.Id] = w;
            }
        }

        public void AddController(ISimController controller)
        {
            _controllers.Add(controller);
        }

        // ---- Intents (the only write surface for input and AI) ----

        private enum IntentKind { BeginHold, CancelHold, ReleaseSend }

        private struct Intent
        {
            public IntentKind Kind;
            public Owner Actor;
            public int NodeId;
            public int WireId;
        }

        /// <summary>Begin holding an owned Idle node (it starts brightening immediately — the opponent sees it).</summary>
        public void EnqueueBeginHold(Owner actor, int nodeId) =>
            _intents.Enqueue(new Intent { Kind = IntentKind.BeginHold, Actor = actor, NodeId = nodeId });

        /// <summary>Cancel a hold. Costs nothing — but the brighten was already visible (feinting is intended).</summary>
        public void EnqueueCancelHold(Owner actor, int nodeId) =>
            _intents.Enqueue(new Intent { Kind = IntentKind.CancelHold, Actor = actor, NodeId = nodeId });

        /// <summary>Release the hold over a connected wire: the send fires with whatever hold accumulated.</summary>
        public void EnqueueReleaseSend(Owner actor, int nodeId, int wireId) =>
            _intents.Enqueue(new Intent { Kind = IntentKind.ReleaseSend, Actor = actor, NodeId = nodeId, WireId = wireId });

        // ---- Stepping ----

        /// <summary>Accumulator entry point for presentation layers. Never read frame delta inside Core.</summary>
        public void Advance(double frameSeconds)
        {
            _accumulator += frameSeconds;
            double dt = Tuning.Dt;
            while (_accumulator >= dt)
            {
                Step();
                _accumulator -= dt;
            }
        }

        /// <summary>One fixed 1/60 s tick.</summary>
        public void Step()
        {
            if (_result != MatchResult.None)
            {
                // Time still advances after the match ends (nothing else does):
                // otherwise every `while (sim.Tick < X) sim.Step()` loop out
                // there becomes an infinite loop the moment a match finishes.
                _tick++;
                return;
            }

            ExpireTimers();          // 1
            DrainIntents();          // 2
            TickControllers();       // 3
            AccrueCharge();          // 4
            UpdateHolds();           // 5
            StepContests();          // 6 (BeamPhase.cs)
            StepBeams();             // 7 (BeamPhase.cs)
            EvaluateOutcome();       // 8

            _tick++;
        }

        private void ExpireTimers()
        {
            foreach (GameNode n in _nodes)
            {
                if (n.State == NodeState.Disabled && _tick >= n.DisabledUntilTick)
                    SetNodeState(n, NodeState.Idle);
                else if (n.State == NodeState.CaptureLocked && _tick >= n.LockUntilTick)
                    SetNodeState(n, NodeState.Idle);
            }
        }

        private void DrainIntents()
        {
            while (_intents.Count > 0)
            {
                Intent intent = _intents.Dequeue();
                if (intent.Actor == Owner.Neutral) continue;
                GameNode node = NodeById(intent.NodeId);
                if (node == null || node.Owner != intent.Actor) continue;

                switch (intent.Kind)
                {
                    case IntentKind.BeginHold:
                        if (node.State != NodeState.Idle) break;
                        if (node.Charge < Tuning.MinSendCharge) break;
                        node.HoldStartTick = _tick;
                        node.OverchargeArmed = false;
                        SetNodeState(node, NodeState.Overcharging);
                        NodeOvercharging?.Invoke(node.Id);
                        break;

                    case IntentKind.CancelHold:
                        if (node.State != NodeState.Overcharging) break;
                        EndHold(node);
                        SetNodeState(node, NodeState.Idle);
                        break;

                    case IntentKind.ReleaseSend:
                        if (node.State != NodeState.Overcharging) break;
                        Wire wire = WireById(intent.WireId);
                        if (wire == null || (wire.NodeA != node.Id && wire.NodeB != node.Id)) break;
                        if (node.Charge < Tuning.MinSendCharge) goto case IntentKind.CancelHold;
                        if (intent.Actor == Owner.Player &&
                            Level.Objective == ObjectiveType.Efficiency &&
                            PlayerSends >= Level.ObjectiveMaxSends)
                        {
                            // Send budget exhausted: the release degrades to a free cancel.
                            goto case IntentKind.CancelHold;
                        }
                        ExecuteSend(node, wire);
                        break;
                }
            }
        }

        private void ExecuteSend(GameNode node, Wire wire)
        {
            long holdTicks = node.HoldTicks(_tick);
            EndHold(node);
            float power;
            float speed;

            if (holdTicks >= Tuning.OverchargeTicks)
            {
                // Burst: everything, fast, and the node goes dark (spec §5.3).
                power = node.Charge;
                node.Charge = 0f;
                speed = Tuning.BaseBeamSpeed * Tuning.BurstSpeedMultiplier;
                node.DisabledUntilTick = _tick + Tuning.BurstCooldownTicks;
                SetNodeState(node, NodeState.Disabled);
                NodeDisabled?.Invoke(node.Id);
            }
            else
            {
                float progress = holdTicks / (float)Tuning.OverchargeTicks;
                float fraction = Tuning.MinSendFraction + (1f - Tuning.MinSendFraction) * progress;
                power = node.Charge * fraction;
                node.Charge -= power;
                speed = Tuning.BaseBeamSpeed;
                SetNodeState(node, NodeState.Idle);
            }

            if (node.Owner == Owner.Player) PlayerSends++;
            else AiSends++;

            if (power <= Tuning.PowerEpsilon) return;
            SpawnBeam(wire, node.Owner, power, speed, wire.DirectionFrom(node.Id));
        }

        private Beam SpawnBeam(Wire wire, Owner owner, float power, float speed, int dir, float t = -1f, bool holdThisTick = false)
        {
            var beam = new Beam
            {
                Id = _nextBeamId++,
                WireId = wire.Id,
                Owner = owner,
                Power = power,
                Speed = speed,
                Dir = dir,
                T = t >= 0f ? t : (dir > 0 ? 0f : 1f),
                HoldThisTick = holdThisTick,
            };
            beam.PrevT = beam.T;
            _beams.Add(beam);
            BeamSpawned?.Invoke(beam.Id, wire.Id, owner, power, dir);
            return beam;
        }

        private void TickControllers()
        {
            if (_controllers.Count == 0) return;
            // Alternate order by tick parity so neither side owns the constant
            // first-mover advantage (the old project's unresolved mirror bias).
            if (_tick % 2 == 0)
            {
                for (int i = 0; i < _controllers.Count; i++) _controllers[i].Tick(this);
            }
            else
            {
                for (int i = _controllers.Count - 1; i >= 0; i--) _controllers[i].Tick(this);
            }
        }

        private void AccrueCharge()
        {
            float dt = Tuning.Dt;
            foreach (GameNode n in _nodes)
            {
                if (n.Owner == Owner.Neutral || n.State == NodeState.Disabled) continue;
                float max = n.MaxCharge(Tuning);
                n.Charge += Tuning.BaseChargeRate * n.Degree * dt;
                if (n.Charge > max) n.Charge = max;
            }
        }

        private void UpdateHolds()
        {
            foreach (GameNode n in _nodes)
            {
                if (n.State != NodeState.Overcharging) continue;
                if (n.OverchargeArmed) continue;
                if (n.HoldTicks(_tick) >= Tuning.OverchargeTicks)
                {
                    n.OverchargeArmed = true;
                    NodeOverchargeArmed?.Invoke(n.Id);
                }
            }
        }

        /// <summary>Clear all hold state on a node (cancel, send, or capture).</summary>
        private static void EndHold(GameNode node)
        {
            node.HoldStartTick = -1;
            node.OverchargeArmed = false;
        }

        private void SetNodeState(GameNode node, NodeState state)
        {
            if (node.State == state) return;
            NodeState prev = node.State;
            node.State = state;
            NodeStateChanged?.Invoke(node.Id, state, prev);
        }

        // ---- Node resolution (spec §5.7) ----

        private void ResolveArrival(Owner owner, float power, int nodeId, int wireId)
        {
            if (power <= Tuning.PowerEpsilon) return;
            GameNode node = _nodesById[nodeId];
            BeamArrived?.Invoke(wireId, nodeId, owner, power);

            if (node.Owner == owner)
            {
                float max = node.MaxCharge(Tuning);
                node.Charge += power;
                if (node.Charge > max) node.Charge = max; // overflow lost
                return;
            }

            float defense = node.Owner == Owner.Neutral ? node.NeutralDefense : node.Charge;
            if (power > defense)
            {
                Owner prevOwner = node.Owner;
                node.Owner = owner;
                node.Charge = power - defense;
                EndHold(node); // capture cancels any hold in progress
                node.LockUntilTick = _tick + Tuning.CaptureLockTicks;
                SetNodeState(node, NodeState.CaptureLocked);
                if (owner == Owner.Player) PlayerCaptures++;
                else AiCaptures++;
                NodeCaptured?.Invoke(node.Id, owner, prevOwner);
            }
            else
            {
                if (node.Owner == Owner.Neutral)
                {
                    node.NeutralDefense = defense - power; // never regenerates (chipping is intended)
                    if (node.NeutralDefense < 0f) node.NeutralDefense = 0f;
                }
                else
                {
                    node.Charge = defense - power;
                    if (node.Charge < 0f) node.Charge = 0f;
                }
                NodeChipped?.Invoke(node.Id, owner, power);
            }
        }

        // ---- Outcome (spec §5.8 + §10.2) ----

        private void EvaluateOutcome()
        {
            bool playerNodes = false, aiNodes = false;
            foreach (GameNode n in _nodes)
            {
                if (n.Owner == Owner.Player) playerNodes = true;
                else if (n.Owner == Owner.Ai) aiNodes = true;
            }
            bool playerFlight = false, aiFlight = false;
            foreach (Beam b in _beams)
            {
                if (b.Owner == Owner.Player) playerFlight = true;
                else aiFlight = true;
            }
            foreach (Contest c in _contests)
            {
                if (c.PowerPlayer > Tuning.PowerEpsilon) playerFlight = true;
                if (c.PowerAi > Tuning.PowerEpsilon) aiFlight = true;
            }
            bool playerAlive = playerNodes || playerFlight;
            bool aiAlive = aiNodes || aiFlight;

            MatchResult result = MatchResult.None;
            switch (Level.Objective)
            {
                case ObjectiveType.Eliminate:
                case ObjectiveType.Efficiency:
                    if (!playerAlive && !aiAlive) result = MatchResult.Draw;
                    else if (!aiAlive) result = MatchResult.PlayerWin;
                    else if (!playerAlive) result = MatchResult.AiWin;
                    break;

                case ObjectiveType.Survive:
                    // "Hold at least one node for N seconds": decided ONCE, at the
                    // deadline tick. Holding a node then wins; holding none loses,
                    // even with beams still in flight — a beam is not a holding.
                    if (!playerAlive) result = MatchResult.AiWin;
                    else
                    {
                        long surviveTicks = (long)Math.Round(Level.ObjectiveSeconds * Tuning.TickRate);
                        if (_tick + 1 >= surviveTicks)
                            result = playerNodes ? MatchResult.PlayerWin : MatchResult.AiWin;
                    }
                    break;

                case ObjectiveType.Capture:
                    if (!playerAlive && !aiAlive) result = MatchResult.Draw;
                    else if (!playerAlive) result = MatchResult.AiWin;
                    else
                    {
                        bool all = true;
                        foreach (int id in Level.ObjectiveNodeIds)
                        {
                            if (_nodesById[id].Owner != Owner.Player) { all = false; break; }
                        }
                        if (all) result = MatchResult.PlayerWin;
                    }
                    break;
            }

            if (result != MatchResult.None)
            {
                _result = result;
                MatchEnded?.Invoke(result);
            }
        }

        /// <summary>Headless runners call this to declare a stalled match (spec has no in-sim clock limit).</summary>
        public void ForceTimeout()
        {
            if (_result != MatchResult.None) return;
            _result = MatchResult.Timeout;
            MatchEnded?.Invoke(_result);
        }

        // ---- Test hooks ----

        internal Beam SpawnBeamForTest(int wireId, Owner owner, float power, float speed, float t, int dir) =>
            SpawnBeam(_wiresById[wireId], owner, power, speed, dir, t);

        internal Contest SpawnContestForTest(int wireId, float contactT, float powerPlayer, float powerAi, int dirPlayer, float speedPlayer, float speedAi)
        {
            var contest = new Contest
            {
                Id = _nextContestId++,
                WireId = wireId,
                ContactT = contactT,
                PrevContactT = contactT,
                PowerPlayer = powerPlayer,
                PowerAi = powerAi,
                DirPlayer = dirPlayer,
                SpeedPlayer = speedPlayer,
                SpeedAi = speedAi,
            };
            _contests.Add(contest);
            return contest;
        }
    }
}
