using Godot;
using Lightship.Core;
using Lightship.Core.Sim;

namespace Lightship.View
{
    /// <summary>
    /// Follows the player with no smoothing (captures must be deterministic),
    /// clamps to the arena, and steps the zoom per tier (spec 5: at most ~10 %
    /// per tier), tweened over the same 0.8 s as the reshape.
    /// </summary>
    public partial class CameraRig : Camera2D
    {
        private GameController _gc;

        public float CurrentZoom { get; private set; } = 1f;

        public void Setup(GameController gc)
        {
            _gc = gc;
            PositionSmoothingEnabled = false;
            LimitLeft = 0;
            LimitTop = 0;
            LimitRight = (int)gc.Tuning.ArenaWidth;
            LimitBottom = (int)gc.Tuning.ArenaHeight;
        }

        public override void _Ready() => MakeCurrent();

        public float Sync()
        {
            Game game = _gc.Game;
            Run run = game.Run;
            Arena arena = game.Arena;
            float target = run.Zoom;
            float zoom = target;
            if (run.Reshape != null)
            {
                // Tween from the previous tier's zoom across the reshape.
                ReshapeState r = run.Reshape;
                float span = r.EndTick - r.StartTick;
                float t = span > 0 ? Mathf.Clamp((arena.Tick + _gc.Alpha - r.StartTick) / span, 0f, 1f) : 1f;
                float from = _gc.Tuning.ZoomForTier(run.Tier - 1);
                zoom = Mathf.Lerp(from, target, t * t * (3f - 2f * t));
            }
            CurrentZoom = zoom;
            Zoom = new Vector2(zoom, zoom);
            if (arena.Player != null)
            {
                Vec2 p = Vec2.Lerp(arena.Player.PrevPos, arena.Player.Pos, _gc.Alpha);
                Position = new Vector2(p.X, p.Y);
            }
            return zoom;
        }
    }
}
