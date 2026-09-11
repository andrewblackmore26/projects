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
            // Spec 11.7: shots leave from the part that carries the pattern's component
            // (the Ember's ember_c for flame_spray); a ship without one fires from ahead of its core.
            Vec2 origin = self.Pos + aim * (self.BoundRadius * 0.6f);
            foreach (Ships.PartDefinition p in self.Def.Parts)
                if (p.Component == Def.Id && !p.IsTether) { origin = self.ToWorld(p.Pos); break; }
            switch (step.Kind)
            {
                case StepKind.Cone:
                    for (int k = 0; k < step.Count; k++)
                    {
                        float t = step.Count > 1 ? k / (float)(step.Count - 1) - 0.5f : 0f;
                        Fire(arena, self, origin, aim.Rotated(Geometry.Outline.Rad(step.SpreadDeg * t)), step);
                    }
                    break;
                case StepKind.Fan:
                {
                    float t = step.Repeat > 1 ? _fanIndex / (float)(step.Repeat - 1) - 0.5f : 0f;
                    Fire(arena, self, origin, aim.Rotated(Geometry.Outline.Rad(step.SpreadDeg * t)), step);
                    _fanIndex++;
                    break;
                }
                case StepKind.Ring:
                    for (int k = 0; k < step.Count; k++)
                        Fire(arena, self, origin, aim.Rotated(2f * MathF.PI * k / step.Count), step);
                    break;
                case StepKind.Mine:
                    arena.SpawnBullet(self.Side, self.Element, self.Pos, Vec2.Zero, step.Radius, step.Damage, step.TtlTicks, 0, self.Id);
                    break;
                default:   // Bolt and the M3 kinds fire a single bullet for now
                    Fire(arena, self, origin, aim, step);
                    break;
            }
        }

        private static void Fire(Arena arena, Ship self, Vec2 origin, Vec2 dir, PatternStep step)
        {
            arena.SpawnBullet(self.Side, self.Element, origin, dir * step.Speed, step.Radius, step.Damage, step.TtlTicks, 0, self.Id);
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
