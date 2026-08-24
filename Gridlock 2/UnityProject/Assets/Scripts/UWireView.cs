using System.Collections.Generic;
using UnityEngine;
using Gridlock.Core;
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// One wire: a ribbon mesh built once, then driven entirely through a
    /// MaterialPropertyBlock (spec sections 8.4 and 11). Beams are bright beads
    /// at uniform positions and the contest front is the colour boundary --
    /// nothing moves a transform, so the board stays cheap and the motion is
    /// exact at any framerate.
    /// </summary>
    public class UWireView : MonoBehaviour
    {
        private const int MaxPulses = 8;

        private static readonly int OwnerColorA = Shader.PropertyToID("_OwnerColorA");
        private static readonly int OwnerColorB = Shader.PropertyToID("_OwnerColorB");
        private static readonly int BoundaryT = Shader.PropertyToID("_BoundaryT");
        private static readonly int BaseIntensity = Shader.PropertyToID("_BaseIntensity");
        private static readonly int CoreUv = Shader.PropertyToID("_CoreUv");
        private static readonly int ContestActive = Shader.PropertyToID("_ContestActive");
        private static readonly int ContestColor = Shader.PropertyToID("_ContestColor");
        private static readonly int ContestHeat = Shader.PropertyToID("_ContestHeat");
        private static readonly int PulseCount = Shader.PropertyToID("_PulseCount");
        private static readonly int PulsePos = Shader.PropertyToID("_PulsePos");
        private static readonly int PulseSize = Shader.PropertyToID("_PulseSize");
        private static readonly int PulseColor = Shader.PropertyToID("_PulseColor");

        private Wire _wire;
        private MeshRenderer _renderer;
        private MaterialPropertyBlock _block;
        private float _lengthWorld;
        private float _worldPerPixel;

        private readonly float[] _pulsePos = new float[MaxPulses];
        private readonly float[] _pulseSize = new float[MaxPulses];
        private readonly Vector4[] _pulseColor = new Vector4[MaxPulses];
        private readonly List<Beam> _onWire = new List<Beam>();

        public void Setup(Wire wire, UBoardTransform layout, Material material)
        {
            _wire = wire;

            var pts = new List<Vector2>(wire.PixelPath.Length);
            foreach (Vec2 p in wire.PixelPath) pts.Add(UBoardTransform.ToWorld(p));

            _lengthWorld = 0f;
            for (int i = 1; i < pts.Count; i++) _lengthWorld += Vector2.Distance(pts[i - 1], pts[i]);

            // Wide enough in PIXELS that the resolved pixel reaches the HDR value
            // the shader writes: a sub-pixel emissive ribbon cannot bloom.
            float halfWidthPx = 4.0f;
            _worldPerPixel = layout.WorldPerPixel;
            float halfWidth = halfWidthPx * _worldPerPixel;

            var filter = gameObject.AddComponent<MeshFilter>();
            filter.mesh = URibbon.Build(pts, halfWidth, false);
            _renderer = gameObject.AddComponent<MeshRenderer>();
            _renderer.sharedMaterial = material;
            _renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            _renderer.receiveShadows = false;

            _block = new MaterialPropertyBlock();
            _block.SetFloat(CoreUv, Mathf.Clamp(1.5f / (2f * halfWidthPx), 0.08f, 0.45f));
            _block.SetColor(ContestColor, UPalette.Hdr(UPalette.ContestWhite, UPalette.ContestEmission));
            _renderer.SetPropertyBlock(_block);
        }

        public void UpdateFrom(UGameController game, float baseIntensity)
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
                boundary = game.ContactT(contest);
                CoreOwner sideFromA = contest.DirPlayer > 0 ? CoreOwner.Player : CoreOwner.Ai;
                CoreOwner sideFromB = sideFromA == CoreOwner.Player ? CoreOwner.Ai : CoreOwner.Player;
                colorA = UPalette.Hdr(UPalette.OwnerColor(sideFromA), UPalette.OwnerEmission * 0.8f);
                colorB = UPalette.Hdr(UPalette.OwnerColor(sideFromB), UPalette.OwnerEmission * 0.8f);
                float heat = Mathf.Min(contest.PowerPlayer, contest.PowerAi);
                _block.SetFloat(ContestActive, 1f);
                _block.SetFloat(ContestHeat, Mathf.Clamp(heat / 12f, 0.3f, 3f));
            }
            else
            {
                boundary = 0.5f;
                colorA = UPalette.WireEndColor(ownerA);
                colorB = UPalette.WireEndColor(ownerB);
                _block.SetFloat(ContestActive, 0f);
            }

            _block.SetFloat(BoundaryT, boundary);
            _block.SetColor(OwnerColorA, colorA);
            _block.SetColor(OwnerColorB, colorB);
            _block.SetFloat(BaseIntensity, baseIntensity);

            _onWire.Clear();
            foreach (Beam b in sim.Beams)
            {
                if (b.WireId == _wire.Id) _onWire.Add(b);
            }
            _onWire.Sort((x, y) => y.Power.CompareTo(x.Power));

            int count = Mathf.Min(_onWire.Count, MaxPulses);
            // A bead reads at a roughly fixed on-screen size, so convert the
            // pixel length into wire-t through the world scale.
            float beadT = _lengthWorld > 0f
                ? Mathf.Clamp(22f * _worldPerPixel / _lengthWorld, 0.012f, 0.30f)
                : 0.05f;
            for (int i = 0; i < count; i++)
            {
                Beam b = _onWire[i];
                _pulsePos[i] = game.BeamT(b);
                _pulseSize[i] = beadT;
                float weight = Mathf.Clamp(0.55f + b.Power / 22f, 0.55f, 2.4f);
                _pulseColor[i] = UPalette.Hdr(UPalette.OwnerColor(b.Owner), UPalette.OwnerEmission * weight);
            }
            for (int i = count; i < MaxPulses; i++)
            {
                _pulsePos[i] = -1f;
                _pulseSize[i] = 0.01f;
                _pulseColor[i] = Vector4.zero;
            }

            // SetInteger, not the deprecated SetInt: in Unity 6 SetInt uploads a
            // float and the shader's int parameter reads garbage.
            _block.SetInteger(PulseCount, count);
            _block.SetFloatArray(PulsePos, _pulsePos);
            _block.SetFloatArray(PulseSize, _pulseSize);
            _block.SetVectorArray(PulseColor, _pulseColor);
            _renderer.SetPropertyBlock(_block);
        }
    }
}
