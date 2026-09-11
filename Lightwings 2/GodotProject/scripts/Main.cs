using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;
using Lightship.Core.Config;
using Lightship.Core.Ships;

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
    ///   --screenshot=PATH:SECONDS                       deterministic capture + measure lines
    ///   --bg                                            playfield only (pipeline check)
    ///   --max-seconds=N                                 auto-quit
    /// </summary>
    public partial class Main : Node2D
    {
        private static readonly int[] LadderSizes = { 3, 6, 8, 12, 16, 24 };
        private static readonly float[] LadderLevels = { 1.8f, 4f, 8f, 16f, 32f };
        private const int LadderX0 = 200, LadderY0 = 560, LadderDx = 120, LadderDy = 60;

        private Dictionary<string, string> _args;
        private Tuning _tuning;
        private ShipCatalog _catalog;
        private ShaderMaterial _shipMaterial;
        private ColorRect _backgroundRect;
        private SheetLayout _sheet;

        private string _shotPath;
        private float _shotSeconds = 10f;
        private bool _captureArmed;
        private int _framesSinceTarget;
        private bool _diffPending;
        private Frame _frameA;
        private float _maxSeconds = -1f;
        private double _elapsed;

        public override void _Ready()
        {
            _args = ParseArgs(OS.GetCmdlineUserArgs());
            _tuning = new Tuning();

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

            SetupEnvironment();
            SetupBackground();
            SetupBloom();
            _shipMaterial = ShipMeshFactory.NewMaterial();

            string mode = Mode();
            switch (mode)
            {
                case "sheet":
                    _sheet = new SheetLayout();
                    AddChild(_sheet);
                    _sheet.Build(_catalog, _shipMaterial);
                    _sheet.BloomOn = !Has("no-bloom");
                    break;
                case "bg":
                    break;
                case "emitter":
                    break;
                default:
                    GD.Print("lightship: mode '" + mode + "' is not built yet");
                    break;
            }

            if (Has("emitter") && mode == "bg")
            {
                // Diagnostic (bg mode only, so nothing overlaps the sheet): flat emitter
                // blocks and a size x level ladder; luma beyond their edges IS the bloom.
                var block = new ColorRect { Position = new Vector2(1200, 100), Size = new Vector2(200, 100), MouseFilter = Control.MouseFilterEnum.Ignore };
                block.Material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/emitter_probe.gdshader") };
                AddChild(block);
                // The same shader on a mesh: separates "mesh path" from "shader" if only one blooms.
                var quad = new ArrayMesh();
                var arrays = new Godot.Collections.Array();
                arrays.Resize((int)Mesh.ArrayType.Max);
                arrays[(int)Mesh.ArrayType.Vertex] = new[] { new Vector2(0, 0), new Vector2(200, 0), new Vector2(200, 100), new Vector2(0, 100) };
                arrays[(int)Mesh.ArrayType.Index] = new[] { 0, 1, 2, 0, 2, 3 };
                quad.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays);
                var meshBlock = new MeshInstance2D { Mesh = quad, Position = new Vector2(1200, 300) };
                meshBlock.Material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/emitter_probe.gdshader") };
                AddChild(meshBlock);
                // A sub-threshold block: its buffer value says whether the output stage linearises.
                var dimBlock = new ColorRect { Position = new Vector2(1200, 700), Size = new Vector2(200, 100), MouseFilter = Control.MouseFilterEnum.Ignore };
                var dimMat = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/emitter_probe.gdshader") };
                dimMat.SetShaderParameter("level", 0.5f);
                dimBlock.Material = dimMat;
                AddChild(dimBlock);
                // The ship shader itself forced to a flat 1.8 on a quad carrying a CUSTOM0 attribute.
                var quad2 = new ArrayMesh();
                var arrays2 = new Godot.Collections.Array();
                arrays2.Resize((int)Mesh.ArrayType.Max);
                arrays2[(int)Mesh.ArrayType.Vertex] = new[] { new Vector2(0, 0), new Vector2(200, 0), new Vector2(200, 100), new Vector2(0, 100) };
                arrays2[(int)Mesh.ArrayType.TexUV] = new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
                arrays2[(int)Mesh.ArrayType.Custom0] = new float[16];
                arrays2[(int)Mesh.ArrayType.Index] = new[] { 0, 1, 2, 0, 2, 3 };
                var flags2 = (Mesh.ArrayFormat)((long)Mesh.ArrayCustomFormat.RgbaFloat << (int)Mesh.ArrayFormat.FormatCustom0Shift);
                quad2.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays2, null, null, flags2);
                var shipBlock = new MeshInstance2D { Mesh = quad2, Position = new Vector2(1200, 500) };
                ShaderMaterial shipMat = ShipMeshFactory.NewMaterial();
                shipMat.SetShaderParameter("debug_flat", 1.8f);
                shipBlock.Material = shipMat;
                AddChild(shipBlock);
                // Size x level ladder: square emitters, rows by emission level, columns by size.
                for (int r = 0; r < LadderLevels.Length; r++)
                    for (int c = 0; c < LadderSizes.Length; c++)
                    {
                        int size = LadderSizes[c];
                        var sq = new ColorRect { Position = new Vector2(LadderX0 + c * LadderDx - size / 2f, LadderY0 + r * LadderDy - size / 2f), Size = new Vector2(size, size), MouseFilter = Control.MouseFilterEnum.Ignore };
                        var m = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/emitter_probe.gdshader") };
                        m.SetShaderParameter("level", LadderLevels[r]);
                        sq.Material = m;
                        AddChild(sq);
                    }
            }

            string shot = Arg("screenshot", null);
            if (shot != null) SetupScreenshot(shot);
            if (Has("max-seconds"))
                _maxSeconds = float.Parse(Arg("max-seconds", "0"), CultureInfo.InvariantCulture);

            Godot.Environment active = GetViewport().FindWorld3D()?.Environment;
            GD.Print("lightship: mode=" + mode + " ships=" + _catalog.Count + " hdr2d=" + GetViewport().UseHdr2D +
                " env=" + (active != null) + " glow=" + (active != null && active.GlowEnabled) +
                " bgMode=" + (active != null ? active.BackgroundMode.ToString() : "none") +
                " msaa2d=" + GetViewport().Msaa2D + " disable3d=" + GetViewport().Disable3D);
        }

        private string Mode()
        {
            if (Has("editor")) return "editor";
            if (Has("sheet")) return "sheet";
            if (Has("bench")) return "bench";
            if (Has("hash")) return "hash";
            if (Has("bg")) return "bg";
            if (Has("emitter")) return "emitter";
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
                // Off by default: measured on this machine, the built-in glow adds
                // nothing for emitters under ~12 px (see BloomLayer). --godot-glow
                // turns it back on for comparison.
                GlowEnabled = Has("godot-glow"),
                GlowIntensity = ArgFloat("glow-intensity", 0.9f),
                GlowStrength = ArgFloat("glow-strength", 1.0f),
                // NOT a bloom-amount knob: it adds a constant to the bright pass,
                // so ANY value above zero blooms the entire frame and reads as fog.
                GlowBloom = 0.0f,
                GlowHdrThreshold = ArgFloat("glow-threshold", 1.0f),
                GlowHdrScale = ArgFloat("glow-scale", 1.0f),
                GlowHdrLuminanceCap = ArgFloat("glow-cap", 12.0f),
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

        private BloomLayer _bloom;

        /// <summary>The bloom the spec asks for: threshold 1.0, small radius, high intensity, measured.</summary>
        private void SetupBloom()
        {
            _bloom = new BloomLayer();
            AddChild(_bloom);
            if (!Has("no-bloom"))
                _bloom.Configure(ArgFloat("bloom-threshold", 1.0f), ArgFloat("bloom-intensity", 1.0f),
                                 ArgFloat("bloom-radius", 8f), ArgFloat("bloom-sigma", 3.2f));
            else
                _bloom.Configure(1.0f, 0f, 8f, 3.2f);
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
                if (_framesSinceTarget >= 4)
                {
                    if (_diffPending) CaptureSecond();
                    else CaptureFirst();
                }
                return;
            }

            _elapsed += delta;
            if (_maxSeconds > 0f && _elapsed >= _maxSeconds)
            {
                GD.Print("lightship: max-seconds reached");
                GetTree().Quit(0);
            }
        }

        private void CaptureFirst()
        {
            Frame frame = Frame.Grab(GetViewport());
            if (!Save(frame, _shotPath)) return;
            GD.Print("lightship: screenshot " + _shotPath + " mode=" + Mode());
            // Report the ground rect's actual size: a zero-sized background
            // draws nothing and the measured "background" is really the clear
            // colour, which is a different value through a different transfer.
            GD.Print("measure: groundRect=" + (_backgroundRect == null ? "none" : _backgroundRect.Size.ToString()));
            GD.Print(frame.BasicMeasureLine());
            if (Has("emitter") && Mode() == "bg")
            {
                // Luma along +X from the right edge of the block at (1400, 150) and along +Y below it.
                var sb = new System.Text.StringBuilder("measure: emitter edgeX=");
                foreach (int o in new[] { -4, 0, 2, 4, 8, 12, 16, 24, 32, 48 }) sb.Append(frame.Luma(1400 + o, 150).ToString("F0")).Append(',');
                sb.Append(" edgeY=");
                foreach (int o in new[] { -4, 0, 2, 4, 8, 12, 16, 24, 32, 48 }) sb.Append(frame.Luma(1300, 200 + o).ToString("F0")).Append(',');
                sb.Append(" hdrAtBlock=").Append(frame.Lin[(150 * frame.W + 1300) * 3].ToString("F2"));
                sb.Append(" meshEdgeX=");
                foreach (int o in new[] { -4, 0, 2, 4, 8, 12, 16, 24, 32, 48 }) sb.Append(frame.Luma(1400 + o, 350).ToString("F0")).Append(',');
                sb.Append(" hdrAtMesh=").Append(frame.Lin[(350 * frame.W + 1300) * 3].ToString("F2"));
                sb.Append(" shipShaderEdgeX=");
                foreach (int o in new[] { -4, 0, 2, 4, 8, 12, 16, 24, 32, 48 }) sb.Append(frame.Luma(1400 + o, 550).ToString("F0")).Append(',');
                sb.Append(" hdrAtShipShader=").Append(frame.Lin[(550 * frame.W + 1300) * 3].ToString("F2"));
                sb.Append(" hdrAtDim0.5=").Append(frame.Lin[(750 * frame.W + 1300) * 3].ToString("F4"));
                GD.Print(sb.ToString());
                // Per (level, size): glow added at the centre (hdr minus the level) and luma 3/6/12 px beyond the edge.
                for (int r = 0; r < LadderLevels.Length; r++)
                {
                    var ladder = new System.Text.StringBuilder("measure: ladder level=" + LadderLevels[r]);
                    for (int c = 0; c < LadderSizes.Length; c++)
                    {
                        int size = LadderSizes[c];
                        int cx = LadderX0 + c * LadderDx, cy = LadderY0 + r * LadderDy, edge = cx + size / 2;
                        float added = frame.Lin[(cy * frame.W + cx) * 3] - LadderLevels[r];
                        ladder.Append(" s").Append(size).Append("=+").Append(added.ToString("F2"))
                              .Append("/").Append(frame.Luma(edge + 3, cy).ToString("F0"))
                              .Append(",").Append(frame.Luma(edge + 6, cy).ToString("F0"))
                              .Append(",").Append(frame.Luma(edge + 12, cy).ToString("F0"));
                    }
                    GD.Print(ladder.ToString());
                }
            }

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

        private float ArgFloat(string key, float fallback) =>
            _args.TryGetValue(key, out string v) && v.Length > 0 ? float.Parse(v, CultureInfo.InvariantCulture) : fallback;

        private string Arg(string key, string fallback) =>
            _args.TryGetValue(key, out string v) && v.Length > 0 ? v : fallback;
    }
}
