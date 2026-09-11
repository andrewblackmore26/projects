using System.Collections.Generic;
using Godot;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Lightship.Core.World;

namespace Lightship.View
{
    /// <summary>
    /// Minimal HUD (spec 16) on a CanvasLayer above the bloom, so text stays
    /// crisp: HP bar, an energy bar split by the two leading light types that
    /// locks and pulses at the threshold, the evolve prompt, the minimap and the
    /// full map (Tab), what an edge will do when it will not let you through,
    /// the gate warning before a lock-in, and the gatekeeper's bar. The ship
    /// itself carries the rest.
    /// </summary>
    public partial class Hud : CanvasLayer
    {
        public const int LayerIndex = 2;
        public static readonly Color TextColor = new Color(0.86f, 0.96f, 1f);
        private GameController _gc;
        private InputController _input;
        private HudCanvas _canvas;
        private Label _prompt;
        private Label _debug;
        private Label _banner;
        private Label _notice;
        private Label _warning;
        private int _lastDeaths;
        private float _bannerTime;
        private float _noticeUntil, _bigUntil;   // simulation seconds: captures freeze them like everything else
        private readonly List<GameEvent> _events = new List<GameEvent>();
        private long _seq;

        public MapView Minimap { get; private set; }
        public MapView FullMap { get; private set; }
        public bool FullMapOpen => FullMap != null && FullMap.Visible;
        public string WarningText => _warning.Visible ? _warning.Text : "";
        public Label WarningLabel => _warning;
        public Label NoticeLabel => _notice;

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
            _banner.Position = new Vector2(-500, -140);
            _banner.Size = new Vector2(1000, 50);
            _banner.HorizontalAlignment = HorizontalAlignment.Center;
            AddChild(_banner);
            _notice = NewLabel(20);
            _notice.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.CenterTop);
            _notice.Position = new Vector2(-500, 64);
            _notice.Size = new Vector2(1000, 30);
            _notice.HorizontalAlignment = HorizontalAlignment.Center;
            AddChild(_notice);
            _warning = NewLabel(22);
            _warning.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.CenterTop);
            _warning.Position = new Vector2(-600, 100);
            _warning.Size = new Vector2(1200, 64);
            _warning.HorizontalAlignment = HorizontalAlignment.Center;
            _warning.AddThemeColorOverride("font_color", Palette.StrokeOf(ColorRole.FireRed));
            AddChild(_warning);

            Minimap = new MapView();
            AddChild(Minimap);
            Minimap.Setup(gc, false);
            FullMap = new MapView { Visible = false };
            AddChild(FullMap);
            FullMap.Setup(gc, true);
            FullMap.TeleportChosen = () =>
            {
                SetFullMap(false);
                input.SuppressFireUntilRelease();
            };
            _seq = gc.Game.Events.Total;
        }

        private static Label NewLabel(int size)
        {
            var l = new Label { MouseFilter = Control.MouseFilterEnum.Ignore };
            l.AddThemeFontSizeOverride("font_size", size);
            l.AddThemeColorOverride("font_color", TextColor);
            return l;
        }

        public void SetFullMap(bool open)
        {
            if (_gc.Game.World == null) open = false;
            FullMap.Visible = open;
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
                // Spec 5: a step change, not a ramp.
                _prompt.Modulate = new Color(1, 1, 1, ((int)Mathf.Floor(game.Time * 4f) % 2 == 0) ? 1f : 0.45f);
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
                _bigUntil = 0f;
            }
            _bannerTime -= delta;

            ReadEvents(game);
            float now = game.Time;
            _banner.Visible = _bannerTime > 0f || now < _bigUntil;
            _notice.Visible = now < _noticeUntil;
            _warning.Text = GateWarning(run);
            _warning.Visible = _warning.Text.Length > 0;
            Minimap.Visible = game.World != null && !FullMapOpen;
            if (FullMapOpen)
            {
                // The map is the only thing to read while it is open (the prompt collided with its legend).
                _prompt.Visible = _notice.Visible = _warning.Visible = _banner.Visible = false;
            }
            else _prompt.Visible = true;

            _debug.Visible = _input.DebugVisible;
            if (_debug.Visible)
                _debug.Text = "tick " + game.Arena.Tick + "   energy " + run.Energy.ToString("F0") + "   tier " + run.Tier +
                              "   hp " + game.Arena.Player?.Hp.ToString("F0") + "   bullets " + game.Arena.Bullets.Live +
                              "   pickups " + game.Arena.Pickups.Live + "   enemies " + game.Arena.AliveEnemies() +
                              (game.World != null ? "   sector " + run.Sector : "") +
                              "   fps " + Engine.GetFramesPerSecond() + (_input.AutoFire ? "   AUTO-FIRE" : "");
            _canvas.QueueRedraw();
            Minimap.QueueRedraw();
            if (FullMapOpen) FullMap.QueueRedraw();
        }

        /// <summary>World events turned into words: where you are, why an edge held, what a gate did.</summary>
        private void ReadEvents(Game game)
        {
            game.Events.Since(_seq, _events);
            _seq = game.Events.Total;
            float now = game.Time;
            foreach (GameEvent e in _events)
            {
                var at = new SectorCoord((int)e.To.X, (int)e.To.Y);
                switch (e.Kind)
                {
                    case EventKind.SectorEntered:
                        Notice(now, at.Layer == 0 ? "ORIGIN  ·  SAFE" : "SECTOR " + at + "  ·  " + e.Element.ToString().ToUpperInvariant() + " LIGHT  ·  LAYER " + at.Layer, 2.2f);
                        break;
                    case EventKind.CrossBlocked:
                        Notice(now, BlockedText((CrossResult)(int)e.Value, game, at), 1.6f);
                        break;
                    case EventKind.SectorCleared:
                        if (e.Value > 0f) Notice(now, "SECTOR CLEARED  ·  IT IS YOURS", 2.2f);
                        break;
                    case EventKind.Teleported:
                        Notice(now, "JUMPED TO THE CHECKPOINT " + at, 2.2f);
                        break;
                    case EventKind.GateLocked:
                        Big(now, "LOCKED IN  ·  BEAT THE GATEKEEPER TO LEAVE", 2.5f);
                        break;
                    case EventKind.GateBeaten:
                        Big(now, "GATE BEATEN  ·  CHECKPOINT", 2.5f);
                        break;
                    case EventKind.BorderShifted:
                        Notice(now, "BORDERS SHIFTED WHILE YOU WERE GONE", 2.5f);
                        break;
                }
            }
        }

        private void Notice(float now, string text, float life)
        {
            _notice.Text = text;
            _noticeUntil = now + life;
        }

        private void Big(float now, string text, float life)
        {
            _banner.Text = text;
            _bigUntil = now + life;
            _bannerTime = 0f;
        }

        public static string BlockedText(CrossResult r, Game game, SectorCoord to)
        {
            switch (r)
            {
                case CrossResult.VeilNeedsEnergy:
                    return "THE VEIL NEEDS " + game.World.ThresholdToEnter(to).ToString("F0") + " ENERGY  (YOU HAVE " + game.Run.Energy.ToString("F0") + ")";
                case CrossResult.VeilOnlyGates: return "THE VEIL  ·  ONLY A GATE CROSSES IT";
                case CrossResult.LockedIn: return "LOCKED IN  ·  BEAT THE GATEKEEPER";
                default: return "THE EDGE OF THE WORLD";
            }
        }

        /// <summary>Spec 7 "no surprise traps": near an edge into an unbeaten gate, say what entering does, before it happens.</summary>
        public static string GateWarning(Run run)
        {
            if (run.World == null || run.LockedIn || run.Player == null) return "";
            foreach (Edge e in Edges.All)
            {
                if (!run.EdgeIntoGate(e) || run.DistanceToEdge(e) > run.T.GateWarnDistance) continue;
                SectorCoord gate = run.Sector.Step(e);
                string text = "GATE AHEAD  ·  ENTERING LOCKS EVERY EXIT UNTIL ITS GATEKEEPER FALLS";
                float need = run.World.ThresholdToEnter(gate);
                if (run.Energy < need) text += "\nTHE VEIL NEEDS " + need.ToString("F0") + " ENERGY TO ENTER";
                return text;
            }
            return "";
        }

        /// <summary>The gatekeeper's bar: top centre, its colour, its name, and when it runs.</summary>
        public static Rect2 BossBarRect(Vector2 view) => new Rect2(view.X / 2f - 240f, 40f, 480f, 8f);

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
                DrawRect(new Rect2(x, y, w * Mathf.Clamp(hpFrac, 0f, 1f), h), TextColor);

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
                Color c1 = first == Element.None ? TextColor : Palette.StrokeOf(Palette.RoleOf(first));
                Color c2 = second == Element.None ? c1 : Palette.StrokeOf(Palette.RoleOf(second));
                bool locked = run.EvolveAvailable;
                float pulse = locked ? (((int)Mathf.Floor(game.Time * 4f) % 2 == 0) ? 1f : 0.45f) : 1f;
                DrawRect(new Rect2(x, ey, firstW, h), c1 * new Color(1, 1, 1, pulse));
                DrawRect(new Rect2(x + firstW, ey, filled - firstW, h), c2 * new Color(1, 1, 1, pulse));
                if (locked) DrawRect(new Rect2(x - 2, ey - 2, w + 4, h + 4), new Color(1, 1, 1, pulse), false, 1f);

                // The gatekeeper (spec 7): a boss bar while it stands.
                Ship k = game.Arena.Gatekeeper;
                if (k != null && k.Alive)
                {
                    Rect2 bar = BossBarRect(GetViewportRect().Size);
                    Color kc = Palette.StrokeOf(Palette.RoleOf(k.Element));
                    DrawRect(bar, new Color(0.2f, 0.12f, 0.12f, 0.7f));
                    DrawRect(new Rect2(bar.Position, new Vector2(bar.Size.X * Mathf.Clamp(k.Hp / k.MaxHp, 0f, 1f), bar.Size.Y)), kc);
                    string name = k.Def.Name.ToUpperInvariant() + "  ·  GATEKEEPER" + (k.Retreating ? "  ·  RETREATING" : "");
                    DrawString(ThemeDB.FallbackFont, new Vector2(bar.Position.X, bar.Position.Y - 6f), name, HorizontalAlignment.Left, -1, 15, kc);
                }
            }
        }
    }
}
