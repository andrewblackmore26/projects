using System;
using System.Collections.Generic;
using Lightship.Core.Config;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim.Abilities
{
    /// <summary>
    /// Spec 11.7: every visible part is an ability. A loadout is built from a
    /// ship definition's abilities and the parts that carry them (their
    /// "mounts", in ship-local units): the weapon fires from its component's
    /// part, drones hatch from the pods, and so on. The player and rivals fire
    /// their loadout's weapon; regular enemies fire a fixed pattern (spec 8) and
    /// their other parts still work (a Flare enemy's vents leave a trail).
    /// </summary>
    public sealed class Loadout
    {
        public readonly Tuning Tuning;
        public readonly List<Ability> Abilities = new List<Ability>();
        public Weapon Primary;
        public byte BulletFlags;

        private Loadout(Tuning t) { Tuning = t; }

        public bool Has(string id)
        {
            foreach (Ability a in Abilities) if (a.Id == id) return true;
            return false;
        }

        public T Get<T>() where T : Ability
        {
            foreach (Ability a in Abilities) if (a is T t) return t;
            return null;
        }

        public static List<Vec2> MountsOf(ShipDefinition def, string component)
        {
            var mounts = new List<Vec2>();
            foreach (PartDefinition p in def.Parts)
                if (p.Component == component && !p.IsTether) mounts.Add(p.Pos);
            return mounts;
        }

        /// <summary>
        /// The loadout a definition implies. withWeapon=false is a regular enemy's: its fixed
        /// pattern is its weapon (spec 8), but every other part still does its job.
        /// </summary>
        public static Loadout Build(ShipDefinition def, Tuning t, bool withWeapon = true)
        {
            var l = new Loadout(t);
            foreach (string id in def.Abilities)
            {
                Ability a = AbilityLibrary.Create(id, MountsOf(def, id), t);
                if (a != null) l.Abilities.Add(a);
            }
            l.Primary = withWeapon ? Weapon.For(def, l, t) : null;
            foreach (Ability a in l.Abilities) l.BulletFlags |= a.BulletFlags;
            return l;
        }

        public void Tick(Arena arena, Ship self, in PlayerInput input)
        {
            Primary?.Tick(arena, self, input, BulletFlags);
            foreach (Ability a in Abilities) a.Tick(arena, self, input);
        }
    }

    /// <summary>One ability carried by a part. Passive unless it reads the ability keys.</summary>
    public abstract class Ability
    {
        public readonly string Id;
        public readonly List<Vec2> Mounts;
        /// <summary>Flags this ability adds to the primary weapon's bullets.</summary>
        public virtual byte BulletFlags => 0;

        protected Ability(string id, List<Vec2> mounts)
        {
            Id = id;
            Mounts = mounts;
        }

        public virtual void Tick(Arena arena, Ship self, in PlayerInput input) { }
    }

    /// <summary>The ability ids the simulation knows, and the ones regular enemies express as patterns.</summary>
    public static class AbilityLibrary
    {
        /// <summary>Every id that has behaviour. The loader test asserts every authored ability is in here.</summary>
        public static readonly HashSet<string> Known = new HashSet<string>
        {
            "flame_spray", "infect", "spread", "hatch", "ram", "burning_trail", "wide_cone",
        };

        public static Ability Create(string id, List<Vec2> mounts, Tuning t)
        {
            switch (id)
            {
                case "infect": return new InfectAbility(mounts);
                case "spread": return new SpreadAbility(mounts);
                case "hatch": return new HatchAbility(mounts, t);
                case "flame_spray": return new MarkerAbility(id, mounts);   // the weapon itself (Weapon.For)
                case "wide_cone": return new MarkerAbility(id, mounts);     // extra barrels on the flame spray (Weapon.For)
                case "burning_trail": return new BurningTrailAbility(mounts, t);
                default: return null;
            }
        }
    }

    /// <summary>An ability whose whole behaviour is the weapon choice it implies.</summary>
    public sealed class MarkerAbility : Ability
    {
        public MarkerAbility(string id, List<Vec2> mounts) : base(id, mounts) { }
    }

    /// <summary>Corruption T1 (spec 12): shots infect on hit, a short damage over time.</summary>
    public sealed class InfectAbility : Ability
    {
        public InfectAbility(List<Vec2> mounts) : base("infect", mounts) { }
        public override byte BulletFlags => Sim.BulletFlags.Infect;
    }

    /// <summary>Corruption T2: an infection jumps from its host to the nearest uninfected hostile nearby.</summary>
    public sealed class SpreadAbility : Ability
    {
        public SpreadAbility(List<Vec2> mounts) : base("spread", mounts) { }
        public override byte BulletFlags => Sim.BulletFlags.Spreads;
    }

    /// <summary>
    /// Fire T2 (spec 12): while the ship is moving, each vent drops embers that burn
    /// where they fall for a short while, damaging any hostile that flies through them.
    /// They drift back slowly, so the trail marks the path the ship took.
    /// </summary>
    public sealed class BurningTrailAbility : Ability
    {
        private readonly Tuning _t;
        private long _next;

        public BurningTrailAbility(List<Vec2> mounts, Tuning t) : base("burning_trail", mounts) { _t = t; }

        public override void Tick(Arena arena, Ship self, in PlayerInput input)
        {
            if (arena.Tick < _next || self.Vel.LengthSquared() < _t.TrailMinSpeed * _t.TrailMinSpeed) return;
            _next = arena.Tick + _t.TrailIntervalTicks;
            Vec2 back = -self.Facing * 20f;
            foreach (Vec2 m in Mounts)
                arena.SpawnBullet(self.Side, Element.Fire, self.ToWorld(m), back, _t.TrailRadius, _t.TrailDamage, _t.TrailTtlTicks, 0, self.Id);
        }
    }

    /// <summary>
    /// Corruption T3: each pod hatches a drone that seeks the nearest hostile
    /// and rams it (infecting, if the ship infects). One drone per pod alive
    /// at a time, a fresh one every HatchIntervalTicks while there is a target.
    /// </summary>
    public sealed class HatchAbility : Ability
    {
        private readonly long[] _next;
        private readonly int[] _droneIds;
        private readonly Tuning _t;

        public HatchAbility(List<Vec2> mounts, Tuning t) : base("hatch", mounts)
        {
            _t = t;
            _next = new long[mounts.Count];
            _droneIds = new int[mounts.Count];
            for (int i = 0; i < _droneIds.Length; i++) _droneIds[i] = -1;
        }

        public override void Tick(Arena arena, Ship self, in PlayerInput input)
        {
            if (arena.NearestHostile(self.Pos, self.Side, 900f) == null) return;
            for (int i = 0; i < Mounts.Count; i++)
            {
                if (arena.Tick < _next[i]) continue;
                if (_droneIds[i] >= 0 && arena.FindShip(_droneIds[i]) is Ship d && d.Alive) continue;
                Ship drone = arena.SpawnDrone(self, self.ToWorld(Mounts[i]));
                _droneIds[i] = drone.Id;
                _next[i] = arena.Tick + _t.HatchIntervalTicks;
            }
        }
    }
}
