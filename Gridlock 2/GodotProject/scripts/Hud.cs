using Godot;
using Gridlock.Core;
// See WireView: Node.Owner would otherwise shadow the simulation's Owner enum.
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// Minimal readout. Lives on a CanvasLayer above the board, which bypasses
    /// the glow pass -- text stays crisp instead of blooming into mush, and the
    /// board keeps the whole HDR budget.
    /// </summary>
    public partial class Hud : CanvasLayer
    {
        private GameController _game;
        private Label _status;
        private Label _result;

        public void Setup(GameController game, string levelName)
        {
            _game = game;
            Layer = 1;

            _status = new Label
            {
                Text = levelName,
                Position = new Vector2(22, 16),
                Modulate = new Color(0.62f, 0.72f, 0.85f, 0.85f),
            };
            AddChild(_status);

            _result = new Label
            {
                Visible = false,
                HorizontalAlignment = HorizontalAlignment.Center,
            };
            _result.AddThemeFontSizeOverride("font_size", 40);
            AddChild(_result);

            game.Sim.MatchEnded += OnMatchEnded;
            _levelName = levelName;
        }

        private string _levelName = "";

        private void OnMatchEnded(MatchResult result)
        {
            _result.Text = result == MatchResult.PlayerWin ? "CIRCUIT HELD"
                : result == MatchResult.AiWin ? "CIRCUIT LOST"
                : result.ToString().ToUpperInvariant();
            _result.Modulate = result == MatchResult.PlayerWin ? Palette.PlayerBase : Palette.AiBase;
            _result.Visible = true;
        }

        public override void _Process(double delta)
        {
            if (_game == null) return;

            int player = 0, ai = 0, neutral = 0;
            foreach (GameNode n in _game.Sim.Nodes)
            {
                if (n.Owner == CoreOwner.Player) player++;
                else if (n.Owner == CoreOwner.Ai) ai++;
                else neutral++;
            }
            _status.Text = _levelName + "    " + _game.Sim.TimeSeconds.ToString("F1") + "s" +
                "    nodes  you " + player + " / ai " + ai + " / open " + neutral;

            if (_result.Visible)
            {
                Vector2 size = GetViewport().GetVisibleRect().Size;
                _result.Size = new Vector2(size.X, 60);
                _result.Position = new Vector2(0, size.Y * 0.42f);
            }
        }
    }
}
