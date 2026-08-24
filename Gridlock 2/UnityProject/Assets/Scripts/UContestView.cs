using UnityEngine;
using Gridlock.Core;

namespace Gridlock.View
{
    /// <summary>
    /// Sparks at a contest's contact point, thrown PERPENDICULAR to the wire in
    /// both directions at a rate set by min(powerPlayer, powerAi) -- an even
    /// grind throws a shower, a one-sided rout barely sputters (spec 8.5). The
    /// white-hot core and the shoving colour boundary come from the wire shader;
    /// this adds the debris and the reinforcement kick.
    /// </summary>
    public class UContestView : MonoBehaviour
    {
        private ParticleSystem _up;
        private ParticleSystem _down;
        private int _wireId;
        private float _kick;

        public void Setup(Wire wire, Material sparkMaterial)
        {
            _wireId = wire.Id;
            _up = MakeEmitter("sparksUp", sparkMaterial);
            _down = MakeEmitter("sparksDown", sparkMaterial);
            gameObject.SetActive(false);
        }

        private ParticleSystem MakeEmitter(string name, Material material)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            var ps = go.AddComponent<ParticleSystem>();

            ParticleSystem.MainModule main = ps.main;
            main.startLifetime = 0.42f;
            main.startSpeed = new ParticleSystem.MinMaxCurve(0.9f, 2.6f);
            main.startSize = new ParticleSystem.MinMaxCurve(0.05f, 0.14f);
            // Above 1.0 so the sparks bloom like everything else on the board.
            main.startColor = new Color(3.2f, 3.2f, 3.4f, 1f);
            main.gravityModifier = 0f;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.maxParticles = 128;
            main.playOnAwake = false;

            ParticleSystem.EmissionModule emission = ps.emission;
            emission.rateOverTime = 0f;

            ParticleSystem.ShapeModule shape = ps.shape;
            shape.shapeType = ParticleSystemShapeType.Cone;
            shape.angle = 22f;
            shape.radius = 0.01f;

            var renderer = go.GetComponent<ParticleSystemRenderer>();
            renderer.material = material;
            renderer.renderMode = ParticleSystemRenderMode.Billboard;
            renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            return ps;
        }

        /// <summary>A big reinforcement lands: kick the sparks for a moment.</summary>
        public void NotifyReinforced() => _kick = 1f;

        public void UpdateFrom(UGameController game, Wire wire, float delta)
        {
            Contest contest = null;
            foreach (Contest c in game.Sim.Contests)
            {
                if (c.WireId == _wireId) { contest = c; break; }
            }

            if (contest == null)
            {
                if (gameObject.activeSelf)
                {
                    SetRate(_up, 0f);
                    SetRate(_down, 0f);
                    gameObject.SetActive(false);
                }
                _kick = 0f;
                return;
            }

            float t = game.ContactT(contest);
            Vector2 here = UBoardTransform.ToWorld(wire.PositionAt(t));
            // Tangent from a short step along the wire, so the spray stays
            // perpendicular even where the wire turns.
            const float step = 0.01f;
            Vector2 ahead = UBoardTransform.ToWorld(wire.PositionAt(Mathf.Min(1f, t + step)));
            Vector2 behind = UBoardTransform.ToWorld(wire.PositionAt(Mathf.Max(0f, t - step)));
            Vector2 tangent = ahead - behind;
            if (tangent.sqrMagnitude < 1e-6f) tangent = Vector2.right;
            tangent.Normalize();
            var normal = new Vector2(-tangent.y, tangent.x);

            if (!gameObject.activeSelf) gameObject.SetActive(true);
            transform.position = new Vector3(here.x, here.y, 0f);

            if (_kick > 0f) _kick = Mathf.Max(0f, _kick - delta * 2.2f);

            float heat = Mathf.Min(contest.PowerPlayer, contest.PowerAi);
            float rate = Mathf.Clamp(heat / 14f, 0.06f, 1f) * (1f + _kick) * 220f;

            Aim(_up, normal, rate);
            Aim(_down, -normal, rate);
        }

        private static void Aim(ParticleSystem ps, Vector2 dir, float rate)
        {
            // A cone emits along its local +Z, so point +Z at the wire normal.
            ps.transform.rotation = Quaternion.LookRotation(new Vector3(dir.x, dir.y, 0f), Vector3.forward);
            SetRate(ps, rate);
            if (!ps.isPlaying) ps.Play();
        }

        private static void SetRate(ParticleSystem ps, float rate)
        {
            ParticleSystem.EmissionModule emission = ps.emission;
            emission.rateOverTime = rate;
        }
    }
}
