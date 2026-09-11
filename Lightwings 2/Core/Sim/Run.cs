using System;
using System.Collections.Generic;
using Lightship.Core.Ai;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.World;

namespace Lightship.Core.Sim
{
    public sealed class ReshapeState
    {
        public ShipDefinition From;
        public ShipDefinition To;
        public long StartTick;
        public long EndTick;

        public float Progress(long tick) =>
            EndTick <= StartTick ? 1f : Math.Clamp((tick - StartTick) / (float)(EndTick - StartTick), 0f, 1f);
    }

    /// <summary>What this life has done to one sector: it is forgotten at death (the run resets).</summary>
    public sealed class SectorLife
    {
        public int Killed;          // regular enemies destroyed there this life
        public float LightPool;     // ambient light left in its pool
        public bool Cleared;
    }

    /// <summary>
    /// One life (spec 4, 5, 7): energy only goes up, tiers step at thresholds,
    /// evolution is player-triggered and offers the two most-absorbed lights.
    /// Owns the arena of the sector the player is in (only that one simulates)
    /// and answers its questions about the player.
    /// </summary>
    public sealed class Run : IArenaHost
    {
        public readonly Game Game;
        public readonly Tuning T;
        public float Energy;
        public int Tier = 1;
        public Element Root;
        public ShipDefinition Ship;                       // the player's current definition (player variant)
        public readonly float[] Absorbed = new float[8]; // since the last evolution, by (int)Element
        public EvolveOffer Offer = new EvolveOffer();
        public ReshapeState Reshape;
        public Arena Arena;
        public readonly HumanPilot Human = new HumanPilot();
        public int EnemiesKilled;
        public int Evolutions;

        // ---- world (null in the sandbox) ----
        public readonly WorldGrid World;
        public SectorCoord Sector;
        /// <summary>Spec 7: inside a gate whose gatekeeper still stands, every exit is shut.</summary>
        public bool LockedIn;
        public int Crossings;
        public int SectorsCleared;
        private readonly Dictionary<SectorCoord, SectorLife> _life = new Dictionary<SectorCoord, SectorLife>();
        private long _lastBlockedTick = long.MinValue / 2;
        private int _warnedEdge = -1;
        /// <summary>The edge being pushed into and for how many consecutive ticks (a crossing needs CrossDwellTicks).</summary>
        public int PushEdge { get; private set; } = -1;
        public int PushTicks { get; private set; }

        public Ship Player => Arena.Player;
        public Meta Meta => Game.Meta;
        public float Zoom => T.ZoomForTier(Tier);
        public bool Invulnerable => Reshape != null;
        public float Threshold => T.ThresholdForTier(Tier);
        /// <summary>
        /// Spec 5: locks at the threshold and stays available until taken. Never
        /// during a reshape: a second evolution mid-tween would snap the ship and
        /// the camera from a half-blended pose (the next offer waits for the end).
        /// </summary>
        public bool EvolveAvailable => Tier < 5 && Reshape == null && Offer.Count > 0 && Energy >= Threshold;
        public bool Dead => Player == null || !Player.Alive;
        public Sector CurrentSector => World?[Sector];

        /// <summary>
        /// A new life. startTick and firstShipId carry on from the life before: arena ticks and
        /// ship ids never restart within a game, so no absolute-tick timer anywhere (a pilot's
        /// aim re-roll, a loadout cooldown) can outlive its clock. Restarting them froze the novice
        /// bot's aim error for a whole life after its first death (15 s of misses at 140 units).
        /// </summary>
        public Run(Game game, ShipDefinition seed, IPilot playerPilot, SectorCoord start, long startTick = 0, int firstShipId = 1)
        {
            Game = game;
            T = game.T;
            World = game.World;
            Ship = seed.AsPlayerVariant();
            Root = seed.Element;
            // A seed is played at its own tier (a T3 seed has T3 HP, zoom and offers).
            Tier = Math.Clamp(seed.Tier, 1, 5);
            Energy = Tier >= 2 ? T.ThresholdForTier(Tier - 1) : 0f;
            Sector = start;
            Arena = new Arena(T, ForkFor(start), game.Events, this, game.Catalog, SetupFor(start), startTick, firstShipId);
            Arena.SpawnPlayer(Ship, Arena.Centre, playerPilot ?? Human, Health.MaxHp(Tier, T));
            if (World != null) OnEntered(Arena.Centre);
            RecomputeOffer();
        }

        public void SetPilot(IPilot pilot) => Player.Pilot = pilot ?? Human;

        /// <summary>
        /// One tick. The evolve and teleport intents are read from what the PILOT decided
        /// this tick (Player.LastInput), not from the input argument: the argument only
        /// feeds the human pilot, and reading it directly silently ignored every bot's and
        /// rival's decision.
        /// </summary>
        public void Step(PlayerInput input)
        {
            Human.Latest = input;
            Arena.Step();
            if (Reshape != null && Arena.Tick >= Reshape.EndTick)
            {
                Reshape = null;
                Game.Events.Add(EventKind.ReshapeEnded, Arena.Tick, Player.Pos, Ship.Element, Tier, Player.Id);
            }
            RecomputeOffer();
            if (Player.Alive && Player.LastInput.Evolve && EvolveAvailable) Evolve(Player.LastInput.EvolveChoice);
            if (World != null && Player.Alive) StepWorld();
        }

        public void RecomputeOffer() =>
            Offer = Evolution.ComputeOffer(Root, Tier, Absorbed, Game.Meta.Unlocked, Game.Catalog);

        /// <summary>Spec 5: take an offered form. Reshape runs for ReshapeTicks, invulnerable; tallies reset.</summary>
        public void Evolve(int choice)
        {
            if (!EvolveAvailable) return;
            ShipDefinition option = Offer.Options[Math.Clamp(choice, 0, Offer.Count - 1)];
            ShipDefinition next = option.AsPlayerVariant();
            Reshape = new ReshapeState { From = Ship, To = next, StartTick = Arena.Tick, EndTick = Arena.Tick + T.ReshapeTicks };
            Ship = next;
            Tier++;
            Root = option.Element;
            Evolutions++;
            Array.Clear(Absorbed, 0, Absorbed.Length);
            Player.SetDefinition(next);
            Player.MaxHp = Health.MaxHp(Tier, T);
            Player.Hp = MathF.Min(Player.MaxHp, Player.Hp + T.HpPerTier);
            Game.Events.Add(EventKind.Evolved, Arena.Tick, Player.Pos, option.Element, Tier, Player.Id);
            Game.Events.Add(EventKind.ReshapeStarted, Arena.Tick, Player.Pos, option.Element, Tier, Player.Id);
            RecomputeOffer();
        }

        // ---- world ----

        private DeterministicRandom ForkFor(SectorCoord c) =>
            // The sandbox keeps M1's exact stream, so its state hash is unchanged by the world.
            World == null ? Game.Rng.Fork(0x5A5A) : Game.Rng.Fork(0x5A5A ^ ((ulong)(uint)(c.X + 16) << 8) ^ (ulong)(uint)(c.Y + 16));

        public SectorLife Life(SectorCoord c)
        {
            if (!_life.TryGetValue(c, out SectorLife l))
            {
                l = new SectorLife { LightPool = T.SectorLightPool };
                _life[c] = l;
            }
            return l;
        }

        /// <summary>What a sector's arena holds on entry: its owner's light, its layer's enemies, minus what this life already beat.</summary>
        public SectorSetup SetupFor(SectorCoord c)
        {
            if (World == null) return SectorSetup.Sandbox(T);
            Sector s = World[c];
            SectorLife life = Life(c);
            if (s.Layer == 0) return new SectorSetup { Light = Element.None, EnemyTier = 1, EnemyBudget = 0, LightPool = 0f };
            // Player territory stays the player's through death (spec 7): no garrison comes back.
            // Its ambient light (the element it held) still flows, so a new life can regrow there.
            bool mine = Meta.PlayerTerritory.Contains(c);
            int budget = life.Cleared || mine ? 0 : Math.Max(0, s.EnemyCount - life.Killed);
            return new SectorSetup
            {
                Light = s.Owner, EnemyTier = s.EnemyTier, EnemyBudget = budget, LightPool = life.LightPool,
                AmbientIntervalTicks = mine ? T.TerritoryAmbientIntervalTicks : 0,
                AmbientSize = mine ? T.TerritoryAmbientSize : 0,
            };
        }

        private void StepWorld()
        {
            // A fallen gatekeeper opens the gate for good: it becomes a checkpoint (spec 7).
            if (LockedIn && (Arena.Gatekeeper == null || !Arena.Gatekeeper.Alive))
            {
                LockedIn = false;
                Meta.BeatenGates.Add(Sector);
                Meta.Checkpoints.Add(Sector);
                Game.Events.Add(EventKind.GateBeaten, Arena.Tick, Player.Pos, CurrentSector.Owner, Sector.Layer, Player.Id, new Vec2(Sector.X, Sector.Y));
            }

            // Clearing a sector flips it to the player; the flip persists through death.
            SectorLife life = Life(Sector);
            if (Sector.Layer > 0 && !life.Cleared && Arena.Cleared)
            {
                life.Cleared = true;
                SectorsCleared++;
                bool fresh = Meta.PlayerTerritory.Add(Sector);
                // It is the player's now, this visit included (a bot grazed at the rival's rate for 263 s).
                Arena.AmbientIntervalTicks = T.TerritoryAmbientIntervalTicks;
                Arena.AmbientSize = T.TerritoryAmbientSize;
                Game.Events.Add(EventKind.SectorCleared, Arena.Tick, Player.Pos, CurrentSector.Owner, fresh ? 1f : 0f, Player.Id, new Vec2(Sector.X, Sector.Y));
            }

            PlayerInput intent = Player.LastInput;
            if (intent.Teleport && TryTeleport(intent.TeleportTarget)) return;

            // Flying into an edge crosses it if the rules allow; otherwise the edge holds and says why.
            int pushing = PushingEdge(intent.Move);
            PushTicks = pushing >= 0 && pushing == PushEdge ? PushTicks + 1 : (pushing >= 0 ? 1 : 0);
            PushEdge = pushing;
            // A deliberate push, not a brush: backing off from a cone into an edge must not leave the fight.
            if (pushing >= 0 && PushTicks >= T.CrossDwellTicks)
            {
                var e = (Edge)pushing;
                SectorCoord to = Sector.Step(e);
                CrossResult r = World.CanCross(Sector, to, Energy, LockedIn, Meta);
                if (r == CrossResult.Ok)
                {
                    Cross(e);
                    return;
                }
                if (Arena.Tick - _lastBlockedTick >= T.CrossBlockedCooldownTicks)
                {
                    _lastBlockedTick = Arena.Tick;
                    Game.Events.Add(EventKind.CrossBlocked, Arena.Tick, Player.Pos, Element.None, (int)r, Player.Id, new Vec2(to.X, to.Y));
                }
            }
            StepGateWarning();
        }

        /// <summary>The edge the player is pressed against and still pushing into, or -1.</summary>
        private int PushingEdge(Vec2 move)
        {
            Vec2 p = Player.Pos;
            const float push = 0.2f;
            if (p.X <= 0f && move.X < -push) return (int)Edge.West;
            if (p.X >= Arena.Width && move.X > push) return (int)Edge.East;
            if (p.Y <= 0f && move.Y < -push) return (int)Edge.North;
            if (p.Y >= Arena.Height && move.Y > push) return (int)Edge.South;
            return -1;
        }

        /// <summary>Distance from the player to an edge of the arena.</summary>
        public float DistanceToEdge(Edge e)
        {
            Vec2 p = Player.Pos;
            switch (e)
            {
                case Edge.West: return p.X;
                case Edge.East: return Arena.Width - p.X;
                case Edge.North: return p.Y;
                default: return Arena.Height - p.Y;
            }
        }

        /// <summary>Would crossing this edge work right now, and if not, why (for the barriers and the HUD).</summary>
        public CrossResult EdgeResult(Edge e) =>
            World == null ? CrossResult.WorldEdge : World.CanCross(Sector, Sector.Step(e), Energy, LockedIn, Meta);

        /// <summary>Does this edge lead into a gate that has not fallen (a lock-in on entry)?</summary>
        public bool EdgeIntoGate(Edge e) =>
            World != null && World[Sector.Step(e)] is Sector n && n.IsGate && !Meta.BeatenGates.Contains(n.Coord);

        /// <summary>
        /// Spec 7 "no surprise traps": approaching an edge into an unbeaten gate warns once per
        /// approach, before the crossing, whether or not the player can cross yet.
        /// </summary>
        private void StepGateWarning()
        {
            foreach (Edge e in Edges.All)
            {
                if (!EdgeIntoGate(e)) continue;
                float d = DistanceToEdge(e);
                if (d <= T.GateWarnDistance && _warnedEdge != (int)e)
                {
                    _warnedEdge = (int)e;
                    SectorCoord gate = Sector.Step(e);
                    Game.Events.Add(EventKind.GateWarning, Arena.Tick, Player.Pos, World[gate].Owner, (int)EdgeResult(e), Player.Id, new Vec2(gate.X, gate.Y));
                }
                else if (d > T.GateWarnDistance * 1.3f && _warnedEdge == (int)e) _warnedEdge = -1;
            }
        }

        private void Cross(Edge e)
        {
            Vec2 p = Player.Pos;
            float inset = T.SectorEntryInset;
            Vec2 at;
            switch (e)
            {
                case Edge.East: at = new Vec2(inset, p.Y); break;
                case Edge.West: at = new Vec2(Arena.Width - inset, p.Y); break;
                case Edge.North: at = new Vec2(p.X, Arena.Height - inset); break;
                default: at = new Vec2(p.X, inset); break;
            }
            Crossings++;
            Travel(Sector.Step(e), at);
        }

        /// <summary>Spec 7: from the map, to a checkpoint, if energy meets that layer's veil. Never out of a lock-in.</summary>
        public bool CanTeleportTo(SectorCoord to) =>
            World != null && !LockedIn && to != Sector && World.CanTeleport(to, Energy, Meta);

        public bool TryTeleport(SectorCoord to)
        {
            if (!CanTeleportTo(to)) return false;
            Travel(to, Arena.Centre);
            Game.Events.Add(EventKind.Teleported, Arena.Tick, Player.Pos, CurrentSector.Owner, to.Layer, Player.Id, new Vec2(to.X, to.Y));
            return true;
        }

        /// <summary>
        /// Tests, tools and captures only: put the run in a sector without the crossing rules
        /// (arriving at its centre, gate lock-in and all). Play never calls this.
        /// </summary>
        public void Warp(SectorCoord to)
        {
            if (World == null || !World.Contains(to)) throw new ArgumentException("no sector " + to);
            Travel(to, Arena.Centre);
        }

        /// <summary>Leave this sector's arena (remembering what this life did there) and build the next one around the same ship.</summary>
        private void Travel(SectorCoord to, Vec2 at)
        {
            Ship player = Player;
            SectorLife here = Life(Sector);
            here.Killed += Arena.RegularsKilled;
            here.LightPool = Arena.LightPool;
            Arena old = Arena;
            Arena = new Arena(T, ForkFor(to), Game.Events, this, Game.Catalog, SetupFor(to), old.Tick, old.NextShipId);
            Arena.AdoptPlayer(player, at);
            Sector = to;
            _lastBlockedTick = long.MinValue / 2;
            _warnedEdge = -1;
            PushEdge = -1;
            PushTicks = 0;
            OnEntered(at);
        }

        private void OnEntered(Vec2 at)
        {
            Meta.Explored.Add(Sector);
            Sector s = CurrentSector;
            Game.Events.Add(EventKind.SectorEntered, Arena.Tick, at, s.Owner, s.Layer, Player.Id, new Vec2(Sector.X, Sector.Y));
            if (!s.IsGate || Meta.BeatenGates.Contains(Sector) || s.GatekeeperShip == null) return;
            ShipDefinition keeper = Game.Catalog.Get(s.GatekeeperShip);
            if (keeper == null) return;
            // The gatekeeper waits across the arena from where the player came in.
            Vec2 away = Arena.Centre - at;
            Vec2 pos = Arena.Centre + (away.LengthSquared() > 1f ? away.Normalized() : Vec2.Forward) * 500f;
            Arena.Gatekeeper = Arena.SpawnRival(keeper, pos, new RivalPilot(T, Arena.Rng.NextUlong()));
            LockedIn = true;
            Game.Events.Add(EventKind.GateLocked, Arena.Tick, at, s.Owner, keeper.Tier, Arena.Gatekeeper.Id, new Vec2(Sector.X, Sector.Y));
        }

        // ---- IArenaHost ----

        public int PlayerTier => Tier;
        public bool PlayerInvulnerable => Invulnerable;
        public float PlayerCoreRadius => T.CoreRadiusPx / Zoom;
        public float MagnetRadius => T.MagnetRadius(Tier) * (Invulnerable ? T.ReshapeMagnetMultiplier : 1f);

        /// <summary>Energy absorbed from the sector's own ambient light (spec 6: most should come from enemies).</summary>
        public float EnergyFromAmbient;
        public float EnergyAbsorbed;

        public void OnAbsorb(Element element, float energy) => OnAbsorb(element, energy, false);

        public void OnAbsorb(Element element, float energy, bool ambient)
        {
            Energy += energy;
            EnergyAbsorbed += energy;
            if (ambient) EnergyFromAmbient += energy;
            if ((int)element >= 0 && (int)element < Absorbed.Length) Absorbed[(int)element] += energy;
        }

        public void OnEnemyKilled(Ship enemy) => EnemiesKilled++;

        /// <summary>
        /// Open decision 1 (spec 4, 20): with DamageShedsLightFraction > 0 a hit knocks
        /// that fraction of the damage out as light. Energy never drops below the
        /// current tier's floor, so a hit can cost progress but never an evolution.
        /// </summary>
        public float EnergyShed;
        private float _shedCarry;   // fractional light owed, so contact damage (0.25 HP a tick) sheds too

        public void OnPlayerDamaged(float amount, Vec2 at)
        {
            float f = T.DamageShedsLightFraction;
            if (f <= 0f) return;
            float floor = Tier >= 2 ? T.ThresholdForTier(Tier - 1) : 0f;
            _shedCarry += amount * f;
            float whole = MathF.Floor(_shedCarry);
            if (whole < 1f) return;
            _shedCarry -= whole;
            float shed = MathF.Min(whole, MathF.Max(0f, Energy - floor));
            if (shed < 1f) return;
            Energy -= shed;
            EnergyShed += shed;
            Element e = Root == Element.None ? Element.Corruption : Root;
            Arena.SpawnShedLight(Player.Pos, e, shed, MagnetRadius + 20f);
        }
    }
}
