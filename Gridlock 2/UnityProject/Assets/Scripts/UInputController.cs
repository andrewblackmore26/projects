using UnityEngine;
using Gridlock.Core;
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// Press, hold, drag, release (spec section 7). A hold and a drag both begin
    /// as "pointer down, stationary", so the node starts charging the INSTANT it
    /// is touched and what happens next decides the outcome. Releasing anywhere
    /// invalid cancels for free -- but the opponent already saw the node
    /// brighten, which is what makes feinting a real move.
    ///
    /// Nothing here reads simulation state back to decide UI: intents drain a
    /// tick later, so the drag runs off local input state only.
    ///
    /// Uses the legacy Input class deliberately: it covers mouse and touch in one
    /// path and, unlike the Input System package, can be compile-verified on a
    /// machine with no usable Unity licence. See README for the migration note.
    /// </summary>
    public class UInputController : MonoBehaviour
    {
        private const float TapPixels = 12f;

        private UGameController _game;
        private UBoardView _board;
        private Camera _camera;
        private LineRenderer _targetLine;

        private bool _pressed;
        private Vector2 _pressPosition;
        private Vector2 _pointer;
        private float _pressTime;
        private int _pressedNodeId = -1;
        private int _holdNodeId = -1;
        private int _targetNodeId = -1;
        private int _targetWireId = -1;

        public void Setup(UGameController game, UBoardView board, Camera camera, Material lineMaterial)
        {
            _game = game;
            _board = board;
            _camera = camera;

            var lineObject = new GameObject("targetingLine");
            lineObject.transform.SetParent(transform, false);
            _targetLine = lineObject.AddComponent<LineRenderer>();
            _targetLine.material = lineMaterial;
            _targetLine.positionCount = 2;
            _targetLine.useWorldSpace = true;
            _targetLine.numCapVertices = 2;
            _targetLine.enabled = false;
        }

        private void Update()
        {
            if (_game == null) return;

            bool down = Input.GetMouseButtonDown(0);
            bool up = Input.GetMouseButtonUp(0);
            Vector2 screen = Input.mousePosition;

            if (Input.touchCount > 0)
            {
                Touch touch = Input.GetTouch(0);
                screen = touch.position;
                down = touch.phase == TouchPhase.Began;
                up = touch.phase == TouchPhase.Ended || touch.phase == TouchPhase.Canceled;
            }

            if (down) BeginPress(screen);
            else if (_pressed) UpdateDrag(screen);
            if (up) EndPress(screen);

            DrawTargetingLine();
        }

        private Vector2 ToWorld(Vector2 screen)
        {
            Vector3 world = _camera.ScreenToWorldPoint(new Vector3(screen.x, screen.y, -_camera.transform.position.z));
            return new Vector2(world.x, world.y);
        }

        private void BeginPress(Vector2 screen)
        {
            _pressed = true;
            _pressPosition = screen;
            _pointer = screen;
            _pressTime = Time.time;
            _targetNodeId = -1;
            _targetWireId = -1;

            GameNode node = _board.PickNode(ToWorld(screen));
            _pressedNodeId = node == null ? -1 : node.Id;
            _holdNodeId = -1;
            if (node == null) return;

            // The node begins charging immediately -- this is the brightening the
            // opponent sees, and why hold and drag need no disambiguation.
            if (node.Owner == CoreOwner.Player && node.State == NodeState.Idle &&
                node.Charge >= _game.Tuning.MinSendCharge)
            {
                _holdNodeId = node.Id;
                _game.Sim.EnqueueBeginHold(CoreOwner.Player, node.Id);
            }
        }

        private void UpdateDrag(Vector2 screen)
        {
            _pointer = screen;
            _targetNodeId = -1;
            _targetWireId = -1;
            if (_holdNodeId < 0) return;

            GameNode target = _board.PickNode(ToWorld(screen));
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

        private void EndPress(Vector2 screen)
        {
            if (!_pressed) return;
            UpdateDrag(screen);
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
            float heldFor = Time.time - _pressTime;
            bool moved = Vector2.Distance(_pressPosition, screen) > TapPixels;
            if (!moved && heldFor < _game.Tuning.OverchargeTime && _pressedNodeId >= 0)
                _board.Inspect(_pressedNodeId);

            _holdNodeId = -1;
            _pressedNodeId = -1;
            _targetNodeId = -1;
            _targetWireId = -1;
        }

        private void DrawTargetingLine()
        {
            if (!_pressed || _holdNodeId < 0)
            {
                _targetLine.enabled = false;
                return;
            }

            GameNode source = _game.Sim.NodeById(_holdNodeId);
            Vector2 from = _board.WorldOf(source);
            Vector2 to = ToWorld(_pointer);
            bool valid = _targetWireId >= 0;

            Color colour = valid
                ? UPalette.Hdr(UPalette.PlayerBase, 1.6f)
                : new Color(0.32f, 0.35f, 0.42f, 0.9f);
            float width = (valid ? 3f : 2f) * _board.Layout.WorldPerPixel;

            _targetLine.enabled = true;
            _targetLine.startColor = colour;
            _targetLine.endColor = colour;
            _targetLine.startWidth = width;
            _targetLine.endWidth = width;
            _targetLine.SetPosition(0, new Vector3(from.x, from.y, 0f));
            _targetLine.SetPosition(1, new Vector3(to.x, to.y, 0f));
        }
    }
}
