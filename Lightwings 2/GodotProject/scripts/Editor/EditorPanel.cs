using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;
using Lightship.Core.Ships;

namespace Lightship.View.Editor
{
    /// <summary>
    /// The editor's controls, on a CanvasLayer above the bloom. Left column:
    /// ship fields, part list and the operations. Right column: the selected
    /// part's fields, rebuilt for its shape. Bottom: validation and tween.
    /// </summary>
    public partial class EditorPanel : CanvasLayer
    {
        private ShipEditor _ed;
        private bool _refreshing;

        private LineEdit _shipId, _shipName;
        private OptionButton _element, _chassis, _load, _tweenTarget;
        private SpinBox _tier;
        private CheckBox _breathes;
        private ItemList _parts;
        private OptionButton _addShape;
        private VBoxContainer _props;
        private Label _status;
        private HSlider _tween;

        private static readonly string[] Periods = { "auto", "2.0", "1.6" };
        private static readonly string[] Phases = { "auto", "0", "-0.7", "-1.3" };
        private static readonly string[] Layers = { "auto", "ring", "tether", "outer", "body", "component" };

        public void Setup(ShipEditor ed)
        {
            _ed = ed;
            Layer = 2;
            var left = new VBoxContainer { Position = new Vector2(12, 12), Size = new Vector2(260, 876) };
            AddChild(left);

            left.AddChild(Title("SHIP"));
            _shipId = Line(left, "id", t => { _ed.Ship.Id = t; _ed.Changed(); });
            _shipName = Line(left, "name", t => { _ed.Ship.Name = t; _ed.Changed(); });
            _element = Options(left, "element", Enum.GetNames(typeof(Element)), i => { _ed.Ship.Element = (Element)i; _ed.Changed(); });
            _tier = Spin(left, "tier", 1, 5, 1, v => { _ed.Ship.Tier = (int)v; _ed.Changed(); });
            _chassis = Options(left, "chassis", Enum.GetNames(typeof(ColorRole)), i => { _ed.Ship.ChassisColor = (ColorRole)i; _ed.Changed(); });
            _breathes = new CheckBox { Text = "breathes" };
            _breathes.Toggled += on => { if (!_refreshing) { _ed.Ship.Breathes = on; _ed.Changed(); } };
            left.AddChild(_breathes);

            left.AddChild(Title("PARTS"));
            _parts = new ItemList { CustomMinimumSize = new Vector2(250, 260) };
            _parts.ItemSelected += i => { if (!_refreshing) _ed.Select((int)i); };
            left.AddChild(_parts);

            var addRow = new HBoxContainer();
            _addShape = new OptionButton();
            foreach (string s in Enum.GetNames(typeof(Shape))) _addShape.AddItem(s);
            addRow.AddChild(_addShape);
            addRow.AddChild(Button("Add", () => _ed.AddPart((Shape)_addShape.Selected)));
            left.AddChild(addRow);
            var opsRow = new HBoxContainer();
            opsRow.AddChild(Button("Delete", _ed.DeleteSelected));
            opsRow.AddChild(Button("Mirror", _ed.MirrorSelected));
            opsRow.AddChild(Button("Up", () => MoveInList(-1)));
            opsRow.AddChild(Button("Down", () => MoveInList(1)));
            left.AddChild(opsRow);

            left.AddChild(Title("FILE"));
            var fileRow = new HBoxContainer();
            fileRow.AddChild(Button("Save", () =>
            {
                bool ok = _ed.Save(null, out string path);
                _status.Text = ok ? "saved " + path : "NOT saved: " + _ed.LastError;
            }));
            fileRow.AddChild(Button("Next tier", _ed.DuplicateAsNextTier));
            fileRow.AddChild(Button("New", () => _ed.Load(ShipEditor.NewShip())));
            left.AddChild(fileRow);
            _load = new OptionButton();
            _load.ItemSelected += i => { if (!_refreshing) _ed.LoadById(_load.GetItemText((int)i)); };
            left.AddChild(Labeled("load", _load));

            left.AddChild(Title("RESHAPE PREVIEW"));
            _tweenTarget = new OptionButton();
            _tweenTarget.ItemSelected += i =>
            {
                _ed.TweenTarget = i == 0 ? null : _ed.Catalog.Get(_tweenTarget.GetItemText((int)i));
                _ed.TweenT = i == 0 ? -1f : (float)_tween.Value;
                _ed.Changed();
            };
            left.AddChild(Labeled("to", _tweenTarget));
            _tween = new HSlider { MinValue = 0, MaxValue = 1, Step = 0.01, CustomMinimumSize = new Vector2(240, 16) };
            _tween.ValueChanged += v => { if (_ed.TweenTarget != null) { _ed.TweenT = (float)v; _ed.Changed(); } };
            left.AddChild(_tween);

            _props = new VBoxContainer { Position = new Vector2(1150, 12), Size = new Vector2(440, 600) };
            AddChild(_props);

            _status = new Label { Position = new Vector2(300, 860), Size = new Vector2(840, 30), AutowrapMode = TextServer.AutowrapMode.WordSmart };
            _status.AddThemeFontSizeOverride("font_size", 13);
            AddChild(_status);

            _ed.CatalogChanged += RebuildShipLists;
            RebuildShipLists();
            Refresh();
        }

        /// <summary>The load and tween lists follow the catalog, including ships saved this session.</summary>
        private void RebuildShipLists()
        {
            _refreshing = true;
            _load.Clear();
            _tweenTarget.Clear();
            _tweenTarget.AddItem("(none)");
            foreach (ShipDefinition s in _ed.Catalog.All)
            {
                _load.AddItem(s.Id);
                _tweenTarget.AddItem(s.Id);
            }
            _refreshing = false;
        }

        private void MoveInList(int dir)
        {
            int i = _ed.Selected, j = i + dir;
            if (i < 0 || j < 0 || j >= _ed.Ship.Parts.Count) return;
            PartDefinition p = _ed.Ship.Parts[i];
            _ed.Ship.Parts[i] = _ed.Ship.Parts[j];
            _ed.Ship.Parts[j] = p;
            _ed.Select(j);
            _ed.Changed();
        }

        /// <summary>Mirror the model into the controls without re-triggering edits.</summary>
        public void Refresh()
        {
            if (_ed?.Ship == null || _parts == null) return;
            _refreshing = true;
            ShipDefinition s = _ed.Ship;
            if (_shipId.Text != s.Id) _shipId.Text = s.Id;
            if (_shipName.Text != (s.Name ?? "")) _shipName.Text = s.Name ?? "";
            _element.Selected = (int)s.Element;
            _tier.Value = s.Tier;
            _chassis.Selected = (int)s.ChassisColor;
            _breathes.ButtonPressed = s.Breathes;

            _parts.Clear();
            foreach (PartDefinition p in s.Parts)
                _parts.AddItem(p.Id + "  (" + p.Shape.ToString().ToLowerInvariant() + (p.Component != null ? ", " + p.Component : "") + ")");
            if (_ed.Selected >= 0) _parts.Select(_ed.Selected);

            BuildProps();
            string warn = _ed.LastWarnings.Count > 0 ? "  |  " + string.Join("  |  ", _ed.LastWarnings) : "";
            _status.Text = _ed.LastError != null ? "ERROR: " + _ed.LastError
                         : "ok  parts=" + s.Parts.Count + "  footprint=" + _ed.Footprint.ToString("F1") + " px (tier " + s.Tier + " expects " +
                           ShipLoader.ExpectedFootprint[Math.Clamp(s.Tier - 1, 0, 4)] + ")" + warn;
            _refreshing = false;
        }

        private void BuildProps()
        {
            foreach (Node c in _props.GetChildren()) { _props.RemoveChild(c); c.QueueFree(); }
            PartDefinition p = _ed.SelectedPart;
            _props.AddChild(Title(p == null ? "NO PART SELECTED" : "PART  " + p.Shape.ToString().ToUpperInvariant()));
            if (p == null) return;
            Line(_props, "id", t =>
            {
                string old = p.Id;
                if (t == old) return;
                // Reject an empty id or one another part already has, before touching any tether:
                // merging two parts' tether references under one id cannot be undone by renaming back.
                if (t.Length == 0 || _ed.Ship.FindPart(t) != null)
                {
                    _status.Text = "rename refused: '" + t + "' is " + (t.Length == 0 ? "empty" : "already a part id");
                    Refresh();
                    return;
                }
                p.Id = t;
                foreach (PartDefinition q in _ed.Ship.Parts) { if (q.From == old) q.From = t; if (q.To == old) q.To = t; }
                _ed.Changed();
            }).Text = p.Id;
            Options(_props, "color", Enum.GetNames(typeof(ColorRole)), i => { p.Color = (ColorRole)i; _ed.Changed(); }).Selected = (int)p.Color;
            if (p.IsTether)
            {
                Line(_props, "from", t => { p.From = t; _ed.Changed(); }).Text = p.From ?? "";
                Line(_props, "to", t => { p.To = t; _ed.Changed(); }).Text = p.To ?? "";
            }
            else
            {
                Spin(_props, "x", -200, 200, 0.5, v => { p.Pos = new Lightship.Core.Vec2((float)v, p.Pos.Y); _ed.Changed(); }).Value = p.Pos.X;
                Spin(_props, "y", -200, 200, 0.5, v => { p.Pos = new Lightship.Core.Vec2(p.Pos.X, (float)v); _ed.Changed(); }).Value = p.Pos.Y;
                Spin(_props, "rot", -180, 180, 1, v => { p.RotDeg = (float)v; _ed.Changed(); }).Value = p.RotDeg;
                foreach (string key in ShapeParams.Keys(p.Shape))
                {
                    string k = key;
                    bool angle = k.EndsWith("_deg");
                    Spin(_props, k, angle ? -360 : -100, angle ? 360 : 200, 0.1, v => { p.Params[k] = (float)v; _ed.Changed(); }).Value = p.Param(k);
                }
            }
            Options(_props, "light period", Periods, i => { p.PeriodIndex = i - 1; _ed.Changed(); }).Selected = p.PeriodIndex + 1;
            Options(_props, "light phase", Phases, i => { p.PhaseIndex = i - 1; _ed.Changed(); }).Selected = p.PhaseIndex + 1;
            Options(_props, "layer", Layers, i => { p.Layer = i == 0 ? (PartLayer?)null : (PartLayer)(i - 1); _ed.Changed(); }).Selected = p.Layer.HasValue ? (int)p.Layer.Value + 1 : 0;
            Line(_props, "component", t => { p.Component = t.Length == 0 ? null : t; _ed.Changed(); }).Text = p.Component ?? "";
            var dashed = new CheckBox { Text = "dashed reach ring", ButtonPressed = p.Dashed };
            dashed.Toggled += on => { p.Dashed = on; _ed.Changed(); };
            _props.AddChild(dashed);
        }

        // ---- small builders ----

        private static Label Title(string text)
        {
            var l = new Label { Text = text };
            l.AddThemeFontSizeOverride("font_size", 13);
            l.AddThemeColorOverride("font_color", new Color(0.44f, 0.83f, 1f));
            return l;
        }

        private static Control Labeled(string label, Control c)
        {
            var row = new HBoxContainer();
            row.AddChild(new Label { Text = label, CustomMinimumSize = new Vector2(80, 0) });
            c.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
            row.AddChild(c);
            return row;
        }

        private LineEdit Line(Container parent, string label, Action<string> onCommit)
        {
            var e = new LineEdit();
            e.TextSubmitted += t => { if (!_refreshing) onCommit(t); };
            e.FocusExited += () => { if (!_refreshing) onCommit(e.Text); };
            parent.AddChild(Labeled(label, e));
            return e;
        }

        private OptionButton Options(Container parent, string label, string[] items, Action<int> onPick)
        {
            var o = new OptionButton();
            foreach (string s in items) o.AddItem(s);
            o.ItemSelected += i => { if (!_refreshing) onPick((int)i); };
            parent.AddChild(Labeled(label, o));
            return o;
        }

        private SpinBox Spin(Container parent, string label, double min, double max, double step, Action<double> onChange)
        {
            var s = new SpinBox { MinValue = min, MaxValue = max, Step = step, AllowGreater = true, AllowLesser = true };
            s.ValueChanged += v => { if (!_refreshing) onChange(v); };
            parent.AddChild(Labeled(label, s));
            return s;
        }

        private static Button Button(string text, Action onPress)
        {
            var b = new Button { Text = text };
            b.Pressed += onPress;
            return b;
        }
    }
}
