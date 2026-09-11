using System;

namespace Lightship.Core.Sim.Patterns
{
    /// <summary>Advances a cursor through a pattern by tick and emits the bullets.</summary>
    public sealed class PatternRunner
    {
        public readonly PatternDefinition Def;
        private int _step;
        private int _repeatsDone;
        private long _nextTick;
        private int _fanIndex;

        public PatternRunner(PatternDefinition def, long startTick)
        {
            Def = def;
            _nextTick = startTick + 30;   // a short grace so a fresh spawn does not fire instantly
        }

        public bool InRange(Arena arena, Ship self) =>
            arena.Player != null && Vec2.Distance(arena.Player.Pos, self.Pos) <= Def.Range;

        public void Tick(Arena arena, Ship self, bool wantsFire)
        {
            if (Def.Steps.Count == 0) return;
            if (arena.Tick < _nextTick) return;
            if (!wantsFire || !InRange(arena, self))
            {
                _nextTick = arena.Tick + 6;   // re-check soon, keep the cursor where it is
                return;
            }
            PatternStep step = Def.Steps[_step];
            Emit(arena, self, step);
            _repeatsDone++;
            if (_repeatsDone >= step.Repeat)
            {
                _repeatsDone = 0;
                _fanIndex = 0;
                _step = (_step + 1) % Def.Steps.Count;
                _nextTick = arena.Tick + step.PauseTicks;
            }
            else
            {
                _nextTick = arena.Tick + step.IntervalTicks;
            }
        }

        private void Emit(Arena arena, Ship self, PatternStep step)
        {
            Vec2 aim = AimDirection(arena, self, step);
            float muzzle = self.BoundRadius * 0.6f;
            switch (step.Kind)
            {
                case StepKind.Cone:
                    for (int k = 0; k < step.Count; k++)
                    {
                        float t = step.Count > 1 ? k / (float)(step.Count - 1) - 0.5f : 0f;
                        Fire(arena, self, aim.Rotated(Geometry.Outline.Rad(step.SpreadDeg * t)), muzzle, step);
                    }
                    break;
                case StepKind.Fan:
                {
                    float t = step.Repeat > 1 ? _fanIndex / (float)(step.Repeat - 1) - 0.5f : 0f;
                    Fire(arena, self, aim.Rotated(Geometry.Outline.Rad(step.SpreadDeg * t)), muzzle, step);
                    _fanIndex++;
                    break;
                }
                case StepKind.Ring:
                    for (int k = 0; k < step.Count; k++)
                        Fire(arena, self, aim.Rotated(2f * MathF.PI * k / step.Count), muzzle, step);
                    break;
                case StepKind.Mine:
                    arena.SpawnBullet(self.Faction, self.Element, self.Pos, Vec2.Zero, step.Radius, step.Damage, step.TtlTicks);
                    break;
                default:   // Bolt and the M3 kinds fire a single bullet for now
                    Fire(arena, self, aim, muzzle, step);
                    break;
            }
            self.NextFireTick = arena.Tick;
        }

        private static void Fire(Arena arena, Ship self, Vec2 dir, float muzzle, PatternStep step)
        {
            arena.SpawnBullet(self.Faction, self.Element, self.Pos + dir * muzzle, dir * step.Speed, step.Radius, step.Damage, step.TtlTicks);
        }

        private static Vec2 AimDirection(Arena arena, Ship self, PatternStep step)
        {
            Ship target = arena.Player;
            if (target == null || step.Aim == AimMode.Forward) return self.Facing;
            Vec2 to = target.Pos - self.Pos;
            if (step.Aim == AimMode.Lead)
            {
                float dist = to.Length();
                float time = step.Speed > 1f ? dist / step.Speed : 0f;
                to = target.Pos + target.Vel * time - self.Pos;
            }
            return to.LengthSquared() > 1e-6f ? to.Normalized() : self.Facing;
        }
    }
}
