using System;
using System.Collections.Generic;
using Lightship.Core.Ai;
using Lightship.Core.Config;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
using Lightship.Core.Sim.Abilities;
using Lightship.Core.Sim.Patterns;

namespace Lightship.Core.Sim
{
    /// <summary>What the arena needs to know about the player's run without owning it.</summary>
    public interface IArenaHost
    {
        int PlayerTier { get; }
        bool PlayerInvulnerable { get; }
        float PlayerCoreRadius { get; }
        float MagnetRadius { get; }
        void OnAbsorb(Element element, float energy, bool ambient);
        void OnEnemyKilled(Ship enemy);
        void OnPlayerDamaged(float amount, Vec2 at);
    }

    /// <summary>
    /// What a sector puts in its arena (spec 7): its light, the tier of its regular
    /// enemies and how many are still to come this life. The sandbox is endless.
    /// </summary>
    public struct SectorSetup
    {
        public Element Light;          // ambient pickups and regular enemies; None = no light (the safe origin)
        public int EnemyTier;
        public int EnemyBudget;        // regular enemies still to spawn; -1 = endless (sandbox)
        public float LightPool;
        public int AmbientIntervalTicks;   // ticks between ambient pickups; 0 = the tuning default
        public int AmbientSize;            // ambient pickup size (0 = 1 energy, 1 = 5)

        public static SectorSetup Sandbox(Tuning t) =>
            new SectorSetup { Light = Element.Fire, EnemyTier = 1, EnemyBudget = -1, LightPool = t.SectorLightPool };
    }

    /// <summary>
    /// One sector being simulated: ships, bullets, pickups and the collision
    /// passes, stepped at a fixed 60 Hz. Everything here is deterministic given
    /// the seed and the inputs. Hostility is by side (see Sides): one collision
    /// pass serves the player, its drones, enemies and (M2) rivals alike.
    /// </summary>
    public sealed class Arena
    {
        public readonly Tuning T;
        public readonly DeterministicRandom Rng;
        public readonly EventLog Events;
        public readonly IArenaHost Host;
        public readonly ShipCatalog Catalog;

        public readonly List<Ship> Ships = new List<Ship>();
        public Ship Player;
        public readonly BulletPool Bullets;
        public readonly PickupPool Pickups;
        public readonly SpatialHash Hash;

        public float Width, Height;
        public Element SectorElement;
        public float LightPool;
        public long Tick;
        public int EnemiesKilled;
        public int EnemiesSpawned;
        /// <summary>Regular enemies destroyed by anyone (a sector counts these to be cleared).</summary>
        public int RegularsKilled;
        public int EnemyTier = 1;
        /// <summary>Regular enemies still allowed to spawn; -1 = endless.</summary>
        public int EnemyBudget = -1;
        /// <summary>The gate's rival boss, while this arena is a gate being fought.</summary>
        public Ship Gatekeeper;
        public bool SpawnEnemies = true;
        public bool SpawnAmbientLight = true;
        /// <summary>Bench only: bullets bounce off the arena walls instead of leaving, so the live count holds.</summary>
        public bool BounceBullets;
        /// <summary>Ticks between ambient pickups here (player territory sheds light faster: it is where a new life regrows).</summary>
        public int AmbientIntervalTicks;
        public int AmbientSize;

        private long _nextEnemySpawn;
        private int _nextShipId = 1;
        private readonly List<int> _query = new List<int>(256);
        private readonly List<Ship> _spawnQueue = new List<Ship>();

        public float Time => Tick * T.Dt;
        public Vec2 Centre => new Vec2(Width / 2f, Height / 2f);

        /// <summary>
        /// A new arena. Within one life the tick and the ship ids carry on from the sector the
        /// player came from (startTick, firstShipId): every timer in the player's loadout and
        /// reshape is an absolute tick, and a view keyed by ship id must never see an id reused.
        /// </summary>
        public Arena(Tuning t, DeterministicRandom rng, EventLog events, IArenaHost host, ShipCatalog catalog, SectorSetup setup,
            long startTick = 0, int firstShipId = 1)
        {
            T = t; Rng = rng; Events = events; Host = host; Catalog = catalog;
            Width = t.ArenaWidth; Height = t.ArenaHeight;
            SectorElement = setup.Light;
            EnemyTier = Math.Max(1, setup.EnemyTier);
            EnemyBudget = setup.EnemyBudget;
            LightPool = setup.LightPool;
            AmbientIntervalTicks = setup.AmbientIntervalTicks;
            AmbientSize = setup.AmbientSize;
            SpawnAmbientLight = setup.Light != Element.None;
            SpawnEnemies = setup.EnemyBudget != 0;
            Bullets = new BulletPool(t.BulletCapacity);
            Pickups = new PickupPool(t.PickupCapacity);
            Hash = new SpatialHash(Width, Height, t.HashCell, t.BulletCapacity);
            Tick = startTick;
            _nextShipId = firstShipId;
            _nextEnemySpawn = startTick + 60;
        }

        /// <summary>The id the next ship will get (a following arena starts here).</summary>
        public int NextShipId => _nextShipId;

        /// <summary>
        /// Spec 7: nothing left to fight. Regular enemies all spawned and gone, and no gatekeeper
        /// standing. Always false in the endless sandbox.
        /// </summary>
        public bool Cleared =>
            EnemyBudget >= 0 && EnemiesSpawned >= EnemyBudget && AliveRegulars() == 0 && (Gatekeeper == null || !Gatekeeper.Alive);

        // ---- spawning ----

        public Ship SpawnShip(ShipDefinition def, Faction faction, Vec2 pos, IPilot pilot, float hp, float speed)
        {
            var s = new Ship
            {
                Id = _nextShipId++, Faction = faction, Side = Sides.Of(faction, def.Element), Pos = pos, PrevPos = pos,
                Pilot = pilot, Hp = hp, MaxHp = hp, Speed = speed, SpawnTick = Tick,
            };
            s.SetDefinition(def);
            s.BreathPhase = Rng.Range(0f, T.BreathPeriod);
            // Ships born during a tick join after it, so no loop over Ships ever sees the list change.
            if (_inStep) _spawnQueue.Add(s); else Ships.Add(s);
            return s;
        }

        public Ship SpawnPlayer(ShipDefinition def, Vec2 pos, IPilot pilot, float hp)
        {
            Player = SpawnShip(def, Faction.Player, pos, pilot, hp, T.PlayerSpeed);
            Player.CoreOnlyHitbox = true;
            Player.Loadout = Loadout.Build(def, T);
            return Player;
        }

        /// <summary>The player arriving from another sector: same ship, same HP and loadout, a fresh position.</summary>
        public void AdoptPlayer(Ship player, Vec2 pos)
        {
            Player = player;
            player.Pos = pos;
            player.PrevPos = pos;      // no interpolation smear across the cut
            player.Vel = Vec2.Zero;
            if (_inStep) _spawnQueue.Add(player); else Ships.Add(player);
        }

        /// <summary>
        /// A rival (spec 8): the same tree and loadout as the player, driven by decisions.
        /// Rival-class HP; regenerates like the player; grabs light.
        /// </summary>
        public Ship SpawnRival(ShipDefinition def, Vec2 pos, IPilot pilot)
        {
            float hp = Health.MaxHp(def.Tier, T) * T.RivalHpMultiplier;
            Ship s = SpawnShip(def, Faction.Rival, pos, pilot, hp, T.RivalSpeed);
            s.Loadout = Loadout.Build(def, T);
            if (Player != null) s.Facing = (Player.Pos - pos).Normalized();
            Events.Add(EventKind.RivalSpawned, Tick, pos, def.Element, def.Tier, s.Id);
            return s;
        }

        public Ship SpawnEnemy(ShipDefinition def, Vec2 pos, PatternDefinition pattern)
        {
            float hp = T.EnemyT1Hp + T.EnemyHpPerTier * (def.Tier - 1);
            Ship s = SpawnShip(def, Faction.Enemy, pos, new EnemyPilot(), hp, T.EnemySpeed);
            s.Pattern = new PatternRunner(pattern, Tick);
            // Every visible part is an ability (spec 11.7): the pattern is its weapon, and the rest
            // of its parts (a Flare's vents, a Worm's nucleus) work as they would for anyone.
            s.Loadout = Loadout.Build(def, T, withWeapon: false);
            if (Player != null) s.Facing = (Player.Pos - pos).Normalized();
            EnemiesSpawned++;
            Events.Add(EventKind.EnemySpawned, Tick, pos, def.Element, def.Tier, s.Id);
            return s;
        }

        /// <summary>A drone hatched by an owner's pod: its side, its chassis colour, its infection if it infects.</summary>
        public Ship SpawnDrone(Ship owner, Vec2 pos)
        {
            ColorRole chassis = owner.Side == Sides.Player ? ColorRole.PlayerBlue : owner.Def.ChassisColor;
            Ship d = SpawnShip(BuiltinShips.Drone(chassis), owner.Faction, pos, new DronePilot(), T.DroneHp, T.DroneSpeed);
            d.Side = owner.Side;
            d.IsDrone = true;
            d.OwnerShipId = owner.Id;
            d.Facing = owner.Facing;
            d.DespawnTick = Tick + T.DroneLifeTicks;
            d.RamDamage = T.DroneRamDamage;
            d.RamFlags = owner.Loadout != null ? owner.Loadout.BulletFlags : (byte)0;
            Events.Add(EventKind.DroneHatched, Tick, pos, Element.Corruption, 0f, d.Id);
            return d;
        }

        public int SpawnBullet(byte side, Element element, Vec2 pos, Vec2 vel, float radius, float damage, int ttlTicks,
            byte flags = 0, int ownerId = -1) =>
            Bullets.Spawn(side, element, ElementShapes.BulletShapeOf(element), pos.X, pos.Y, vel.X, vel.Y, radius, damage, ttlTicks, Tick, flags, ownerId);

        /// <summary>Convenience for tests and probes: side from faction and element.</summary>
        public int SpawnBullet(Faction owner, Element element, Vec2 pos, Vec2 vel, float radius, float damage, int ttlTicks) =>
            SpawnBullet(Sides.Of(owner, element), element, pos, vel, radius, damage, ttlTicks);

        public int SpawnPickup(Element element, int size, Vec2 pos, bool ambient)
        {
            size = Math.Clamp(size, 0, 2);
            float value = T.PickupValues[size];
            Vec2 drift = Vec2.FromAngle(Rng.Range(0f, 2f * MathF.PI)) * T.PickupDriftSpeed;
            int period = Rng.RangeInt(0, 4) == 3 ? 1 : 0;
            int phase = Rng.RangeInt(0, 3);
            return Pickups.Spawn(element, size, value, pos.X, pos.Y, drift.X, drift.Y, period, phase, T.PickupTtlTicks, Tick, ambient);
        }

        /// <summary>Drop an energy total as the fewest pickups (20 / 5 / 1), scattered around a point.</summary>
        public void SpawnDrops(Vec2 pos, Element element, float energy)
        {
            int remaining = (int)MathF.Round(energy);
            int guard = 0;
            while (remaining > 0 && guard++ < 64)
            {
                int size = remaining >= 20 ? 2 : (remaining >= 5 ? 1 : 0);
                remaining -= (int)T.PickupValues[size];
                Vec2 offset = Vec2.FromAngle(Rng.Range(0f, 2f * MathF.PI)) * Rng.Range(4f, 18f);
                if (SpawnPickup(element, size, pos + offset, false) < 0) break;
            }
        }

        /// <summary>
        /// Open decision 1: light knocked out of the player by damage. Flung past the
        /// magnet radius so it has to be flown back to, never re-absorbed on the spot;
        /// near a wall the direction is re-rolled rather than clamped back inward.
        /// </summary>
        public void SpawnShedLight(Vec2 from, Element element, float energy, float minDistance)
        {
            int remaining = (int)MathF.Round(energy);
            int guard = 0;
            while (remaining > 0 && guard++ < 32)
            {
                int size = remaining >= 20 ? 2 : (remaining >= 5 ? 1 : 0);
                remaining -= (int)T.PickupValues[size];
                Vec2 pos = from;
                for (int attempt = 0; attempt < 12; attempt++)
                {
                    Vec2 dir = Vec2.FromAngle(Rng.Range(0f, 2f * MathF.PI));
                    pos = from + dir * Rng.Range(minDistance, minDistance + 50f);
                    if (pos.X >= 0f && pos.X <= Width && pos.Y >= 0f && pos.Y <= Height) break;
                }
                pos = new Vec2(Math.Clamp(pos.X, 0f, Width), Math.Clamp(pos.Y, 0f, Height));
                if (SpawnPickup(element, size, pos, false) < 0) break;
            }
        }

        /// <summary>
        /// Bench only: fill the arena with slow enemy bullets that bounce off the
        /// walls, so the budget is measured at a live count that holds. Bullets
        /// that reach the player's core still hit it and are freed.
        /// </summary>
        public void DebugSpawnBullets(int n)
        {
            BounceBullets = true;
            for (int i = 0; i < n; i++)
            {
                var pos = new Vec2(Rng.Range(0f, Width), Rng.Range(0f, Height));
                Vec2 vel = Vec2.FromAngle(Rng.Range(0f, 2f * MathF.PI)) * Rng.Range(40f, 120f);
                Element e = (Element)Rng.RangeInt(1, 5);
                if (SpawnBullet(Faction.Enemy, e, pos, vel, 3f, 4f, 60 * 60) < 0) break;
            }
        }

        // ---- the tick ----

        private bool _inStep;

        public void Step()
        {
            Tick++;
            float dt = T.Dt;
            _inStep = true;

            // 1. Pilots decide, ships move and turn.
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship s = Ships[i];
                if (!s.Alive) continue;
                PlayerInput input = s.Pilot != null ? s.Pilot.Decide(this, s) : default;
                s.LastInput = input;
                Vec2 move = input.Move;
                if (move.LengthSquared() > 1f) move = move.Normalized();
                s.PrevPos = s.Pos;
                s.Pos = s.Pos + move * s.Speed * dt;
                s.Pos = new Vec2(Math.Clamp(s.Pos.X, 0f, Width), Math.Clamp(s.Pos.Y, 0f, Height));
                // Velocity is what the ship actually did, after the wall: a ship pinned against an
                // edge is standing still (no burning trail, and nobody leads it into the wall).
                s.Vel = (s.Pos - s.PrevPos) / dt;
                if (input.Aim.LengthSquared() > 1e-6f) s.Facing = input.Aim.Normalized();
            }

            // 2. Weapons and abilities: loadouts for the player and rivals, patterns for enemies.
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship s = Ships[i];
                if (!s.Alive) continue;
                if (s.Loadout != null) s.Loadout.Tick(this, s, s.LastInput);
                if (s.Pattern != null) s.Pattern.Tick(this, s, s.LastInput.Fire);
            }

            // 3. Bullets move and expire.
            float margin = 64f;
            for (int i = 0; i < Bullets.High; i++)
            {
                if (!Bullets.Alive[i]) continue;
                Bullets.X[i] += Bullets.VX[i] * dt;
                Bullets.Y[i] += Bullets.VY[i] * dt;
                if (BounceBullets)
                {
                    if (Bullets.X[i] < 0f || Bullets.X[i] > Width) Bullets.VX[i] = -Bullets.VX[i];
                    if (Bullets.Y[i] < 0f || Bullets.Y[i] > Height) Bullets.VY[i] = -Bullets.VY[i];
                }
                if (--Bullets.Ttl[i] <= 0 || Bullets.X[i] < -margin || Bullets.X[i] > Width + margin ||
                    Bullets.Y[i] < -margin || Bullets.Y[i] > Height + margin)
                    Bullets.Free(i);
            }

            // 4. Spatial hash.
            Hash.Rebuild(Bullets);

            // 5. Collisions: bullets against every ship of another side, bodies against the player's core, drone rams.
            for (int i = 0; i < Ships.Count; i++)
                if (Ships[i].Alive) CollideBullets(Ships[i]);
            if (Player != null && Player.Alive) CollideBodiesWithPlayerCore(dt);
            for (int i = 0; i < Ships.Count; i++)
                if (Ships[i].Alive && Ships[i].IsDrone) CollideDrone(Ships[i]);

            // 6. Status effects: infection damage and spread.
            for (int i = 0; i < Ships.Count; i++)
                if (Ships[i].Alive && Ships[i].Infected(Tick)) StepInfection(Ships[i], dt);

            // 7. Pickups drift, are pulled in and absorbed.
            StepPickups(dt);

            // 8. Spawns, expiry and regeneration.
            if (SpawnAmbientLight) StepAmbientLight(dt);
            if (SpawnEnemies) StepEnemySpawns();
            for (int i = 0; i < Ships.Count; i++)
                if (Ships[i].IsDrone && Ships[i].Alive && Tick >= Ships[i].DespawnTick) Ships[i].Alive = false;
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship s = Ships[i];
                // Spec 9 regen for the player; spec 8 rivals "retreat to regenerate" under the same rule.
                if (s.Alive && (ReferenceEquals(s, Player) || s.IsRival))
                    s.Hp = Health.Regen(s.Hp, s.MaxHp, Tick, s.LastDamageTick, T);
            }

            // 9. Bury the dead (the player stays: the run reads its death) and admit the newborn.
            _inStep = false;
            for (int i = Ships.Count - 1; i >= 0; i--)
                if (!Ships[i].Alive && !ReferenceEquals(Ships[i], Player)) Ships.RemoveAt(i);
            if (_spawnQueue.Count > 0)
            {
                Ships.AddRange(_spawnQueue);
                _spawnQueue.Clear();
            }
        }

        private void CollideBullets(Ship s)
        {
            bool core = s.CoreOnlyHitbox;
            float coreR = core ? Host.PlayerCoreRadius : 0f;
            Hash.Query(s.Pos.X, s.Pos.Y, (core ? coreR : s.BoundRadius) + 12f, _query);
            for (int q = 0; q < _query.Count && s.Alive; q++)
            {
                int b = _query[q];
                if (!Bullets.Alive[b] || !Sides.Hostile(Bullets.Side[b], s.Side)) continue;
                var bp = new Vec2(Bullets.X[b], Bullets.Y[b]);
                if (core)
                {
                    float reach = coreR + Bullets.Radius[b];
                    if (Vec2.DistanceSquared(bp, s.Pos) > reach * reach) continue;
                    Bullets.Free(b);
                    if (ReferenceEquals(s, Player) && Host.PlayerInvulnerable) continue;
                    Damage(s, Bullets.Damage[b], Bullets.Side[b], bp, true);
                    // Corruption spores infect whatever they hit, the player's core included (spec 12).
                    if (s.Alive && (Bullets.Flags[b] & BulletFlags.Infect) != 0)
                        Infect(s, Bullets.Side[b], (Bullets.Flags[b] & BulletFlags.Spreads) != 0);
                }
                else
                {
                    if (!HitsBody(s, bp, Bullets.Radius[b])) continue;
                    Bullets.Free(b);
                    Damage(s, Bullets.Damage[b], Bullets.Side[b], bp, true);
                    if (s.Alive && (Bullets.Flags[b] & BulletFlags.Infect) != 0)
                        Infect(s, Bullets.Side[b], (Bullets.Flags[b] & BulletFlags.Spreads) != 0);
                }
            }
        }

        private void CollideBodiesWithPlayerCore(float dt)
        {
            if (Host.PlayerInvulnerable) return;
            float coreR = Host.PlayerCoreRadius;
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship e = Ships[i];
                if (!e.Alive || e.IsDrone || !Sides.Hostile(e.Side, Player.Side)) continue;
                float reach = e.BoundRadius + coreR;
                if (Vec2.DistanceSquared(e.Pos, Player.Pos) > reach * reach) continue;
                if (e.Geometry.ContainsPoint(e.ToLocal(Player.Pos)))
                    Damage(Player, T.ContactDamagePerSecond * dt, e.Side, Player.Pos, false);
            }
        }

        /// <summary>A drone touching a hostile body rams it: damage, its infection, and the drone is spent.</summary>
        private void CollideDrone(Ship d)
        {
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship t = Ships[i];
                if (!t.Alive || t.IsDrone || !Sides.Hostile(t.Side, d.Side)) continue;
                bool hit = t.CoreOnlyHitbox
                    ? Vec2.Distance(t.Pos, d.Pos) <= Host.PlayerCoreRadius + d.BoundRadius * 0.6f
                    : HitsBody(t, d.Pos, d.BoundRadius * 0.6f);
                if (!hit) continue;
                if (!(ReferenceEquals(t, Player) && Host.PlayerInvulnerable)) Damage(t, d.RamDamage, d.Side, d.Pos, true);
                if (t.Alive && (d.RamFlags & BulletFlags.Infect) != 0 && !t.CoreOnlyHitbox)
                    Infect(t, d.Side, (d.RamFlags & BulletFlags.Spreads) != 0);
                d.Alive = false;
                return;
            }
        }

        /// <summary>The drawn body is hit, not its bounding circles (a circle at the point touches a part's fill or outline).</summary>
        public static bool HitsBody(Ship s, Vec2 world, float radius)
        {
            float reach = s.BoundRadius + radius;
            if (Vec2.DistanceSquared(s.Pos, world) > reach * reach) return false;
            Vec2 local = s.ToLocal(world);
            for (int p = 0; p < s.Geometry.Parts.Count; p++)
                if (s.Geometry.Parts[p].Touches(local, radius)) return true;
            float cr = s.Geometry.CoreRadius + radius;
            return local.LengthSquared() <= cr * cr;
        }

        // ---- damage, infection, death ----

        public void Infect(Ship s, byte bySide, bool spreads)
        {
            bool fresh = !s.Infected(Tick);
            s.InfectedUntil = Tick + T.InfectDurationTicks;
            s.InfectDps = T.InfectDps;
            s.InfectSide = bySide;
            s.InfectSpreads |= spreads;
            if (fresh)
            {
                s.NextSpreadTick = Tick + T.SpreadFirstJumpTicks;
                Events.Add(EventKind.Infected, Tick, s.Pos, Element.Corruption, 0f, s.Id);
            }
        }

        private void StepInfection(Ship s, float dt)
        {
            Damage(s, s.InfectDps * dt, s.InfectSide, s.Pos, false);
            if (!s.Alive || !s.InfectSpreads || Tick < s.NextSpreadTick) return;
            s.NextSpreadTick = Tick + T.SpreadIntervalTicks;
            Ship best = null;
            float bestD = T.SpreadRadius * T.SpreadRadius;
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship o = Ships[i];
                if (!o.Alive || o == s || o.CoreOnlyHitbox || o.Infected(Tick)) continue;
                if (!Sides.Hostile(o.Side, s.InfectSide)) continue;
                float d = Vec2.DistanceSquared(o.Pos, s.Pos);
                if (d < bestD) { bestD = d; best = o; }
            }
            if (best == null) return;
            Infect(best, s.InfectSide, true);
            Events.Add(EventKind.InfectSpread, Tick, s.Pos, Element.Corruption, 0f, best.Id, best.Pos);
        }

        /// <summary>
        /// All damage goes through here. Direct hits on non-player ships shed a little
        /// light (spec 6, rate-limited); damage over time does not. A kill by the
        /// player's side drops energy scaled by the tier gap (spec 8).
        /// </summary>
        public void Damage(Ship s, float amount, byte attackerSide, Vec2 at, bool direct)
        {
            if (!s.Alive) return;
            if (ReferenceEquals(s, Player)) { DamagePlayer(amount, at); return; }
            s.Hp -= amount;
            s.LastDamageTick = Tick;
            if (direct)
            {
                Events.Add(EventKind.Hit, Tick, at, s.Element, amount, s.Id);
                if (!s.IsDrone && Tick - s.LastShedTick >= T.HitShedCooldownTicks)
                {
                    s.LastShedTick = Tick;
                    SpawnPickup(s.Element, 0, at, false);
                }
            }
            if (s.Hp > 0f) return;
            s.Hp = 0f;
            s.Alive = false;
            if (s.IsDrone) return;
            if (s.Faction == Faction.Enemy) RegularsKilled++;
            Events.Add(EventKind.Kill, Tick, s.Pos, s.Element, 0f, s.Id);
            if (attackerSide != Sides.Player) return;
            EnemiesKilled++;
            float energy = Rewards.DropEnergy(s.Tier) * Rewards.Scale(s.Tier, Host.PlayerTier, T.RewardGapFactor)
                           * (s.Faction == Faction.Rival ? T.RivalDropMultiplier : 1f);
            SpawnDrops(s.Pos, s.Element, energy);
            Host.OnEnemyKilled(s);
        }

        /// <summary>Kept for tests and tools: a direct hit by the player's side.</summary>
        public void DamageEnemy(Ship e, float amount, Vec2 at) => Damage(e, amount, Sides.Player, at, true);

        public void DamagePlayer(float amount, Vec2 at)
        {
            // The one choke point for the reshape's invulnerability (spec 5): an infection that was
            // ticking before the evolve used to keep hurting through it.
            if (Player == null || !Player.Alive || Host.PlayerInvulnerable) return;
            Player.Hp -= amount;
            Player.LastDamageTick = Tick;
            Events.Add(EventKind.PlayerDamaged, Tick, at, Element.None, amount, Player.Id);
            Host.OnPlayerDamaged(amount, at);
            if (Player.Hp <= 0f)
            {
                Player.Hp = 0f;
                Player.Alive = false;
                Events.Add(EventKind.PlayerDied, Tick, Player.Pos, Element.None, 0f, Player.Id);
            }
        }

        // ---- pickups and spawns ----

        private readonly List<Ship> _rivals = new List<Ship>();

        private void StepPickups(float dt)
        {
            bool playerAlive = Player != null && Player.Alive;
            float magnet = Host.MagnetRadius;
            float absorbR = Host.PlayerCoreRadius + T.AbsorbRadius;
            _rivals.Clear();
            for (int i = 0; i < Ships.Count; i++)
                if (Ships[i].Alive && Ships[i].IsRival) _rivals.Add(Ships[i]);
            for (int i = 0; i < Pickups.High; i++)
            {
                if (!Pickups.Alive[i]) continue;
                if (--Pickups.Ttl[i] <= 0) { Pickups.Free(i); continue; }
                if (_rivals.Count > 0 && RivalGrabs(i)) continue;
                if (playerAlive)
                {
                    float dx = Player.Pos.X - Pickups.X[i], dy = Player.Pos.Y - Pickups.Y[i];
                    float d2 = dx * dx + dy * dy;
                    if (d2 <= absorbR * absorbR)
                    {
                        Host.OnAbsorb((Element)Pickups.Elem[i], Pickups.Value[i], Pickups.Ambient[i]);
                        Events.Add(EventKind.Absorb, Tick, new Vec2(Pickups.X[i], Pickups.Y[i]), (Element)Pickups.Elem[i], Pickups.Value[i]);
                        Pickups.Free(i);
                        continue;
                    }
                    if (d2 <= magnet * magnet)
                    {
                        float d = MathF.Sqrt(d2);
                        float pull = 320f;
                        Pickups.VX[i] = dx / d * pull;
                        Pickups.VY[i] = dy / d * pull;
                    }
                    else
                    {
                        Pickups.VX[i] = Pickups.DriftX[i];
                        Pickups.VY[i] = Pickups.DriftY[i];
                    }
                }
                Pickups.X[i] += Pickups.VX[i] * dt;
                Pickups.Y[i] += Pickups.VY[i] * dt;
                if (Pickups.X[i] < 0f || Pickups.X[i] > Width) { Pickups.DriftX[i] = -Pickups.DriftX[i]; Pickups.X[i] = Math.Clamp(Pickups.X[i], 0f, Width); }
                if (Pickups.Y[i] < 0f || Pickups.Y[i] > Height) { Pickups.DriftY[i] = -Pickups.DriftY[i]; Pickups.Y[i] = Math.Clamp(Pickups.Y[i], 0f, Height); }
            }
        }

        /// <summary>Spec 8: a rival flying over light takes it (and the player does not get it). It heals the rival.</summary>
        private bool RivalGrabs(int i)
        {
            // Light it just shed from its own hull is not on offer yet: it has to fly back for it.
            if (Tick - Pickups.Born[i] < T.RivalGrabMinAgeTicks) return false;
            for (int r = 0; r < _rivals.Count; r++)
            {
                Ship s = _rivals[r];
                float reach = s.Geometry.CoreRadius + T.AbsorbRadius + 6f;
                float dx = s.Pos.X - Pickups.X[i], dy = s.Pos.Y - Pickups.Y[i];
                if (dx * dx + dy * dy > reach * reach) continue;
                s.Hp = MathF.Min(s.MaxHp, s.Hp + Pickups.Value[i] * T.RivalHealPerEnergy);
                Events.Add(EventKind.RivalAbsorb, Tick, new Vec2(Pickups.X[i], Pickups.Y[i]), (Element)Pickups.Elem[i], Pickups.Value[i], s.Id);
                Pickups.Free(i);
                return true;
            }
            return false;
        }

        private void StepAmbientLight(float dt)
        {
            LightPool = MathF.Min(T.SectorLightPool, LightPool + T.SectorLightRegenPerSecond * dt);
            if (Tick % (AmbientIntervalTicks > 0 ? AmbientIntervalTicks : T.AmbientSpawnIntervalTicks) != 0) return;
            float value = T.PickupValues[AmbientSize];
            if (LightPool < value || Pickups.LiveAmbient >= T.AmbientLightCap) return;
            var pos = new Vec2(Rng.Range(40f, Width - 40f), Rng.Range(40f, Height - 40f));
            if (SpawnPickup(SectorElement, AmbientSize, pos, true) >= 0) LightPool -= value;
        }

        private void StepEnemySpawns()
        {
            if (Tick < _nextEnemySpawn) return;
            if (EnemyBudget >= 0 && EnemiesSpawned >= EnemyBudget) return;
            if (AliveEnemies() >= T.MaxEnemies) { _nextEnemySpawn = Tick + 30; return; }
            _nextEnemySpawn = Tick + T.EnemySpawnIntervalTicks;
            ShipDefinition def = Catalog.Find(SectorElement == Element.None ? Element.Fire : SectorElement, EnemyTier)
                                 ?? Catalog.Find(Element.Fire, 1);
            if (def == null) return;
            // Enemies arrive in packs (a pack flies together, so an infection has a neighbour to jump to).
            Vec2 pos = FarFromPlayer(500f);
            int room = T.MaxEnemies - AliveEnemies();
            int n = Math.Min(T.EnemyPackSize, room);
            if (EnemyBudget >= 0) n = Math.Min(n, EnemyBudget - EnemiesSpawned);
            for (int k = 0; k < n; k++)
            {
                Vec2 at = pos + Vec2.FromAngle(2f * MathF.PI * k / Math.Max(n, 1)) * (k == 0 ? 0f : T.EnemyPackSpacing);
                at = new Vec2(Math.Clamp(at.X, 40f, Width - 40f), Math.Clamp(at.Y, 40f, Height - 40f));
                SpawnEnemy(def, at, PatternLibrary.ForEnemy(def.Element, def.Tier));
            }
        }

        private Vec2 FarFromPlayer(float minDistance)
        {
            for (int tries = 0; tries < 16; tries++)
            {
                var pos = new Vec2(Rng.Range(80f, Width - 80f), Rng.Range(80f, Height - 80f));
                if (Player == null || Vec2.Distance(pos, Player.Pos) >= minDistance) return pos;
            }
            return new Vec2(Rng.Range(80f, Width - 80f), 80f);
        }

        // ---- queries for pilots and views ----

        public Ship FindShip(int id)
        {
            for (int i = 0; i < Ships.Count; i++) if (Ships[i].Id == id) return Ships[i];
            for (int i = 0; i < _spawnQueue.Count; i++) if (_spawnQueue[i].Id == id) return _spawnQueue[i];
            return null;
        }

        /// <summary>The nearest living, non-drone ship hostile to a side, within a radius.</summary>
        public Ship NearestHostile(Vec2 from, byte side, float within = float.MaxValue)
        {
            Ship best = null;
            float bestD = within < float.MaxValue ? within * within : float.MaxValue;
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship s = Ships[i];
                if (!s.Alive || s.IsDrone || !Sides.Hostile(s.Side, side)) continue;
                float d = Vec2.DistanceSquared(s.Pos, from);
                if (d < bestD) { bestD = d; best = s; }
            }
            return best;
        }

        public Ship NearestEnemy(Vec2 from) => NearestHostile(from, Sides.Player);

        public int NearestPickup(Vec2 from, float within, int minAgeTicks = 0)
        {
            int best = -1;
            float bestD = within * within;
            for (int i = 0; i < Pickups.High; i++)
            {
                if (!Pickups.Alive[i] || Tick - Pickups.Born[i] < minAgeTicks) continue;
                float dx = Pickups.X[i] - from.X, dy = Pickups.Y[i] - from.Y;
                float d = dx * dx + dy * dy;
                if (d < bestD) { bestD = d; best = i; }
            }
            return best;
        }

        public int AliveEnemies()
        {
            int n = 0;
            for (int i = 0; i < Ships.Count; i++) if (Ships[i].Alive && Ships[i].Faction != Faction.Player) n++;
            return n;
        }

        /// <summary>Living regular enemies (not rivals, not drones).</summary>
        public int AliveRegulars()
        {
            int n = 0;
            for (int i = 0; i < Ships.Count; i++) if (Ships[i].Alive && Ships[i].Faction == Faction.Enemy && !Ships[i].IsDrone) n++;
            return n;
        }

        public int AliveDrones()
        {
            int n = 0;
            for (int i = 0; i < Ships.Count; i++) if (Ships[i].Alive && Ships[i].IsDrone) n++;
            return n;
        }

        /// <summary>Bullets within a radius, into the shared query list (do not hold it).</summary>
        public List<int> BulletsNear(Vec2 at, float radius)
        {
            Hash.Query(at.X, at.Y, radius, _query);
            return _query;
        }
    }
}
