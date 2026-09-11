using System.Collections.Generic;
using Godot;
using Lightship.Core.Ships;
using Lightship.Core.Sim;

namespace Lightship.View
{
    /// <summary>
    /// Minimal HUD (spec 16) on a CanvasLayer above the bloom, so text stays
    /// crisp: HP bar, an energy bar split by the two leading light types that
    /// locks and pulses at the threshold, and the evolve prompt. The ship
    /// itself carries the rest.
    /// </summary>
    public partial class Hud : CanvasLayer
    {
        public const int LayerIndex = 2;
        private GameController _gc;
        private InputController _input;
        private HudCanvas _canvas;
        private Label _prompt;
        private Label _debug;
        private Label _banner;
        private int _lastDeaths;
        private float _bannerTime;

        public void Setup(GameController gc, InputController input)
        {
            _gc = gc;
            _input = input;
            Layer = LayerIndex;
            _canvas = new HudCanvas { Hud = this, MouseFilter = Control.MouseFilterEnum.Ignore };
            _canvas.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
            AddChild(_canvas);
            _prompt = NewLabel(18);
            _prompt.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.CenterBottom);
            _prompt.Position = new Vector2(-300, -120);
            _prompt.Size = new Vector2(600, 60);
            _prompt.HorizontalAlignment = HorizontalAlignment.Center;
            AddChild(_prompt);
            _debug = NewLabel(13);
            _debug.Position = new Vector2(16, 60);
            AddChild(_debug);
            _banner = NewLabel(28);
            _banner.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.Center);
            _banner.Position = new Vector2(-300, -120);
            _banner.Size = new Vector2(600, 50);
            _banner.HorizontalAlignment = HorizontalAlignment.Center;
            AddChild(_banner);
        }

        private static Label NewLabel(int size)
        {
            var l = new Label { MouseFilter = Control.MouseFilterEnum.Ignore };
            l.AddThemeFontSizeOverride("font_size", size);
            l.AddThemeColorOverride("font_color", new Color(0.86f, 0.96f, 1f));
            return l;
        }

        public void Sync(float delta)
        {
            Game game = _gc.Game;
            Run run = game.Run;
            if (run.EvolveAvailable)
            {
                var parts = new List<string>();
                for (int i = 0; i < run.Offer.Count; i++)
                {
                    ShipDefinition o = run.Offer.Options[i];
                    string mark = i == _input.SelectedOption ? ">" : " ";
                    parts.Add(mark + "[" + (i + 1) + "] " + o.Element + " " + o.Name);
                }
                _prompt.Text = "EVOLVE  (E)    " + string.Join("     ", parts);
                _prompt.Modulate = new Color(1, 1, 1, 0.65f + 0.35f * Mathf.Sin(game.Time * Mathf.Tau * 2f));
            }
            else
            {
                _prompt.Text = run.Reshape != null ? "reshaping" : "";
                _prompt.Modulate = new Color(1, 1, 1, 1);
            }

            if (game.Meta.Deaths != _lastDeaths)
            {
                _lastDeaths = game.Meta.Deaths;
                _bannerTime = 2.5f;
                _banner.Text = "REBOOT " + game.Meta.Deaths;
            }
            _bannerTime -= delta;
            _banner.Visible = _bannerTime > 0f;

            _debug.Visible = _input.DebugVisible;
            if (_debug.Visible)
                _debug.Text = "tick " + game.Arena.Tick + "   energy " + run.Energy.ToString("F0") + "   tier " + run.Tier +
                              "   hp " + game.Arena.Player?.Hp.ToString("F0") + "   bullets " + game.Arena.Bullets.Live +
                              "   pickups " + game.Arena.Pickups.Live + "   enemies " + game.Arena.AliveEnemies() +
                              "   fps " + Engine.GetFramesPerSecond() + (_input.AutoFire ? "   AUTO-FIRE" : "");
            _canvas.QueueRedraw();
        }

        /// <summary>The bars, drawn with plain canvas calls (this layer is above the bloom).</summary>
        public partial class HudCanvas : Control
        {
            public Hud Hud;

            public override void _Draw()
            {
                if (Hud?._gc == null) return;
                Game game = Hud._gc.Game;
                Run run = game.Run;
                Ship player = game.Arena.Player;
                const float x = 16f, y = 16f, w = 260f, h = 6f;

                // HP.
                float hpFrac = player != null && player.MaxHp > 0f ? player.Hp / player.MaxHp : 0f;
                DrawRect(new Rect2(x, y, w, h), new Color(0.2f, 0.25f, 0.3f, 0.6f));
                DrawRect(new Rect2(x, y, w * Mathf.Clamp(hpFrac, 0f, 1f), h), new Color(0.86f, 0.96f, 1f));

                // Energy toward the next threshold, split by the two leading light types.
                float lower = run.Tier >= 2 ? run.T.ThresholdForTier(run.Tier - 1) : 0f;
                float upper = run.Threshold;
                float frac = float.IsInfinity(upper) ? 1f : Mathf.Clamp((run.Energy - lower) / Mathf.Max(upper - lower, 1f), 0f, 1f);
                float ey = y + 12f;
                DrawRect(new Rect2(x, ey, w, h), new Color(0.2f, 0.25f, 0.3f, 0.6f));
                Element first = Element.None, second = Element.None;
                float a1 = 0f, a2 = 0f;
                for (int e = 1; e <= 4; e++)
                {
                    float v = run.Absorbed[e];
                    if (v > a1) { second = first; a2 = a1; first = (Element)e; a1 = v; }
                    else if (v > a2) { second = (Element)e; a2 = v; }
                }
                float total = a1 + a2;
                float filled = w * frac;
                float firstW = total > 0f ? filled * a1 / total : filled;
                Color c1 = first == Element.None ? new Color(0.86f, 0.96f, 1f) : Palette.StrokeOf(Palette.RoleOf(first));
                Color c2 = second == Element.None ? c1 : Palette.StrokeOf(Palette.RoleOf(second));
                bool locked = run.EvolveAvailable;
                float pulse = locked ? 0.6f + 0.4f * Mathf.Sin(game.Time * Mathf.Tau * 2f) : 1f;
                DrawRect(new Rect2(x, ey, firstW, h), c1 * new Color(1, 1, 1, pulse));
                DrawRect(new Rect2(x + firstW, ey, filled - firstW, h), c2 * new Color(1, 1, 1, pulse));
                if (locked) DrawRect(new Rect2(x - 2, ey - 2, w + 4, h + 4), new Color(1, 1, 1, pulse), false, 1f);
            }
        }
    }
}
