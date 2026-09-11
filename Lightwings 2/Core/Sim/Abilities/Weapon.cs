using System;
using System.Collections.Generic;
using Lightship.Core.Config;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim.Abilities
{
    /// <summary>One place shots leave the ship: a part's position (ship-local) and the turn off the aim.</summary>
    public struct Barrel
    {
        public Vec2 Mount;
        public float AngleDeg;
    }

    /// <summary>
    /// The primary weapon a form fires with (hold Fire), chosen by its components and
    /// fired from the parts carrying them (spec 11.7: the part IS the ability). Fire
    /// forms spray a short cone from the ember; Scorch's wide cone adds a spray from each
    /// flank ember, turned out (three overlapping sprays). Corruption forms shoot
    /// infecting spores from the spore bud. Lightning and void weapons land in M3.
    /// </summary>
    public sealed class Weapon
    {
        public string Component;
        public readonly List<Barrel> Barrels = new List<Barrel>();
        public int IntervalTicks;
        public int Count = 1;
        public float SpreadDeg;
        public float Speed, Radius, Damage;
        public int TtlTicks;
        public Element BulletElement;   // colour/shape of the bullets; the player's side draws them light blue
        private long _next;

        /// <summary>World units a shot travels before it expires.</summary>
        public float Reach(Tuning t) => Speed * TtlTicks * t.Dt;

        public static Weapon For(ShipDefinition def, Loadout l, Tuning t)
        {
            Weapon w;
            if (def.Abilities.Contains("flame_spray"))
            {
                w = new Weapon
                {
                    Component = "flame_spray", IntervalTicks = 12, Count = 5,
                    SpreadDeg = 30f, Speed = 360f, Radius = 2.5f, Damage = 4f, TtlTicks = 30, BulletElement = Element.Fire,
                };
                w.AddBarrels(def, "flame_spray", 0f);
                if (def.Abilities.Contains("wide_cone"))
                    foreach (Vec2 m in Loadout.MountsOf(def, "wide_cone"))
                        w.Barrels.Add(new Barrel { Mount = m, AngleDeg = MathF.Sign(m.X) * t.WideConeAngleDeg });
            }
            else if (def.Abilities.Contains("infect"))
            {
                w = new Weapon
                {
                    Component = "infect", IntervalTicks = t.PlayerFireIntervalTicks,
                    Speed = t.PlayerBulletSpeed, Radius = t.PlayerBulletRadius, Damage = t.PlayerBulletDamage,
                    TtlTicks = t.PlayerBulletTtlTicks, BulletElement = Element.Corruption,
                };
                w.AddBarrels(def, "infect", 0f);
            }
            else
            {
                w = new Weapon
                {
                    Component = null, IntervalTicks = t.PlayerFireIntervalTicks,
                    Speed = t.PlayerBulletSpeed, Radius = t.PlayerBulletRadius, Damage = t.PlayerBulletDamage,
                    TtlTicks = t.PlayerBulletTtlTicks, BulletElement = Element.None,
                };
            }
            return w;
        }

        /// <summary>The component's parts fire as one barrel from their average position (a pair fires from between them).</summary>
        private void AddBarrels(ShipDefinition def, string component, float angle)
        {
            List<Vec2> mounts = Loadout.MountsOf(def, component);
            if (mounts.Count == 0) return;
            Vec2 sum = Vec2.Zero;
            foreach (Vec2 m in mounts) sum = sum + m;
            Barrels.Add(new Barrel { Mount = sum / mounts.Count, AngleDeg = angle });
        }

        /// <summary>Where the main shot leaves the ship: the first barrel, else just ahead of the core.</summary>
        public Vec2 Muzzle(Ship self) =>
            Barrels.Count == 0 ? self.Pos + self.Facing * 8f : self.ToWorld(Barrels[0].Mount);

        public void Tick(Arena arena, Ship self, in PlayerInput input, byte flags)
        {
            if (!input.Fire || arena.Tick < _next) return;
            _next = arena.Tick + IntervalTicks;
            Vec2 aim = self.Facing;
            if (Barrels.Count == 0)
            {
                Volley(arena, self, self.Pos + aim * 8f, aim, flags);
                return;
            }
            foreach (Barrel b in Barrels)
                Volley(arena, self, self.ToWorld(b.Mount), aim.Rotated(Outline.Rad(b.AngleDeg)), flags);
        }

        private void Volley(Arena arena, Ship self, Vec2 from, Vec2 aim, byte flags)
        {
            for (int k = 0; k < Count; k++)
            {
                float t = Count > 1 ? k / (float)(Count - 1) - 0.5f : 0f;
                Vec2 dir = aim.Rotated(Outline.Rad(SpreadDeg * t));
                arena.SpawnBullet(self.Side, BulletElement, from, dir * Speed, Radius, Damage, TtlTicks, flags, self.Id);
            }
        }
    }
}
