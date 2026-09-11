using System.Collections.Generic;
using Godot;
using Lightship.Core;
using Lightship.Core.Ships;
using Lightship.Core.Sim;

namespace Lightship.View
{
    /// <summary>
    /// Everything in the arena, drawn from Core state each frame: one ShipView
    /// per ship, the pickup and bullet batches, and the effects. Draw order
    /// (spec 15): pickups, enemy ships, player, player bullets, enemy bullets,
    /// effects.
    /// </summary>
    public partial class ArenaView : Node2D
    {
        public const int ZPickups = 0, ZEnemies = 1, ZPlayer = 2, ZPlayerBullets = 3, ZEnemyBullets = 4, ZFx = 5;
        /// <summary>Spec 5: at the threshold the ship locks and pulses in steps (not a ramp): 4 steps a second.</summary>
        public const float PulseStepsPerSecond = 4f;
        public const float PulseStrokeLevel = 1.35f;

        private GameController _gc;
        private ShaderMaterial _shipMat;
        private ShaderMaterial _playerMat;
        private readonly Dictionary<int, ShipView> _views = new Dictionary<int, ShipView>();
        private readonly Dictionary<int, ShipDefinition> _viewDefs = new Dictionary<int, ShipDefinition>();
        private readonly HashSet<int> _seen = new HashSet<int>();
        private readonly List<int> _remove = new List<int>();
        private Arena _arena;
        private float _builtZoom = -1f;
        private bool _wasLocked;
        private float _lockTime;

        public BulletLayer PlayerBullets { get; private set; }
        public BulletLayer EnemyBullets { get; private set; }
        public PickupLayer Pickups { get; private set; }
        public FxLayer Fx { get; private set; }
        public EdgeBarriers Barriers { get; private set; }
        public AimLines Aims { get; private set; }
        public float Zoom { get; private set; } = 1f;
        /// <summary>1 while the player's ship is in the bright half of its lock pulse.</summary>
        public float PlayerPulse { get; private set; }
        public bool PlayerLocked => _wasLocked;

        public void Setup(GameController gc, ShaderMaterial shipMat)
        {
            _gc = gc;
            _shipMat = shipMat;
            // The player's ship has its own material so it can lock and pulse alone. Built fresh:
            // ShaderMaterial.Duplicate() dropped the Color[] palette uniforms (measured: the
            // player rendered as a black silhouette, 0 light-blue pixels in the play probe).
            _playerMat = ShipMeshFactory.NewMaterial();
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
            Barriers = new EdgeBarriers { ZIndex = ZPickups };
            AddChild(Barriers);
            Aims = new AimLines { ZIndex = ZFx };
            AddChild(Aims);
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
                // A new sector or a new life replaced the arena: every view and effect of the old one goes.
                foreach (ShipView v in _views.Values) v.QueueFree();
                _views.Clear();
                _viewDefs.Clear();
                _arena = arena;
                Fx.Reset(game.Events.Total);
            }

            bool zoomChanged = Mathf.Abs(zoom - _builtZoom) > 1e-4f;
            _builtZoom = zoom;
            Zoom = zoom;
            _shipMat.SetShaderParameter("sim_time", time);
            Pickups.SetTime(time);

            // Spec 5: on reaching the threshold the ship locks (its running lights hold still)
            // and pulses as a step change, until the evolution is taken.
            Run run = game.Run;
            bool locked = run.EvolveAvailable;
            if (locked && !_wasLocked) _lockTime = time;
            _wasLocked = locked;
            PlayerPulse = locked ? ((int)Mathf.Floor((time - _lockTime) * PulseStepsPerSecond) % 2 == 0 ? 1f : 0f) : 0f;
            _playerMat.SetShaderParameter("sim_time", locked ? _lockTime : time);
            _playerMat.SetShaderParameter("stroke_level", Mathf.Lerp(Palette.StrokeLevel, PulseStrokeLevel, PlayerPulse));

            _seen.Clear();
            foreach (Ship s in arena.Ships)
            {
                if (!s.Alive) continue;
                _seen.Add(s.Id);
                bool isPlayer = ReferenceEquals(s, arena.Player);
                if (!_views.TryGetValue(s.Id, out ShipView view))
                {
                    view = new ShipView { Material = isPlayer ? _playerMat : _shipMat, ZIndex = s.Side == Sides.Player ? ZPlayer : ZEnemies };
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
            Fx.Sync(game, zoom, _gc.Alpha);
            Barriers.Sync(game, zoom, _gc.Alpha);
            Aims.Sync(game, zoom, _gc.Alpha);
        }
    }

    /// <summary>
    /// Short events, drawn for at least 0.25 s so they register (spec 9), and
    /// status markers. Everything is timed in SIMULATION seconds: a capture
    /// freezes the frame, and effects freeze with it; a jump of many ticks does
    /// not replay old events as new ones.
    /// </summary>
    public partial class FxLayer : Node2D
    {
        private struct Fx
        {
            public Vector2 Pos, To;
            public Color Color;
            public float R0, R1, Start, Life;
            public bool Line;
        }

        /// <summary>A frame longer than 0.25 s, so the first and last frames still leave 0.25 s on screen.</summary>
        public const float MinLife = 0.25f + 1f / 60f;
        private readonly List<Fx> _fx = new List<Fx>();
        private readonly List<GameEvent> _events = new List<GameEvent>();
        private readonly List<(Vector2 pos, float r)> _infected = new List<(Vector2, float)>();
        private long _nextSeq;
        private float _zoom = 1f;
        private float _now;
        public int Active => _fx.Count;
        public int InfectedMarkers => _infected.Count;

        /// <summary>Forget everything before this sequence number (a new arena began).</summary>
        public void Reset(long seq)
        {
            _fx.Clear();
            _nextSeq = seq;
        }

        public void Sync(Game game, float zoom, float alpha)
        {
            _zoom = zoom;
            Arena arena = game.Arena;
            float dt = game.T.Dt;
            _now = (arena.Tick + alpha) * dt;
            game.Events.Since(_nextSeq, _events);
            foreach (GameEvent e in _events)
            {
                _nextSeq = e.Seq + 1;
                if (e.Tick > arena.Tick) continue;   // from a previous arena
                var pos = new Vector2(e.Pos.X, e.Pos.Y);
                Color c = Palette.StrokeOf(Palette.RoleOf(e.Element));
                Fx fx;
                switch (e.Kind)
                {
                    case EventKind.Hit: fx = new Fx { Pos = pos, Color = c, R0 = 2f, R1 = 9f, Life = MinLife }; break;
                    case EventKind.Kill: fx = new Fx { Pos = pos, Color = c, R0 = 6f, R1 = 34f, Life = 0.45f }; break;
                    case EventKind.Absorb: fx = new Fx { Pos = pos, Color = c, R0 = 7f, R1 = 1f, Life = MinLife }; break;
                    case EventKind.PlayerDamaged: fx = new Fx { Pos = pos, Color = new Color(1f, 1f, 1f), R0 = 4f, R1 = 12f, Life = MinLife }; break;
                    case EventKind.InfectSpread:
                        fx = new Fx { Pos = pos, To = new Vector2(e.To.X, e.To.Y), Color = Palette.StrokeOf(ColorRole.CorruptionGreen), Life = 0.4f, Line = true };
                        break;
                    // Evolution has no effect of its own: spec 5 says no flash, the reshape IS the event.
                    default: continue;
                }
                fx.Start = e.Tick * dt;
                if (_now - fx.Start < fx.Life) _fx.Add(fx);
            }
            for (int i = _fx.Count - 1; i >= 0; i--)
                if (_now - _fx[i].Start >= _fx[i].Life) _fx.RemoveAt(i);

            // Infection is a status, not an event: a ring of spores around every infected ship while it lasts.
            _infected.Clear();
            foreach (Ship s in arena.Ships)
                if (s.Alive && s.Infected(arena.Tick))
                {
                    Vec2 p = Vec2.Lerp(s.PrevPos, s.Pos, alpha);
                    _infected.Add((new Vector2(p.X, p.Y), s.BoundRadius + 5f));
                }
            QueueRedraw();
        }

        public override void _Draw()
        {
            float w = 1.5f / _zoom;
            foreach (Fx f in _fx)
            {
                float t = Mathf.Clamp((_now - f.Start) / f.Life, 0f, 1f);
                var c = new Color(f.Color.R, f.Color.G, f.Color.B, 1f - t);
                if (f.Line) DrawLine(f.Pos, f.To, c, w, true);
                else DrawArc(f.Pos, Mathf.Lerp(f.R0, f.R1, t), 0f, Mathf.Tau, 24, c, w, true);
            }
            Color spore = Palette.StrokeOf(ColorRole.CorruptionGreen);
            float spin = _now * 1.5f;
            foreach (var (pos, r) in _infected)
                for (int k = 0; k < 6; k++)
                {
                    float a = spin + Mathf.Tau * k / 6f;
                    DrawCircle(pos + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * r, 1.3f / _zoom, spore);
                }
        }
    }
}
