using System;
using Lightship.Core.Config;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
using Lightship.Core.Sim.Patterns;

namespace Lightship.Core.Sim
{
    /// <summary>
    /// A ship in the arena: definition, geometry (ship-local world units), pose,
    /// HP and its pilot. The player's hitbox is the core only; enemies are hit
    /// anywhere on the body (decision 2 in the plan).
    /// </summary>
    public sealed class Ship
    {
        public int Id;
        public Faction Faction;
        public Element Element;
        public int Tier;
        public ShipDefinition Def;
        public ShipGeometry Geometry;

        public Vec2 Pos;
        public Vec2 PrevPos;
        public Vec2 Vel;
        public Vec2 Facing = Vec2.Forward;
        public float Hp;
        public float MaxHp;
        public long LastDamageTick = long.MinValue / 2;
        public long LastShedTick = long.MinValue / 2;
        public long NextFireTick;
        public long SpawnTick;
        public bool Alive = true;
        public float BreathPhase;
        public float Speed;

        public IPilot Pilot;
        public PatternRunner Pattern;
        public PlayerInput LastInput;

        public float BoundRadius => Geometry.BoundRadius;

        /// <summary>Node rotation in radians: local forward (0,-1) turned onto Facing.</summary>
        public float Rotation => Facing.Angle() + MathF.PI / 2f;

        public Vec2 ToLocal(Vec2 world) => (world - Pos).Rotated(-Rotation);
        public Vec2 ToWorld(Vec2 local) => Pos + local.Rotated(Rotation);

        /// <summary>Spec 11.6: living elements breathe 1.00 to 1.05 over 2 s with a per-ship phase.</summary>
        public float BreathScale(float time, Tuning t) =>
            Def.Breathes ? Easing.Breath(time, t.BreathPeriod, t.BreathAmplitude, BreathPhase) : 1f;

        public void SetDefinition(ShipDefinition def)
        {
            Def = def;
            Geometry = ShipGeometry.Build(ResolvedShip.From(def));
            Element = def.Element;
            Tier = def.Tier;
        }
    }
}
