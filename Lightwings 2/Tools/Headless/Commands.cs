using System;
using System.Collections.Generic;
using Lightship.Core;
using Lightship.Core.Config;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;

namespace Lightship.Headless
{
    /// <summary>One method per CLI command. Filled in as the milestones land.</summary>
    public static class Commands
    {
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

        /// <summary>The headless twin of the sheet capture: where each light sits at t = 2.0 s.</summary>
        public static int SheetInfo()
        {
            var warnings = new List<string>();
            ShipCatalog catalog = ShipCatalog.LoadDirectory(Paths.ShipsDir(), warnings);
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
