using System;
using System.Collections.Generic;
using Godot;
using Gridlock.Core;
// Godot's Node has its own Owner property, which would shadow the simulation's
// Owner enum inside every Node-derived view. Alias it once, explicitly.
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// One wire: a ribbon mesh built once, then driven entirely through shader
    /// uniforms (spec section 8.4). Beams are bright beads at uniform positions,
    /// the contest front is the colour boundary -- nothing here moves a sprite,
    /// so a board of forty wires stays a handful of draw calls.
    /// </summary>
    public partial class WireView : MeshInstance2D
    {
        private const int MaxPulses = 8;

        private Wire _wire;
        private ShaderMaterial _mat;
        private float _lengthPx;

        private readonly float[] _pulsePos = new float[MaxPulses];
        private readonly float[] _pulseSize = new float[MaxPulses];
        private readonly Color[] _pulseColor = new Color[MaxPulses];
        private readonly List<Beam> _onWire = new List<Beam>();

        public void Setup(Wire wire, BoardTransform transform, Shader shader)
        {
            _wire = wire;
            var pts = new Vector2[wire.PixelPath.Length];
            for (int i = 0; i < pts.Length; i++) pts[i] = transform.ToScreen(wire.PixelPath[i]);

            _lengthPx = 0f;
            for (int i = 1; i < pts.Length; i++) _lengthPx += pts[i - 1].DistanceTo(pts[i]);

            // Wide enough that the resolved pixel actually reaches the HDR value
            // the shader writes: a sub-pixel emissive ribbon cannot bloom.
            float halfWidth = Mathf.Clamp(transform.Scale * 0.055f, 3.0f, 6.0f);
            Mesh = Ribbon.Build(pts, halfWidth, closed: false);

            _mat = new ShaderMaterial { Shader = shader };
            // Keep the crisp core near 1.5 px however wide the ribbon is drawn.
            _mat.SetShaderParameter("core_uv", Mathf.Clamp(1.5f / (2f * halfWidth), 0.08f, 0.45f));
            _mat.SetShaderParameter("contest_color", Palette.Hdr(Palette.ContestWhite, Palette.ContestEmission));
            Material = _mat;
            ZIndex = 0;
        }

        public void UpdateFrom(GameController game, float baseIntensity)
        {
            Simulation sim = game.Sim;
            CoreOwner ownerA = sim.NodeById(_wire.NodeA).Owner;
            CoreOwner ownerB = sim.NodeById(_wire.NodeB).Owner;

            Contest contest = null;
            foreach (Contest c in sim.Contests)
            {
                if (c.WireId == _wire.Id) { contest = c; break; }
            }

            float boundary;
            Color colorA, colorB;
            if (contest != null)
            {
                // The colour split IS the front: it snaps to the contact point
                // and visibly shoves back and forth (spec section 8.5).
                boundary = game.ContactT(contest);
                CoreOwner sideFromA = contest.DirPlayer > 0 ? CoreOwner.Player : CoreOwner.Ai;
                CoreOwner sideFromB = sideFromA == CoreOwner.Player ? CoreOwner.Ai : CoreOwner.Player;
                colorA = Palette.Hdr(Palette.OwnerColor(sideFromA), Palette.OwnerEmission * 0.8f);
                colorB = Palette.Hdr(Palette.OwnerColor(sideFromB), Palette.OwnerEmission * 0.8f);
                float heat = Mathf.Min(contest.PowerPlayer, contest.PowerAi);
                _mat.SetShaderParameter("contest_active", 1.0f);
                _mat.SetShaderParameter("contest_heat", Mathf.Clamp(heat / 12f, 0.3f, 3.0f));
            }
            else
            {
                boundary = 0.5f;
                colorA = Palette.WireEndColor(ownerA);
                colorB = Palette.WireEndColor(ownerB);
                _mat.SetShaderParameter("contest_active", 0.0f);
            }

            _mat.SetShaderParameter("boundary_t", boundary);
            _mat.SetShaderParameter("owner_color_a", colorA);
            _mat.SetShaderParameter("owner_color_b", colorB);
            _mat.SetShaderParameter("base_intensity", baseIntensity);

            _onWire.Clear();
            foreach (Beam b in sim.Beams)
            {
                if (b.WireId == _wire.Id) _onWire.Add(b);
            }
            // Heaviest first, so if a wire is crowded the beads that matter win
            // the eight slots.
            _onWire.Sort((x, y) => y.Power.CompareTo(x.Power));

            int count = Math.Min(_onWire.Count, MaxPulses);
            float beadT = _lengthPx > 0f ? Mathf.Clamp(22f / _lengthPx, 0.012f, 0.30f) : 0.05f;
            for (int i = 0; i < count; i++)
            {
                Beam b = _onWire[i];
                _pulsePos[i] = game.BeamT(b);
                _pulseSize[i] = beadT;
                float weight = Mathf.Clamp(0.55f + b.Power / 22f, 0.55f, 2.4f);
                _pulseColor[i] = Palette.Hdr(Palette.OwnerColor(b.Owner), Palette.OwnerEmission * weight);
            }
            for (int i = count; i < MaxPulses; i++)
            {
                _pulsePos[i] = -1f;
                _pulseSize[i] = 0.01f;
                _pulseColor[i] = new Color(0, 0, 0, 0);
            }

            _mat.SetShaderParameter("pulse_count", count);
            _mat.SetShaderParameter("pulse_pos", _pulsePos);
            _mat.SetShaderParameter("pulse_size", _pulseSize);
            _mat.SetShaderParameter("pulse_color", _pulseColor);
        }
    }
}
