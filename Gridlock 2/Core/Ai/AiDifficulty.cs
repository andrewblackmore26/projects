namespace Gridlock.Core.Ai
{
    /// <summary>
    /// One AI difficulty tier (spec §9.4). Difficulty comes from constraints on
    /// ACTING, never on knowing or earning: the AI sees exactly what the player
    /// sees and obeys the same economy. DecisionInterval is the primary lever —
    /// it reads as reaction speed ("sharper"), not as cheating.
    /// </summary>
    public class AiDifficulty
    {
        public int Tier;

        /// <summary>Seconds between decisions (jittered ±20% per decision).</summary>
        public float DecisionInterval;

        /// <summary>Multiplicative score noise: score × (1 + U(−noise, +noise)).</summary>
        public float NoiseFactor;

        /// <summary>Best candidate must exceed this score to act (banking charge is a valid move).</summary>
        public float ActionThreshold;

        public bool BurstEnabled;
        public bool ThreatResponse;
        public bool Anticipate;

        /// <summary>The spec §9.4 tier table, tiers 1..10. Out-of-range clamps.</summary>
        public static AiDifficulty FromTier(int tier)
        {
            if (tier < 1) tier = 1;
            if (tier > 10) tier = 10;
            float[] interval = { 3.0f, 2.5f, 2.2f, 1.8f, 1.5f, 1.2f, 1.0f, 0.85f, 0.7f, 0.6f };
            float[] noise = { 0.50f, 0.40f, 0.35f, 0.28f, 0.22f, 0.18f, 0.14f, 0.10f, 0.07f, 0.05f };
            float[] threshold = { 8f, 7f, 6f, 6f, 5f, 5f, 4f, 4f, 3f, 3f };
            int i = tier - 1;
            return new AiDifficulty
            {
                Tier = tier,
                DecisionInterval = interval[i],
                NoiseFactor = noise[i],
                ActionThreshold = threshold[i],
                BurstEnabled = tier >= 4,
                ThreatResponse = tier >= 3,
                Anticipate = tier >= 6,
            };
        }
    }
}
