using System;
using System.Reflection;
using Godot;
using Gridlock.Core.Config;

namespace Gridlock.View
{
    /// <summary>
    /// Live tuning panel (F1). Reflects over Tuning's public fields, which the
    /// simulation reads every tick, so every constant in the game is adjustable
    /// while it runs -- an acceptance criterion, and the only sane way to tune a
    /// game whose feel lives in a dozen interacting numbers.
    /// </summary>
    public partial class DebugPanel : CanvasLayer
    {
        private Tuning _tuning;
        private Control _root;

        public void Setup(Tuning tuning)
        {
            _tuning = tuning;
            Layer = 2;

            var panel = new PanelContainer();
            panel.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.RightWide);
            panel.Position = new Vector2(0, 0);
            panel.CustomMinimumSize = new Vector2(330, 0);

            var scroll = new ScrollContainer();
            scroll.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
            var list = new VBoxContainer();
            list.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;

            var title = new Label { Text = "TUNING  (F1)" };
            list.AddChild(title);

            foreach (FieldInfo field in typeof(Tuning).GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                if (field.FieldType != typeof(float) && field.FieldType != typeof(int)) continue;
                list.AddChild(BuildRow(field));
            }

            scroll.AddChild(list);
            panel.AddChild(scroll);
            _root = panel;
            _root.Visible = false;
            AddChild(panel);
        }

        private Control BuildRow(FieldInfo field)
        {
            var row = new HBoxContainer();
            var label = new Label
            {
                Text = field.Name,
                CustomMinimumSize = new Vector2(190, 0),
            };
            row.AddChild(label);

            var spin = new SpinBox
            {
                Step = field.FieldType == typeof(int) ? 1 : 0.01,
                MinValue = 0,
                MaxValue = 1000,
                CustomMinimumSize = new Vector2(120, 0),
            };
            spin.Value = field.FieldType == typeof(int)
                ? Convert.ToDouble((int)field.GetValue(_tuning))
                : Convert.ToDouble((float)field.GetValue(_tuning));
            spin.ValueChanged += value =>
            {
                if (field.FieldType == typeof(int)) field.SetValue(_tuning, (int)value);
                else field.SetValue(_tuning, (float)value);
            };
            row.AddChild(spin);
            return row;
        }

        public override void _UnhandledKeyInput(InputEvent @event)
        {
            if (@event is InputEventKey key && key.Pressed && !key.Echo && key.Keycode == Key.F1)
            {
                _root.Visible = !_root.Visible;
                GetViewport().SetInputAsHandled();
            }
        }
    }
}
