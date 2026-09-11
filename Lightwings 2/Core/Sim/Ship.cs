using System;
using Lightship.Core.Config;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
using Lightship.Core.Sim.Abilities;
using Lightship.Core.Sim.Patterns;

namespace Lightship.Core.Sim
{
    /// <summary>
    /// A ship in the arena: definition, geometry (ship-local world units), pose,
    /// HP, status and its pilot. The player's hitbox is the core only; every
    /// other ship is hit anywhere on its drawn body.
    /// </summary>
    public sealed class Ship
    {
        public int Id;
        public Faction Faction;
        public byte Side;
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
        public long SpawnTick;
        public bool Alive = true;
        public float BreathPhase;
        public float Speed;

        /// <summary>Spec 9: only the player's core takes bullets; everything else is hit on its body.</summary>
        public bool CoreOnlyHitbox;

        public IPilot Pilot;
        public PatternRunner Pattern;     // regular enemies: fixed patterns (spec 8)
        public Loadout Loadout;           // the player and rivals: abilities from their parts (spec 11.7)
        public PlayerInput LastInput;

        // Drones (corruption T3 hatch): short-lived rammers belonging to another ship.
        public bool IsDrone;
        public int OwnerShipId = -1;
        public long DespawnTick = long.MaxValue;
        public float RamDamage;
        public byte RamFlags;

        // Infection (corruption): damage over time from a hostile side, optionally spreading.
        public long InfectedUntil = long.MinValue / 2;
        public float InfectDps;
        public byte InfectSide;
        public bool InfectSpreads;
        public long NextSpreadTick;

        public float BoundRadius => Geometry.BoundRadius;
        public bool Infected(long tick) => tick < InfectedUntil;

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
            if (Loadout != null) Loadout = Loadout.Build(def, Loadout.Tuning);
        }
    }
}
