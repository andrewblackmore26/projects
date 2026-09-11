using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;
using Lightship.Core.Config;

namespace Lightship.View
{
    /// <summary>
    /// Entry point and the only scene file in the project: everything else is
    /// built from code, driven by ship data.
    ///
    /// Modes (arguments after a bare "--"):
    ///   --play [--seed=N] [--bot] [--ship=id]          the game (default)
    ///   --editor [--ship=id]                            ship editor (dev)
    ///   --sheet [--lightdiff]                           every authored ship laid out in a grid
    ///   --bench=N [--frames=F]                          N bullets alive, prints frame timings
    ///   --hash --ticks=N --seed=S                       deterministic fingerprint (headless-safe)
    ///   --screenshot=PATH:SECONDS                       deterministic capture + measure line
    ///   --bg                                            playfield only (pipeline check)
    ///   --max-seconds=N                                 auto-quit
    /// </summary>
    public partial class Main : Node2D
    {
        private Dictionary<string, string> _args;
        private Tuning _tuning;
        private ColorRect _backgroundRect;

        private string _shotPath;
        private float _shotSeconds = 10f;
        private bool _captureArmed;
        private int _framesSinceTarget;
        private float _maxSeconds = -1f;
        private double _elapsed;

        public override void _Ready()
        {
            _args = ParseArgs(OS.GetCmdlineUserArgs());
            _tuning = new Tuning();

            SetupEnvironment();
            SetupBackground();

            string shot = Arg("screenshot", null);
            if (shot != null) SetupScreenshot(shot);
            if (Has("max-seconds"))
                _maxSeconds = float.Parse(Arg("max-seconds", "0"), CultureInfo.InvariantCulture);

            GD.Print("lightship: mode=" + Mode() + " hdr2d=" + GetViewport().UseHdr2D);
        }

        private string Mode()
        {
            if (Has("editor")) return "editor";
            if (Has("sheet")) return "sheet";
            if (Has("bench")) return "bench";
            if (Has("hash")) return "hash";
            if (Has("bg")) return "bg";
            return "play";
        }

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
            _captureArmed = true;
        }

        private void SetupEnvironment()
        {
            var env = new Godot.Environment
            {
                BackgroundMode = Godot.Environment.BGMode.Canvas,
                // Only the base canvas is part of the glowed background; the HUD
                // layer sits above it and stays crisp.
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
                // screen, so the playfield can be MEASURED against the spec.
                TonemapMode = Godot.Environment.ToneMapper.Linear,
                TonemapWhite = 1.0f,
            };
            // Small radius, high intensity (spec 15): the widest mips stay at
            // zero because each is a half-resolution blur and leaving them up
            // smears every emitter across the frame (measured on Gridlock 2:
            // bg 11,30,36 with them up versus the spec value with them down).
            // SetGlowLevel is 0-indexed (0..6) though the inspector labels 1..7.
            float[] levels = { 0.25f, 0.55f, 0.9f, 0.7f, 0.25f, 0.0f, 0.0f };
            for (int i = 0; i < levels.Length; i++) env.SetGlowLevel(i, levels[i]);

            AddChild(new WorldEnvironment { Environment = env });
        }

        /// <summary>
        /// Paint the playfield with a raw shader rather than relying on the
        /// clear colour, which Godot converts from sRGB on the way in.
        /// </summary>
        private void SetupBackground()
        {
            // On its own CanvasLayer below the arena: a Control parented to a
            // Node2D has no parent rect to anchor against and would silently
            // draw nothing. Layer stays at or below BackgroundCanvasMaxLayer so
            // the ground remains part of the glowed canvas.
            var layer = new CanvasLayer { Layer = -1 };
            var rect = new ColorRect
            {
                Color = new Color(1, 1, 1, 1),
                MouseFilter = Control.MouseFilterEnum.Ignore,
            };
            rect.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
            var mat = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/background.gdshader") };
            mat.SetShaderParameter("ground", Palette.Playfield);
            rect.Material = mat;
            layer.AddChild(rect);
            AddChild(layer);
            _backgroundRect = rect;
        }

        public override void _Process(double delta)
        {
            if (_captureArmed)
            {
                // Deterministic capture: jump an exact number of ticks (once a
                // simulation exists), then let the frame draw before grabbing it.
                if (_framesSinceTarget == 0)
                {
                    _framesSinceTarget = 1;
                    return;
                }
                _framesSinceTarget++;
                if (_framesSinceTarget >= 4) DoCapture();
                return;
            }

            _elapsed += delta;
            if (_maxSeconds > 0f && _elapsed >= _maxSeconds)
            {
                GD.Print("lightship: max-seconds reached");
                GetTree().Quit(0);
            }
        }

        private void DoCapture()
        {
            _captureArmed = false;
            Frame frame = Frame.Grab(GetViewport());
            Error err = frame.SavePng(_shotPath);
            if (err != Error.Ok)
            {
                GD.PrintErr("ERROR: screenshot save failed: " + err + " path=" + _shotPath);
                GetTree().Quit(1);
                return;
            }
            GD.Print("lightship: screenshot " + _shotPath + " mode=" + Mode());
            // Report the ground rect's actual size: a zero-sized background
            // draws nothing and the measured "background" is really the clear
            // colour, which is a different value through a different transfer.
            GD.Print("measure: groundRect=" + (_backgroundRect == null ? "none" : _backgroundRect.Size.ToString()));
            GD.Print(frame.BasicMeasureLine());
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
    }
}
