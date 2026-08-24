using System;
using System.Collections.Generic;
using Godot;
using Gridlock.Core;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;
// See WireView: Node.Owner would otherwise shadow the simulation's Owner enum.
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// Entry point and the only scene file in the project: everything else is
    /// built from code, driven by level data.
    ///
    /// Modes (arguments after a bare "--"):
    ///   --play  [--level=X] [--ai=N]                   player versus the AI (default)
    ///   --match [--p=N] [--a=N] [--seed=S]             AI versus AI, for watching
    ///   --hash  --ticks=N [--p --a --seed]             print a state fingerprint and quit
    ///   --screenshot=PATH:SECONDS                      deterministic frame capture
    ///   --max-seconds=N                                auto-quit (smoke runs)
    /// </summary>
    public partial class Main : Node2D
    {
        private const string DefaultLevel = "res://levels/level_06_mirrorlock.json";

        private GameController _game;
        private BoardView _board;
        private InputController _input;
        private Dictionary<string, string> _args;

        private string _screenshotPath;
        private float _screenshotSeconds;
        private bool _captureArmed;
        private bool _captureOnContest;
        private int _framesSinceTarget;
        private float _maxSeconds = -1f;
        private Hud _hud;
        private ColorRect _backgroundRect;

        public override void _Ready()
        {
            _args = ParseArgs(OS.GetCmdlineUserArgs());

            var tuning = new Tuning();
            string levelPath = Arg("level", DefaultLevel);
            BuiltLevel level;
            try
            {
                level = LevelLoader.LoadFromJson(ReadLevel(levelPath), tuning);
            }
            catch (Exception e)
            {
                GD.PrintErr("ERROR: could not load level '" + levelPath + "': " + e.Message);
                GetTree().Quit(1);
                return;
            }
            foreach (string warning in level.Warnings) GD.Print("level warning: " + warning);

            _game = new GameController(level, tuning);

            if (Has("hash"))
            {
                RunHashGate();
                return;
            }

            bool attract = Has("match") || Has("screenshot");
            ulong seed = ulong.Parse(Arg("seed", "1"));
            if (attract) _game.AttachStandardAi(int.Parse(Arg("p", "5")), int.Parse(Arg("a", "5")), seed);
            else _game.AddAi(CoreOwner.Ai, int.Parse(Arg("ai", "5")), seed);

            SetupEnvironment();
            SetupBackground();

            _board = new BoardView();
            AddChild(_board);
            _board.Build(_game, GetViewport().GetVisibleRect().Size);

            _hud = new Hud();
            AddChild(_hud);
            _hud.Setup(_game, level.Data.Name);

            var debug = new DebugPanel();
            AddChild(debug);
            debug.Setup(tuning);

            if (!attract)
            {
                _input = new InputController();
                AddChild(_input);
                _input.Setup(_game, _board);
            }

            string shot = Arg("screenshot", null);
            if (shot != null) SetupScreenshot(shot);
            if (Arg("max-seconds", null) != null) _maxSeconds = float.Parse(Arg("max-seconds", "0"));

            GD.Print("gridlock: level=" + level.Data.Id + " nodes=" + level.Nodes.Count +
                " wires=" + level.Wires.Count + " mode=" + (attract ? "attract" : "play"));
        }

        /// <summary>
        /// Cross-engine determinism gate: this line must be byte-identical to the
        /// dotnet CLI's `hash` output for the same level, tiers and seed. If the
        /// two engines ever disagree, the simulation is not deterministic and
        /// nothing downstream (replays, balance runs, multiplayer) can be trusted.
        /// </summary>
        private void RunHashGate()
        {
            ulong seed = ulong.Parse(Arg("seed", "1"));
            _game.AttachStandardAi(int.Parse(Arg("p", "5")), int.Parse(Arg("a", "5")), seed);

            long ticks = long.Parse(Arg("ticks", "3600"));
            while (_game.Sim.Tick < ticks && _game.Sim.Result == MatchResult.None) _game.Sim.Step();

            GD.Print("tick=" + _game.Sim.Tick + " result=" + _game.Sim.Result +
                " hash=" + StateHash.Compute(_game.Sim).ToString("x16"));
            GetTree().Quit(0);
        }

        private void SetupScreenshot(string spec)
        {
            int colon = spec.LastIndexOf(':');
            // Windows paths carry a drive colon; split on the LAST one only, and
            // only when what follows is a duration or the "contest" keyword.
            string tail = colon > 1 ? spec.Substring(colon + 1) : "";
            if (tail == "contest")
            {
                _screenshotPath = spec.Substring(0, colon);
                // Run until the front line actually exists: the contest is the
                // one visual the whole look hangs on, so a capture that happens
                // to miss it proves nothing (spec section 8.5).
                _captureOnContest = true;
                _screenshotSeconds = 600f;
            }
            else if (colon > 1 && float.TryParse(tail, out float seconds))
            {
                _screenshotPath = spec.Substring(0, colon);
                _screenshotSeconds = seconds;
            }
            else
            {
                _screenshotPath = spec;
                _screenshotSeconds = 10f;
            }
            _captureArmed = true;
            // The capture is of the BOARD: HUD text would pollute the pixel
            // statistics it is measured with.
            if (_hud != null) _hud.Visible = false;
        }

        private void SetupEnvironment()
        {
            var env = new Godot.Environment
            {
                BackgroundMode = Godot.Environment.BGMode.Canvas,
                // Only the base canvas is part of the glowed background; HUD and
                // debug layers sit above it and stay crisp.
                BackgroundCanvasMaxLayer = 0,
                GlowEnabled = true,
                GlowIntensity = 0.9f,
                GlowStrength = 1.0f,
                // NOT a bloom-amount knob: it adds a constant to the bright pass,
                // so ANY value above zero blooms the entire frame and reads as fog.
                GlowBloom = 0.0f,
                GlowHdrThreshold = 1.0f,
                GlowHdrScale = 1.0f,
                GlowBlendMode = Godot.Environment.GlowBlendModeEnum.Additive,
                // Linear keeps written values below 1.0 landing unchanged on
                // screen, so the background can be MEASURED against the spec.
                TonemapMode = Godot.Environment.ToneMapper.Linear,
                TonemapWhite = 1.0f,
            };
            // Soft falloff, but the WIDEST mips stay near zero: each one is a
            // half-resolution blur, so leaving 6 and 7 up smears every emitter
            // across the entire frame and the board reads as fog rather than as
            // neon on black. Measured: bg 11,30,36 and meanLuma 62 with the wide
            // mips up, versus the spec's 5,7,13 with them down.
            // SetGlowLevel is 0-indexed (0..6) though the inspector labels them 1..7.
            float[] levels = { 0.25f, 0.55f, 0.9f, 0.7f, 0.25f, 0.0f, 0.0f };
            for (int i = 0; i < levels.Length; i++) env.SetGlowLevel(i, levels[i]);

            AddChild(new WorldEnvironment { Environment = env });
        }

        /// <summary>
        /// Paint the ground with a raw shader rather than relying on the clear
        /// colour, which Godot converts from sRGB on the way in (#05070D lands
        /// near black that way, and the glow loses the surface it should sit on).
        /// </summary>
        private void SetupBackground()
        {
            // On its own CanvasLayer below the board: a Control parented to a
            // Node2D has no parent rect to anchor against, and its size in
            // _Ready is not yet the final window size, so it would silently draw
            // nothing. A CanvasLayer child anchors to the viewport and follows
            // resizes. Layer stays at or below BackgroundCanvasMaxLayer so the
            // ground remains part of the glowed canvas.
            var layer = new CanvasLayer { Layer = -1 };
            var rect = new ColorRect
            {
                Color = new Color(1, 1, 1, 1),
                MouseFilter = Control.MouseFilterEnum.Ignore,
            };
            rect.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
            var mat = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/background.gdshader") };
            mat.SetShaderParameter("ground", Palette.Screen(Palette.Background));
            rect.Material = mat;
            layer.AddChild(rect);
            AddChild(layer);
            _backgroundRect = rect;
        }

        public override void _Process(double delta)
        {
            // _board is null in the hash gate (and after a failed load), where the
            // quit only takes effect at the end of the frame.
            if (_game == null || _board == null) return;

            if (_captureArmed)
            {
                // Deterministic capture: jump an exact number of ticks, then let
                // the frame draw before grabbing it.
                if (_framesSinceTarget == 0)
                {
                    long limit = (long)(_screenshotSeconds * _game.Tuning.TickRate);
                    if (_captureOnContest)
                    {
                        while (_game.Sim.Tick < limit && _game.Sim.Contests.Count == 0 &&
                               _game.Sim.Result == MatchResult.None)
                            _game.Sim.Step();
                        if (_game.Sim.Contests.Count == 0)
                            GD.PrintErr("ERROR: no contest occurred within " + _screenshotSeconds + "s");
                    }
                    else
                    {
                        _game.AdvanceTicks(limit);
                    }
                    _board.UpdateViews(1f / 60f);
                    _framesSinceTarget = 1;
                    return;
                }
                _board.UpdateViews((float)delta);
                _framesSinceTarget++;
                if (_framesSinceTarget >= 4) Capture();
                return;
            }

            _game.Advance(delta);
            _board.UpdateViews((float)delta);

            if (_maxSeconds > 0f && _game.Sim.TimeSeconds >= _maxSeconds)
            {
                GD.Print("gridlock: max-seconds reached, result=" + _game.Sim.Result);
                GetTree().Quit(0);
            }
        }

        private void Capture()
        {
            _captureArmed = false;
            Image hdr = GetViewport().GetTexture().GetImage();
            Image display = ToDisplayImage(hdr);

            Error err = display.SavePng(_screenshotPath);
            if (err != Error.Ok) GD.PrintErr("ERROR: screenshot save failed: " + err);
            else GD.Print("gridlock: screenshot " + _screenshotPath +
                " at sim " + _game.Sim.TimeSeconds.ToString("F1") + "s" +
                " beams=" + _game.Sim.Beams.Count + " contests=" + _game.Sim.Contests.Count);
            if (err == Error.Ok) Measure(hdr, display);
            GetTree().Quit(err == Error.Ok ? 0 : 1);
        }

        /// <summary>
        /// Convert the captured HDR buffer into what a viewer actually sees.
        ///
        /// With hdr_2d the viewport texture is the LINEAR buffer: a canvas
        /// shader's output is linearised on the way in, and SavePng writes those
        /// linear floats straight to 8 bits without re-encoding. That crushes the
        /// dark end -- the spec background lands on 0,0,1 and every colour claim
        /// measured from such a file is wrong. Encoding back to sRGB here makes
        /// the round trip exact: a written #05070D measures as #05070D.
        /// </summary>
        private static Image ToDisplayImage(Image hdr)
        {
            int w = hdr.GetWidth(), h = hdr.GetHeight();
            Image outImage = Image.CreateEmpty(w, h, false, Image.Format.Rgba8);
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    Color c = hdr.GetPixel(x, y);
                    outImage.SetPixel(x, y, new Color(
                        LinearToSrgb(c.R), LinearToSrgb(c.G), LinearToSrgb(c.B), 1f));
                }
            }
            return outImage;
        }

        private static float LinearToSrgb(float c)
        {
            if (c <= 0f) return 0f;
            if (c >= 1f) return 1f;
            return c <= 0.0031308f ? 12.92f * c : 1.055f * Mathf.Pow(c, 1f / 2.4f) - 0.055f;
        }

        /// <summary>
        /// Measure the captured frame and print the numbers. Every colour claim
        /// about this game goes through here: a screenshot that merely "looks
        /// fine" has repeatedly hidden a black shader or a blown-out board on
        /// this project's ancestor.
        ///
        /// Two measurements, because they answer different questions. The
        /// viewport image is the raw HDR buffer (hdr_2d), so its peak proves the
        /// shaders really are writing values above 1.0 for the glow pass to
        /// catch. The reloaded PNG is what a person actually sees, so that is
        /// what the spec's palette is checked against.
        /// </summary>
        private void Measure(Image hdr, Image png)
        {
            float hdrPeak = 0f;
            for (int y = 0; y < hdr.GetHeight(); y += 2)
            {
                for (int x = 0; x < hdr.GetWidth(); x += 2)
                {
                    Color c = hdr.GetPixel(x, y);
                    hdrPeak = Mathf.Max(hdrPeak, Mathf.Max(c.R, Mathf.Max(c.G, c.B)));
                }
            }

            int w = png.GetWidth(), h = png.GetHeight();
            // Sample the background away from the board but inside the frame.
            Color corner = png.GetPixel(6, 6);
            double lumaSum = 0;
            int samples = 0, bright = 0, nearWhite = 0, peak = 0;

            for (int y = 0; y < h; y += 2)
            {
                for (int x = 0; x < w; x += 2)
                {
                    Color c = png.GetPixel(x, y);
                    int r = (int)Mathf.Round(c.R * 255f), g = (int)Mathf.Round(c.G * 255f), b = (int)Mathf.Round(c.B * 255f);
                    double luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
                    lumaSum += luma;
                    samples++;
                    peak = Mathf.Max(peak, Mathf.Max(r, Mathf.Max(g, b)));
                    if (luma > 90) bright++;
                    if (luma > 220) nearWhite++;
                }
            }

            string Rgb(Color c) => ((int)Mathf.Round(c.R * 255f)) + "," +
                                   ((int)Mathf.Round(c.G * 255f)) + "," +
                                   ((int)Mathf.Round(c.B * 255f));

            // Report the ground rect's actual size: a zero-sized background
            // draws nothing and the measured "background" is really the clear
            // colour, which is a different value through a different transfer.
            GD.Print("measure: groundRect=" +
                (_backgroundRect == null ? "none" : _backgroundRect.Size.ToString()));

            GD.Print("measure: size=" + w + "x" + h +
                " bg=" + Rgb(corner) +
                " meanLuma=" + (lumaSum / Mathf.Max(samples, 1)).ToString("F1") +
                " peak=" + peak +
                " hdrPeak=" + hdrPeak.ToString("F2") +
                " brightPct=" + (bright * 100.0 / Mathf.Max(samples, 1)).ToString("F2") +
                " nearWhitePct=" + (nearWhite * 100.0 / Mathf.Max(samples, 1)).ToString("F3"));
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

        private static string ReadLevel(string path)
        {
            if (path.StartsWith("res://") || path.StartsWith("user://"))
            {
                using var file = FileAccess.Open(path, FileAccess.ModeFlags.Read);
                if (file == null) throw new Exception("cannot open " + path + ": " + FileAccess.GetOpenError());
                return file.GetAsText();
            }
            return System.IO.File.ReadAllText(path);
        }
    }
}
