using System;
using System.Collections.Generic;
using Lightship.Core.Ai;
using Lightship.Core.Config;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim
{
    public sealed class ReshapeState
    {
        public ShipDefinition From;
        public ShipDefinition To;
        public long StartTick;
        public long EndTick;

        public float Progress(long tick) =>
            EndTick <= StartTick ? 1f : Math.Clamp((tick - StartTick) / (float)(EndTick - StartTick), 0f, 1f);
    }

    /// <summary>
    /// One life (spec 4, 5): energy only goes up, tiers step at thresholds,
    /// evolution is player-triggered and offers the two most-absorbed lights.
    /// Owns the arena and answers its questions about the player.
    /// </summary>
    public sealed class Run : IArenaHost
    {
        public readonly Game Game;
        public readonly Tuning T;
        public float Energy;
        public int Tier = 1;
        public Element Root;
        public ShipDefinition Ship;                       // the player's current definition (player variant)
        public readonly float[] Absorbed = new float[8]; // since the last evolution, by (int)Element
        public EvolveOffer Offer = new EvolveOffer();
        public ReshapeState Reshape;
        public Arena Arena;
        public readonly HumanPilot Human = new HumanPilot();
        public int EnemiesKilled;
        public int Evolutions;

        public Ship Player => Arena.Player;
        public float Zoom => T.ZoomForTier(Tier);
        public bool Invulnerable => Reshape != null;
        public float Threshold => T.ThresholdForTier(Tier);
        /// <summary>
        /// Spec 5: locks at the threshold and stays available until taken. Never
        /// during a reshape: a second evolution mid-tween would snap the ship and
        /// the camera from a half-blended pose (the next offer waits for the end).
        /// </summary>
        public bool EvolveAvailable => Tier < 5 && Reshape == null && Offer.Count > 0 && Energy >= Threshold;
        public bool Dead => Player == null || !Player.Alive;

        public Run(Game game, ShipDefinition seed, Element sectorElement, IPilot playerPilot)
        {
            Game = game;
            T = game.T;
            Ship = seed.AsPlayerVariant();
            Root = seed.Element;
            // A seed is played at its own tier (a T3 seed has T3 HP, zoom and offers).
            Tier = Math.Clamp(seed.Tier, 1, 5);
            Energy = Tier >= 2 ? T.ThresholdForTier(Tier - 1) : 0f;
            Arena = new Arena(T, game.Rng.Fork(0x5A5A), game.Events, this, game.Catalog, sectorElement);
            Arena.SpawnPlayer(Ship, Arena.Centre, playerPilot ?? Human, Health.MaxHp(Tier, T));
            RecomputeOffer();
        }

        public void SetPilot(IPilot pilot) => Player.Pilot = pilot ?? Human;

        /// <summary>
        /// One tick. The evolve intent is read from what the PILOT decided this
        /// tick (Player.LastInput), not from the input argument: the argument
        /// only feeds the human pilot, and reading it directly silently ignored
        /// every bot's and rival's evolve decision.
        /// </summary>
        public void Step(PlayerInput input)
        {
            Human.Latest = input;
            Arena.Step();
            if (Reshape != null && Arena.Tick >= Reshape.EndTick)
            {
                Reshape = null;
                Game.Events.Add(EventKind.ReshapeEnded, Arena.Tick, Player.Pos, Ship.Element, Tier, Player.Id);
            }
            RecomputeOffer();
            if (Player.Alive && Player.LastInput.Evolve && EvolveAvailable) Evolve(Player.LastInput.EvolveChoice);
        }

        public void RecomputeOffer() =>
            Offer = Evolution.ComputeOffer(Root, Tier, Absorbed, Game.Meta.Unlocked, Game.Catalog);

        /// <summary>Spec 5: take an offered form. Reshape runs for ReshapeTicks, invulnerable; tallies reset.</summary>
        public void Evolve(int choice)
        {
            if (!EvolveAvailable) return;
            ShipDefinition option = Offer.Options[Math.Clamp(choice, 0, Offer.Count - 1)];
            ShipDefinition next = option.AsPlayerVariant();
            Reshape = new ReshapeState { From = Ship, To = next, StartTick = Arena.Tick, EndTick = Arena.Tick + T.ReshapeTicks };
            Ship = next;
            Tier++;
            Root = option.Element;
            Evolutions++;
            Array.Clear(Absorbed, 0, Absorbed.Length);
            Player.SetDefinition(next);
            Player.MaxHp = Health.MaxHp(Tier, T);
            Player.Hp = MathF.Min(Player.MaxHp, Player.Hp + T.HpPerTier);
            Game.Events.Add(EventKind.Evolved, Arena.Tick, Player.Pos, option.Element, Tier, Player.Id);
            Game.Events.Add(EventKind.ReshapeStarted, Arena.Tick, Player.Pos, option.Element, Tier, Player.Id);
            RecomputeOffer();
        }

        // ---- IArenaHost ----

        public int PlayerTier => Tier;
        public bool PlayerInvulnerable => Invulnerable;
        public float PlayerCoreRadius => T.CoreRadiusPx / Zoom;
        public float MagnetRadius => T.MagnetRadius(Tier) * (Invulnerable ? T.ReshapeMagnetMultiplier : 1f);

        /// <summary>Energy absorbed from the sector's own ambient light (spec 6: most should come from enemies).</summary>
        public float EnergyFromAmbient;
        public float EnergyAbsorbed;

        public void OnAbsorb(Element element, float energy) => OnAbsorb(element, energy, false);

        public void OnAbsorb(Element element, float energy, bool ambient)
        {
            Energy += energy;
            EnergyAbsorbed += energy;
            if (ambient) EnergyFromAmbient += energy;
            if ((int)element >= 0 && (int)element < Absorbed.Length) Absorbed[(int)element] += energy;
        }

        public void OnEnemyKilled(Ship enemy) => EnemiesKilled++;

        /// <summary>
        /// Open decision 1 (spec 4, 20): with DamageShedsLightFraction > 0 a hit knocks
        /// that fraction of the damage out as light. Energy never drops below the
        /// current tier's floor, so a hit can cost progress but never an evolution.
        /// </summary>
        public float EnergyShed;
        private float _shedCarry;   // fractional light owed, so contact damage (0.25 HP a tick) sheds too

        public void OnPlayerDamaged(float amount, Vec2 at)
        {
            float f = T.DamageShedsLightFraction;
            if (f <= 0f) return;
            float floor = Tier >= 2 ? T.ThresholdForTier(Tier - 1) : 0f;
            _shedCarry += amount * f;
            float whole = MathF.Floor(_shedCarry);
            if (whole < 1f) return;
            _shedCarry -= whole;
            float shed = MathF.Min(whole, MathF.Max(0f, Energy - floor));
            if (shed < 1f) return;
            Energy -= shed;
            EnergyShed += shed;
            Element e = Root == Element.None ? Element.Corruption : Root;
            Arena.SpawnShedLight(Player.Pos, e, shed, MagnetRadius + 20f);
        }
    }
}
