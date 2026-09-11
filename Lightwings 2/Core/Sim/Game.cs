using System.Collections.Generic;
using Lightship.Core.Config;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim
{
    /// <summary>What persists through death (spec 7): unlocks now; checkpoints and territory in M2.</summary>
    public sealed class Meta
    {
        public readonly List<Element> Unlocked = new List<Element> { Element.Corruption, Element.Fire };
        public int Deaths;
    }

    /// <summary>
    /// The whole game state: meta that survives death, the current run, and
    /// the event log. Built the same way by the Godot player, the CLI and the
    /// tests, so every engine steps the same match.
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
        public Run Run { get; private set; }
        public long Tick { get; private set; }
        private IPilot _playerPilot;

        public Arena Arena => Run.Arena;
        public float Time => Tick * T.Dt;

        public Game(Tuning tuning, ShipCatalog catalog, ulong seed, string seedShipId = DefaultSeedShip, IPilot playerPilot = null)
        {
            T = tuning;
            Catalog = catalog;
            Seed = seed;
            SeedShipId = seedShipId;
            Rng = new DeterministicRandom(seed);
            _playerPilot = playerPilot;
            Run = new Run(this, catalog.Get(seedShipId) ?? throw new System.ArgumentException("no ship " + seedShipId), Element.Fire, playerPilot);
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

        /// <summary>Spec 7: full reset of the run; meta is kept. M1 has one arena, so back to its centre.</summary>
        public void Die()
        {
            Meta.Deaths++;
            Run = new Run(this, Catalog.Get(SeedShipId), Element.Fire, _playerPilot);
        }
    }
}
