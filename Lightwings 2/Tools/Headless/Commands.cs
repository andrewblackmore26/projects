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
                BotSkill skill = opts.ContainsKey("novice") ? BotSkill.Novice() : BotSkill.Perfect();
                if (opts.ContainsKey("nododge")) skill.Dodge = false;
                var game = new Game(tuning, catalog, s, ship, new BotPilot(s) { Skill = skill });
                float energy60 = -1f, energy120 = -1f;
                // First evolution in GAME ticks, sampled here (the game clock is the one the spec's
                // two minutes are measured on; arena ticks happen to match it but need not).
                long first = -1;
                while (game.Tick < ticks)
                {
                    game.Step(default);
                    if (first < 0 && game.Events.Count(EventKind.Evolved) > 0) first = game.Tick;
                    if (energy60 < 0f && game.Time >= 60f) energy60 = game.Run.Energy;
                    if (energy120 < 0f && game.Time >= 120f) energy120 = game.Run.Energy;
                }
                float firstSec = first >= 0 ? first * tuning.Dt : -1f;
                if (first < 0) allEvolved = false; else worst = Math.Max(worst, firstSec);
                Console.WriteLine("bot: seed=" + s + " firstEvolveSec=" + (first >= 0 ? firstSec.ToString("F1") : "none") +
                    " energy60=" + energy60.ToString("F0") + " energy120=" + energy120.ToString("F0") +
                    " energyEnd=" + game.Run.Energy.ToString("F0") + " tier=" + game.Run.Tier +
                    " evolutions=" + game.Events.Count(EventKind.Evolved) +
                    " kills=" + game.Events.Count(EventKind.Kill) + " spawned=" + game.Events.Count(EventKind.EnemySpawned) +
                    " deaths=" + game.Meta.Deaths + " drones=" + game.Events.Count(EventKind.DroneHatched) +
                    " infections=" + game.Events.Count(EventKind.Infected) + " spreads=" + game.Events.Count(EventKind.InfectSpread) +
                    " damageTaken=" + game.Events.Count(EventKind.PlayerDamaged) +
                    " energyShed=" + game.Run.EnergyShed.ToString("F0") +
                    " ambientShare=" + (game.Run.EnergyAbsorbed > 0 ? game.Run.EnergyFromAmbient / game.Run.EnergyAbsorbed : 0f).ToString("F2"));
            }
            bool pass = allEvolved && worst <= gate;
            Console.WriteLine("bot: profile=" + (opts.ContainsKey("novice") ? "novice" : "perfect") + (opts.ContainsKey("nododge") ? "+nododge" : "") +
                " runs=" + runs + " firstEvolveMaxSec=" + (allEvolved ? worst.ToString("F1") : "none") +
                " gateSec=" + gate + " pass=" + (pass ? 1 : 0));
            return pass ? 0 : 1;
        }

        /// <summary>
        /// The world bot, several seeds (spec 19 M2): when it leaves the origin, clears
        /// sectors, reaches and beats the gate; how the rival fought; and, with --regrow,
        /// how long a death after the gate costs before the bot is back at the checkpoint.
        /// Exit 1 when a gate is not beaten within --gate-sec or a regrow exceeds --regrow-sec.
        /// </summary>
        public static int World(Tuning tuning, Dictionary<string, string> opts)
        {
            var inv = System.Globalization.CultureInfo.InvariantCulture;
            float seconds = float.Parse(Opt(opts, "seconds", "900"), inv);
            ulong seed = ulong.Parse(Opt(opts, "seed", "1"));
            int runs = int.Parse(Opt(opts, "runs", "3"));
            float gateLimit = float.Parse(Opt(opts, "gate-sec", "600"), inv);
            float regrowLimit = float.Parse(Opt(opts, "regrow-sec", "240"), inv);
            bool regrow = opts.ContainsKey("regrow");
            ShipCatalog catalog = Catalog();
            bool pass = true;
            for (int r = 0; r < runs; r++)
            {
                ulong s = seed + (ulong)r;
                BotSkill skill = opts.ContainsKey("novice") ? BotSkill.Novice() : BotSkill.Perfect();
                Game game = Game.NewWorld(tuning, catalog, s, skill);
                long limit = (long)(seconds * tuning.TickRate);
                long firstEvolve = -1, firstExit = -1, gateEntered = -1, gateBeaten = -1, died = -1, back = -1;
                int warningsBeforeGate = 0, deathsAtGate = 0;
                float energyAtGate = 0f, energyBack = 0f;
                int tierAtGate = 0, blockedTraced = 0;
                bool trace = opts.ContainsKey("trace");
                var seen = new List<GameEvent>();
                long seq = 0;
                while (game.Tick < limit)
                {
                    game.Step(default);
                    game.Events.Since(seq, seen);
                    seq = game.Events.Total;
                    foreach (GameEvent e in seen)
                    {
                        if (trace && (e.Kind == EventKind.SectorEntered || e.Kind == EventKind.GateLocked || e.Kind == EventKind.GateBeaten ||
                                      e.Kind == EventKind.PlayerDied || e.Kind == EventKind.Evolved || e.Kind == EventKind.Teleported ||
                                      e.Kind == EventKind.RivalRetreat || e.Kind == EventKind.SectorCleared ||
                                      (e.Kind == EventKind.CrossBlocked && blockedTraced++ < 12)))
                            Console.WriteLine("  trace: t=" + (game.Tick * tuning.Dt).ToString("F1") + " " + e.Kind + " to=(" + e.To.X + "," + e.To.Y + ")" +
                                " value=" + e.Value.ToString("F2") + " sector=" + game.Run.Sector + " ship=" + game.Run.Ship.Id +
                                " pos=(" + e.Pos.X.ToString("F0") + "," + e.Pos.Y.ToString("F0") + ") hp=" + (game.Run.Player?.Hp ?? 0f).ToString("F0") +
                                " energy=" + game.Run.Energy.ToString("F0"));
                        if (e.Kind == EventKind.Evolved && firstEvolve < 0) firstEvolve = game.Tick;
                        if (e.Kind == EventKind.SectorEntered && firstExit < 0 && (e.To.X != 0f || e.To.Y != 0f)) firstExit = game.Tick;
                        if (e.Kind == EventKind.GateWarning && gateEntered < 0) warningsBeforeGate++;
                        if (e.Kind == EventKind.GateLocked && gateEntered < 0) { gateEntered = game.Tick; energyAtGate = game.Run.Energy; tierAtGate = game.Run.Tier; }
                        if (e.Kind == EventKind.GateBeaten && gateBeaten < 0) gateBeaten = game.Tick;
                        if (e.Kind == EventKind.Teleported && died >= 0 && back < 0) { back = game.Tick; energyBack = game.Run.Energy; }
                    }
                    if (gateEntered >= 0 && gateBeaten < 0 && game.Run.Sector.Layer == 0) deathsAtGate++;
                    if (opts.TryGetValue("trace-from", out string tf) && game.Tick >= float.Parse(tf, inv) * tuning.TickRate && game.Tick % 60 == 0)
                    {
                        Arena a = game.Arena; Ship p = a.Player;
                        Ship h = a.NearestHostile(p.Pos, p.Side);
                        Console.WriteLine("  life: t=" + (game.Tick * tuning.Dt).ToString("F0") + " sector=" + game.Run.Sector + " pos=(" + p.Pos.X.ToString("F0") + "," + p.Pos.Y.ToString("F0") +
                            ") hp=" + p.Hp.ToString("F0") + " infected=" + p.Infected(a.Tick) + " energy=" + game.Run.Energy.ToString("F0") + " alive=" + a.AliveRegulars() +
                            " spawned=" + a.EnemiesSpawned + "/" + a.EnemyBudget + " hostile=" + (h == null ? "none" : h.Def.Id + "#" + h.Id + "@(" + h.Pos.X.ToString("F0") + "," + h.Pos.Y.ToString("F0") + ") hp=" + h.Hp.ToString("F0") + " d=" + Lightship.Core.Vec2.Distance(h.Pos, p.Pos).ToString("F0")) +
                            " move=(" + p.LastInput.Move.X.ToString("F2") + "," + p.LastInput.Move.Y.ToString("F2") + ") fire=" + p.LastInput.Fire + " bullets=" + a.Bullets.Live);
                    }
                    if (regrow && gateBeaten >= 0 && died < 0)
                    {
                        // The scripted death: everything the run carried goes; the checkpoint stays.
                        died = game.Tick;
                        game.Die();
                    }
                    if (regrow && back >= 0) break;
                    if (!regrow && gateBeaten >= 0 && game.Tick > gateBeaten + 60 && !opts.ContainsKey("trace-from")) break;
                }
                float Sec(long t) => t < 0 ? -1f : t * tuning.Dt;
                float regrowSec = back >= 0 ? (back - died) * tuning.Dt : -1f;
                bool ok = gateBeaten >= 0 && Sec(gateBeaten) <= gateLimit && (!regrow || (back >= 0 && regrowSec <= regrowLimit));
                if (!ok) pass = false;
                Console.WriteLine("world: seed=" + s + " firstEvolveSec=" + Sec(firstEvolve).ToString("F1") +
                    " firstExitSec=" + Sec(firstExit).ToString("F1") + " gateEnteredSec=" + Sec(gateEntered).ToString("F1") +
                    " gateBeatenSec=" + Sec(gateBeaten).ToString("F1") + " energyAtGate=" + energyAtGate.ToString("F0") +
                    " tierAtGate=" + tierAtGate + " gateWarnings=" + warningsBeforeGate +
                    " deaths=" + game.Meta.Deaths + " crossings=" + game.Events.Count(EventKind.SectorEntered) +
                    " cleared=" + game.Events.Count(EventKind.SectorCleared) + " territory=" + game.Meta.PlayerTerritory.Count +
                    " checkpoints=" + game.Meta.Checkpoints.Count + " blocked=" + game.Events.Count(EventKind.CrossBlocked) +
                    " aimLines=" + game.Events.Count(EventKind.AimLine) + " retreats=" + game.Events.Count(EventKind.RivalRetreat) +
                    " rivalGrabs=" + game.Events.Count(EventKind.RivalAbsorb) +
                    (regrow ? " regrowSec=" + regrowSec.ToString("F1") + " energyBack=" + energyBack.ToString("F0") : "") +
                    " ok=" + (ok ? 1 : 0));
            }
            Console.WriteLine("world: profile=" + (opts.ContainsKey("novice") ? "novice" : "perfect") + " runs=" + runs +
                " gateLimitSec=" + gateLimit + (regrow ? " regrowLimitSec=" + regrowLimit : "") + " pass=" + (pass ? 1 : 0));
            return pass ? 0 : 1;
        }

        /// <summary>
        /// Can a fresh life beat the sectors next to the origin? For each sector owner and
        /// layer, a new tier-1 life is warped in and fights with the (non-travelling) bot
        /// until the sector is clear, it dies, or --limit seconds pass. Prints clear time,
        /// HP lost and the energy it earned, per profile and seed.
        /// </summary>
        public static int Sweep(Tuning tuning, Dictionary<string, string> opts)
        {
            var inv = System.Globalization.CultureInfo.InvariantCulture;
            ulong seed = ulong.Parse(Opt(opts, "seed", "1"));
            int runs = int.Parse(Opt(opts, "runs", "5"));
            float limitSec = float.Parse(Opt(opts, "limit", "120"), inv);
            int layer = int.Parse(Opt(opts, "layer", "1"));
            string ship = Opt(opts, "ship", Game.DefaultSeedShip);
            ShipCatalog catalog = Catalog();
            bool pass = true;
            foreach (string profile in new[] { "perfect", "novice" })
            {
                foreach (Element owner in new[] { Element.Fire, Element.Corruption })
                {
                    int cleared = 0, died = 0;
                    float clearSum = 0f, hpLostSum = 0f, energySum = 0f;
                    for (int r = 0; r < runs; r++)
                    {
                        ulong s = seed + (ulong)r;
                        BotSkill skill = profile == "novice" ? BotSkill.Novice() : BotSkill.Perfect();
                        var game = new Game(tuning, catalog, s, ship, new BotPilot(s) { Skill = skill }, GameMode.World);
                        Lightship.Core.World.SectorCoord at = default;
                        foreach (var sec in game.World.SortedSectors())
                            if (sec.Layer == layer && sec.Owner == owner && !sec.IsGate) { at = sec.Coord; break; }
                        game.Run.Warp(at);
                        Run run = game.Run;
                        long start = game.Tick, limit = start + (long)(limitSec * tuning.TickRate);
                        float hpLost = 0f, lastHp = run.Player.Hp;
                        bool dead = false;
                        while (game.Tick < limit)
                        {
                            game.Step(default);
                            if (!ReferenceEquals(game.Run, run)) { dead = true; break; }
                            if (run.Player.Hp < lastHp) hpLost += lastHp - run.Player.Hp;
                            lastHp = run.Player.Hp;
                            if (run.Life(at).Cleared) break;
                        }
                        bool clear = !dead && run.Life(at).Cleared;
                        if (clear) { cleared++; clearSum += (game.Tick - start) * tuning.Dt; }
                        if (dead) died++;
                        hpLostSum += hpLost;
                        energySum += run.Energy;
                    }
                    bool ok = died == 0 && cleared == runs;
                    if (profile == "perfect" && !ok) pass = false;
                    Console.WriteLine("sweep: profile=" + profile + " owner=" + owner + " layer=" + layer + " ship=" + ship + " runs=" + runs +
                        " cleared=" + cleared + " died=" + died +
                        " clearSecMean=" + (cleared > 0 ? clearSum / cleared : -1f).ToString("F1") +
                        " hpLostMean=" + (hpLostSum / runs).ToString("F0") + " energyMean=" + (energySum / runs).ToString("F0") +
                        " ok=" + (ok ? 1 : 0));
                }
            }
            Console.WriteLine("sweep: pass=" + (pass ? 1 : 0) + " (perfect must clear every sector without dying; novice is reported)");
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
            Game game = opts.ContainsKey("world")
                ? Game.NewWorld(tuning, Catalog(), seed, BotSkill.Perfect())
                : new Game(tuning, Catalog(), seed, Game.DefaultSeedShip, new BotPilot());
            while (game.Tick < ticks) game.Step(default);
            Console.WriteLine("tick=" + game.Tick + " energy=" + game.Run.Energy.ToString("F1") + " tier=" + game.Run.Tier +
                " hash=" + StateHash.Compute(game).ToString("x16"));
            return 0;
        }

        /// <summary>The headless twin of the sheet capture: where each light sits at t = 2.0 s.</summary>
        public static int SheetInfo(Dictionary<string, string> opts = null)
        {
            ShipCatalog catalog = Catalog();
            float t = opts != null && opts.ContainsKey("t") ? float.Parse(opts["t"], System.Globalization.CultureInfo.InvariantCulture) : 2.0f;
            string only = opts != null && opts.ContainsKey("ship") ? opts["ship"] : null;
            foreach (ShipDefinition s in catalog.All)
            {
                if (only != null && s.Id != only) continue;
                ShipGeometry g = ShipGeometry.Build(ResolvedShip.From(s));
                Console.WriteLine("sheet-info: t=" + t + " id=" + s.Id + " footprintPx=" + g.Footprint.ToString("F1") + " parts=" + g.Parts.Count);
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
