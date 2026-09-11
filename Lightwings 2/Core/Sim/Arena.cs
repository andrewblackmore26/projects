using System;
using System.Collections.Generic;
using Lightship.Core.Config;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
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
    /// One sector being simulated: ships, bullets, pickups and the collision
    /// passes, stepped at a fixed 60 Hz. Everything here is deterministic given
    /// the seed and the inputs.
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
        public int EnemyTier = 1;
        public bool SpawnEnemies = true;
        public bool SpawnAmbientLight = true;
        /// <summary>Bench only: bullets bounce off the arena walls instead of leaving, so the live count holds.</summary>
        public bool BounceBullets;

        private long _nextEnemySpawn;
        private int _nextShipId = 1;
        private readonly List<int> _query = new List<int>(256);

        public float Time => Tick * T.Dt;
        public Vec2 Centre => new Vec2(Width / 2f, Height / 2f);

        public Arena(Tuning t, DeterministicRandom rng, EventLog events, IArenaHost host, ShipCatalog catalog, Element sectorElement)
        {
            T = t; Rng = rng; Events = events; Host = host; Catalog = catalog;
            Width = t.ArenaWidth; Height = t.ArenaHeight;
            SectorElement = sectorElement;
            LightPool = t.SectorLightPool;
            Bullets = new BulletPool(t.BulletCapacity);
            Pickups = new PickupPool(t.PickupCapacity);
            Hash = new SpatialHash(Width, Height, t.HashCell, t.BulletCapacity);
            _nextEnemySpawn = 60;
        }

        // ---- spawning ----

        public Ship SpawnShip(ShipDefinition def, Faction faction, Vec2 pos, IPilot pilot, float hp, float speed)
        {
            var s = new Ship { Id = _nextShipId++, Faction = faction, Pos = pos, PrevPos = pos, Pilot = pilot, Hp = hp, MaxHp = hp, Speed = speed, SpawnTick = Tick };
            s.SetDefinition(def);
            s.BreathPhase = Rng.Range(0f, T.BreathPeriod);
            Ships.Add(s);
            return s;
        }

        public Ship SpawnPlayer(ShipDefinition def, Vec2 pos, IPilot pilot, float hp)
        {
            Player = SpawnShip(def, Faction.Player, pos, pilot, hp, T.PlayerSpeed);
            return Player;
        }

        public Ship SpawnEnemy(ShipDefinition def, Vec2 pos, PatternDefinition pattern)
        {
            float hp = T.EnemyT1Hp + T.EnemyHpPerTier * (def.Tier - 1);
            Ship s = SpawnShip(def, Faction.Enemy, pos, new Ai.EnemyPilot(), hp, T.EnemySpeed);
            s.Pattern = new PatternRunner(pattern, Tick);
            if (Player != null) s.Facing = (Player.Pos - pos).Normalized();
            Events.Add(EventKind.EnemySpawned, Tick, pos, def.Element, def.Tier, s.Id);
            return s;
        }

        public int SpawnBullet(Faction owner, Element element, Vec2 pos, Vec2 vel, float radius, float damage, int ttlTicks) =>
            Bullets.Spawn(owner, element, ElementShapes.BulletShapeOf(element), pos.X, pos.Y, vel.X, vel.Y, radius, damage, ttlTicks, Tick);

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
        /// magnet radius so it has to be flown back to, never re-absorbed on the spot.
        /// </summary>
        public void SpawnShedLight(Vec2 from, Element element, float energy, float minDistance)
        {
            int remaining = (int)MathF.Round(energy);
            int guard = 0;
            while (remaining > 0 && guard++ < 32)
            {
                int size = remaining >= 20 ? 2 : (remaining >= 5 ? 1 : 0);
                remaining -= (int)T.PickupValues[size];
                Vec2 dir = Vec2.FromAngle(Rng.Range(0f, 2f * MathF.PI));
                Vec2 pos = from + dir * Rng.Range(minDistance, minDistance + 50f);
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

        public void Step()
        {
            Tick++;
            float dt = T.Dt;

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
                s.Vel = move * s.Speed;
                s.Pos = s.Pos + s.Vel * dt;
                s.Pos = new Vec2(Math.Clamp(s.Pos.X, 0f, Width), Math.Clamp(s.Pos.Y, 0f, Height));
                if (input.Aim.LengthSquared() > 1e-6f) s.Facing = input.Aim.Normalized();
            }

            // 2. Firing.
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship s = Ships[i];
                if (!s.Alive) continue;
                if (s.Faction == Faction.Player)
                {
                    if (s.LastInput.Fire && Tick >= s.NextFireTick)
                    {
                        Vec2 dir = s.Facing;
                        SpawnBullet(Faction.Player, Element.None, s.Pos + dir * 8f, dir * T.PlayerBulletSpeed,
                            T.PlayerBulletRadius, T.PlayerBulletDamage, T.PlayerBulletTtlTicks);
                        s.NextFireTick = Tick + T.PlayerFireIntervalTicks;
                    }
                }
                else if (s.Pattern != null)
                {
                    s.Pattern.Tick(this, s, s.LastInput.Fire);
                }
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

            // 5. Collisions.
            if (Player != null && Player.Alive)
            {
                CollideEnemyBulletsWithPlayerCore();
                CollideEnemyBodiesWithPlayerCore(dt);
            }
            CollidePlayerBulletsWithEnemies();

            // 6. Pickups drift, are pulled in and absorbed.
            StepPickups(dt);

            // 7. Spawns and regeneration.
            if (SpawnAmbientLight) StepAmbientLight(dt);
            if (SpawnEnemies) StepEnemySpawns();
            if (Player != null && Player.Alive)
                Player.Hp = Health.Regen(Player.Hp, Player.MaxHp, Tick, Player.LastDamageTick, T);

            // 8. Bury the dead.
            for (int i = Ships.Count - 1; i >= 0; i--)
                if (!Ships[i].Alive && Ships[i].Faction != Faction.Player) Ships.RemoveAt(i);
        }

        private void CollideEnemyBulletsWithPlayerCore()
        {
            float coreR = Host.PlayerCoreRadius;
            Hash.Query(Player.Pos.X, Player.Pos.Y, coreR + 12f, _query);
            for (int q = 0; q < _query.Count; q++)
            {
                int b = _query[q];
                if (!Bullets.Alive[b] || Bullets.Owner[b] == (byte)Faction.Player) continue;
                float dx = Bullets.X[b] - Player.Pos.X, dy = Bullets.Y[b] - Player.Pos.Y;
                float reach = coreR + Bullets.Radius[b];
                if (dx * dx + dy * dy > reach * reach) continue;
                if (!Host.PlayerInvulnerable) DamagePlayer(Bullets.Damage[b], new Vec2(Bullets.X[b], Bullets.Y[b]));
                Bullets.Free(b);
            }
        }

        private void CollideEnemyBodiesWithPlayerCore(float dt)
        {
            if (Host.PlayerInvulnerable) return;
            float coreR = Host.PlayerCoreRadius;
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship e = Ships[i];
                if (!e.Alive || e.Faction == Faction.Player) continue;
                float reach = e.BoundRadius + coreR;
                if (Vec2.DistanceSquared(e.Pos, Player.Pos) > reach * reach) continue;
                Vec2 local = e.ToLocal(Player.Pos);
                if (e.Geometry.ContainsPoint(local))
                    DamagePlayer(T.ContactDamagePerSecond * dt, Player.Pos);
            }
        }

        private void CollidePlayerBulletsWithEnemies()
        {
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship e = Ships[i];
                if (!e.Alive || e.Faction == Faction.Player) continue;
                Hash.Query(e.Pos.X, e.Pos.Y, e.BoundRadius + 12f, _query);
                for (int q = 0; q < _query.Count && e.Alive; q++)
                {
                    int b = _query[q];
                    if (!Bullets.Alive[b] || Bullets.Owner[b] != (byte)Faction.Player) continue;
                    var bp = new Vec2(Bullets.X[b], Bullets.Y[b]);
                    if (!HitsBody(e, bp, Bullets.Radius[b])) continue;
                    Bullets.Free(b);
                    DamageEnemy(e, Bullets.Damage[b], bp);
                }
            }
        }

        /// <summary>Any part's bounding circle contains the point: enemies are hit anywhere on the body.</summary>
        public static bool HitsBody(Ship s, Vec2 world, float radius)
        {
            float reach = s.BoundRadius + radius;
            if (Vec2.DistanceSquared(s.Pos, world) > reach * reach) return false;
            Vec2 local = s.ToLocal(world);
            for (int p = 0; p < s.Geometry.Parts.Count; p++)
            {
                PartGeometry part = s.Geometry.Parts[p];
                if (part.IsTether || part.Dashed) continue;
                float r = part.BoundRadius + radius;
                if (Vec2.DistanceSquared(part.Centre, local) <= r * r) return true;
            }
            return Vec2.DistanceSquared(local, Vec2.Zero) <= (s.Geometry.CoreRadius + radius) * (s.Geometry.CoreRadius + radius);
        }

        public void DamagePlayer(float amount, Vec2 at)
        {
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

        public void DamageEnemy(Ship e, float amount, Vec2 at)
        {
            e.Hp -= amount;
            e.LastDamageTick = Tick;
            Events.Add(EventKind.Hit, Tick, at, e.Element, amount, e.Id);
            // Hits shed a little light of the enemy's element (spec 6), rate-limited per enemy.
            if (Tick - e.LastShedTick >= T.HitShedCooldownTicks)
            {
                e.LastShedTick = Tick;
                SpawnPickup(e.Element, 0, at, false);
            }
            if (e.Hp <= 0f)
            {
                e.Hp = 0f;
                e.Alive = false;
                EnemiesKilled++;
                float energy = Rewards.DropEnergy(e.Tier) * Rewards.Scale(e.Tier, Host.PlayerTier, T.RewardGapFactor);
                SpawnDrops(e.Pos, e.Element, energy);
                Events.Add(EventKind.Kill, Tick, e.Pos, e.Element, energy, e.Id);
                Host.OnEnemyKilled(e);
            }
        }

        private void StepPickups(float dt)
        {
            bool playerAlive = Player != null && Player.Alive;
            float magnet = Host.MagnetRadius;
            float absorbR = Host.PlayerCoreRadius + T.AbsorbRadius;
            for (int i = 0; i < Pickups.High; i++)
            {
                if (!Pickups.Alive[i]) continue;
                if (--Pickups.Ttl[i] <= 0) { Pickups.Free(i); continue; }
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

        private void StepAmbientLight(float dt)
        {
            LightPool = MathF.Min(T.SectorLightPool, LightPool + T.SectorLightRegenPerSecond * dt);
            if (Tick % T.AmbientSpawnIntervalTicks != 0) return;
            if (LightPool < 1f || Pickups.LiveAmbient >= T.AmbientLightCap) return;
            var pos = new Vec2(Rng.Range(40f, Width - 40f), Rng.Range(40f, Height - 40f));
            if (SpawnPickup(SectorElement, 0, pos, true) >= 0) LightPool -= 1f;
        }

        private void StepEnemySpawns()
        {
            if (Tick < _nextEnemySpawn) return;
            int alive = 0;
            for (int i = 0; i < Ships.Count; i++) if (Ships[i].Alive && Ships[i].Faction != Faction.Player) alive++;
            if (alive >= T.MaxEnemies) { _nextEnemySpawn = Tick + 30; return; }
            _nextEnemySpawn = Tick + T.EnemySpawnIntervalTicks;
            ShipDefinition def = Catalog.Find(SectorElement == Element.None ? Element.Fire : SectorElement, EnemyTier)
                                 ?? Catalog.Find(Element.Fire, 1);
            if (def == null) return;
            Vec2 pos = FarFromPlayer(500f);
            SpawnEnemy(def, pos, PatternLibrary.ForEnemy(def.Element, def.Tier));
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

        // ---- queries for pilots ----

        public Ship NearestEnemy(Vec2 from)
        {
            Ship best = null;
            float bestD = float.MaxValue;
            for (int i = 0; i < Ships.Count; i++)
            {
                Ship s = Ships[i];
                if (!s.Alive || s.Faction == Faction.Player) continue;
                float d = Vec2.DistanceSquared(s.Pos, from);
                if (d < bestD) { bestD = d; best = s; }
            }
            return best;
        }

        public int NearestPickup(Vec2 from, float within)
        {
            int best = -1;
            float bestD = within * within;
            for (int i = 0; i < Pickups.High; i++)
            {
                if (!Pickups.Alive[i]) continue;
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

        /// <summary>Bullets of other factions within a radius, into the shared query list (do not hold it).</summary>
        public List<int> EnemyBulletsNear(Vec2 at, float radius)
        {
            Hash.Query(at.X, at.Y, radius, _query);
            return _query;
        }
    }
}
