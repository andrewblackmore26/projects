using Godot;
using Gridlock.Core;

namespace Gridlock.View
{
    /// <summary>
    /// Sparks at a contest's contact point, thrown PERPENDICULAR to the wire in
    /// both directions at a rate set by min(powerPlayer, powerAi) -- an even
    /// grind throws a shower, a one-sided rout barely sputters (spec 8.5).
    /// The white-hot core itself and the shoving colour boundary are drawn by
    /// the wire shader; this adds the debris and the reinforcement kick.
    /// </summary>
    public partial class ContestView : Node2D
    {
        private GpuParticles2D _up;
        private GpuParticles2D _down;
        private int _wireId;
        private float _kick;

        public void Setup(Wire wire)
        {
            _wireId = wire.Id;
            _up = MakeEmitter();
            _down = MakeEmitter();
            AddChild(_up);
            AddChild(_down);
            ZIndex = 3;
            Visible = false;
        }

        private static GpuParticles2D MakeEmitter()
        {
            var gradient = new Gradient();
            gradient.SetColor(0, new Color(1f, 1f, 1f, 1f));
            gradient.SetColor(1, new Color(1f, 1f, 1f, 0f));
            var texture = new GradientTexture2D
            {
                Gradient = gradient,
                Fill = GradientTexture2D.FillEnum.Radial,
                FillFrom = new Vector2(0.5f, 0.5f),
                FillTo = new Vector2(1.0f, 0.5f),
                Width = 12,
                Height = 12,
            };

            var process = new ParticleProcessMaterial
            {
                Direction = new Vector3(0f, 1f, 0f),
                Spread = 22f,
                InitialVelocityMin = 90f,
                InitialVelocityMax = 260f,
                Gravity = Vector3.Zero,
                ScaleMin = 0.25f,
                ScaleMax = 0.7f,
                // Above 1.0 so the sparks bloom like everything else.
                Color = new Color(3.2f, 3.2f, 3.4f, 1f),
                Damping = new Vector2(120f, 260f),
            };

            return new GpuParticles2D
            {
                Amount = 96,
                Lifetime = 0.42,
                Explosiveness = 0f,
                ProcessMaterial = process,
                Texture = texture,
                Emitting = false,
                Material = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add },
            };
        }

        /// <summary>A big reinforcement lands: kick the sparks for a moment.</summary>
        public void NotifyReinforced() => _kick = 1f;

        public void UpdateFrom(GameController game, BoardTransform transform, Wire wire, float delta)
        {
            Contest contest = null;
            foreach (Contest c in game.Sim.Contests)
            {
                if (c.WireId == _wireId) { contest = c; break; }
            }

            if (contest == null)
            {
                if (Visible)
                {
                    Visible = false;
                    _up.Emitting = false;
                    _down.Emitting = false;
                }
                _kick = 0f;
                return;
            }

            float t = game.ContactT(contest);
            Vector2 here = transform.ToScreen(wire.PositionAt(t));
            // Tangent from a short step along the wire, so the spray stays
            // perpendicular even where the wire turns.
            float step = 0.01f;
            Vector2 ahead = transform.ToScreen(wire.PositionAt(Mathf.Min(1f, t + step)));
            Vector2 behind = transform.ToScreen(wire.PositionAt(Mathf.Max(0f, t - step)));
            Vector2 tangent = (ahead - behind);
            if (tangent.LengthSquared() < 1e-6f) tangent = Vector2.Right;
            tangent = tangent.Normalized();
            var normal = new Vector2(-tangent.Y, tangent.X);

            Position = here;
            Visible = true;

            if (_kick > 0f) _kick = Mathf.Max(0f, _kick - delta * 2.2f);

            float heat = Mathf.Min(contest.PowerPlayer, contest.PowerAi);
            float ratio = Mathf.Clamp(heat / 14f, 0.06f, 1f) * (1f + _kick);

            SetEmitter(_up, normal, ratio);
            SetEmitter(_down, -normal, ratio);
        }

        private static void SetEmitter(GpuParticles2D emitter, Vector2 dir, float ratio)
        {
            var process = (ParticleProcessMaterial)emitter.ProcessMaterial;
            process.Direction = new Vector3(dir.X, dir.Y, 0f);
            emitter.AmountRatio = Mathf.Clamp(ratio, 0.02f, 1f);
            emitter.Emitting = true;
        }
    }
}
