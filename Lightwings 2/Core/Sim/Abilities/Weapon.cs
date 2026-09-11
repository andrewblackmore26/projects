using System.Collections.Generic;
using Lightship.Core.Config;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim.Abilities
{
    /// <summary>
    /// The primary weapon a form fires with (hold Fire), chosen by its root
    /// element and fired from the part carrying its component (spec 11.7: the
    /// part IS the ability). Fire forms spray a short cone from the ember,
    /// corruption forms shoot infecting spores from the spore bud. Lightning
    /// and void weapons land with their ships in M3.
    /// </summary>
    public sealed class Weapon
    {
        public string Component;
        public List<Vec2> Mounts;
        public int IntervalTicks;
        public int Count = 1;
        public float SpreadDeg;
        public float Speed, Radius, Damage;
        public int TtlTicks;
        public Element BulletElement;   // colour/shape of the bullets; the player's side draws them light blue
        private long _next;

        public static Weapon For(ShipDefinition def, Loadout l, Tuning t)
        {
            if (def.Abilities.Contains("flame_spray"))
                return new Weapon
                {
                    Component = "flame_spray", Mounts = Loadout.MountsOf(def, "flame_spray"), IntervalTicks = 12, Count = 5,
                    SpreadDeg = 30f, Speed = 360f, Radius = 2.5f, Damage = 4f, TtlTicks = 30, BulletElement = Element.Fire,
                };
            if (def.Abilities.Contains("infect"))
                return new Weapon
                {
                    Component = "infect", Mounts = Loadout.MountsOf(def, "infect"), IntervalTicks = t.PlayerFireIntervalTicks,
                    Speed = t.PlayerBulletSpeed, Radius = t.PlayerBulletRadius, Damage = t.PlayerBulletDamage,
                    TtlTicks = t.PlayerBulletTtlTicks, BulletElement = Element.Corruption,
                };
            return new Weapon
            {
                Component = null, Mounts = new List<Vec2>(), IntervalTicks = t.PlayerFireIntervalTicks,
                Speed = t.PlayerBulletSpeed, Radius = t.PlayerBulletRadius, Damage = t.PlayerBulletDamage,
                TtlTicks = t.PlayerBulletTtlTicks, BulletElement = Element.None,
            };
        }

        /// <summary>Where the shots leave the ship: the component's part, else just ahead of the core.</summary>
        public Vec2 Muzzle(Ship self)
        {
            if (Mounts.Count == 0) return self.Pos + self.Facing * 8f;
            Vec2 sum = Vec2.Zero;
            foreach (Vec2 m in Mounts) sum = sum + m;
            return self.ToWorld(sum / Mounts.Count);
        }

        public void Tick(Arena arena, Ship self, in PlayerInput input, byte flags)
        {
            if (!input.Fire || arena.Tick < _next) return;
            _next = arena.Tick + IntervalTicks;
            Vec2 aim = self.Facing;
            Vec2 from = Muzzle(self);
            for (int k = 0; k < Count; k++)
            {
                float t = Count > 1 ? k / (float)(Count - 1) - 0.5f : 0f;
                Vec2 dir = aim.Rotated(Outline.Rad(SpreadDeg * t));
                arena.SpawnBullet(self.Side, BulletElement, from, dir * Speed, Radius, Damage, TtlTicks, flags, self.Id);
            }
        }
    }
}
