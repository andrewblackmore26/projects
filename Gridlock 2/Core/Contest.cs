using Gridlock.Core.Config;

namespace Gridlock.Core
{
    /// <summary>
    /// A tug-of-war on a wire where opposing beams met (spec §5.6). Lanchester-
    /// style mutual attrition: each side burns the other proportionally to its
    /// own power; the contact point shoves toward the weaker side.
    ///
    /// Invariants: at most one contest per wire, and the two sides always travel
    /// in opposite directions (DirAi == -DirPlayer — same-direction opposing
    /// contact is a chase clash, resolved instantly, never a contest).
    ///
    /// The single-contest invariant is what makes this two-sided type sufficient,
    /// and it holds because NO pair of beams on a wire can pass through each
    /// other: opposing beams contest or clash, same-owner same-direction beams
    /// merge, and same-owner opposite-direction beams net out. Allowing any of
    /// them through would permit two disjoint fronts on one wire, and the wedge
    /// between two fronts belongs to a single owner pushing BOTH ways — which
    /// this type structurally cannot express.
    /// </summary>
    public class Contest
    {
        public int Id;
        public int WireId;

        /// <summary>Front position in wire t-space, 0..1.</summary>
        public float ContactT;

        /// <summary>Front position at the previous tick (presentation interpolation).</summary>
        public float PrevContactT;

        public float PowerPlayer;
        public float PowerAi;

        /// <summary>Travel direction the player-side beam had (+1 = A→B). AI side is the negation.</summary>
        public int DirPlayer;

        /// <summary>Speeds each side entered with — the survivor resumes at its own speed.</summary>
        public float SpeedPlayer;
        public float SpeedAi;

        public int DirAi => -DirPlayer;

        public float PowerOf(Owner side) => side == Owner.Player ? PowerPlayer : PowerAi;

        /// <summary>
        /// One tick of burn and push, exactly per spec §5.6: burns computed from
        /// PRE-tick values, subtracted, then push computed from the POST-burn
        /// values. Push moves contactT in the player's travel direction when the
        /// player is stronger. ContactT is left UNCLAMPED — the caller tests
        /// boundary crossing against the raw value (endpoint arrival requires the
        /// front to have MOVED into the boundary, not merely to sit on it), then
        /// clamps. PrevContactT keeps the pre-move value.
        /// </summary>
        public void StepBurnAndPush(Tuning tuning, float dt)
        {
            float burnP = PowerAi * tuning.ContestBurnRate * dt;
            float burnA = PowerPlayer * tuning.ContestBurnRate * dt;
            PowerPlayer -= burnP;
            PowerAi -= burnA;

            PrevContactT = ContactT;
            float sum = PowerPlayer + PowerAi;
            if (sum > 0f)
            {
                float push = (PowerPlayer - PowerAi) / sum;
                ContactT += push * tuning.ContestPushSpeed * dt * DirPlayer;
            }
        }

        public void ClampContact()
        {
            if (ContactT < 0f) ContactT = 0f;
            else if (ContactT > 1f) ContactT = 1f;
        }
    }
}
