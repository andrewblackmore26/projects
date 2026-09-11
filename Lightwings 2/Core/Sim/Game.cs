using System.Collections.Generic;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.World;

namespace Lightship.Core.Sim
{
    /// <summary>
    /// What persists through death (spec 7): unlocked light types, checkpoints,
    /// player territory, what has been seen, which gates have fallen.
    /// </summary>
    public sealed class Meta
    {
        public readonly List<Element> Unlocked = new List<Element> { Element.Corruption, Element.Fire };
        public int Deaths;
        public readonly HashSet<SectorCoord> Checkpoints = new HashSet<SectorCoord>();
        public readonly HashSet<SectorCoord> PlayerTerritory = new HashSet<SectorCoord>();
        public readonly HashSet<SectorCoord> Explored = new HashSet<SectorCoord>();
        public readonly HashSet<SectorCoord> BeatenGates = new HashSet<SectorCoord>();
    }

    /// <summary>
    /// Sandbox is the M1 arena: one endless fire sector with walls, used by the loop
    /// tests, the bench and the capture probes. World is the game (spec 7): a grid of
    /// sectors, a safe origin, veils and a gate.
    /// </summary>
    public enum GameMode { Sandbox, World }

    /// <summary>
    /// The whole game state: meta that survives death, the world, the current run, and
    /// the event log. Built the same way by the Godot player, the CLI and the tests, so
    /// every engine steps the same match.
    /// </summary>
    public sealed class Game
    {
        public const string DefaultSeedShip = "corruption_t1_glitch";

        public readonly Tuning T;
        public readonly ShipCatalog Catalog;
        public readonly DeterministicRandom Rng;
        public readonly EventLog Events = new EventLog();
        public readonly Meta Meta = new Meta();
        public readonly ulong Seed;
        public readonly string SeedShipId;
        public readonly GameMode Mode;
        /// <summary>The sector grid; null in the sandbox.</summary>
        public readonly WorldGrid World;
        public Run Run { get; private set; }
        public long Tick { get; private set; }
        private IPilot _playerPilot;

        public Arena Arena => Run.Arena;
        public float Time => Tick * T.Dt;

        public Game(Tuning tuning, ShipCatalog catalog, ulong seed, string seedShipId = DefaultSeedShip, IPilot playerPilot = null,
            GameMode mode = GameMode.Sandbox)
        {
            T = tuning;
            Catalog = catalog;
            Seed = seed;
            SeedShipId = seedShipId;
            Mode = mode;
            Rng = new DeterministicRandom(seed);
            _playerPilot = playerPilot;
            if (mode == GameMode.World) World = WorldGrid.Build(tuning);
            Run = new Run(this, catalog.Get(seedShipId) ?? throw new System.ArgumentException("no ship " + seedShipId), playerPilot, WorldGrid.Origin);
        }

        /// <summary>
        /// The one way to build the world game, for the Godot player, the CLI and the tests alike.
        /// With a bot skill the world bot flies it; without one the human does.
        /// </summary>
        public static Game NewWorld(Tuning t, ShipCatalog catalog, ulong seed, Ai.BotSkill botSkill = null, string seedShip = DefaultSeedShip)
        {
            var g = new Game(t, catalog, seed, seedShip, null, GameMode.World);
            if (botSkill != null) g.SetPlayerPilot(new Ai.WorldPilot(g, new Ai.BotPilot(seed) { Skill = botSkill }));
            return g;
        }

        public void SetPlayerPilot(IPilot pilot)
        {
            _playerPilot = pilot;
            Run.SetPilot(pilot);
        }

        public void Step(PlayerInput input)
        {
            Run.Step(input);
            Tick++;
            if (Run.Dead) Die();
        }

        /// <summary>
        /// Spec 7: full reset of the run (energy 0, tier-1 seed, back at the origin); meta is
        /// kept. Between lives the rivals fight off-screen, so a border or two may move.
        /// </summary>
        public void Die()
        {
            Meta.Deaths++;
            List<SectorCoord> shifted = World?.DriftBorders(Rng, Meta, T.BorderFlipsPerDeath);
            Run = new Run(this, Catalog.Get(SeedShipId), _playerPilot, WorldGrid.Origin, Arena.Tick, Arena.NextShipId);
            // After the new life's arrival, so the notice is the last word of the step (not the origin's).
            if (shifted != null)
                foreach (SectorCoord c in shifted)
                    Events.Add(EventKind.BorderShifted, Arena.Tick, new Vec2(c.X, c.Y), World[c].Owner);
        }
    }
}
