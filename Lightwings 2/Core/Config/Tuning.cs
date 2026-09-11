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
        public int TerritoryAmbientIntervalTicks = 30;    // ticks between ambient spawns in player territory, quiet land where a
                                                          // new life regrows (grazing is flight-limited to ~1 pickup per 1.5 s)
        public int TerritoryAmbientSize = 1;              // pickup size there (1 = 5 energy): ~3 energy/s grazed, from a pool of
                                                          // SectorLightPool per sector per life, so it cannot be farmed forever
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

        // ---- corruption abilities (spec 12) ----
        public int InfectDurationTicks = 180;             // ticks an infection lasts (3 s), refreshed by each infecting hit
        public float InfectDps = 5f;                      // HP per second while infected
        public float SpreadRadius = 150f;                 // world units an infection can jump
        public int SpreadIntervalTicks = 60;              // ticks between jumps from one host
        public int SpreadFirstJumpTicks = 15;             // ticks from infection to the first jump (0.25 s: seen before the host dies)
        public int HatchIntervalTicks = 240;              // ticks between drones from one pod (4 s)
        public float DroneSpeed = 300f;                   // world units per second
        public float DroneHp = 12f;                       // HP
        public float DroneRamDamage = 14f;                // HP dealt when a drone rams a hostile
        public int DroneLifeTicks = 720;                  // ticks before an unused drone fades (12 s)

        // ---- enemies (spec 8) ----
        public int EnemySpawnIntervalTicks = 540;         // ticks between enemy packs while below MaxEnemies
        public int EnemyPackSize = 2;                     // enemies per spawn, arriving together (gives spread a neighbour)
        public float EnemyPackSpacing = 70f;              // world units between pack members
        public int MaxEnemies = 4;                        // enemies alive at once (M1 arena)
        public float EnemyT1Hp = 40f;                     // HP of a tier-1 regular enemy
        public float EnemyHpPerTier = 30f;                // HP added per enemy tier
        public float EnemySpeed = 140f;                   // world units per second
        public float EnemyPreferredRange = 220f;          // world units an enemy tries to hold from the player

        // ---- fire abilities (spec 12) ----
        public int TrailIntervalTicks = 5;                // ticks between burning-trail embers per vent while moving
        public float TrailDamage = 3f;                    // HP per trail ember
        public float TrailRadius = 4f;                    // world units
        public int TrailTtlTicks = 50;                    // ticks a trail ember burns
        public float TrailMinSpeed = 60f;                 // world units per second the ship must be moving to leave a trail
        public float WideConeAngleDeg = 20f;              // degrees each flank spray is turned out from the centre spray

        // ---- world (spec 7) ----
        public float[] VeilThresholds = { 0f, 300f };     // energy to cross outward from layer n to n+1 (index n); 0 = no veil
        public int SectorEnemyBase = 4;                   // regular enemies in a layer-0 sector's budget (layer 0 itself is safe)
        public int SectorEnemyPerLayer = 2;               // regular enemies added per layer
        public float SectorEntryInset = 48f;              // world units inside the opposite edge where a crossing player appears
        public int BorderFlipsPerDeath = 2;               // rival border sectors that may change hands between lives
        public float GateWarnDistance = 420f;             // world units from an edge into an unbeaten gate at which the HUD warns
        public int CrossBlockedCooldownTicks = 45;        // ticks between repeated "cannot cross" events while pushing an edge
        public int CrossDwellTicks = 12;                  // ticks (0.2 s) of pushing into an edge before it crosses (a brush does not)

        // ---- rivals (spec 8) ----
        public float RivalHpMultiplier = 2.5f;            // rival HP = player HP at its tier x this
        public float RivalSpeed = 210f;                   // world units per second (the player is faster: it can chase a retreat)
        public float RivalDropMultiplier = 4f;            // "rival bosses shed a lot": kill drop x this
        public int RivalDelayMinTicks = 9;                // perception delay, ticks (150 ms)
        public int RivalDelayMaxTicks = 18;               // perception delay, ticks (300 ms)
        public float RivalAimErrorMinDeg = 2f;            // aim error magnitude per burst, degrees
        public float RivalAimErrorMaxDeg = 5f;
        public int RivalAimLineTicks = 30;                // ticks (0.5 s) the aim line shows before a burst: spec 9's
                                                          // minimum warning for a cone that cannot be dodged on reaction up close
        public int RivalBurstTicks = 48;                  // ticks a burst holds the trigger
        public int RivalPauseTicks = 30;                  // ticks between bursts
        public float RivalRetreatBelow = 0.35f;           // HP fraction at which a rival retreats to regenerate
        public float RivalRecoverAbove = 0.70f;           // HP fraction at which it comes back
        public float RivalHealPerEnergy = 2f;             // HP a rival regains per energy of light it grabs
        public float RivalPerception = 900f;
        public int RivalGrabMinAgeTicks = 30;             // ticks a pickup must exist before a rival can take it (not its own fresh shed light)              // world units within which a rival picks targets

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
