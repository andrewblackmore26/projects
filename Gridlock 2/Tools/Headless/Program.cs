using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using Gridlock.Core;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;

namespace Gridlock.Headless
{
    /// <summary>
    /// The measurement tool. Every balance/design claim in tasks/todo.md comes
    /// from a command here — never from reasoning alone (lessons.md).
    /// </summary>
    public static class Program
    {
        public static int Main(string[] args)
        {
            if (args.Length == 0)
            {
                Console.WriteLine("commands:");
                Console.WriteLine("  match   --level <file|dev:name> --p N --a N --seed S [--max-seconds X] [-v]");
                Console.WriteLine("  balance --level <file|dev:name> --tier N --runs N [--seed S] [--max-seconds X]");
                Console.WriteLine("  ladder  --level <file|dev:name> --runs N [--seed S]");
                Console.WriteLine("  validate <file|dir> [...]");
                Console.WriteLine("  hash    --level <file|dev:name> --ticks N [--p N --a N --seed S]");
                Console.WriteLine("  perf    --level <file|dev:name> --ticks N");
                Console.WriteLine("  gen     --out <dir>          (writes the built-in campaign levels)");
                return 2;
            }
            try
            {
                switch (args[0])
                {
                    case "match": return CmdMatch(args);
                    case "balance": return CmdBalance(args);
                    case "ladder": return CmdLadder(args);
                    case "validate": return CmdValidate(args);
                    case "hash": return CmdHash(args);
                    case "perf": return CmdPerf(args);
                    case "gen": return CmdGen(args);
                    default:
                        Console.Error.WriteLine("unknown command " + args[0]);
                        return 2;
                }
            }
            catch (Exception e)
            {
                Console.Error.WriteLine("error: " + e.Message);
                return 1;
            }
        }

        // ---- argument helpers ----

        /// <summary>
        /// Fresh Tuning with any `--set Field=Value` overrides applied (repeatable).
        /// The CLI twin of the in-game debug panel: every experiment names the
        /// knob it turned. Example: --set WAnticipate=0 --set ContestPushSpeed=0.3
        /// </summary>
        private static Tuning MakeTuning(string[] args)
        {
            var tuning = new Tuning();
            for (int i = 1; i + 1 < args.Length; i++)
            {
                if (args[i] != "--set") continue;
                string[] parts = args[i + 1].Split('=');
                if (parts.Length != 2) throw new ArgumentException("--set expects Field=Value, got " + args[i + 1]);
                var field = typeof(Tuning).GetField(parts[0]);
                if (field == null) throw new ArgumentException("no Tuning field named " + parts[0]);
                if (field.FieldType == typeof(float))
                    field.SetValue(tuning, float.Parse(parts[1], System.Globalization.CultureInfo.InvariantCulture));
                else if (field.FieldType == typeof(int))
                    field.SetValue(tuning, int.Parse(parts[1]));
                else throw new ArgumentException(parts[0] + " has unsupported type " + field.FieldType.Name);
            }
            return tuning;
        }

        private static string Arg(string[] args, string name, string fallback = null)
        {
            for (int i = 1; i + 1 < args.Length; i++)
            {
                if (args[i] == name) return args[i + 1];
            }
            return fallback;
        }

        private static bool Flag(string[] args, string name)
        {
            foreach (string a in args)
            {
                if (a == name) return true;
            }
            return false;
        }

        private static LevelData LoadLevel(string spec)
        {
            if (spec == null) throw new ArgumentException("missing --level");
            if (spec.StartsWith("dev:"))
            {
                switch (spec.Substring(4))
                {
                    case "duel": return DevBoards.Duel();
                    case "strip": return DevBoards.TwoNodeStrip(playerCharge: 6f, aiCharge: 6f);
                    case "chain3": return DevBoards.Chain3();
                    default: throw new ArgumentException("unknown dev board " + spec);
                }
            }
            LevelData level = LevelLoader.Parse(File.ReadAllText(spec));
            LevelLoader.Build(level, new Tuning()); // validate before use
            return level;
        }

        // ---- commands ----

        private static int CmdMatch(string[] args)
        {
            LevelData level = LoadLevel(Arg(args, "--level", "dev:duel"));
            int p = int.Parse(Arg(args, "--p", "5"));
            int a = int.Parse(Arg(args, "--a", "5"));
            ulong seed = ulong.Parse(Arg(args, "--seed", "1"));
            float maxSeconds = float.Parse(Arg(args, "--max-seconds", "600"));

            var sw = Stopwatch.StartNew();
            MatchStats s = HeadlessMatch.Run(level, MakeTuning(args), p, a, seed, maxSeconds);
            sw.Stop();

            Console.WriteLine("level=" + level.Id + " p=" + p + " a=" + a + " seed=" + seed);
            Console.WriteLine("result=" + s.Result + " simSeconds=" + s.SimSeconds.ToString("F1") +
                " ticks=" + s.Ticks + " wallMs=" + sw.ElapsedMilliseconds);
            Console.WriteLine("sends P/A=" + s.PlayerSends + "/" + s.AiSends +
                " captures P/A=" + s.PlayerCaptures + "/" + s.AiCaptures);
            Console.WriteLine("contests=" + s.ContestsStarted +
                " sideDeath=" + s.ContestSideDeathResolutions +
                " endpoint=" + s.ContestEndpointResolutions +
                " mutual=" + s.ContestMutualDeaths);
            Console.WriteLine("unwinnableRejected P/A=" + s.UnwinnableRejectedPlayer + "/" + s.UnwinnableRejectedAi);
            Console.WriteLine("hash=" + s.FinalHash.ToString("x16"));
            return 0;
        }

        private static int CmdBalance(string[] args)
        {
            LevelData level = LoadLevel(Arg(args, "--level", "dev:duel"));
            int tier = int.Parse(Arg(args, "--tier", "5"));
            int runs = int.Parse(Arg(args, "--runs", "1000"));
            ulong seed0 = ulong.Parse(Arg(args, "--seed", "1"));
            float maxSeconds = float.Parse(Arg(args, "--max-seconds", "600"));
            int pairs = runs / 2;

            var results = new MatchStats[pairs * 2];
            string levelJson = LevelWriter.Write(ToLevelData(level)); // reparse per thread (no shared state)
            var sw = Stopwatch.StartNew();
            Parallel.For(0, pairs * 2, i =>
            {
                ulong seed = seed0 + (ulong)(i / 2);
                bool mirror = i % 2 == 1;
                LevelData copy = LevelLoader.Parse(levelJson);
                results[i] = HeadlessMatch.Run(copy, MakeTuning(args), tier, tier, seed, maxSeconds, mirror);
            });
            sw.Stop();

            Report(results, "equal-tier " + tier, sw.ElapsedMilliseconds);
            return 0;
        }

        private static int CmdLadder(string[] args)
        {
            LevelData level = LoadLevel(Arg(args, "--level", "dev:duel"));
            int runs = int.Parse(Arg(args, "--runs", "200"));
            ulong seed0 = ulong.Parse(Arg(args, "--seed", "1"));
            string levelJson = LevelWriter.Write(ToLevelData(level));

            Console.WriteLine("ladder: higher tier plays the PLAYER side and the AI side alternately (mirrored seeds)");
            Console.WriteLine("pair  higherWins  lowerWins  timeouts  higherWinRate");
            bool monotone = true;
            for (int t = 1; t <= 9; t++)
            {
                int higher = t + 1;
                var results = new MatchStats[runs];
                int capturedT = t;
                Parallel.For(0, runs, i =>
                {
                    ulong seed = seed0 + (ulong)(i / 2);
                    bool higherIsPlayer = i % 2 == 0;
                    LevelData copy = LevelLoader.Parse(levelJson);
                    MatchStats s = HeadlessMatch.Run(copy, MakeTuning(args),
                        higherIsPlayer ? capturedT + 1 : capturedT,
                        higherIsPlayer ? capturedT : capturedT + 1,
                        seed, HeadlessMatch.DefaultMaxSeconds, mirrorSeeds: !higherIsPlayer);
                    // Normalize: store "higher side won" in PlayerCaptures slot? No —
                    // recompute below from result + orientation.
                    s.PlayerSends = higherIsPlayer ? 1 : 0; // orientation marker (repurposed, headless-only)
                    results[i] = s;
                });
                int higherWins = 0, lowerWins = 0, timeouts = 0;
                foreach (MatchStats s in results)
                {
                    bool higherIsPlayer = s.PlayerSends == 1;
                    if (s.Result == MatchResult.Timeout) timeouts++;
                    else if (s.Result == MatchResult.PlayerWin) { if (higherIsPlayer) higherWins++; else lowerWins++; }
                    else if (s.Result == MatchResult.AiWin) { if (higherIsPlayer) lowerWins++; else higherWins++; }
                }
                float rate = higherWins * 100f / Math.Max(1, higherWins + lowerWins);
                Console.WriteLine(higher + "v" + t + "    " + higherWins + "        " + lowerWins +
                    "        " + timeouts + "        " + rate.ToString("F1") + "%");
                if (rate < 50f) monotone = false;
            }
            Console.WriteLine(monotone ? "ladder: MONOTONE" : "ladder: INVERTED SOMEWHERE — investigate before shipping");
            return monotone ? 0 : 1;
        }

        private static int CmdValidate(string[] args)
        {
            var files = new List<string>();
            for (int i = 1; i < args.Length; i++)
            {
                if (Directory.Exists(args[i])) files.AddRange(Directory.GetFiles(args[i], "*.json"));
                else files.Add(args[i]);
            }
            int failures = 0;
            foreach (string f in files)
            {
                try
                {
                    BuiltLevel built = LevelLoader.LoadFromJson(File.ReadAllText(f), new Tuning());
                    string warn = built.Warnings.Count > 0 ? " (" + built.Warnings.Count + " warnings)" : "";
                    Console.WriteLine("OK   " + Path.GetFileName(f) + ": " + built.Nodes.Count + " nodes, " +
                        built.Wires.Count + " wires" + warn);
                    foreach (string w in built.Warnings) Console.WriteLine("     warn: " + w);
                }
                catch (LevelValidationException e)
                {
                    Console.WriteLine("FAIL " + Path.GetFileName(f) + ": " + e.Message);
                    failures++;
                }
            }
            return failures == 0 ? 0 : 1;
        }

        private static int CmdHash(string[] args)
        {
            LevelData level = LoadLevel(Arg(args, "--level", "dev:duel"));
            long ticks = long.Parse(Arg(args, "--ticks", "3600"));
            int p = int.Parse(Arg(args, "--p", "5"));
            int a = int.Parse(Arg(args, "--a", "5"));
            ulong seed = ulong.Parse(Arg(args, "--seed", "1"));

            var sim = new Simulation(level, MakeTuning(args));
            HeadlessMatch.AttachControllers(sim, p, a, seed, false, out _, out _);
            while (sim.Tick < ticks && sim.Result == MatchResult.None) sim.Step();
            Console.WriteLine("tick=" + sim.Tick + " result=" + sim.Result + " hash=" + StateHash.Compute(sim).ToString("x16"));
            return 0;
        }

        private static int CmdPerf(string[] args)
        {
            LevelData level = LoadLevel(Arg(args, "--level", "dev:duel"));
            long ticks = long.Parse(Arg(args, "--ticks", "20000"));

            var sim = new Simulation(level, MakeTuning(args));
            HeadlessMatch.AttachControllers(sim, 8, 8, 123, false, out _, out _);

            var perTick = new List<double>((int)Math.Min(ticks, 100000));
            var sw = new Stopwatch();
            long done = 0;
            while (done < ticks)
            {
                if (sim.Result != MatchResult.None) break;
                sw.Restart();
                sim.Step();
                sw.Stop();
                perTick.Add(sw.Elapsed.TotalMilliseconds * 1000.0);
                done++;
            }
            perTick.Sort();
            double mean = 0;
            foreach (double v in perTick) mean += v;
            mean /= Math.Max(1, perTick.Count);
            double P(double q) => perTick[(int)(q * (perTick.Count - 1))];
            Console.WriteLine("ticks=" + perTick.Count + " mean=" + mean.ToString("F1") +
                "us p50=" + P(0.5).ToString("F1") + "us p99=" + P(0.99).ToString("F1") +
                "us max=" + P(1.0).ToString("F1") + "us");
            return 0;
        }

        private static int CmdGen(string[] args)
        {
            string outDir = Arg(args, "--out", Path.Combine("..", "..", "Levels"));
            Directory.CreateDirectory(outDir);
            foreach (LevelData level in CampaignLevels.All())
            {
                string json = LevelWriter.Write(level);
                BuiltLevel built = LevelLoader.LoadFromJson(json, new Tuning()); // authored output must validate
                string path = Path.Combine(outDir, level.Id + ".json");
                File.WriteAllText(path, json);
                Console.WriteLine("wrote " + path + " (" + built.Nodes.Count + " nodes, " +
                    built.Wires.Count + " wires" + (built.Warnings.Count > 0 ? ", " + built.Warnings.Count + " warnings" : "") + ")");
            }
            return 0;
        }

        private static void Report(MatchStats[] results, string label, long wallMs)
        {
            int playerWins = 0, aiWins = 0, timeouts = 0;
            int playerWinsNormal = 0, playerWinsMirror = 0, normalCount = 0, mirrorCount = 0;
            long totalTicks = 0;
            var lengths = new List<float>();
            int unwinnable = 0, contests = 0, endpoint = 0, sideDeath = 0;
            for (int i = 0; i < results.Length; i++)
            {
                MatchStats s = results[i];
                totalTicks += s.Ticks;
                lengths.Add(s.SimSeconds);
                unwinnable += s.UnwinnableRejectedPlayer + s.UnwinnableRejectedAi;
                contests += s.ContestsStarted;
                endpoint += s.ContestEndpointResolutions;
                sideDeath += s.ContestSideDeathResolutions;
                bool mirror = i % 2 == 1;
                if (mirror) mirrorCount++; else normalCount++;
                switch (s.Result)
                {
                    case MatchResult.PlayerWin:
                        playerWins++;
                        if (mirror) playerWinsMirror++; else playerWinsNormal++;
                        break;
                    case MatchResult.AiWin: aiWins++; break;
                    default: timeouts++; break;
                }
            }
            lengths.Sort();
            int decided = playerWins + aiWins;
            float winRate = decided > 0 ? playerWins * 100f / decided : 0f;
            float rateNormal = normalCount > 0 ? playerWinsNormal * 100f / normalCount : 0f;
            float rateMirror = mirrorCount > 0 ? playerWinsMirror * 100f / mirrorCount : 0f;
            Console.WriteLine("balance [" + label + "]: runs=" + results.Length + " wallMs=" + wallMs);
            Console.WriteLine("  playerWinRate=" + winRate.ToString("F1") + "%  (P " + playerWins + " / A " + aiWins +
                " / timeout " + timeouts + ")");
            Console.WriteLine("  side split: normal-orientation " + rateNormal.ToString("F1") +
                "%  mirrored " + rateMirror.ToString("F1") + "%  delta " +
                Math.Abs(rateNormal - rateMirror).ToString("F1") + "pts");
            Console.WriteLine("  match length p50=" + Percentile(lengths, 0.5).ToString("F0") + "s p90=" +
                Percentile(lengths, 0.9).ToString("F0") + "s  stallRate=" +
                (timeouts * 100f / results.Length).ToString("F2") + "%");
            Console.WriteLine("  contests=" + contests + " (sideDeath " + sideDeath + ", endpointSurge " + endpoint +
                ")  unwinnableRejected=" + unwinnable);
        }

        private static float Percentile(List<float> sorted, double q) =>
            sorted.Count == 0 ? 0f : sorted[(int)(q * (sorted.Count - 1))];

        private static LevelData ToLevelData(LevelData level) => level;
    }
}

