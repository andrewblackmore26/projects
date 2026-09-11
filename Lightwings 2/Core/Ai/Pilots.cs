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
    /// A regular enemy (spec 8): approach to its preferred range, strafe there,
    /// face the player and let its fixed pattern do the shooting.
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

    /// <summary>
    /// The scripted player used by tests, the CLI and captures: chase light,
    /// keep a fighting distance from the nearest enemy, lead its shots, dodge
    /// bullets that will pass close, and evolve the moment it can. Simple by
    /// design: spec 8 requires every player form to be bot-pilotable.
    /// </summary>
    public sealed class BotPilot : IPilot
    {
        public const float FightRange = 200f;
        public const float DodgeDistance = 14f;
        public const int DodgeLookaheadTicks = 20;
        public const float DodgeScan = 140f;

        /// <summary>False gives a weaker player: it still chases light and fights, but never dodges.</summary>
        public bool Dodge = true;

        public PlayerInput Decide(Arena arena, Ship self)
        {
            var input = new PlayerInput { Fire = true, Evolve = true, EvolveChoice = 0 };
            Ship enemy = arena.NearestEnemy(self.Pos);
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

            // Dodge: any enemy bullet whose path passes within DodgeDistance of the core soon.
            Vec2 dodge = Vec2.Zero;
            float dt = arena.T.Dt;
            var near = arena.EnemyBulletsNear(self.Pos, DodgeScan);
            BulletPool b = arena.Bullets;
            for (int q = 0; Dodge && q < near.Count; q++)
            {
                int i = near[q];
                if (!b.Alive[i] || b.Owner[i] == (byte)Faction.Player) continue;
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

            input.Move = move;
            if (enemy != null)
            {
                Vec2 to = enemy.Pos - self.Pos;
                float time = to.Length() / arena.T.PlayerBulletSpeed;
                Vec2 lead = enemy.Pos + enemy.Vel * time - self.Pos;
                input.Aim = lead.LengthSquared() > 1e-6f ? lead.Normalized() : self.Facing;
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
