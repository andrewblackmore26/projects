using System;
using System.Collections.Generic;
using System.IO;
using Lightship.Core.Config;

namespace Lightship.Headless
{
    /// <summary>
    /// Engine-free command line over the Core simulation. Every command prints
    /// numbers, never adjectives, and exits non-zero when a gate fails.
    ///
    ///   lightship-headless validate [dir]              every ship JSON loads; footprints and warnings
    ///   lightship-headless bot --seconds 180 --seed 1 --runs 5
    ///   lightship-headless bench --bullets 2000 --ticks 600
    ///   lightship-headless hash --ticks 3600 --seed 1
    ///   lightship-headless sheet-info
    ///   --set Field=Value   (repeatable) overrides a Tuning field for the run
    /// </summary>
    public static class Program
    {
        public static int Main(string[] argv)
        {
            if (argv.Length == 0) { Usage(); return 2; }
            string cmd = argv[0];
            var opts = ParseOptions(argv, 1, out List<string> positional);
            var tuning = new Tuning();
            foreach (string set in opts.GetValueOrDefault("set-list", "").Split('', StringSplitOptions.RemoveEmptyEntries))
            {
                int eq = set.IndexOf('=');
                if (eq < 0 || !tuning.TrySet(set.Substring(0, eq), set.Substring(eq + 1)))
                {
                    Console.Error.WriteLine("ERROR: unknown tuning override: " + set);
                    return 2;
                }
                Console.WriteLine("tuning: " + set);
            }

            try
            {
                switch (cmd)
                {
                    case "validate": return Commands.Validate(positional.Count > 0 ? positional[0] : Paths.ShipsDir());
                    case "bot": return Commands.Bot(tuning, opts);
                    case "bench": return Commands.Bench(tuning, opts);
                    case "hash": return Commands.Hash(tuning, opts);
                    case "sheet-info": return Commands.SheetInfo();
                    default: Usage(); return 2;
                }
            }
            catch (Exception e)
            {
                Console.Error.WriteLine("ERROR: " + e.Message);
                return 1;
            }
        }

        private static void Usage()
        {
            Console.WriteLine("usage: lightship-headless <validate|bot|bench|hash|sheet-info> [--key value] [--set Field=Value]");
        }

        /// <summary>--key value pairs and --flag switches; "--set" accumulates.</summary>
        private static Dictionary<string, string> ParseOptions(string[] argv, int start, out List<string> positional)
        {
            var map = new Dictionary<string, string>();
            positional = new List<string>();
            for (int i = start; i < argv.Length; i++)
            {
                string a = argv[i];
                if (!a.StartsWith("--")) { positional.Add(a); continue; }
                string key = a.Substring(2);
                string value = "";
                int eq = key.IndexOf('=');
                if (eq >= 0) { value = key.Substring(eq + 1); key = key.Substring(0, eq); }
                else if (i + 1 < argv.Length && !argv[i + 1].StartsWith("--")) { value = argv[++i]; }
                if (key == "set") map["set-list"] = map.GetValueOrDefault("set-list", "") + value + "";
                else map[key] = value;
            }
            return map;
        }
    }

    public static class Paths
    {
        /// <summary>Walk up from the executable until Lightship.sln is found.</summary>
        public static string RepoRoot()
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 12 && dir != null; i++)
            {
                if (File.Exists(Path.Combine(dir, "Lightship.sln"))) return dir;
                dir = Path.GetDirectoryName(dir);
            }
            throw new InvalidOperationException("Lightship.sln not found above " + AppContext.BaseDirectory);
        }

        public static string ShipsDir() => Path.Combine(RepoRoot(), "GodotProject", "data", "ships");
    }
}
