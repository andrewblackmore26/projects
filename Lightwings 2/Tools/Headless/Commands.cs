using System;
using System.Collections.Generic;
using System.Diagnostics;
using Lightship.Core;
using Lightship.Core.Ai;
using Lightship.Core.Config;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
using Lightship.Core.Sim;

namespace Lightship.Headless
{
    /// <summary>One method per CLI command. Every command prints numbers and exits non-zero on a failed gate.</summary>
    public static class Commands
    {
        private static string Opt(Dictionary<string, string> opts, string key, string fallback) =>
            opts.TryGetValue(key, out string v) && v.Length > 0 ? v : fallback;

        private static ShipCatalog Catalog()
        {
            var warnings = new List<string>();
            ShipCatalog c = ShipCatalog.LoadDirectory(Paths.ShipsDir(), warnings);
            foreach (string w in warnings) Console.WriteLine("warning: " + w);
            return c;
        }

        /// <summary>
        /// Every ship file loads; print the footprint of each against the tier
        /// size in the spec, every warning, and a summary. Exit 1 on a hard
        /// error. The gate in tasks/todo.md is warnings=0.
        /// </summary>
        public static int Validate(string dir)
        {
            var warnings = new List<string>();
            ShipCatalog catalog;
            try
            {
                catalog = ShipCatalog.LoadDirectory(dir, warnings);
            }
            catch (ShipFormatException e)
            {
                Console.Error.WriteLine("ERROR: " + e.Message);
                return 1;
            }
            foreach (ShipDefinition s in catalog.All)
            {
                ShipGeometry g = ShipGeometry.Build(ResolvedShip.From(s));
                Console.WriteLine("ship: id=" + s.Id + " element=" + s.Element + " tier=" + s.Tier +
                    " parts=" + s.Parts.Count + " abilities=" + s.Abilities.Count +
                    " footprintPx=" + g.Footprint.ToString("F1") +
                    " expectedPx=" + ShipLoader.ExpectedFootprint[s.Tier - 1] +
                    " size=" + g.Width.ToString("F1") + "x" + g.Height.ToString("F1") +
                    " boundRadius=" + g.BoundRadius.ToString("F1"));
            }
            foreach (string w in warnings) Console.WriteLine("warning: " + w);
            Console.WriteLine("validate: ships=" + catalog.Count + " warnings=" + warnings.Count + " errors=0");
            return 0;
        }

        /// <summary>
        /// The scripted player, several seeds: when the first evolution lands
        /// is the M1 acceptance number (spec 19: within 2 minutes).
        /// </summary>
        public static int Bot(Tuning tuning, Dictionary<string, string> opts)
        {
            float seconds = float.Parse(Opt(opts, "seconds", "180"), System.Globalization.CultureInfo.InvariantCulture);
            ulong seed = ulong.Parse(Opt(opts, "seed", "1"));
            int runs = int.Parse(Opt(opts, "runs", "5"));
            float gate = float.Parse(Opt(opts, "gate", "120"), System.Globalization.CultureInfo.InvariantCulture);
            string ship = Opt(opts, "ship", Game.DefaultSeedShip);
            ShipCatalog catalog = Catalog();
            long ticks = (long)(seconds * tuning.TickRate);
            float worst = 0f;
            bool allEvolved = true;
            for (int r = 0; r < runs; r++)
            {
                ulong s = seed + (ulong)r;
                var game = new Game(tuning, catalog, s, ship, new BotPilot { Dodge = !opts.ContainsKey("nododge") });
                float energy60 = -1f, energy120 = -1f;
                while (game.Tick < ticks)
                {
                    game.Step(default);
                    if (energy60 < 0f && game.Time >= 60f) energy60 = game.Run.Energy;
                    if (energy120 < 0f && game.Time >= 120f) energy120 = game.Run.Energy;
                }
                long first = game.Events.FirstTick(EventKind.Evolved);
                float firstSec = first >= 0 ? first * tuning.Dt : -1f;
                if (first < 0) allEvolved = false; else worst = Math.Max(worst, firstSec);
                Console.WriteLine("bot: seed=" + s + " firstEvolveSec=" + (first >= 0 ? firstSec.ToString("F1") : "none") +
                    " energy60=" + energy60.ToString("F0") + " energy120=" + energy120.ToString("F0") +
                    " energyEnd=" + game.Run.Energy.ToString("F0") + " tier=" + game.Run.Tier +
                    " evolutions=" + game.Events.Count(EventKind.Evolved) +
                    " kills=" + game.Events.Count(EventKind.Kill) + " deaths=" + game.Meta.Deaths +
                    " damageTaken=" + game.Events.Count(EventKind.PlayerDamaged) +
                    " energyShed=" + game.Run.EnergyShed.ToString("F0") +
                    " ambientShare=" + (game.Run.EnergyAbsorbed > 0 ? game.Run.EnergyFromAmbient / game.Run.EnergyAbsorbed : 0f).ToString("F2"));
            }
            bool pass = allEvolved && worst <= gate;
            Console.WriteLine("bot: runs=" + runs + " firstEvolveMaxSec=" + (allEvolved ? worst.ToString("F1") : "none") +
                " gateSec=" + gate + " pass=" + (pass ? 1 : 0));
            return pass ? 0 : 1;
        }

        /// <summary>ms per tick with N bullets alive; the budget is 2000 live bullets at 60 fps.</summary>
        public static int Bench(Tuning tuning, Dictionary<string, string> opts)
        {
            int ticks = int.Parse(Opt(opts, "ticks", "600"));
            string list = Opt(opts, "bullets", "1000,2000");
            ShipCatalog catalog = Catalog();
            bool pass = true;
            foreach (string item in list.Split(','))
            {
                int bullets = int.Parse(item.Trim());
                var game = new Game(tuning, catalog, 1, Game.DefaultSeedShip, new BotPilot());
                game.Arena.SpawnEnemies = false;
                game.Arena.DebugSpawnBullets(bullets);
                var samples = new double[ticks];
                var sw = new Stopwatch();
                for (int i = 0; i < ticks; i++)
                {
                    sw.Restart();
                    game.Step(default);
                    sw.Stop();
                    samples[i] = sw.Elapsed.TotalMilliseconds;
                }
                Array.Sort(samples);
                double mean = 0; foreach (double d in samples) mean += d; mean /= ticks;
                double p50 = samples[ticks / 2], p99 = samples[(int)(ticks * 0.99)];
                Console.WriteLine("bench: bullets=" + bullets + " live=" + game.Arena.Bullets.Live + " ticks=" + ticks +
                    " meanMs=" + mean.ToString("F3") + " p50Ms=" + p50.ToString("F3") + " p99Ms=" + p99.ToString("F3"));
                if (mean >= 2.0) pass = false;
            }
            Console.WriteLine("bench: gateMeanMs=2.0 pass=" + (pass ? 1 : 0));
            return pass ? 0 : 1;
        }

        /// <summary>Fingerprint after N ticks with the bot; must equal the Godot player's --hash line.</summary>
        public static int Hash(Tuning tuning, Dictionary<string, string> opts)
        {
            long ticks = long.Parse(Opt(opts, "ticks", "3600"));
            ulong seed = ulong.Parse(Opt(opts, "seed", "1"));
            var game = new Game(tuning, Catalog(), seed, Game.DefaultSeedShip, new BotPilot());
            while (game.Tick < ticks) game.Step(default);
            Console.WriteLine("tick=" + game.Tick + " energy=" + game.Run.Energy.ToString("F1") + " tier=" + game.Run.Tier +
                " hash=" + StateHash.Compute(game).ToString("x16"));
            return 0;
        }

        /// <summary>The headless twin of the sheet capture: where each light sits at t = 2.0 s.</summary>
        public static int SheetInfo()
        {
            ShipCatalog catalog = Catalog();
            const float t = 2.0f;
            foreach (ShipDefinition s in catalog.All)
            {
                ShipGeometry g = ShipGeometry.Build(ResolvedShip.From(s));
                Console.WriteLine("sheet-info: id=" + s.Id + " footprintPx=" + g.Footprint.ToString("F1") + " parts=" + g.Parts.Count);
                foreach (PartGeometry p in g.Parts)
                {
                    if (p.Dashed) continue;
                    float offset = LightSegment.Offset(p.Period, p.Phase, t);
                    Vec2 lit = p.PointAtU(LightSegment.LitCentreU(offset));
                    Vec2 dark = p.PointAtU(LightSegment.DarkU(offset));
                    Console.WriteLine("  part=" + p.Id + " layer=" + p.Layer + " perimeter=" + p.Perimeter.ToString("F1") +
                        " period=" + p.Period + " phase=" + p.Phase +
                        " lit=(" + lit.X.ToString("F1") + "," + lit.Y.ToString("F1") + ")" +
                        " dark=(" + dark.X.ToString("F1") + "," + dark.Y.ToString("F1") + ")");
                }
            }
            return 0;
        }
    }
}
