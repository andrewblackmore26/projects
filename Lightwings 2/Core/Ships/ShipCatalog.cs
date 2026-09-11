using System;
using System.Collections.Generic;
using System.IO;

namespace Lightship.Core.Ships
{
    /// <summary>
    /// Every authored ship, by id and by (element, tier). Loaded from the one
    /// directory of JSON files that tests, the CLI and the game all read.
    /// </summary>
    public sealed class ShipCatalog
    {
        private readonly Dictionary<string, ShipDefinition> _byId = new Dictionary<string, ShipDefinition>();
        private readonly List<ShipDefinition> _all = new List<ShipDefinition>();

        public IReadOnlyList<ShipDefinition> All => _all;
        public int Count => _all.Count;

        public static ShipCatalog LoadDirectory(string dir, List<string> warnings)
        {
            if (!Directory.Exists(dir)) throw new DirectoryNotFoundException("ship directory not found: " + dir);
            string[] files = Directory.GetFiles(dir, "*.json");
            Array.Sort(files, StringComparer.Ordinal);
            var texts = new List<KeyValuePair<string, string>>();
            foreach (string file in files)
                texts.Add(new KeyValuePair<string, string>(Path.GetFileName(file), File.ReadAllText(file)));
            return FromFiles(texts, warnings);
        }

        /// <summary>Build from (file name, JSON text) pairs: the game reads them through the engine's own file access.</summary>
        public static ShipCatalog FromFiles(IEnumerable<KeyValuePair<string, string>> files, List<string> warnings)
        {
            var catalog = new ShipCatalog();
            foreach (KeyValuePair<string, string> kv in files)
            {
                ShipDefinition ship = ShipLoader.Parse(kv.Value, warnings);
                string expectedId = Path.GetFileNameWithoutExtension(kv.Key);
                if (ship.Id != expectedId)
                    throw new ShipFormatException("file " + kv.Key + " holds ship '" + ship.Id + "' (file name and id must match)");
                catalog.Add(ship);
            }
            catalog.Validate(warnings);
            return catalog;
        }

        public static ShipCatalog FromShips(IEnumerable<ShipDefinition> ships)
        {
            var catalog = new ShipCatalog();
            foreach (ShipDefinition s in ships) catalog.Add(s);
            return catalog;
        }

        public void Add(ShipDefinition ship)
        {
            if (_byId.ContainsKey(ship.Id)) throw new ShipFormatException("duplicate ship id '" + ship.Id + "'");
            _byId[ship.Id] = ship;
            _all.Add(ship);
        }

        public ShipDefinition Get(string id) => _byId.TryGetValue(id, out ShipDefinition s) ? s : null;

        /// <summary>Add a ship, or replace the one with the same id (the editor after a save).</summary>
        public void Put(ShipDefinition ship)
        {
            if (_byId.TryGetValue(ship.Id, out ShipDefinition old)) _all[_all.IndexOf(old)] = ship;
            else _all.Add(ship);
            _byId[ship.Id] = ship;
        }

        /// <summary>The id of another ship that already claims this element and tier, or null.</summary>
        public string ClaimedBy(Element element, int tier, string exceptId)
        {
            foreach (ShipDefinition s in _all)
                if (s.Element == element && s.Tier == tier && s.Id != exceptId) return s.Id;
            return null;
        }

        /// <summary>The authored design for an element at a tier, or null when it does not exist yet.</summary>
        public ShipDefinition Find(Element element, int tier)
        {
            foreach (ShipDefinition s in _all) if (s.Element == element && s.Tier == tier) return s;
            return null;
        }

        /// <summary>Cross-file rules: growth by addition (spec 11.8) and one design per (element, tier).</summary>
        public void Validate(List<string> warnings)
        {
            var seen = new Dictionary<(Element, int), string>();
            foreach (ShipDefinition s in _all)
            {
                var key = (s.Element, s.Tier);
                if (seen.TryGetValue(key, out string other))
                    throw new ShipFormatException("ships '" + other + "' and '" + s.Id + "' both claim " + s.Element + " tier " + s.Tier);
                seen[key] = s.Id;
            }
            if (warnings == null) return;
            foreach (ShipDefinition s in _all)
            {
                if (s.Tier < 2) continue;
                ShipDefinition prev = Find(s.Element, s.Tier - 1);
                if (prev == null) continue;
                if (s.Parts.Count <= prev.Parts.Count)
                    warnings.Add("ship '" + s.Id + "': " + s.Parts.Count + " parts is not more than tier " + prev.Tier + " (" + prev.Parts.Count + "); tiers grow by addition (spec 11.8)");
                // Spec 11.8 / 12: earlier parts remain. Each id of the previous tier is kept, or named by a part's "replaces".
                foreach (PartDefinition old in prev.Parts)
                {
                    if (s.FindPart(old.Id) != null) continue;
                    bool replaced = false;
                    foreach (PartDefinition p in s.Parts) if (p.Replaces == old.Id) { replaced = true; break; }
                    if (!replaced)
                        warnings.Add("ship '" + s.Id + "': drops tier " + prev.Tier + " part '" + old.Id + "' without a part that replaces it (spec 11.8: earlier parts remain)");
                }
            }
        }
    }
}
