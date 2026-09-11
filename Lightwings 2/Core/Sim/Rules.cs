using System;
using System.Collections.Generic;
using Lightship.Core.Config;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim
{
    /// <summary>Spec 9 HP rules as pure functions.</summary>
    public static class Health
    {
        public static float MaxHp(int tier, Tuning t) => t.HpBase + t.HpPerTier * (tier - 1);

        /// <summary>Regenerates 10 % of max per second once 3 s have passed without damage.</summary>
        public static float Regen(float hp, float maxHp, long tick, long lastDamageTick, Tuning t)
        {
            if (tick - lastDamageTick < t.RegenDelayTicks) return hp;
            return MathF.Min(maxHp, hp + t.RegenFractionPerSecond * maxHp * t.Dt);
        }
    }

    /// <summary>Spec 8 rewards: energy scales by the tier gap when the target is above the player.</summary>
    public static class Rewards
    {
        public static float Scale(int enemyTier, int playerTier, float factor) =>
            MathF.Pow(factor, Math.Max(0, enemyTier - playerTier));

        /// <summary>Base energy an enemy of a tier drops when destroyed (tune).</summary>
        public static float DropEnergy(int enemyTier) => 17f + 13f * (enemyTier - 1);

        /// <summary>Which tier the player holds for a given energy total.</summary>
        public static int TierForEnergy(float energy, Tuning t)
        {
            int tier = 1;
            for (int i = 0; i < t.EnergyThresholds.Length; i++)
                if (energy >= t.EnergyThresholds[i]) tier = i + 2;
            return Math.Min(tier, 5);
        }
    }

    public sealed class EvolveOffer
    {
        public readonly List<ShipDefinition> Options = new List<ShipDefinition>();
        public int Count => Options.Count;
    }

    /// <summary>Spec 5: which forms an evolution offers, from what was absorbed since the last one.</summary>
    public static class Evolution
    {
        public static EvolveOffer ComputeOffer(Element root, int tier, float[] absorbed, IReadOnlyList<Element> unlocked, ShipCatalog catalog)
        {
            var offer = new EvolveOffer();
            if (tier >= 5) return offer;
            int next = tier + 1;

            // Candidates: unlocked elements that have an authored next tier.
            var candidates = new List<Element>();
            foreach (Element e in unlocked)
                if (e != Element.None && catalog.Find(e, next) != null && !candidates.Contains(e)) candidates.Add(e);
            if (candidates.Count == 0) return offer;

            // Rank by absorbed light, ties to the current root, then enum order.
            candidates.Sort((a, b) =>
            {
                float fa = absorbed[(int)a], fb = absorbed[(int)b];
                if (fa != fb) return fb.CompareTo(fa);
                if (a == root) return -1;
                if (b == root) return 1;
                return ((int)a).CompareTo((int)b);
            });

            var picked = new List<Element>();
            int limit = tier == 1 ? 3 : 2;
            foreach (Element e in candidates)
                if (absorbed[(int)e] > 0f && picked.Count < limit) picked.Add(e);

            if (tier >= 2 && picked.Count == 1 && picked[0] != root && candidates.Contains(root)) picked.Add(root);
            if (picked.Count == 0)
            {
                if (candidates.Contains(root)) picked.Add(root);
                else picked.Add(candidates[0]);
            }

            foreach (Element e in picked) offer.Options.Add(catalog.Find(e, next));
            return offer;
        }
    }
}
