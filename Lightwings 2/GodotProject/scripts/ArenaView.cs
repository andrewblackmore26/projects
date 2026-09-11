using System.Collections.Generic;
using Godot;
using Lightship.Core;
using Lightship.Core.Ships;
using Lightship.Core.Sim;

namespace Lightship.View
{
    /// <summary>
    /// Everything in the arena, drawn from Core state each frame: one ShipView
    /// per ship, the pickup and bullet batches, and the hit/absorb effects.
    /// Draw order (spec 15): pickups, enemy ships, player, player bullets,
    /// enemy bullets, effects.
    /// </summary>
    public partial class ArenaView : Node2D
    {
        public const int ZPickups = 0, ZEnemies = 1, ZPlayer = 2, ZPlayerBullets = 3, ZEnemyBullets = 4, ZFx = 5;

        private GameController _gc;
        private ShaderMaterial _shipMat;
        private readonly Dictionary<int, ShipView> _views = new Dictionary<int, ShipView>();
        private readonly Dictionary<int, ShipDefinition> _viewDefs = new Dictionary<int, ShipDefinition>();
        private readonly HashSet<int> _seen = new HashSet<int>();
        private readonly List<int> _remove = new List<int>();
        private Arena _arena;
        private float _builtZoom = -1f;

        public BulletLayer PlayerBullets { get; private set; }
        public BulletLayer EnemyBullets { get; private set; }
        public PickupLayer Pickups { get; private set; }
        public FxLayer Fx { get; private set; }
        public float Zoom { get; private set; } = 1f;

        public void Setup(GameController gc, ShaderMaterial shipMat)
        {
            _gc = gc;
            _shipMat = shipMat;
            int cap = gc.Tuning.BulletCapacity;
            Pickups = new PickupLayer();
            Pickups.Setup(gc.Tuning.PickupCapacity, ZPickups);
            AddChild(Pickups);
            PlayerBullets = new BulletLayer();
            PlayerBullets.Setup(cap, Faction.Player, ZPlayerBullets);
            AddChild(PlayerBullets);
            EnemyBullets = new BulletLayer();
            EnemyBullets.Setup(cap, Faction.Enemy, ZEnemyBullets);
            AddChild(EnemyBullets);
            Fx = new FxLayer { ZIndex = ZFx };
            AddChild(Fx);
        }

        public ShipView PlayerView =>
            _arena?.Player != null && _views.TryGetValue(_arena.Player.Id, out ShipView v) ? v : null;

        public IEnumerable<KeyValuePair<int, ShipView>> Views => _views;

        /// <summary>Pull the frame from Core: positions interpolated by alpha, meshes rebuilt only when needed.</summary>
        public void Sync(float zoom)
        {
            Game game = _gc.Game;
            Arena arena = game.Arena;
            float alpha = _gc.Alpha, dt = _gc.Tuning.Dt;
            float time = _gc.SimTime;

            if (!ReferenceEquals(arena, _arena))
            {
                // A death replaced the run: ship ids restart, so every view goes.
                foreach (ShipView v in _views.Values) v.QueueFree();
                _views.Clear();
                _viewDefs.Clear();
                _arena = arena;
            }

            bool zoomChanged = Mathf.Abs(zoom - _builtZoom) > 1e-4f;
            _builtZoom = zoom;
            Zoom = zoom;
            _shipMat.SetShaderParameter("sim_time", time);
            Pickups.SetTime(time);

            Run run = game.Run;
            _seen.Clear();
            foreach (Ship s in arena.Ships)
            {
                if (!s.Alive) continue;
                _seen.Add(s.Id);
                bool isPlayer = ReferenceEquals(s, arena.Player);
                if (!_views.TryGetValue(s.Id, out ShipView view))
                {
                    view = new ShipView { Material = _shipMat, ZIndex = isPlayer ? ZPlayer : ZEnemies };
                    AddChild(view);
                    _views[s.Id] = view;
                    _viewDefs[s.Id] = null;
                }

                if (isPlayer && run.Reshape != null)
                {
                    // Spec 5: the reshape, rebuilt every frame from the pure tween.
                    ReshapeState r = run.Reshape;
                    float span = r.EndTick - r.StartTick;
                    float t = span > 0 ? Mathf.Clamp((arena.Tick + alpha - r.StartTick) / span, 0f, 1f) : 1f;
                    view.Rebuild(ShipTween.Blend(r.From, r.To, t), zoom);
                    _viewDefs[s.Id] = null;   // force a clean rebuild when it ends
                }
                else if (!ReferenceEquals(_viewDefs[s.Id], s.Def) || zoomChanged)
                {
                    view.Rebuild(ResolvedShip.From(s.Def), zoom);
                    _viewDefs[s.Id] = s.Def;
                }

                Vec2 p = Vec2.Lerp(s.PrevPos, s.Pos, alpha);
                view.Position = new Vector2(p.X, p.Y);
                view.Rotation = s.Rotation;
                float breath = s.BreathScale(time, _gc.Tuning);
                view.Scale = new Vector2(breath, breath);
            }

            _remove.Clear();
            foreach (int id in _views.Keys) if (!_seen.Contains(id)) _remove.Add(id);
            foreach (int id in _remove)
            {
                _views[id].QueueFree();
                _views.Remove(id);
                _viewDefs.Remove(id);
            }

            Pickups.Sync(arena.Pickups, alpha, dt);
            PlayerBullets.Sync(arena.Bullets, alpha, dt);
            EnemyBullets.Sync(arena.Bullets, alpha, dt);
            Fx.Sync(game, zoom);
        }
    }

    /// <summary>
    /// Short events drawn for at least 0.25 s so they register (spec 9): hits,
    /// kills, absorbs and damage to the player. Timed in real seconds, fed by
    /// the event log's monotonic sequence number.
    /// </summary>
    public partial class FxLayer : Node2D
    {
        private struct Fx
        {
            public Vector2 Pos;
            public Color Color;
            public float R0, R1, Age, Life;
        }

        public const float MinLife = 0.25f;
        private readonly List<Fx> _fx = new List<Fx>();
        private readonly List<GameEvent> _events = new List<GameEvent>();
        private long _nextSeq;
        private float _zoom = 1f;
        public int Active => _fx.Count;

        public void Sync(Game game, float zoom)
        {
            _zoom = zoom;
            game.Events.Since(_nextSeq, _events);
            long now = game.Arena.Tick;
            float dtSim = game.T.Dt;
            foreach (GameEvent e in _events)
            {
                _nextSeq = e.Seq + 1;
                var pos = new Vector2(e.Pos.X, e.Pos.Y);
                Color c = Palette.StrokeOf(Palette.RoleOf(e.Element));
                // Age from SIMULATION time: after a jump (a capture, a stalled frame) old events
                // are already over and must not all fire at once. Ticks restart at death, hence the clamp.
                float age = e.Tick <= now ? (now - e.Tick) * dtSim : 0f;
                Fx fx;
                switch (e.Kind)
                {
                    case EventKind.Hit: fx = new Fx { Pos = pos, Color = c, R0 = 2f, R1 = 9f, Life = MinLife }; break;
                    case EventKind.Kill: fx = new Fx { Pos = pos, Color = c, R0 = 6f, R1 = 34f, Life = 0.45f }; break;
                    case EventKind.Absorb: fx = new Fx { Pos = pos, Color = c, R0 = 7f, R1 = 1f, Life = MinLife }; break;
                    case EventKind.PlayerDamaged: fx = new Fx { Pos = pos, Color = new Color(1f, 1f, 1f), R0 = 4f, R1 = 12f, Life = MinLife }; break;
                    // Evolution has no effect of its own: spec 5 says no flash, the reshape IS the event.
                    default: continue;
                }
                fx.Age = age;
                if (fx.Age < fx.Life) _fx.Add(fx);
            }
            float dt = (float)GetProcessDeltaTime();
            for (int i = _fx.Count - 1; i >= 0; i--)
            {
                Fx f = _fx[i];
                f.Age += dt;
                if (f.Age >= f.Life) _fx.RemoveAt(i);
                else _fx[i] = f;
            }
            QueueRedraw();
        }

        public override void _Draw()
        {
            float w = 1.5f / _zoom;
            foreach (Fx f in _fx)
            {
                float t = f.Age / f.Life;
                float r = Mathf.Lerp(f.R0, f.R1, t);
                var c = new Color(f.Color.R, f.Color.G, f.Color.B, 1f - t);
                DrawArc(f.Pos, r, 0f, Mathf.Tau, 24, c, w, true);
            }
        }
    }
}
