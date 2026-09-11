using System;
using Lightship.Core.Config;
using Lightship.Core.Sim;
using Lightship.Core.Sim.Abilities;

namespace Lightship.Core.Ai
{
    /// <summary>
    /// A rival (spec 8): the player's own tree and components, driven by decisions
    /// instead of a pattern. It dodges, leads its target, retreats to regenerate
    /// when low, grabs light mid-fight and prefers the biggest target near it.
    ///
    /// Human-like limits: it sees the world DelayTicks late (150-300 ms). A bullet
    /// younger than the delay does not exist for it yet, and it aims at where its
    /// target was DelayTicks ago. Each burst carries a fresh 2-5 degree aim error.
    /// Visible intent: an aim line for 0.5 s before every burst (spec 9: an attack that
    /// cannot be dodged on reaction warns at least 0.5 s ahead; Scorch's cone up close is
    /// one), kept up through the burst so every volley flies along a line that was shown,
    /// and an obvious retreat (it stops shooting and runs). A newly seen target is acted on
    /// only DelayTicks after it came into view, from where it was then.
    /// </summary>
    public sealed class RivalPilot : IPilot
    {
        private enum Phase { Idle, Telegraph, Burst, Pause }

        public const int History = 32;               // ring size; must exceed the largest delay
        public const int DodgeLookaheadTicks = 30;
        public const float DodgeScan = 220f;

        public readonly int DelayTicks;
        /// <summary>This burst's signed aim error, degrees (magnitude in [RivalAimErrorMinDeg, RivalAimErrorMaxDeg]).</summary>
        public float AimErrorDeg { get; private set; }
        public int Retreats { get; private set; }
        public int Bursts { get; private set; }
        public int TargetId => _targetId;

        private readonly Tuning _t;
        private readonly DeterministicRandom _rng;
        private Phase _phase = Phase.Idle;
        private long _phaseEnd;
        private int _targetId = -1;
        private readonly Vec2[] _pos = new Vec2[History];
        private readonly Vec2[] _vel = new Vec2[History];
        private float _strafeSign;
        private long _nextStrafeFlip;
        private long _telegraphStart = long.MinValue / 2;
        // A target coming into view is recorded here until it has been seen for DelayTicks.
        private int _pendingId = -1;
        private long _pendingSince;
        private readonly Vec2[] _pendingPos = new Vec2[History];
        private readonly Vec2[] _pendingVel = new Vec2[History];

        public RivalPilot(Tuning t, ulong seed)
        {
            _t = t;
            _rng = new DeterministicRandom(seed ^ 0x51BA1UL);
            DelayTicks = Math.Clamp(_rng.RangeInt(t.RivalDelayMinTicks, t.RivalDelayMaxTicks + 1), 0, History - 1);
            _strafeSign = _rng.NextFloat() < 0.5f ? -1f : 1f;
        }

        public PlayerInput Decide(Arena arena, Ship self)
        {
            var input = new PlayerInput();
            long now = arena.Tick;

            // Retreat below 35 % until back above 70 % (hysteresis keeps the intent readable).
            float hp = self.MaxHp > 0f ? self.Hp / self.MaxHp : 1f;
            if (!self.Retreating && hp < _t.RivalRetreatBelow)
            {
                self.Retreating = true;
                Retreats++;
                arena.Events.Add(EventKind.RivalRetreat, now, self.Pos, self.Element, hp, self.Id);
                EndBurst(self, now);
            }
            else if (self.Retreating && hp >= _t.RivalRecoverAbove) self.Retreating = false;

            Ship target = Perceive(arena, self, PickTarget(arena, self), now);
            if (target == null)
            {
                _targetId = -1;
                Vec2 home = arena.Centre - self.Pos;
                input.Move = (home.LengthSquared() > 200f * 200f ? home.Normalized() * 0.5f : Vec2.Zero) + GrabLight(arena, self, 400f, _t);
                input.Aim = self.Facing;
                StepBurst(arena, self, false);
                return input;
            }

            Remember(now, target);
            Vec2 seen = _pos[Slot(now - DelayTicks)];
            Vec2 seenVel = _vel[Slot(now - DelayTicks)];
            Vec2 to = seen - self.Pos;
            float dist = to.Length();
            Vec2 dir = dist > 1e-3f ? to / dist : self.Facing;

            Weapon w = self.Loadout?.Primary;
            float bulletSpeed = w != null ? w.Speed : 300f;
            float reach = w != null ? w.Speed * w.TtlTicks * _t.Dt : 200f;
            float fight = reach * 0.7f;

            Vec2 move;
            if (self.Retreating)
            {
                // Obvious retreat: straight away from the threat, detouring only for light that is not toward it.
                move = -dir;
                int pk = arena.NearestPickup(self.Pos, 300f, _t.RivalGrabMinAgeTicks);
                if (pk >= 0)
                {
                    Vec2 toP = new Vec2(arena.Pickups.X[pk], arena.Pickups.Y[pk]) - self.Pos;
                    if (toP.LengthSquared() > 1f && Vec2.Dot(toP.Normalized(), dir) < 0.3f) move = toP.Normalized();
                }
            }
            else
            {
                if (now >= _nextStrafeFlip)
                {
                    _strafeSign = -_strafeSign;
                    _nextStrafeFlip = now + _rng.RangeInt(90, 180);
                }
                Vec2 strafe = dir.Perp() * _strafeSign;
                if (dist > fight * 1.2f) move = dir * 0.9f + strafe * 0.3f;
                else if (dist < fight * 0.6f) move = -dir * 0.8f + strafe * 0.5f;
                else move = strafe * 0.8f + dir * 0.1f;
                // Grab light mid-fight when hurt and it is close.
                if (self.Hp < self.MaxHp * 0.9f)
                {
                    Vec2 grab = GrabLight(arena, self, 110f, _t);
                    if (grab.LengthSquared() > 0f) move = grab;
                }
            }

            move = move + AvoidWalls(arena, self);
            Vec2 dodge = Dodge(arena, self);
            if (dodge.LengthSquared() > 1e-4f) move = dodge.Normalized() * 1.5f + move * 0.3f;
            if (move.LengthSquared() > 1f) move = move.Normalized();
            input.Move = move;

            // Lead the target from what it saw, plus this burst's error.
            float time = dist / MathF.Max(bulletSpeed, 1f);
            Vec2 lead = seen + seenVel * time - self.Pos;
            Vec2 aim = lead.LengthSquared() > 1e-6f ? lead.Normalized() : dir;
            aim = aim.Rotated(AimErrorDeg * MathF.PI / 180f);
            input.Aim = self.Retreating && move.LengthSquared() > 1e-4f ? move.Normalized() : aim;
            input.Fire = StepBurst(arena, self, !self.Retreating && dist <= reach * 1.05f);
            return input;
        }

        /// <summary>Aim line (RivalAimLineTicks, 0.5 s), then the burst with the line still up, then a pause. Firing only happens in the burst.</summary>
        private bool StepBurst(Arena arena, Ship self, bool canFire)
        {
            long now = arena.Tick;
            switch (_phase)
            {
                case Phase.Idle:
                    if (!canFire) return false;
                    _phase = Phase.Telegraph;
                    _phaseEnd = now + _t.RivalAimLineTicks;
                    _telegraphStart = now;
                    float mag = _rng.Range(_t.RivalAimErrorMinDeg, _t.RivalAimErrorMaxDeg);
                    AimErrorDeg = _rng.NextFloat() < 0.5f ? -mag : mag;
                    self.AimLineUntil = _phaseEnd;
                    arena.Events.Add(EventKind.AimLine, now, self.Pos, self.Element, _t.RivalAimLineTicks, self.Id);
                    return false;
                case Phase.Telegraph:
                    if (!canFire) { EndBurst(self, now); return false; }
                    if (now < _phaseEnd) return false;
                    _phase = Phase.Burst;
                    _phaseEnd = now + _t.RivalBurstTicks;
                    self.AimLineUntil = _phaseEnd;   // the line stays up while it fires
                    Bursts++;
                    return true;
                case Phase.Burst:
                    if (now >= _phaseEnd || !canFire) { EndBurst(self, now); return false; }
                    return true;
                default:
                    if (now >= _phaseEnd) _phase = Phase.Idle;
                    return false;
            }
        }

        private void EndBurst(Ship self, long now)
        {
            // A cut-short line still stays up for the minimum visible lifetime (spec 9: 0.25 s).
            if (_phase == Phase.Telegraph || _phase == Phase.Burst)
                self.AimLineUntil = Math.Max(now, _telegraphStart + _t.MinVisibleEventTicks);
            _phase = Phase.Pause;
            _phaseEnd = now + _t.RivalPauseTicks;
        }

        /// <summary>Spec 8: the biggest hostile near it (tier, then size), nearest on a tie. Sticks with its target unless a bigger one shows up.</summary>
        private Ship PickTarget(Arena arena, Ship self)
        {
            float range2 = _t.RivalPerception * _t.RivalPerception;
            Ship current = null, best = null;
            float bestD = float.MaxValue;
            foreach (Ship s in arena.Ships)
            {
                if (!s.Alive || s.IsDrone || !Sides.Hostile(s.Side, self.Side)) continue;
                float d = Vec2.DistanceSquared(s.Pos, self.Pos);
                if (d > range2) continue;
                if (s.Id == _targetId) current = s;
                if (best == null || Bigger(s, best) || (!Bigger(best, s) && d < bestD)) { best = s; bestD = d; }
            }
            if (current != null && !Bigger(best, current)) return current;
            return best;
        }

        private static bool Bigger(Ship a, Ship b) =>
            a.Tier != b.Tier ? a.Tier > b.Tier : a.BoundRadius > b.BoundRadius + 2f;

        /// <summary>
        /// The reaction delay applies to noticing, too: a target that has just come into view
        /// (or become the biggest) is recorded but not acted on until it has been seen for
        /// DelayTicks; until then the rival keeps to its old target, or to none.
        /// </summary>
        private Ship Perceive(Arena arena, Ship self, Ship picked, long now)
        {
            if (picked == null) { _pendingId = -1; return null; }
            if (picked.Id == _targetId) { _pendingId = -1; return picked; }
            if (picked.Id != _pendingId)
            {
                _pendingId = picked.Id;
                _pendingSince = now;
            }
            _pendingPos[Slot(now)] = picked.Pos;
            _pendingVel[Slot(now)] = picked.Vel;
            if (now - _pendingSince >= DelayTicks)
            {
                // Adopt it with the history recorded since it came into view: what it saw DelayTicks
                // ago is where the target was when first noticed, never fresher.
                _targetId = picked.Id;
                Array.Copy(_pendingPos, _pos, History);
                Array.Copy(_pendingVel, _vel, History);
                for (long k = now - History + 1; k < _pendingSince; k++)
                {
                    _pos[Slot(k)] = _pendingPos[Slot(_pendingSince)];
                    _vel[Slot(k)] = _pendingVel[Slot(_pendingSince)];
                }
                _pendingId = -1;
                return picked;
            }
            Ship old = _targetId >= 0 ? arena.FindShip(_targetId) : null;
            return old != null && old.Alive && Sides.Hostile(old.Side, self.Side) ? old : null;
        }

        private void Remember(long now, Ship target)
        {
            _pos[Slot(now)] = target.Pos;
            _vel[Slot(now)] = target.Vel;
        }

        private static int Slot(long tick) => (int)(((tick % History) + History) % History);

        /// <summary>Sidestep bullets it has perceived: only those at least DelayTicks old, seen where they were DelayTicks ago.</summary>
        private Vec2 Dodge(Arena arena, Ship self)
        {
            Vec2 dodge = Vec2.Zero;
            float dt = _t.Dt;
            float lag = DelayTicks * dt;
            float body = self.BoundRadius * 0.8f;
            var near = arena.BulletsNear(self.Pos, DodgeScan);
            BulletPool b = arena.Bullets;
            for (int q = 0; q < near.Count; q++)
            {
                int i = near[q];
                if (!b.Alive[i] || !Sides.Hostile(b.Side[i], self.Side)) continue;
                if (arena.Tick - b.Born[i] < DelayTicks) continue;   // not perceived yet
                var rel = new Vec2(b.X[i] - b.VX[i] * lag - self.Pos.X, b.Y[i] - b.VY[i] * lag - self.Pos.Y);
                var vel = new Vec2(b.VX[i] - self.Vel.X, b.VY[i] - self.Vel.Y);
                float v2 = vel.LengthSquared();
                if (v2 < 1e-3f) continue;
                float t = -Vec2.Dot(rel, vel) / v2;
                if (t < 0f || t > DodgeLookaheadTicks * dt) continue;
                Vec2 closest = rel + vel * t;
                if (closest.Length() > body + b.Radius[i]) continue;
                dodge = dodge + (closest.LengthSquared() > 1e-4f ? -closest.Normalized() : vel.Normalized().Perp());
            }
            return dodge;
        }

        /// <summary>Toward light it can actually take (not its own fresh shed light, which it may not grab yet).</summary>
        private static Vec2 GrabLight(Arena arena, Ship self, float within, Tuning t)
        {
            int pk = arena.NearestPickup(self.Pos, within, t.RivalGrabMinAgeTicks);
            if (pk < 0) return Vec2.Zero;
            Vec2 to = new Vec2(arena.Pickups.X[pk], arena.Pickups.Y[pk]) - self.Pos;
            return to.LengthSquared() > 1f ? to.Normalized() : Vec2.Zero;
        }

        private static Vec2 AvoidWalls(Arena arena, Ship self)
        {
            const float band = 160f;
            Vec2 p = self.Pos;
            float x = 0f, y = 0f;
            if (p.X < band) x += 1f - p.X / band;
            if (p.X > arena.Width - band) x -= 1f - (arena.Width - p.X) / band;
            if (p.Y < band) y += 1f - p.Y / band;
            if (p.Y > arena.Height - band) y -= 1f - (arena.Height - p.Y) / band;
            return new Vec2(x, y) * 1.2f;
        }
    }
}
