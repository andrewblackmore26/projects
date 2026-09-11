using System;
using Lightship.Core.Sim;

namespace Lightship.Core.Ai
{
    /// <summary>The human: whatever the presentation layer last handed in.</summary>
    public sealed class HumanPilot : IPilot
    {
        public PlayerInput Latest;
        public PlayerInput Decide(Arena arena, Ship self) => Latest;
    }

    /// <summary>
    /// A regular enemy (spec 8): approach to its pattern's preferred range,
    /// strafe there, face the player and let its fixed pattern do the shooting.
    /// </summary>
    public sealed class EnemyPilot : IPilot
    {
        public PlayerInput Decide(Arena arena, Ship self)
        {
            var input = new PlayerInput();
            Ship player = arena.Player;
            if (player == null || !player.Alive) return input;
            Vec2 to = player.Pos - self.Pos;
            float dist = to.Length();
            Vec2 dir = dist > 1e-3f ? to / dist : Vec2.Forward;
            float preferred = self.Pattern != null ? self.Pattern.Def.PreferredRange : arena.T.EnemyPreferredRange;
            Vec2 strafe = dir.Perp() * ((self.Id & 1) == 0 ? 1f : -1f);
            if (dist > preferred * 1.15f) input.Move = dir * 0.9f + strafe * 0.3f;
            else if (dist < preferred * 0.7f) input.Move = -dir * 0.8f + strafe * 0.4f;
            else input.Move = strafe * 0.7f;
            input.Aim = dir;
            input.Fire = true;
            return input;
        }
    }

    /// <summary>A hatched drone: fly straight at the nearest hostile and ram it.</summary>
    public sealed class DronePilot : IPilot
    {
        public PlayerInput Decide(Arena arena, Ship self)
        {
            var input = new PlayerInput();
            Ship target = arena.NearestHostile(self.Pos, self.Side);
            if (target == null) return input;
            Vec2 to = target.Pos - self.Pos;
            if (to.LengthSquared() < 1e-6f) return input;
            input.Move = to.Normalized();
            input.Aim = input.Move;
            return input;
        }
    }

    /// <summary>How well the scripted player plays. The perfect profile is a ceiling, the novice a floor.</summary>
    public sealed class BotSkill
    {
        public bool Dodge = true;
        public float AimErrorDeg;          // uniform +- error re-rolled every AimRerollTicks
        public int AimRerollTicks = 20;
        public float FireDuty = 1f;        // fraction of the time the trigger is held (in 60-tick cycles)
        public int ReactionTicks;          // enemy positions are read this many ticks late (lead uses stale velocity)
        public bool Evolves = true;        // false holds the ship at its threshold (the lock-pulse capture)

        public static BotSkill Perfect() => new BotSkill();

        /// <summary>A new player's hands: 10 degrees of aim error, fires 60 % of the time, reacts 250 ms late, no dodging.</summary>
        public static BotSkill Novice() => new BotSkill { Dodge = false, AimErrorDeg = 10f, FireDuty = 0.6f, ReactionTicks = 15 };
    }

    /// <summary>
    /// The scripted player used by tests, the CLI and captures: chase light,
    /// keep a fighting distance from the nearest hostile, lead its shots, dodge
    /// bullets that will pass close, and evolve the moment it can. Simple by
    /// design: spec 8 requires every player form to be bot-pilotable.
    /// </summary>
    public sealed class BotPilot : IPilot
    {
        public const float FightRange = 200f;
        public const float DodgeDistance = 14f;
        public const int DodgeLookaheadTicks = 20;
        public const float DodgeScan = 140f;

        public BotSkill Skill = BotSkill.Perfect();
        /// <summary>Kept for existing callers: false disables dodging only.</summary>
        public bool Dodge { get => Skill.Dodge; set => Skill.Dodge = value; }

        private readonly DeterministicRandom _rng;
        private float _aimError;
        private long _nextReroll;
        private readonly Vec2[] _seen = new Vec2[64];   // delayed perception of the target position
        private int _seenTarget = -1;

        public BotPilot(ulong seed = 0x1B07) { _rng = new DeterministicRandom(seed); }

        public PlayerInput Decide(Arena arena, Ship self)
        {
            var input = new PlayerInput { Fire = true, Evolve = Skill.Evolves, EvolveChoice = 0 };
            Ship enemy = arena.NearestHostile(self.Pos, self.Side);
            float magnet = arena.Host.MagnetRadius;
            int pickup = arena.NearestPickup(self.Pos, magnet * 3f);

            Vec2 move = Vec2.Zero;
            if (pickup >= 0)
            {
                var p = new Vec2(arena.Pickups.X[pickup], arena.Pickups.Y[pickup]);
                move = (p - self.Pos).Normalized();
            }
            else if (enemy != null)
            {
                Vec2 to = enemy.Pos - self.Pos;
                float dist = to.Length();
                Vec2 dir = dist > 1e-3f ? to / dist : Vec2.Forward;
                if (dist > FightRange * 1.2f) move = dir;
                else if (dist < FightRange * 0.7f) move = -dir;
                else move = dir.Perp() * 0.6f;
            }
            else
            {
                Vec2 toCentre = arena.Centre - self.Pos;
                if (toCentre.Length() > 200f) move = toCentre.Normalized() * 0.5f;
            }

            // Dodge: any hostile bullet whose path passes within DodgeDistance of the core soon.
            if (Skill.Dodge)
            {
                Vec2 dodge = Vec2.Zero;
                float dt = arena.T.Dt;
                var near = arena.BulletsNear(self.Pos, DodgeScan);
                BulletPool b = arena.Bullets;
                for (int q = 0; q < near.Count; q++)
                {
                    int i = near[q];
                    if (!b.Alive[i] || !Sides.Hostile(b.Side[i], self.Side)) continue;
                    var rel = new Vec2(b.X[i] - self.Pos.X, b.Y[i] - self.Pos.Y);
                    var vel = new Vec2(b.VX[i] - self.Vel.X, b.VY[i] - self.Vel.Y);
                    float v2 = vel.LengthSquared();
                    if (v2 < 1e-3f) continue;
                    float t = -Vec2.Dot(rel, vel) / v2;                 // time of closest approach, seconds
                    if (t < 0f || t > DodgeLookaheadTicks * dt) continue;
                    Vec2 closest = rel + vel * t;
                    if (closest.Length() > DodgeDistance + b.Radius[i]) continue;
                    Vec2 away = closest.LengthSquared() > 1e-4f ? -closest.Normalized() : vel.Normalized().Perp();
                    dodge = dodge + away;
                }
                if (dodge.LengthSquared() > 1e-4f) move = dodge.Normalized();
            }

            input.Move = move;
            if (enemy != null)
            {
                // Perception delay: aim at where the target was ReactionTicks ago.
                if (enemy.Id != _seenTarget) { _seenTarget = enemy.Id; for (int k = 0; k < _seen.Length; k++) _seen[k] = enemy.Pos; }
                _seen[arena.Tick % _seen.Length] = enemy.Pos;
                int lag = Math.Clamp(Skill.ReactionTicks, 0, _seen.Length - 1);
                Vec2 seen = _seen[((arena.Tick - lag) % _seen.Length + _seen.Length) % _seen.Length];
                Vec2 to = seen - self.Pos;
                float time = to.Length() / arena.T.PlayerBulletSpeed;
                Vec2 lead = seen + enemy.Vel * time - self.Pos;
                Vec2 aim = lead.LengthSquared() > 1e-6f ? lead.Normalized() : self.Facing;
                if (Skill.AimErrorDeg > 0f)
                {
                    if (arena.Tick >= _nextReroll)
                    {
                        _aimError = _rng.Range(-Skill.AimErrorDeg, Skill.AimErrorDeg);
                        _nextReroll = arena.Tick + Skill.AimRerollTicks;
                    }
                    aim = aim.Rotated(_aimError * MathF.PI / 180f);
                }
                input.Aim = aim;
                input.Fire = (arena.Tick % 60) < (long)(Skill.FireDuty * 60f);
            }
            else
            {
                input.Aim = move.LengthSquared() > 1e-6f ? move.Normalized() : self.Facing;
                input.Fire = false;
            }
            return input;
        }
    }
}
