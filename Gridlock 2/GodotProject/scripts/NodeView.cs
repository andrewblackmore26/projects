using System;
using Godot;
using Gridlock.Core;
using Gridlock.Core.Config;
// See WireView: Node.Owner would otherwise shadow the simulation's Owner enum.
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// One node: a hex outline whose brightness reads as stored charge, plus the
    /// state tells (spec section 8.6). Overcharging is deliberately loud -- the
    /// opponent is meant to see a node winding up, because that visibility is
    /// what makes feinting a real tactic.
    /// </summary>
    public partial class NodeView : MeshInstance2D
    {
        // Fraction of the hex circumradius. Kept generous, and the ring kept
        // THIN: a thick bright ring blooms inward and fills its own hole, and a
        // node that reads as a glowing disc has lost the hex silhouette that
        // shows its six faces.
        private const float RingRadius = 0.66f;

        private int _nodeId;
        private ShaderMaterial _mat;
        private float _pulsePhase;
        private float _flash;
        private float _initialNeutralDefense;

        public void Setup(GameNode node, BoardTransform transform, Shader shader, Tuning tuning)
        {
            _nodeId = node.Id;
            _initialNeutralDefense = Mathf.Max(node.NeutralDefense, 0.0001f);

            Vec2 centre = HexMath.HexToPixel(node.Coord);
            Vector2 screenCentre = transform.ToScreen(centre);
            // Mesh is built in LOCAL space around the node so the capture flash
            // can scale the ring about its own centre.
            var pts = new Vector2[6];
            for (int i = 0; i < 6; i++)
            {
                Vec2 corner = HexMath.CellCorner(node.Coord, i);
                var scaled = new Vec2(
                    centre.X + (corner.X - centre.X) * RingRadius,
                    centre.Y + (corner.Y - centre.Y) * RingRadius);
                pts[i] = transform.ToScreen(scaled) - screenCentre;
            }

            float halfWidth = Mathf.Clamp(transform.Scale * 0.032f, 2.0f, 3.6f);
            Mesh = Ribbon.Build(pts, halfWidth, closed: true);

            _mat = new ShaderMaterial { Shader = shader };
            _mat.SetShaderParameter("core_uv", Mathf.Clamp(1.5f / (2f * halfWidth), 0.1f, 0.5f));
            Material = _mat;
            ZIndex = 2;

            Position = screenCentre;
            // Stubs on each wired face let a neutral node's degree be read at a
            // glance while its wires are still unlit grey.
            if (node.Owner == CoreOwner.Neutral) BuildFaceStubs(node, transform, shader, halfWidth, screenCentre);
        }

        private void BuildFaceStubs(GameNode node, BoardTransform transform, Shader shader, float halfWidth, Vector2 screenCentre)
        {
            Vec2 centre = HexMath.HexToPixel(node.Coord);
            for (int face = 0; face < 6; face++)
            {
                if (node.WireIdByFace[face] < 0) continue;
                HexMath.FaceEdge(node.Coord, face, out VertexCoord va, out VertexCoord vb);
                Vec2 pa = va.ToPixel(), pb = vb.ToPixel();
                var mid = new Vec2((pa.X + pb.X) * 0.5f, (pa.Y + pb.Y) * 0.5f);
                var inner = new Vec2(
                    centre.X + (mid.X - centre.X) * (RingRadius + 0.06f),
                    centre.Y + (mid.Y - centre.Y) * (RingRadius + 0.06f));

                var stub = new MeshInstance2D
                {
                    Mesh = Ribbon.Build(
                        new[] { transform.ToScreen(inner) - screenCentre, transform.ToScreen(mid) - screenCentre },
                        halfWidth * 0.8f, closed: false),
                    ZIndex = 1,
                };
                var stubMat = new ShaderMaterial { Shader = shader };
                stubMat.SetShaderParameter("core_uv", 0.3f);
                stubMat.SetShaderParameter("ring_color", Palette.Hdr(Palette.NeutralBase, Palette.NeutralEmission));
                stubMat.SetShaderParameter("intensity", 0.9f);
                stub.Material = stubMat;
                AddChild(stub);
            }
        }

        public void NotifyCaptured() => _flash = 1f;

        public void UpdateFrom(GameController game, float delta, float baseIntensity)
        {
            GameNode node = game.Sim.NodeById(_nodeId);
            Tuning tuning = game.Tuning;

            Color ring;
            float intensity;
            if (node.Owner == CoreOwner.Neutral)
            {
                ring = Palette.Hdr(Palette.NeutralBase, Palette.NeutralEmission);
                // Dims as the toll is chipped away, so a softened hub is visible
                // before anyone commits to taking it.
                float remaining = Mathf.Clamp(node.NeutralDefense / _initialNeutralDefense, 0f, 1f);
                intensity = 0.45f + 0.55f * remaining;
            }
            else
            {
                ring = Palette.Hdr(Palette.OwnerColor(node.Owner), Palette.OwnerEmission);
                float max = Mathf.Max(node.MaxCharge(tuning), 0.0001f);
                // Reads as "how full is this node" across the whole range while
                // staying under the level where the glow closes the hex up.
                intensity = 0.28f + 0.46f * Mathf.Clamp(node.Charge / max, 0f, 1f);
            }

            float pulseAmount = 0f;
            float armed = 0f;
            float sweep = -1f;

            switch (node.State)
            {
                case NodeState.Overcharging:
                {
                    float progress = node.OverchargeProgress(game.Sim.Tick, tuning);
                    // Charging is loud on purpose (design pillar 3): this is the
                    // one state allowed to bloom hard, because the opponent
                    // seeing it is the whole point.
                    intensity += 1.3f * progress;
                    pulseAmount = 0.35f + 0.65f * progress;
                    _pulsePhase += delta * (7f + 26f * progress);
                    if (node.OverchargeArmed) armed = 1f;
                    break;
                }
                case NodeState.Disabled:
                    ring = Palette.Hdr(Palette.NeutralBase, 0.5f);
                    intensity = 0.30f;
                    sweep = Mathf.PosMod(Time.GetTicksMsec() / 1000f * 0.25f, 1f);
                    break;
                case NodeState.CaptureLocked:
                    intensity *= 0.85f;
                    break;
            }

            if (_flash > 0f) _flash = Mathf.Max(0f, _flash - delta * 3.0f);

            _mat.SetShaderParameter("ring_color", ring);
            _mat.SetShaderParameter("intensity", intensity);
            _mat.SetShaderParameter("pulse_amount", pulseAmount);
            _mat.SetShaderParameter("pulse_phase", _pulsePhase);
            _mat.SetShaderParameter("armed", armed);
            _mat.SetShaderParameter("sweep", sweep);
            _mat.SetShaderParameter("flash", _flash * _flash);
            _mat.SetShaderParameter("base_intensity", baseIntensity);

            // The capture flash also kicks the ring outward briefly.
            float s = 1f + _flash * 0.18f;
            Scale = new Vector2(s, s);
        }
    }
}
