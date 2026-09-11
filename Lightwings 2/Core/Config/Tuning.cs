using System;
using System.Globalization;
using System.Reflection;

namespace Lightship.Core.Config
{
    /// <summary>
    /// Every number the spec marks (tune), in one place, with its unit. Public
    /// fields so the headless CLI can override any of them by name
    /// (--set Field=Value) and print the knob it turned.
    /// </summary>
    public sealed class Tuning
    {
        // ---- time ----
        public int TickRate = 60;                         // ticks per second
        public float Dt => 1f / TickRate;                 // seconds per tick

        // ---- energy and tiers (spec 5) ----
        public float[] EnergyThresholds = { 100f, 300f, 700f, 1500f }; // energy to reach tier 2..5
        public int ReshapeTicks = 48;                     // ticks (0.8 s) the reshape tween runs, invulnerable
        public float ZoomPerTier = 0.9f;                  // camera zoom multiplier per tier above 1 (<= 10 %/tier)

        // ---- HP (spec 9) ----
        public float HpBase = 100f;                       // HP at tier 1
        public float HpPerTier = 25f;                     // HP added per tier
        public int RegenDelayTicks = 180;                 // ticks without damage before regen (3 s)
        public float RegenFractionPerSecond = 0.10f;      // fraction of max HP regenerated per second
        public float ContactDamagePerSecond = 15f;        // HP/s while an enemy body overlaps the player core

        // ---- pickups (spec 6) ----
        public float[] PickupValues = { 1f, 5f, 20f };    // energy per pickup size 0/1/2
        public float[] MagnetRadiusByTier = { 60f, 80f, 105f, 130f, 160f }; // world units, by tier
        public float AbsorbRadius = 4f;                   // world units beyond the core radius at which a pickup is absorbed
        public float ReshapeMagnetMultiplier = 3f;        // magnet radius multiplier during the reshape
        public float PickupDriftSpeed = 14f;              // world units per second, slow drift
        public int PickupTtlTicks = 60 * 40;              // ticks before an unabsorbed pickup fades
        public float SectorLightPool = 200f;              // energy a sector can shed as ambient light before it is empty
        public float SectorLightRegenPerSecond = 0.2f;    // energy per second the pool regenerates
        public int AmbientLightCap = 12;                  // max ambient pickups alive at once
        public int AmbientSpawnIntervalTicks = 90;        // ticks between ambient pickup spawns
        public int HitShedCooldownTicks = 6;              // ticks between lights shed by one enemy being hit
        public float DamageShedsLightFraction = 0f;       // fraction of damage taken by the PLAYER shed as light (open decision 1; 0 = HP only)

        // ---- rewards (spec 8) ----
        public float RewardGapFactor = 1.5f;              // energy multiplier per enemy tier above the player

        // ---- player (spec 9, 17) ----
        public float CoreRadiusPx = 3f;                   // screen px; the hitbox is this over the camera zoom
        public float PlayerSpeed = 260f;                  // world units per second
        public float PlayerBulletSpeed = 520f;            // world units per second
        public int PlayerFireIntervalTicks = 15;          // ticks between player shots (4/s)
        public float PlayerBulletDamage = 10f;            // HP per player bullet
        public float PlayerBulletRadius = 2.5f;           // world units
        public int PlayerBulletTtlTicks = 72;             // ticks a player bullet lives

        // ---- enemies (spec 8) ----
        public int EnemySpawnIntervalTicks = 360;         // ticks between enemy spawns while below MaxEnemies
        public int MaxEnemies = 4;                        // enemies alive at once (M1 arena)
        public float EnemyT1Hp = 40f;                     // HP of a tier-1 regular enemy
        public float EnemyHpPerTier = 30f;                // HP added per enemy tier
        public float EnemySpeed = 140f;                   // world units per second
        public float EnemyPreferredRange = 220f;          // world units an enemy tries to hold from the player

        // ---- visual system (spec 11, Appendix B) ----
        public float LightFraction = 0.13f;               // fraction of a part's perimeter that is lit
        public float BreathPeriod = 2.0f;                 // seconds per breath (corruption)
        public float BreathAmplitude = 0.05f;             // scale 1.00 -> 1.05 -> 1.00
        public int MinVisibleEventTicks = 15;             // ticks (0.25 s) any hit/absorb stays drawn

        // ---- arena ----
        public float ArenaWidth = 2400f;                  // world units
        public float ArenaHeight = 1350f;                 // world units
        public float HashCell = 64f;                      // world units per spatial-hash cell
        public int BulletCapacity = 4096;                 // bullet pool size (budget is 2000 live)
        public int PickupCapacity = 1024;                 // pickup pool size

        public float ThresholdForTier(int tier)
        {
            // Energy needed to evolve OUT of the given tier (tier 1 -> thresholds[0]).
            if (tier < 1 || tier > EnergyThresholds.Length) return float.PositiveInfinity;
            return EnergyThresholds[tier - 1];
        }

        public float ZoomForTier(int tier) => MathF.Pow(ZoomPerTier, Math.Max(0, tier - 1));

        public float MagnetRadius(int tier)
        {
            int i = Math.Clamp(tier - 1, 0, MagnetRadiusByTier.Length - 1);
            return MagnetRadiusByTier[i];
        }

        /// <summary>
        /// Override one public field by name from a string ("--set Field=Value").
        /// Returns false when the field does not exist or has an unsupported type.
        /// </summary>
        public bool TrySet(string field, string value)
        {
            FieldInfo f = GetType().GetField(field, BindingFlags.Public | BindingFlags.Instance);
            if (f == null) return false;
            var inv = CultureInfo.InvariantCulture;
            if (f.FieldType == typeof(float)) f.SetValue(this, float.Parse(value, inv));
            else if (f.FieldType == typeof(int)) f.SetValue(this, int.Parse(value, inv));
            else if (f.FieldType == typeof(bool)) f.SetValue(this, bool.Parse(value));
            else return false;
            return true;
        }
    }
}
