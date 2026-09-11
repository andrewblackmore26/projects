using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using Godot;
using Lightship.Core.Ai;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.Sim;

namespace Lightship.View
{
    /// <summary>
    /// Entry point and the only scene file in the project: everything else is
    /// built from code, driven by ship data.
    ///
    /// Modes (arguments after a bare "--"):
    ///   --play [--seed=N] [--bot] [--ship=id]          the game (default)
    ///   --editor [--ship=id]                            ship editor (dev)
    ///   --sheet [--lightdiff] [--no-bloom]              every authored ship laid out in a grid
    ///   --bench=N [--frames=F]                          N bullets alive, one tick per frame, timings
    ///   --hash --ticks=N --seed=S                       fingerprint (headless-safe), must equal the CLI
    ///   --bg [--emitter]                                playfield only / the bloom instrument
    ///   --screenshot=PATH:SECONDS                       deterministic capture + measure lines
    ///   --max-seconds=N                                 auto-quit
    ///   --godot-glow / --no-bloom / --bloom-*=X         bloom comparison knobs
    /// </summary>
    public partial class Main : Node2D
    {
        private Dictionary<string, string> _args;
        private Tuning _tuning;
        private ShipCatalog _catalog;
        private ShaderMaterial _shipMaterial;
        private ColorRect _backgroundRect;
        private BloomLayer _bloom;
        private string _mode;

        // sheet
        private SheetLayout _sheet;
        // play / bench
        private GameController _gc;
        private ArenaView _arenaView;
        private CameraRig _camera;
        private InputController _input;
        private Hud _hud;
        private PlayProbe _probe;
        // editor
        private Node _editor;

        // capture
        private string _shotPath;
        private float _shotSeconds = 10f;
        private bool _captureArmed;
        private int _framesSinceTarget;
        private bool _diffPending;
        private Frame _frameA;
        private float _maxSeconds = -1f;
        private double _elapsed;

        // bench
        private int _benchFrames;
        private int _benchDone;
        private readonly List<double> _frameMs = new List<double>();
        private readonly List<double> _stepMs = new List<double>();
        private readonly List<double> _syncMs = new List<double>();
        private ulong _lastFrameUsec;
        private long _drawCallsSum;

        public override void _Ready()
        {
            _args = ParseArgs(OS.GetCmdlineUserArgs());
            _tuning = new Tuning();
            _mode = Mode();

            var warnings = new List<string>();
            try
            {
                _catalog = ShipData.LoadCatalog(warnings);
            }
            catch (Exception e)
            {
                GD.PrintErr("ERROR: could not load ships: " + e.Message);
                GetTree().Quit(1);
                return;
            }
            foreach (string w in warnings) GD.Print("ship warning: " + w);

            if (_mode == "hash")
            {
                RunHashGate();
                return;
            }

            SetupEnvironment();
            SetupBackground();
            SetupBloom();
            _shipMaterial = ShipMeshFactory.NewMaterial();

            switch (_mode)
            {
                case "sheet":
                    _sheet = new SheetLayout();
                    AddChild(_sheet);
                    _sheet.Build(_catalog, _shipMaterial);
                    _sheet.BloomOn = !Has("no-bloom");
                    break;
                case "bg":
                    if (Has("emitter")) Diagnostics.BuildEmitters(this);
                    break;
                case "editor":
                    var editor = new Editor.ShipEditor();
                    _editor = editor;
                    AddChild(editor);
                    editor.Setup(_catalog, _shipMaterial, Arg("ship", null));
                    if (Has("selftest"))
                    {
                        List<string> fails = Editor.EditorSelfTest.Run(editor);
                        editor.Load(_catalog.Get(Arg("ship", "corruption_t3_trojan")).Clone());
                        editor.Select(0);
                        if (Arg("screenshot", null) == null) { GetTree().Quit(fails.Count == 0 ? 0 : 1); return; }
                    }
                    break;
                default:
                    SetupPlay();
                    break;
            }

            string shot = Arg("screenshot", null);
            if (shot != null) SetupScreenshot(shot);
            if (Has("max-seconds"))
                _maxSeconds = float.Parse(Arg("max-seconds", "0"), CultureInfo.InvariantCulture);

            GD.Print("lightship: mode=" + _mode + " ships=" + _catalog.Count + " hdr2d=" + GetViewport().UseHdr2D +
                     " msaa2d=" + GetViewport().Msaa2D + " bloom=" + (Has("no-bloom") ? "off" : "on") +
                     " godotGlow=" + (Has("godot-glow") ? "on" : "off"));
        }

        private string Mode()
        {
            if (Has("hash")) return "hash";
            if (Has("editor")) return "editor";
            if (Has("sheet")) return "sheet";
            if (Has("bench")) return "bench";
            if (Has("bg")) return "bg";
            return "play";
        }

        // ---- play ----

        private void SetupPlay()
        {
            ulong seed = ulong.Parse(Arg("seed", "1"));
            bool bot = Has("bot") || _mode == "bench";
            _gc = new GameController(_tuning, _catalog, seed, Arg("ship", null), bot);

            _arenaView = new ArenaView();
            AddChild(_arenaView);
            _arenaView.Setup(_gc, _shipMaterial);

            _camera = new CameraRig();
            _arenaView.AddChild(_camera);
            _camera.Setup(_gc);

            _input = new InputController();
            AddChild(_input);
            _input.Setup(_gc, _arenaView);

            _hud = new Hud();
            AddChild(_hud);
            _hud.Setup(_gc, _input);

            if (_mode == "bench")
            {
                int bullets = int.Parse(Arg("bench", "2000"));
                _benchFrames = int.Parse(Arg("frames", "300"));
                _gc.Game.Arena.SpawnEnemies = false;
                _gc.Game.Arena.DebugSpawnBullets(bullets);
                // Uncapped: a vsync-locked frame time says nothing about cost.
                DisplayServer.WindowSetVsyncMode(DisplayServer.VSyncMode.Disabled);
                Engine.MaxFps = 0;
                GD.Print("lightship: bench bullets=" + bullets + " frames=" + _benchFrames);
            }
            SyncViews();
        }

        private void SyncViews()
        {
            float zoom = _camera.Sync();
            _arenaView.Sync(zoom);
            _hud.Sync((float)GetProcessDeltaTime());
        }

        /// <summary>
        /// Cross-engine determinism gate: this line must be byte-identical to
        /// `lightship-headless hash` for the same seed and tick count.
        /// </summary>
        private void RunHashGate()
        {
            ulong seed = ulong.Parse(Arg("seed", "1"));
            long ticks = long.Parse(Arg("ticks", "3600"));
            var game = new Game(_tuning, _catalog, seed, Game.DefaultSeedShip, new BotPilot());
            while (game.Tick < ticks) game.Step(default);
            GD.Print("tick=" + game.Tick + " energy=" + game.Run.Energy.ToString("F1", CultureInfo.InvariantCulture) +
                     " tier=" + game.Run.Tier + " hash=" + StateHash.Compute(game).ToString("x16"));
            GetTree().Quit(0);
        }

        // ---- environment ----

        private void SetupScreenshot(string spec)
        {
            // Windows paths carry a drive colon; split on the LAST one only, and
            // only when what follows parses as a duration.
            int colon = spec.LastIndexOf(':');
            string tail = colon > 1 ? spec.Substring(colon + 1) : "";
            if (colon > 1 && float.TryParse(tail, NumberStyles.Float, CultureInfo.InvariantCulture, out float seconds))
            {
                _shotPath = spec.Substring(0, colon);
                _shotSeconds = seconds;
            }
            else
            {
                _shotPath = spec;
            }
            // Bench runs its own frame loop and saves its last frame; everything else
            // jumps to the capture tick deterministically.
            _captureArmed = _mode != "bench";
            if (_hud != null && _captureArmed) _hud.Visible = false;   // the capture measures the arena, not the HUD
        }

        private void SetupEnvironment()
        {
            var env = new Godot.Environment
            {
                BackgroundMode = Godot.Environment.BGMode.Canvas,
                BackgroundCanvasMaxLayer = 0,
                // Off by default: measured on this machine, the built-in glow adds
                // nothing for emitters under ~12 px (see BloomLayer and lessons).
                GlowEnabled = Has("godot-glow"),
                GlowIntensity = ArgFloat("glow-intensity", 0.9f),
                GlowStrength = ArgFloat("glow-strength", 1.0f),
                // NOT a bloom-amount knob: any value above zero blooms the whole frame.
                GlowBloom = 0.0f,
                GlowHdrThreshold = ArgFloat("glow-threshold", 1.0f),
                GlowHdrScale = ArgFloat("glow-scale", 1.0f),
                GlowHdrLuminanceCap = ArgFloat("glow-cap", 12.0f),
                GlowBlendMode = Godot.Environment.GlowBlendModeEnum.Additive,
                // Linear keeps written values below 1.0 landing unchanged on screen.
                TonemapMode = Godot.Environment.ToneMapper.Linear,
                TonemapWhite = 1.0f,
            };
            // SetGlowLevel is 0-indexed (0..6) though the inspector labels 1..7;
            // the two widest mips stay at zero (they fog the frame).
            float[] levels = { 0.25f, 0.55f, 0.9f, 0.7f, 0.25f, 0.0f, 0.0f };
            for (int i = 0; i < levels.Length; i++) env.SetGlowLevel(i, levels[i]);
            AddChild(new WorldEnvironment { Environment = env });
        }

        /// <summary>The playfield, painted by a raw shader so it measures as #050507.</summary>
        private void SetupBackground()
        {
            var layer = new CanvasLayer { Layer = -1 };
            var rect = new ColorRect { Color = new Color(1, 1, 1, 1), MouseFilter = Control.MouseFilterEnum.Ignore };
            rect.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
            var mat = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/background.gdshader") };
            mat.SetShaderParameter("ground", Palette.Playfield);
            rect.Material = mat;
            layer.AddChild(rect);
            AddChild(layer);
            _backgroundRect = rect;
        }

        /// <summary>The bloom the spec asks for: threshold 1.0, small radius, high intensity, measured.</summary>
        private void SetupBloom()
        {
            _bloom = new BloomLayer();
            AddChild(_bloom);
            _bloom.Configure(ArgFloat("bloom-threshold", 1.0f), Has("no-bloom") ? 0f : ArgFloat("bloom-intensity", 1.0f),
                             ArgFloat("bloom-radius", 8f), ArgFloat("bloom-sigma", 3.2f));
        }

        // ---- the frame ----

        public override void _Process(double delta)
        {
            if (_captureArmed)
            {
                ProcessCapture();
                return;
            }

            if (_mode == "bench")
            {
                ProcessBench();
                return;
            }

            if (_gc != null)
            {
                PlayerInput input = _input.Poll();
                _gc.Advance(delta, input);
                SyncViews();
            }

            _elapsed += delta;
            if (_maxSeconds > 0f && _elapsed >= _maxSeconds)
            {
                GD.Print("lightship: max-seconds reached");
                if (_gc != null) GD.Print("lightship: tick=" + _gc.Game.Tick + " tier=" + _gc.Game.Run.Tier + " energy=" + _gc.Game.Run.Energy.ToString("F0"));
                GetTree().Quit(0);
            }
        }

        private void ProcessCapture()
        {
            // Deterministic: jump an exact number of ticks, then let a few frames draw.
            if (_framesSinceTarget == 0)
            {
                if (_gc != null)
                {
                    _gc.AdvanceTicks((long)Math.Round(_shotSeconds * _tuning.TickRate));
                    _probe = new PlayProbe();
                    _probe.Plant(_gc.Game.Arena);
                    SyncViews();
                }
                _framesSinceTarget = 1;
                return;
            }
            if (_gc != null) SyncViews();   // no ticks: the frame is frozen, only the views settle
            _framesSinceTarget++;
            if (_framesSinceTarget >= 4)
            {
                if (_diffPending) CaptureSecond();
                else CaptureFirst();
            }
        }

        private void CaptureFirst()
        {
            Frame frame = Frame.Grab(GetViewport());
            if (!Save(frame, _shotPath)) return;
            GD.Print("lightship: screenshot " + _shotPath + " mode=" + _mode);
            GD.Print("measure: groundRect=" + (_backgroundRect == null ? "none" : _backgroundRect.Size.ToString()));
            GD.Print(frame.BasicMeasureLine());

            if (_mode == "bg" && Has("emitter")) Diagnostics.Measure(frame);
            if (_gc != null && _probe != null)
                foreach (string line in _probe.Measure(frame, GetViewport().GetCanvasTransform(), _gc.Game, _arenaView, _camera.CurrentZoom))
                    GD.Print(line);

            if (_sheet != null)
            {
                foreach (string line in _sheet.Measure(frame)) GD.Print(line);
                if (Has("lightdiff"))
                {
                    // Second capture half a second later: every lit point must have moved on.
                    _frameA = frame;
                    _sheet.SetTime(SheetLayout.CaptureTime + SheetLayout.DiffSeconds);
                    _diffPending = true;
                    _framesSinceTarget = 1;
                    return;
                }
            }
            _captureArmed = false;
            GetTree().Quit(0);
        }

        private void CaptureSecond()
        {
            _captureArmed = false;
            Frame frameB = Frame.Grab(GetViewport());
            string pathB = System.IO.Path.ChangeExtension(_shotPath, null) + "_b.png";
            if (!Save(frameB, pathB)) return;
            GD.Print("lightship: screenshot " + pathB + " at sim " + _sheet.Time.ToString("F2") + "s");
            foreach (string line in _sheet.MeasureDiff(_frameA, frameB, SheetLayout.CaptureTime)) GD.Print(line);
            GetTree().Quit(0);
        }

        private bool Save(Frame frame, string path)
        {
            Error err = frame.SavePng(path);
            if (err == Error.Ok) return true;
            GD.PrintErr("ERROR: screenshot save failed: " + err + " path=" + path);
            _captureArmed = false;
            GetTree().Quit(1);
            return false;
        }

        /// <summary>One tick per frame, uncapped: frame time is the real cost of a 60 Hz frame at N bullets.</summary>
        private void ProcessBench()
        {
            ulong now = Time.GetTicksUsec();
            if (_lastFrameUsec != 0 && _benchDone > 10) _frameMs.Add((now - _lastFrameUsec) / 1000.0);
            _lastFrameUsec = now;

            var sw = Stopwatch.StartNew();
            _gc.StepOnce(default);
            sw.Stop();
            if (_benchDone > 10) _stepMs.Add(sw.Elapsed.TotalMilliseconds);
            sw.Restart();
            SyncViews();
            sw.Stop();
            if (_benchDone > 10)
            {
                _syncMs.Add(sw.Elapsed.TotalMilliseconds);
                _drawCallsSum += (long)Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame);
            }
            _benchDone++;
            if (_benchDone < _benchFrames + 11) return;

            _frameMs.Sort();
            double Mean(List<double> l) { double s = 0; foreach (double d in l) s += d; return s / Math.Max(l.Count, 1); }
            int n = _frameMs.Count;
            GD.Print("measure: bench bullets=" + _gc.Game.Arena.Bullets.Live + " frames=" + n +
                     " avgFrameMs=" + Mean(_frameMs).ToString("F3") + " p50FrameMs=" + _frameMs[n / 2].ToString("F3") +
                     " p99FrameMs=" + _frameMs[(int)(n * 0.99)].ToString("F3") +
                     " avgStepMs=" + Mean(_stepMs).ToString("F3") + " avgSyncMs=" + Mean(_syncMs).ToString("F3") +
                     " drawCalls=" + (_drawCallsSum / Math.Max(n, 1)) + " fps=" + (1000.0 / Mean(_frameMs)).ToString("F0"));
            // A bench run still has to leave a frame behind for the harness.
            Frame frame = Frame.Grab(GetViewport());
            if (_shotPath != null) Save(frame, _shotPath);
            GetTree().Quit(0);
        }

        // ---- helpers ----

        private static Dictionary<string, string> ParseArgs(string[] argv)
        {
            var map = new Dictionary<string, string>();
            foreach (string raw in argv)
            {
                string a = raw.StartsWith("--") ? raw.Substring(2) : raw;
                int eq = a.IndexOf('=');
                if (eq >= 0) map[a.Substring(0, eq)] = a.Substring(eq + 1);
                else map[a] = "";
            }
            return map;
        }

        private bool Has(string key) => _args.ContainsKey(key);

        private string Arg(string key, string fallback) =>
            _args.TryGetValue(key, out string v) && v.Length > 0 ? v : fallback;

        private float ArgFloat(string key, float fallback) =>
            _args.TryGetValue(key, out string v) && v.Length > 0 ? float.Parse(v, CultureInfo.InvariantCulture) : fallback;
    }
}
