using Godot;
using Lightship.Core;
using Lightship.Core.Sim;

namespace Lightship.View
{
    /// <summary>
    /// Spec 17 controls, built into the InputMap in code so rebinding (M5) only
    /// has to edit actions. Produces one PlayerInput per frame; edge actions
    /// (evolve and the option keys) are latched into the GameController.
    /// </summary>
    public partial class InputController : Node
    {
        private GameController _gc;
        private Node2D _world;
        public bool AutoFire { get; private set; }
        public bool DebugVisible { get; private set; }
        public int SelectedOption { get; private set; }

        private static readonly string[] Actions =
        {
            "move_up", "move_down", "move_left", "move_right",
            "aim_up", "aim_down", "aim_left", "aim_right",
            "fire", "ability_1", "ability_2", "evolve", "map", "autofire", "debug",
            "option_1", "option_2", "option_3", "option_prev", "option_next", "quit",
        };

        public void Setup(GameController gc, Node2D world)
        {
            _gc = gc;
            _world = world;
            BuildInputMap();
        }

        public static void BuildInputMap()
        {
            foreach (string a in Actions)
            {
                if (InputMap.HasAction(a)) InputMap.EraseAction(a);
                InputMap.AddAction(a, 0.2f);
            }
            Key("move_up", Godot.Key.W); Key("move_down", Godot.Key.S); Key("move_left", Godot.Key.A); Key("move_right", Godot.Key.D);
            Axis("move_up", JoyAxis.LeftY, -1f); Axis("move_down", JoyAxis.LeftY, 1f);
            Axis("move_left", JoyAxis.LeftX, -1f); Axis("move_right", JoyAxis.LeftX, 1f);
            Axis("aim_up", JoyAxis.RightY, -1f); Axis("aim_down", JoyAxis.RightY, 1f);
            Axis("aim_left", JoyAxis.RightX, -1f); Axis("aim_right", JoyAxis.RightX, 1f);
            InputMap.ActionAddEvent("fire", new InputEventMouseButton { ButtonIndex = MouseButton.Left });
            Axis("fire", JoyAxis.TriggerRight, 1f);
            Key("ability_1", Godot.Key.Space); Button("ability_1", JoyButton.LeftShoulder);
            Key("ability_2", Godot.Key.Shift); Button("ability_2", JoyButton.RightShoulder);
            Key("evolve", Godot.Key.E); Button("evolve", JoyButton.A);
            Key("map", Godot.Key.Tab); Button("map", JoyButton.Back);
            Key("autofire", Godot.Key.F);
            Key("debug", Godot.Key.F1);
            Key("option_1", Godot.Key.Key1); Key("option_2", Godot.Key.Key2); Key("option_3", Godot.Key.Key3);
            Button("option_prev", JoyButton.DpadLeft); Button("option_next", JoyButton.DpadRight);
            Key("quit", Godot.Key.Escape);
        }

        private static void Key(string action, Key key) =>
            InputMap.ActionAddEvent(action, new InputEventKey { PhysicalKeycode = key });

        private static void Axis(string action, JoyAxis axis, float value) =>
            InputMap.ActionAddEvent(action, new InputEventJoypadMotion { Axis = axis, AxisValue = value });

        private static void Button(string action, JoyButton button) =>
            InputMap.ActionAddEvent(action, new InputEventJoypadButton { ButtonIndex = button });

        /// <summary>The held state for this frame; edge actions go straight to the controller's latch.</summary>
        public PlayerInput Poll()
        {
            var input = new PlayerInput();
            if (Input.IsActionJustPressed("quit")) GetTree().Quit(0);
            if (Input.IsActionJustPressed("autofire")) AutoFire = !AutoFire;
            if (Input.IsActionJustPressed("debug")) DebugVisible = !DebugVisible;

            Vector2 move = Input.GetVector("move_left", "move_right", "move_up", "move_down");
            input.Move = new Vec2(move.X, move.Y);

            Ship player = _gc.Game.Arena.Player;
            Vector2 stick = Input.GetVector("aim_left", "aim_right", "aim_up", "aim_down");
            if (stick.Length() > 0.3f)
            {
                Vector2 d = stick.Normalized();
                input.Aim = new Vec2(d.X, d.Y);
            }
            else if (player != null)
            {
                Vector2 m = _world.GetGlobalMousePosition();
                var to = new Vec2(m.X - player.Pos.X, m.Y - player.Pos.Y);
                input.Aim = to.LengthSquared() > 1f ? to.Normalized() : player.Facing;
            }

            input.Fire = Input.IsActionPressed("fire") || AutoFire;
            input.Ability1 = Input.IsActionPressed("ability_1");
            input.Ability2 = Input.IsActionPressed("ability_2");
            input.Map = Input.IsActionPressed("map");

            int options = _gc.Game.Run.Offer.Count;
            if (options > 0)
            {
                if (Input.IsActionJustPressed("option_prev")) SelectedOption = (SelectedOption + options - 1) % options;
                if (Input.IsActionJustPressed("option_next")) SelectedOption = (SelectedOption + 1) % options;
                SelectedOption = Mathf.Clamp(SelectedOption, 0, options - 1);
                for (int k = 0; k < 3; k++)
                    if (k < options && Input.IsActionJustPressed("option_" + (k + 1))) { SelectedOption = k; _gc.RequestEvolve(k); }
                if (Input.IsActionJustPressed("evolve")) _gc.RequestEvolve(SelectedOption);
            }
            return input;
        }
    }
}
