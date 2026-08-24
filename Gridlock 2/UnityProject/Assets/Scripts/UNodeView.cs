using System.Collections.Generic;
using UnityEngine;
using Gridlock.Core;
using Gridlock.Core.Config;
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// One node: a hex outline whose brightness reads as stored charge, plus the
    /// state tells (spec section 8.6). Overcharging is deliberately loud, because
    /// the opponent seeing a node wind up is what makes feinting a real tactic.
    /// </summary>
    public class UNodeView : MonoBehaviour
    {
        private const float RingRadius = 0.66f;

        private static readonly int RingColor = Shader.PropertyToID("_RingColor");
        private static readonly int Intensity = Shader.PropertyToID("_Intensity");
        private static readonly int BaseIntensity = Shader.PropertyToID("_BaseIntensity");
        private static readonly int CoreUv = Shader.PropertyToID("_CoreUv");
        private static readonly int PulsePhase = Shader.PropertyToID("_PulsePhase");
        private static readonly int PulseAmount = Shader.PropertyToID("_PulseAmount");
        private static readonly int Armed = Shader.PropertyToID("_Armed");
        private static readonly int Sweep = Shader.PropertyToID("_Sweep");
        private static readonly int Flash = Shader.PropertyToID("_Flash");

        private int _nodeId;
        private MeshRenderer _renderer;
        private MaterialPropertyBlock _block;
        private float _pulsePhase;
        private float _flash;
        private float _initialNeutralDefense;
        private readonly List<MeshRenderer> _stubs = new List<MeshRenderer>();

        public void Setup(GameNode node, UBoardTransform layout, Material material, Tuning tuning)
        {
            _nodeId = node.Id;
            _initialNeutralDefense = Mathf.Max(node.NeutralDefense, 0.0001f);

            Vec2 centre = HexMath.HexToPixel(node.Coord);
            transform.position = new Vector3(centre.X, centre.Y, 0f);

            // Local space around the node, so the capture flash can scale the
            // ring about its own centre.
            var pts = new List<Vector2>(6);
            for (int i = 0; i < 6; i++)
            {
                Vec2 corner = HexMath.CellCorner(node.Coord, i);
                pts.Add(new Vector2(
                    (corner.X - centre.X) * RingRadius,
                    (corner.Y - centre.Y) * RingRadius));
            }

            // Kept THIN: a thick bright ring blooms inward, fills its own hole,
            // and the hex silhouette that shows the six faces is lost.
            float halfWidthPx = 3.0f;
            float halfWidth = halfWidthPx * layout.WorldPerPixel;

            var filter = gameObject.AddComponent<MeshFilter>();
            filter.mesh = URibbon.Build(pts, halfWidth, true);
            _renderer = gameObject.AddComponent<MeshRenderer>();
            _renderer.sharedMaterial = material;
            _renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            _renderer.receiveShadows = false;

            _block = new MaterialPropertyBlock();
            _block.SetFloat(CoreUv, Mathf.Clamp(1.5f / (2f * halfWidthPx), 0.1f, 0.5f));
            _renderer.SetPropertyBlock(_block);

            if (node.Owner == CoreOwner.Neutral) BuildFaceStubs(node, centre, material, halfWidth);
        }

        /// <summary>Stubs let a neutral node's degree be read while its wires are still unlit.</summary>
        private void BuildFaceStubs(GameNode node, Vec2 centre, Material material, float halfWidth)
        {
            for (int face = 0; face < 6; face++)
            {
                if (node.WireIdByFace[face] < 0) continue;
                HexMath.FaceEdge(node.Coord, face, out VertexCoord va, out VertexCoord vb);
                Vec2 pa = va.ToPixel(), pb = vb.ToPixel();
                var mid = new Vector2((pa.X + pb.X) * 0.5f - centre.X, (pa.Y + pb.Y) * 0.5f - centre.Y);
                Vector2 inner = mid * (RingRadius + 0.06f);

                var stub = new GameObject("stub" + face);
                stub.transform.SetParent(transform, false);
                var filter = stub.AddComponent<MeshFilter>();
                filter.mesh = URibbon.Build(new List<Vector2> { inner, mid }, halfWidth * 0.8f, false);
                var renderer = stub.AddComponent<MeshRenderer>();
                renderer.sharedMaterial = material;
                renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                renderer.receiveShadows = false;

                var block = new MaterialPropertyBlock();
                block.SetFloat(CoreUv, 0.3f);
                block.SetColor(RingColor, UPalette.Hdr(UPalette.NeutralBase, UPalette.NeutralEmission));
                block.SetFloat(Intensity, 0.9f);
                block.SetFloat(BaseIntensity, 1f);
                block.SetFloat(Sweep, -1f);
                renderer.SetPropertyBlock(block);
                _stubs.Add(renderer);
            }
        }

        public void NotifyCaptured() => _flash = 1f;

        public void UpdateFrom(UGameController game, float delta, float baseIntensity)
        {
            GameNode node = game.Sim.NodeById(_nodeId);
            Tuning tuning = game.Tuning;

            Color ring;
            float intensity;
            if (node.Owner == CoreOwner.Neutral)
            {
                ring = UPalette.Hdr(UPalette.NeutralBase, UPalette.NeutralEmission);
                // Dims as the toll is chipped, so a softened hub is visible
                // before anyone commits to taking it.
                float remaining = Mathf.Clamp01(node.NeutralDefense / _initialNeutralDefense);
                intensity = 0.45f + 0.55f * remaining;
            }
            else
            {
                ring = UPalette.Hdr(UPalette.OwnerColor(node.Owner), UPalette.OwnerEmission);
                float max = Mathf.Max(node.MaxCharge(tuning), 0.0001f);
                intensity = 0.28f + 0.46f * Mathf.Clamp01(node.Charge / max);
            }

            float pulseAmount = 0f;
            float armed = 0f;
            float sweep = -1f;

            if (node.State == NodeState.Overcharging)
            {
                float progress = node.OverchargeProgress(game.Sim.Tick, tuning);
                // Charging is loud on purpose (design pillar 3): this is the one
                // state allowed to bloom hard.
                intensity += 1.3f * progress;
                pulseAmount = 0.35f + 0.65f * progress;
                _pulsePhase += delta * (7f + 26f * progress);
                if (node.OverchargeArmed) armed = 1f;
            }
            else if (node.State == NodeState.Disabled)
            {
                ring = UPalette.Hdr(UPalette.NeutralBase, 0.5f);
                intensity = 0.30f;
                sweep = Mathf.Repeat(Time.time * 0.25f, 1f);
            }
            else if (node.State == NodeState.CaptureLocked)
            {
                intensity *= 0.85f;
            }

            if (_flash > 0f) _flash = Mathf.Max(0f, _flash - delta * 3.0f);

            _block.SetColor(RingColor, ring);
            _block.SetFloat(Intensity, intensity);
            _block.SetFloat(PulseAmount, pulseAmount);
            _block.SetFloat(PulsePhase, _pulsePhase);
            _block.SetFloat(Armed, armed);
            _block.SetFloat(Sweep, sweep);
            _block.SetFloat(Flash, _flash * _flash);
            _block.SetFloat(BaseIntensity, baseIntensity);
            _renderer.SetPropertyBlock(_block);

            float s = 1f + _flash * 0.18f;
            transform.localScale = new Vector3(s, s, 1f);
        }
    }
}
