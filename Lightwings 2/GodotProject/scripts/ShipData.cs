using System.Collections.Generic;
using Godot;
using Lightship.Core.Ships;

namespace Lightship.View
{
    /// <summary>Reads the ship JSON files through Godot's file access so exported builds find them inside the pack.</summary>
    public static class ShipData
    {
        public const string ShipsDir = "res://data/ships";

        public static ShipCatalog LoadCatalog(List<string> warnings)
        {
            var files = new List<KeyValuePair<string, string>>();
            string[] names = DirAccess.GetFilesAt(ShipsDir);
            System.Array.Sort(names, System.StringComparer.Ordinal);
            foreach (string name in names)
            {
                if (!name.EndsWith(".json")) continue;
                string text = FileAccess.GetFileAsString(ShipsDir + "/" + name);
                files.Add(new KeyValuePair<string, string>(name, text));
            }
            return ShipCatalog.FromFiles(files, warnings);
        }
    }
}
