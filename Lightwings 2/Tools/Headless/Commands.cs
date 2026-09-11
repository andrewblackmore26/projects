using System;
using System.Collections.Generic;
using Lightship.Core.Config;

namespace Lightship.Headless
{
    /// <summary>One method per CLI command. Filled in as the milestones land.</summary>
    public static class Commands
    {
        public static int Validate(string dir)
        {
            Console.Error.WriteLine("ERROR: validate not implemented yet (M1 step 2)");
            return 2;
        }

        public static int Bot(Tuning tuning, Dictionary<string, string> opts)
        {
            Console.Error.WriteLine("ERROR: bot not implemented yet (M1 step 5)");
            return 2;
        }

        public static int Bench(Tuning tuning, Dictionary<string, string> opts)
        {
            Console.Error.WriteLine("ERROR: bench not implemented yet (M1 step 4)");
            return 2;
        }

        public static int Hash(Tuning tuning, Dictionary<string, string> opts)
        {
            Console.Error.WriteLine("ERROR: hash not implemented yet (M1 step 5)");
            return 2;
        }

        public static int SheetInfo()
        {
            Console.Error.WriteLine("ERROR: sheet-info not implemented yet (M1 step 3)");
            return 2;
        }
    }
}
