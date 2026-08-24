using System.Collections.Generic;
using Godot;
using Gridlock.Core;
// See WireView: Node.Owner would otherwise shadow the simulation's Owner enum.
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// Builds and drives every view for one board. Owns the lattice-to-screen
    /// transform, so input picking and rendering agree by construction.
    /// </summary>
    public partial class BoardView : Node2D
    {
        /// <summary>Lattice-to-screen mapping. Named Layout, not Transform, because Node2D already has one.</summary>
        public BoardTransform Layout { get; private set; }

        private GameController _game;
        private readonly Dictionary<int, WireView> _wires = new Dictionary<int, WireView>();
        private readonly Dictionary<int, NodeView> _nodes = new Dictionary<int, NodeView>();
        private readonly Dictionary<int, ContestView> _contests = new Dictionary<int, ContestView>();

        /// <summary>Tap-to-inspect: node whose wires stay lit, or -1 for everything (spec 7.1).</summary>
        private int _inspectNodeId = -1;
        private float _inspectRemaining;

        public void Build(GameController game, Vector2 viewportSize)
        {
            _game = game;
            Layout = new BoardTransform(game.Level, viewportSize);

            var wireShader = GD.Load<Shader>("res://shaders/wire.gdshader");
            var nodeShader = GD.Load<Shader>("res://shaders/node.gdshader");

            foreach (Wire w in game.Level.Wires)
            {
                var view = new WireView();
                view.Setup(w, Layout, wireShader);
                AddChild(view);
                _wires[w.Id] = view;

                var contest = new ContestView();
                contest.Setup(w);
                AddChild(contest);
                _contests[w.Id] = contest;
            }

            foreach (GameNode n in game.Level.Nodes)
            {
                var view = new NodeView();
                view.Setup(n, Layout, nodeShader, game.Tuning);
                AddChild(view);
                _nodes[n.Id] = view;
            }

            game.Sim.NodeCaptured += OnNodeCaptured;
            game.Sim.ContestReinforced += OnContestReinforced;
        }

        private void OnNodeCaptured(int nodeId, CoreOwner newOwner, CoreOwner prevOwner)
        {
            if (_nodes.TryGetValue(nodeId, out NodeView view)) view.NotifyCaptured();
        }

        private void OnContestReinforced(int contestId, int wireId, CoreOwner side, float power)
        {
            if (_contests.TryGetValue(wireId, out ContestView view)) view.NotifyReinforced();
        }

        /// <summary>Highlight one node's wires and dim the rest, for a couple of seconds.</summary>
        public void Inspect(int nodeId, float seconds = 2f)
        {
            _inspectNodeId = nodeId;
            _inspectRemaining = nodeId >= 0 ? seconds : 0f;
        }

        public void UpdateViews(float delta)
        {
            if (_inspectRemaining > 0f)
            {
                _inspectRemaining -= delta;
                if (_inspectRemaining <= 0f) _inspectNodeId = -1;
            }

            GameNode inspected = _inspectNodeId >= 0 ? _game.Sim.NodeById(_inspectNodeId) : null;

            foreach (KeyValuePair<int, WireView> kv in _wires)
            {
                float intensity = 1f;
                if (inspected != null) intensity = IsAttached(inspected, kv.Key) ? 1f : 0.15f;
                kv.Value.UpdateFrom(_game, intensity);
            }

            foreach (KeyValuePair<int, NodeView> kv in _nodes)
            {
                float intensity = 1f;
                if (inspected != null && kv.Key != _inspectNodeId)
                    intensity = IsNeighbour(inspected, kv.Key) ? 0.6f : 0.15f;
                kv.Value.UpdateFrom(_game, delta, intensity);
            }

            foreach (KeyValuePair<int, ContestView> kv in _contests)
                kv.Value.UpdateFrom(_game, Layout, _game.Sim.WireById(kv.Key), delta);
        }

        private static bool IsAttached(GameNode node, int wireId)
        {
            foreach (int id in node.WireIds)
            {
                if (id == wireId) return true;
            }
            return false;
        }

        private bool IsNeighbour(GameNode node, int otherNodeId)
        {
            foreach (int id in node.WireIds)
            {
                if (_game.Sim.WireById(id).OtherNode(node.Id) == otherNodeId) return true;
            }
            return false;
        }

        /// <summary>Node under a screen point, or null. Uses the same transform the views drew with.</summary>
        public GameNode PickNode(Vector2 screenPoint, float radiusFraction = 0.75f)
        {
            Vec2 lattice = Layout.ToLattice(screenPoint);
            GameNode best = null;
            float bestDist = float.MaxValue;
            foreach (GameNode n in _game.Level.Nodes)
            {
                Vec2 c = HexMath.HexToPixel(n.Coord);
                float dx = c.X - lattice.X, dy = c.Y - lattice.Y;
                float dist = Mathf.Sqrt(dx * dx + dy * dy);
                if (dist < radiusFraction && dist < bestDist)
                {
                    bestDist = dist;
                    best = n;
                }
            }
            return best;
        }

        public Vector2 ScreenOf(GameNode node) => Layout.ToScreen(HexMath.HexToPixel(node.Coord));
    }
}
