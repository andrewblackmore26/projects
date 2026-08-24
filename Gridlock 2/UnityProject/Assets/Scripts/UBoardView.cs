using System.Collections.Generic;
using UnityEngine;
using Gridlock.Core;
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// Builds and drives every view for one board, and owns the lattice-to-world
    /// mapping so input picking and rendering agree by construction.
    /// </summary>
    public class UBoardView : MonoBehaviour
    {
        public UBoardTransform Layout { get; private set; }

        private UGameController _game;
        private readonly Dictionary<int, UWireView> _wires = new Dictionary<int, UWireView>();
        private readonly Dictionary<int, UNodeView> _nodes = new Dictionary<int, UNodeView>();
        private readonly Dictionary<int, UContestView> _contests = new Dictionary<int, UContestView>();

        /// <summary>Tap-to-inspect: node whose wires stay lit, or -1 for everything (spec 7.1).</summary>
        private int _inspectNodeId = -1;
        private float _inspectRemaining;

        public void Build(UGameController game, UBoardTransform layout,
            Material wireMaterial, Material nodeMaterial, Material sparkMaterial)
        {
            _game = game;
            Layout = layout;

            foreach (Wire w in game.Level.Wires)
            {
                var wireObject = new GameObject("wire" + w.Id);
                wireObject.transform.SetParent(transform, false);
                var view = wireObject.AddComponent<UWireView>();
                view.Setup(w, layout, wireMaterial);
                _wires[w.Id] = view;

                var contestObject = new GameObject("contest" + w.Id);
                contestObject.transform.SetParent(transform, false);
                var contest = contestObject.AddComponent<UContestView>();
                contest.Setup(w, sparkMaterial);
                _contests[w.Id] = contest;
            }

            foreach (GameNode n in game.Level.Nodes)
            {
                var nodeObject = new GameObject("node" + n.Id);
                nodeObject.transform.SetParent(transform, false);
                var view = nodeObject.AddComponent<UNodeView>();
                view.Setup(n, layout, nodeMaterial, game.Tuning);
                _nodes[n.Id] = view;
            }

            game.Sim.NodeCaptured += OnNodeCaptured;
            game.Sim.ContestReinforced += OnContestReinforced;
        }

        private void OnNodeCaptured(int nodeId, CoreOwner newOwner, CoreOwner prevOwner)
        {
            if (_nodes.TryGetValue(nodeId, out UNodeView view)) view.NotifyCaptured();
        }

        private void OnContestReinforced(int contestId, int wireId, CoreOwner side, float power)
        {
            if (_contests.TryGetValue(wireId, out UContestView view)) view.NotifyReinforced();
        }

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

            foreach (KeyValuePair<int, UWireView> kv in _wires)
            {
                float intensity = 1f;
                if (inspected != null) intensity = IsAttached(inspected, kv.Key) ? 1f : 0.15f;
                kv.Value.UpdateFrom(_game, intensity);
            }

            foreach (KeyValuePair<int, UNodeView> kv in _nodes)
            {
                float intensity = 1f;
                if (inspected != null && kv.Key != _inspectNodeId)
                    intensity = IsNeighbour(inspected, kv.Key) ? 0.6f : 0.15f;
                kv.Value.UpdateFrom(_game, delta, intensity);
            }

            foreach (KeyValuePair<int, UContestView> kv in _contests)
                kv.Value.UpdateFrom(_game, _game.Sim.WireById(kv.Key), delta);
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

        /// <summary>Node under a world point, or null. Same mapping the views drew with.</summary>
        public GameNode PickNode(Vector2 world, float radius = 0.75f)
        {
            GameNode best = null;
            float bestDist = float.MaxValue;
            foreach (GameNode n in _game.Level.Nodes)
            {
                Vec2 c = HexMath.HexToPixel(n.Coord);
                float dist = Vector2.Distance(world, new Vector2(c.X, c.Y));
                if (dist < radius && dist < bestDist)
                {
                    bestDist = dist;
                    best = n;
                }
            }
            return best;
        }

        public Vector2 WorldOf(GameNode node) => UBoardTransform.ToWorld(HexMath.HexToPixel(node.Coord));
    }
}
