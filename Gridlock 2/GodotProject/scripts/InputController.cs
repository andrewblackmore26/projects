using Godot;
using Gridlock.Core;
// See WireView: Node.Owner would otherwise shadow the simulation's Owner enum.
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// Press, hold, drag, release (spec section 7). The disambiguation problem is
    /// that a hold and a drag both begin as "pointer down, stationary", so the
    /// node starts charging the INSTANT it is touched and what happens next
    /// decides the outcome. Releasing anywhere invalid cancels for free -- but
    /// the opponent already saw the node brighten, which is what makes feinting
    /// a real move.
    ///
    /// Nothing here reads simulation state back to decide UI: intents drain a
    /// tick later, so the drag is driven from local input state only.
    /// </summary>
    public partial class InputController : Node2D
    {
        private const float TapPixels = 12f;

        private GameController _game;
        private BoardView _board;

        private bool _pressed;
        private Vector2 _pressPosition;
        private Vector2 _pointer;
        private double _pressTime;
        private int _pressedNodeId = -1;
        private int _holdNodeId = -1;
        private int _targetNodeId = -1;
        private int _targetWireId = -1;

        public void Setup(GameController game, BoardView board)
        {
            _game = game;
            _board = board;
            ZIndex = 10;
        }

        public override void _UnhandledInput(InputEvent @event)
        {
            if (@event is InputEventMouseButton mb && mb.ButtonIndex == MouseButton.Left)
            {
                if (mb.Pressed) BeginPress(mb.Position);
                else EndPress(mb.Position);
                QueueRedraw();
            }
            else if (@event is InputEventScreenTouch touch)
            {
                if (touch.Pressed) BeginPress(touch.Position);
                else EndPress(touch.Position);
                QueueRedraw();
            }
            else if (@event is InputEventMouseMotion motion && _pressed)
            {
                UpdateDrag(motion.Position);
                QueueRedraw();
            }
            else if (@event is InputEventScreenDrag drag && _pressed)
            {
                UpdateDrag(drag.Position);
                QueueRedraw();
            }
        }

        private void BeginPress(Vector2 position)
        {
            _pressed = true;
            _pressPosition = position;
            _pointer = position;
            _pressTime = Time.GetTicksMsec() / 1000.0;
            _targetNodeId = -1;
            _targetWireId = -1;

            GameNode node = _board.PickNode(position);
            _pressedNodeId = node?.Id ?? -1;
            _holdNodeId = -1;

            if (node == null) return;
            // The node begins charging immediately -- this is the brightening the
            // opponent sees, and it is why hold and drag need no disambiguation.
            if (node.Owner == CoreOwner.Player && node.State == NodeState.Idle &&
                node.Charge >= _game.Tuning.MinSendCharge)
            {
                _holdNodeId = node.Id;
                _game.Sim.EnqueueBeginHold(CoreOwner.Player, node.Id);
            }
        }

        private void UpdateDrag(Vector2 position)
        {
            _pointer = position;
            _targetNodeId = -1;
            _targetWireId = -1;
            if (_holdNodeId < 0) return;

            GameNode target = _board.PickNode(position);
            if (target == null || target.Id == _holdNodeId) return;

            GameNode source = _game.Sim.NodeById(_holdNodeId);
            foreach (int wireId in source.WireIds)
            {
                if (_game.Sim.WireById(wireId).OtherNode(source.Id) != target.Id) continue;
                _targetNodeId = target.Id;
                _targetWireId = wireId;
                break;
            }
        }

        private void EndPress(Vector2 position)
        {
            if (!_pressed) return;
            UpdateDrag(position);
            _pressed = false;

            if (_holdNodeId >= 0)
            {
                if (_targetWireId >= 0)
                    _game.Sim.EnqueueReleaseSend(CoreOwner.Player, _holdNodeId, _targetWireId);
                else
                    _game.Sim.EnqueueCancelHold(CoreOwner.Player, _holdNodeId);
            }

            // A tap with no drag, released before the burst threshold, is the
            // free inspect tool: no cost, no strategic content, just declutter.
            double heldFor = Time.GetTicksMsec() / 1000.0 - _pressTime;
            bool moved = _pressPosition.DistanceTo(position) > TapPixels;
            if (!moved && heldFor < _game.Tuning.OverchargeTime && _pressedNodeId >= 0)
                _board.Inspect(_pressedNodeId);

            _holdNodeId = -1;
            _pressedNodeId = -1;
            _targetNodeId = -1;
            _targetWireId = -1;
        }

        public override void _Process(double delta)
        {
            if (_pressed) QueueRedraw();
        }

        public override void _Draw()
        {
            if (!_pressed || _holdNodeId < 0) return;

            GameNode source = _game.Sim.NodeById(_holdNodeId);
            Vector2 from = _board.ScreenOf(source);
            bool valid = _targetWireId >= 0;

            Color line = valid
                ? Palette.Hdr(Palette.PlayerBase, 1.6f)
                : new Color(0.32f, 0.35f, 0.42f, 0.9f);
            DrawLine(from, _pointer, line, valid ? 3f : 2f, true);

            if (valid)
            {
                Vector2 at = _board.ScreenOf(_game.Sim.NodeById(_targetNodeId));
                DrawArc(at, 26f, 0f, Mathf.Tau, 40, Palette.Hdr(Palette.PlayerBase, 1.6f), 3f, true);
            }
        }
    }
}
