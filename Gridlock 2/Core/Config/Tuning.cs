using System;

namespace Gridlock.Core.Config
{
    /// <summary>
    /// Every magic number in the game, as MUTABLE INSTANCE FIELDS so a runtime
    /// debug panel can edit them live (spec §6). The Simulation holds a Tuning by
    /// reference and reads it every tick.
    ///
    /// UNIT DISCIPLINE (lessons.md): every field carries its unit in a comment.
    /// When a formula's denominator changes meaning, re-derive — do not reuse.
    /// Durations are authored in SECONDS here; the Simulation converts to integer
    /// tick counts (see the *Ticks properties) and compares ticks, never floats.
    /// </summary>
    public class Tuning
    {
        /// <summary>Fixed simulation rate. Unit: ticks/second.</summary>
        public int TickRate = 60;

        /// <summary>Fixed timestep. Unit: seconds/tick.</summary>
        public float Dt => 1f / TickRate;

        // ---- Economy (spec §5.1–§5.2) ----

        /// <summary>Charge accrual per owned node. Unit: charge/second per degree.</summary>
        public float BaseChargeRate = 1.2f;

        /// <summary>Storage cap. Unit: charge per degree (max = value × degree).</summary>
        public float MaxChargePerDegree = 12.0f;

        /// <summary>Anti-snowball lever. Unit: defense charge per degree; set once at load, never regenerates.</summary>
        public float NeutralDefensePerDegree = 8.0f;

        // ---- Sending (spec §5.3) ----

        /// <summary>Fraction of stored charge sent by an instant tap-release. Unit: dimensionless [0..1].</summary>
        public float MinSendFraction = 0.35f;

        /// <summary>Hold duration to arm a burst. Unit: seconds (compare via OverchargeTicks only).</summary>
        public float OverchargeTime = 1.4f;

        /// <summary>Burst beam speed multiplier. Unit: dimensionless.</summary>
        public float BurstSpeedMultiplier = 2.5f;

        /// <summary>Post-burst disable duration. Unit: seconds (compare via BurstCooldownTicks only).</summary>
        public float BurstCooldown = 5.0f;

        /// <summary>Post-capture send lock. Unit: seconds (compare via CaptureLockTicks only).</summary>
        public float CaptureLockTime = 0.5f;

        /// <summary>Minimum stored charge to begin/complete a send. Unit: charge.</summary>
        public float MinSendCharge = 2.0f;

        // ---- Beams and contests (spec §5.5–§5.6) ----

        /// <summary>Normal beam speed. Unit: lattice units/second (÷ wire.Length → t/second).</summary>
        public float BaseBeamSpeed = 4.0f;

        /// <summary>Mutual attrition rate. Unit: fraction of the OPPOSING side's power per second (× dt per tick).</summary>
        public float ContestBurnRate = 0.30f;

        /// <summary>
        /// Front push speed. Unit: contactT per second — T-SPACE, NOT world space.
        /// World-space front speed = value × wire.Length, so long wires surge.
        /// Spec-canon; do not multiply by length without a measured reason (lessons.md).
        /// </summary>
        public float ContestPushSpeed = 0.55f;

        /// <summary>Power below this is dead (culls zombie beams/contest sides). Unit: charge.</summary>
        public float PowerEpsilon = 1e-4f;

        // ---- AI scoring weights (spec §9.3). Unit: score points unless noted. ----

        public float WCapture = 10f;
        public float WChip = 2f;
        public float WDegree = 3f;
        /// <summary>Multiplies travel time in SECONDS (wire.Length / beam speed).</summary>
        public float WTravel = 1.5f;
        public float WReinforce = 8f;
        public float WDefend = 12f;
        public float WAnticipate = 5f;
        public float WFrontier = 2f;
        public float WOverextend = 4f;

        /// <summary>AI aims for defense × this margin when sizing a capture send. Unit: dimensionless.</summary>
        public float AiCaptureMargin = 1.10f;

        /// <summary>
        /// Denominator floor for the capture-ratio score term (informed addition:
        /// a zero-defense target would otherwise produce an infinite ratio). Unit: charge.
        /// </summary>
        public float AiMinDefenseForRatio = 1.0f;

        /// <summary>
        /// Cap on the capture-ratio score term. Kept LOW on purpose: with a high
        /// cap, burst candidates (full charge → bigger ratio) outscore normal
        /// sends almost everywhere and every tier ≥ 4 burst-spams itself into a
        /// dark defenseless node — measured as the 4v3 ladder collapsing to 11%.
        /// Unit: dimensionless.
        /// </summary>
        public float AiCaptureRatioCap = 1.6f;

        /// <summary>
        /// Flat score toll on burst candidates, pricing the 5 s Disabled window
        /// (defense zero, no accrual) the spec's scoring formula ignores. Burst
        /// still wins when it is the only way to capture, or on very long wires
        /// where its speed advantage exceeds the toll. Unit: score points.
        /// </summary>
        public float WBurstRisk = 12f;

        /// <summary>
        /// Multiplier on the target-value terms (W_DEGREE, W_FRONTIER) for sends
        /// that cannot capture. Unconditional value terms made "chip the hub with
        /// everything" auto-pass the action threshold — measured as sharper tiers
        /// sending 4 times with 0 captures and losing their stripped home (6v5
        /// collapsed to 19%). A chip's value is preparatory, so it scores a
        /// fraction of the prize. Unit: dimensionless [0..1].
        /// </summary>
        public float AiChipValueScale = 0.3f;

        // ---- Derived integer tick counts (always compare ticks, never float seconds) ----

        public int OverchargeTicks => Math.Max(1, (int)Math.Round(OverchargeTime * TickRate));
        public int BurstCooldownTicks => Math.Max(1, (int)Math.Round(BurstCooldown * TickRate));
        public int CaptureLockTicks => Math.Max(1, (int)Math.Round(CaptureLockTime * TickRate));
    }
}
