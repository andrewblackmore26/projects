using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;
using Lightship.Core;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;

namespace Lightship.View.Editor
{
    /// <summary>
    /// The in-engine ship editor (spec 14): dev-only, but robust enough for
    /// daily use. It edits a ShipDefinition and redraws it through the exact
    /// game renderer: a 4x magnified working view (strokes stay at their
    /// screen-space widths because the mesh is extruded at the view's zoom),
    /// a 1x preview at base zoom and a silhouette preview at the tier-5 zoom.
    ///
    /// Mouse on the working view: click selects, drag moves, wheel scales the
    /// selected part, Q/E rotate it. Every change re-validates through the
    /// same ShipLoader rules the tests and the CLI use.
    /// </summary>
    public partial class ShipEditor : Node2D
    {
        public const float WorkZoom = 4f;
        public static readonly Vector2 WorkCentre = new Vector2(800, 430);
        public static readonly Vector2 PreviewCentre = new Vector2(1380, 760);
        public static readonly Vector2 SilhouetteCentre = new Vector2(1500, 760);

        private ShipCatalog _catalog;
        private ShaderMaterial _material;
        private ShipView _work, _preview, _silhouette;
        private EditorPanel _panel;
        private float _time;
        private bool _dragging;
        private Vector2 _dragOffset;

        public ShipDefinition Ship { get; private set; }
        public int Selected { get; private set; } = -1;
        public ShipDefinition TweenTarget { get; set; }
        public float TweenT { get; set; } = -1f;   // < 0: no tween preview
        public string LastError { get; private set; }
        public List<string> LastWarnings { get; } = new List<string>();
        public ShipCatalog Catalog => _catalog;
        public float Footprint { get; private set; }

        public void Setup(ShipCatalog catalog, ShaderMaterial material, string shipId)
        {
            _catalog = catalog;
            _material = material;
            _work = new ShipView { Material = material, Position = WorkCentre, Scale = new Vector2(WorkZoom, WorkZoom) };
            _preview = new ShipView { Material = material, Position = PreviewCentre };
            _silhouette = new ShipView { Material = material, Position = SilhouetteCentre };
            AddChild(_work);
            AddChild(_preview);
            AddChild(_silhouette);
            _panel = new EditorPanel();
            AddChild(_panel);

            ShipDefinition start = shipId != null ? catalog.Get(shipId) : null;
            if (start == null && catalog.Count > 0) start = catalog.All[0];
            Load(start != null ? start.Clone() : NewShip());
            _panel.Setup(this);
        }

        public static ShipDefinition NewShip()
        {
            var s = new ShipDefinition { Id = "new_t1_ship", Name = "New", Element = Element.Fire, Tier = 1, ChassisColor = ColorRole.FireRed, CoreColor = ColorRole.FireRed };
            s.Parts.Add(new PartDefinition { Id = "body", Shape = Shape.Circle, Color = ColorRole.FireRed, Params = { ["radius"] = 10f } });
            return s;
        }

        public void Load(ShipDefinition ship)
        {
            Ship = ship;
            Selected = ship.Parts.Count > 0 ? 0 : -1;
            TweenT = -1f;
            Changed();
        }

        public PartDefinition SelectedPart => Selected >= 0 && Selected < Ship.Parts.Count ? Ship.Parts[Selected] : null;

        public void Select(int index)
        {
            Selected = index >= 0 && index < Ship.Parts.Count ? index : -1;
            _panel?.Refresh();
            QueueRedraw();
        }

        /// <summary>Re-validate and rebuild every view. Called after every edit.</summary>
        public void Changed()
        {
            LastWarnings.Clear();
            LastError = null;
            try
            {
                ShipLoader.Validate(Ship, LastWarnings);
            }
            catch (ShipFormatException e)
            {
                LastError = e.Message;
            }
            if (LastError == null)
            {
                ResolvedShip resolved = TweenT >= 0f && TweenTarget != null ? ShipTween.Blend(Ship, TweenTarget, TweenT) : ResolvedShip.From(Ship);
                _work.Rebuild(resolved, WorkZoom);
                _preview.Rebuild(resolved, 1f);
                float minZoom = MathF.Pow(0.9f, 4);
                _silhouette.Rebuild(resolved, minZoom);
                _silhouette.Scale = new Vector2(minZoom, minZoom);
                Footprint = _work.Geometry.Footprint;
            }
            _panel?.Refresh();
            QueueRedraw();
        }

        public override void _Process(double delta)
        {
            _time += (float)delta;
            _material.SetShaderParameter("sim_time", _time);
            if (Ship != null && Ship.Breathes)
            {
                float b = Easing.Breath(_time, 2f, 0.05f, 0f);
                _preview.Scale = new Vector2(b, b);
            }
        }

        // ---- editing operations (also driven by the self-test) ----

        public string UniqueId(string stem)
        {
            string id = stem;
            int n = 2;
            while (Ship.FindPart(id) != null) id = stem + "_" + n++;
            return id;
        }

        public void AddPart(Shape shape)
        {
            var p = new PartDefinition { Id = UniqueId(shape.ToString().ToLowerInvariant()), Shape = shape, Color = Ship.ChassisColor };
            foreach (string key in ShapeParams.Keys(shape))
            {
                float v = ShapeParams.Default(shape, key);
                if (ShapeParams.IsSizeKey(key) && v == 0f) v = key == "length" ? 16f : 6f;
                if (key == "cut_dy") v = -4f;
                if (key == "cut_dx") v = 0f;
                p.Params[key] = v;
            }
            if (shape == Shape.Tether)
            {
                if (Ship.Parts.Count < 2) return;
                p.From = Ship.Parts[0].Id;
                p.To = Ship.Parts[Ship.Parts.Count - 1].Id;
            }
            Ship.Parts.Add(p);
            Selected = Ship.Parts.Count - 1;
            Changed();
        }

        public void DeleteSelected()
        {
            PartDefinition p = SelectedPart;
            if (p == null) return;
            Ship.Parts.RemoveAt(Selected);
            // Tethers attached to a deleted part go with it.
            Ship.Parts.RemoveAll(t => t.IsTether && (t.From == p.Id || t.To == p.Id));
            Selected = Math.Min(Selected, Ship.Parts.Count - 1);
            Changed();
        }

        /// <summary>Spec 11.3: satellites and wings come in mirrored pairs. x -> -x, rot -> -rot, _l <-> _r.</summary>
        public void MirrorSelected()
        {
            PartDefinition p = SelectedPart;
            if (p == null || p.IsTether) return;
            PartDefinition m = p.Clone();
            string id = p.Id.EndsWith("_l") ? p.Id.Substring(0, p.Id.Length - 2) + "_r"
                      : p.Id.EndsWith("_r") ? p.Id.Substring(0, p.Id.Length - 2) + "_l" : p.Id + "_m";
            m.Id = UniqueId(id);
            m.Pos = new Vec2(-p.Pos.X, p.Pos.Y);
            m.RotDeg = -p.RotDeg;
            if (m.Params.ContainsKey("cut_dx")) m.Params["cut_dx"] = -m.Params["cut_dx"];
            if (m.Params.ContainsKey("start_deg")) m.Params["start_deg"] = -m.Param("start_deg") - m.Param("sweep_deg");
            Ship.Parts.Insert(Selected + 1, m);
            Selected++;
            Changed();
        }

        public void MoveSelected(Vec2 pos)
        {
            PartDefinition p = SelectedPart;
            if (p == null || p.IsTether) return;
            p.Pos = new Vec2(MathF.Round(pos.X * 2f) / 2f, MathF.Round(pos.Y * 2f) / 2f);
            Changed();
        }

        public void ScaleSelected(float factor)
        {
            PartDefinition p = SelectedPart;
            if (p == null) return;
            foreach (string key in ShapeParams.Keys(p.Shape))
                if (ShapeParams.IsSizeKey(key) && p.Params.ContainsKey(key)) p.Params[key] = MathF.Round(p.Params[key] * factor * 100f) / 100f;
            Changed();
        }

        public void RotateSelected(float degrees)
        {
            PartDefinition p = SelectedPart;
            if (p == null) return;
            p.RotDeg = ((p.RotDeg + degrees) % 360f + 360f) % 360f;
            if (p.RotDeg > 180f) p.RotDeg -= 360f;
            Changed();
        }

        /// <summary>Spec 14: duplicate a ship as the starting point for the next tier.</summary>
        public void DuplicateAsNextTier()
        {
            ShipDefinition c = Ship.Clone();
            c.Tier = Math.Min(5, Ship.Tier + 1);
            string stem = Ship.Id;
            int t = stem.IndexOf("_t" + Ship.Tier + "_", StringComparison.Ordinal);
            c.Id = t >= 0 ? stem.Substring(0, t) + "_t" + c.Tier + "_new" : stem + "_next";
            c.Name = Ship.Name + "+";
            Load(c);
        }

        public string SavePath(string dir = null) =>
            (dir ?? ProjectSettings.GlobalizePath(ShipData.ShipsDir)) + "/" + Ship.Id + ".json";

        /// <summary>Refuses to write a ship that fails the loader's hard rules.</summary>
        public bool Save(string dir, out string path)
        {
            path = SavePath(dir);
            Changed();
            if (LastError != null) return false;
            System.IO.File.WriteAllText(path, ShipLoader.Serialize(Ship));
            return true;
        }

        // ---- mouse on the working view ----

        public Vec2 WorkLocal(Vector2 screen)
        {
            Vector2 l = (screen - WorkCentre) / WorkZoom;
            return new Vec2(l.X, l.Y);
        }

        /// <summary>The topmost part under the point, else the nearest centre within 6 units.</summary>
        public int PartAt(Vec2 local)
        {
            if (_work.Geometry == null) return -1;
            List<PartGeometry> parts = _work.Geometry.Parts;
            for (int i = parts.Count - 1; i >= 0; i--)
                if (parts[i].ContainsPoint(local)) return Ship.Parts.FindIndex(p => p.Id == parts[i].Id);
            int best = -1;
            float bestD = 6f;
            for (int i = 0; i < Ship.Parts.Count; i++)
            {
                float d = Vec2.Distance(Ship.Parts[i].Pos, local);
                if (d < bestD) { bestD = d; best = i; }
            }
            return best;
        }

        public override void _UnhandledInput(InputEvent e)
        {
            if (e is InputEventMouseButton mb)
            {
                Vec2 local = WorkLocal(mb.Position);
                bool inWork = Mathf.Abs(mb.Position.X - WorkCentre.X) < 330 && Mathf.Abs(mb.Position.Y - WorkCentre.Y) < 330;
                if (!inWork) return;
                if (mb.ButtonIndex == MouseButton.Left && mb.Pressed)
                {
                    int hit = PartAt(local);
                    Select(hit);
                    if (SelectedPart != null)
                    {
                        _dragging = true;
                        _dragOffset = new Vector2(SelectedPart.Pos.X - local.X, SelectedPart.Pos.Y - local.Y);
                    }
                }
                else if (mb.ButtonIndex == MouseButton.Left && !mb.Pressed) _dragging = false;
                else if (mb.ButtonIndex == MouseButton.WheelUp && mb.Pressed) ScaleSelected(1.05f);
                else if (mb.ButtonIndex == MouseButton.WheelDown && mb.Pressed) ScaleSelected(1f / 1.05f);
            }
            else if (e is InputEventMouseMotion mm && _dragging)
            {
                Vec2 local = WorkLocal(mm.Position);
                MoveSelected(new Vec2(local.X + _dragOffset.X, local.Y + _dragOffset.Y));
            }
            else if (e is InputEventKey k && k.Pressed)
            {
                if (k.PhysicalKeycode == Key.Q) RotateSelected(-5f);
                else if (k.PhysicalKeycode == Key.E) RotateSelected(5f);
                else if (k.PhysicalKeycode == Key.Delete) DeleteSelected();
                else if (k.PhysicalKeycode == Key.M) MirrorSelected();
            }
        }

        public override void _Draw()
        {
            // Frames around the three views and the selection outline (plain canvas lines, under the bloom threshold).
            var frame = new Color(0.25f, 0.3f, 0.36f);
            DrawRect(new Rect2(WorkCentre - new Vector2(330, 330), new Vector2(660, 660)), frame, false, 1f);
            DrawRect(new Rect2(PreviewCentre - new Vector2(55, 55), new Vector2(110, 110)), frame, false, 1f);
            DrawRect(new Rect2(SilhouetteCentre - new Vector2(55, 55), new Vector2(110, 110)), frame, false, 1f);
            // Axis cross at the ship origin (the core).
            DrawLine(WorkCentre + new Vector2(-320, 0), WorkCentre + new Vector2(320, 0), new Color(0.12f, 0.14f, 0.17f), 1f);
            DrawLine(WorkCentre + new Vector2(0, -320), WorkCentre + new Vector2(0, 320), new Color(0.12f, 0.14f, 0.17f), 1f);
            if (_work?.Geometry == null || SelectedPart == null) return;
            PartGeometry g = _work.Geometry.Find(SelectedPart.Id);
            if (g == null) return;
            var pts = new Vector2[g.Outline.Length + (g.IsTether ? 0 : 1)];
            for (int i = 0; i < g.Outline.Length; i++) pts[i] = WorkCentre + new Vector2(g.Outline[i].X, g.Outline[i].Y) * WorkZoom;
            if (!g.IsTether) pts[pts.Length - 1] = pts[0];
            DrawPolyline(pts, new Color(1f, 1f, 1f, 0.8f), 1f, true);
        }
    }
}
