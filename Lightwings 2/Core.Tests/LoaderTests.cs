using System.Collections.Generic;
using System.IO;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
using Xunit;

namespace Lightship.Core.Tests
{
    public class LoaderTests
    {
        private const string Minimal = @"{
  ""id"": ""t"", ""element"": ""fire"", ""tier"": 1, ""chassis_color"": ""fire_red"",
  ""abilities"": [""flame_spray""],
  ""parts"": [
    { ""id"": ""body"", ""shape"": ""triangle"", ""base"": 14, ""height"": 24, ""pos"": [0, 1], ""color"": ""fire_red"" },
    { ""id"": ""ember_c"", ""shape"": ""circle"", ""radius"": 3.4, ""pos"": [0, -14], ""color"": ""lightning_yellow"", ""component"": ""flame_spray"" }
    PARTS
  ]
}";

        private static string Json(string extraParts = "") => Minimal.Replace("PARTS", extraParts);

        public static ShipCatalog Authored(out List<string> warnings)
        {
            warnings = new List<string>();
            return ShipCatalog.LoadDirectory(TestHelpers.ShipsDir(), warnings);
        }

        [Fact]
        public void ExampleRoundTrips()
        {
            var warnings = new List<string>();
            ShipDefinition a = ShipLoader.LoadFile(Path.Combine(TestHelpers.ShipsDir(), "fire_t1_ember.json"), warnings);
            string text = ShipLoader.Serialize(a);
            ShipDefinition b = ShipLoader.Parse(text, warnings);
            Assert.Equal(a.Id, b.Id);
            Assert.Equal(a.Parts.Count, b.Parts.Count);
            for (int i = 0; i < a.Parts.Count; i++)
            {
                Assert.Equal(a.Parts[i].Id, b.Parts[i].Id);
                Assert.Equal(a.Parts[i].Pos, b.Parts[i].Pos);
                Assert.Equal(a.Parts[i].Params, b.Parts[i].Params);
                Assert.Equal(a.Parts[i].PeriodIndex, b.Parts[i].PeriodIndex);
                Assert.Equal(a.Parts[i].Layer, b.Parts[i].Layer);
            }
            Assert.Equal(text, ShipLoader.Serialize(b));   // serialisation is a fixed point
            Assert.Empty(warnings);
        }

        [Fact]
        public void CrescentOffsetRoundTrips()
        {
            var w = new List<string>();
            ShipDefinition s = ShipLoader.Parse(Json(@", { ""id"": ""crescent"", ""shape"": ""crescent"", ""radius"": 12, ""cut_radius"": 10, ""cut_offset"": [0, -6], ""pos"": [0, 0], ""color"": ""fire_red"" }"), w);
            PartDefinition c = s.FindPart("crescent");
            Assert.Equal(-6f, c.Param("cut_dy"));
            string text = ShipLoader.Serialize(s);
            Assert.Contains("\"cut_offset\": [", text.Replace("\r", ""));
            Assert.Equal(-6f, ShipLoader.Parse(text, w).FindPart("crescent").Param("cut_dy"));
        }

        [Fact]
        public void RejectsDuplicateId()
        {
            var ex = Assert.Throws<ShipFormatException>(() => ShipLoader.Parse(Json(@", { ""id"": ""body"", ""shape"": ""circle"", ""radius"": 3, ""color"": ""fire_red"" }"), null));
            Assert.Contains("body", ex.Message);
        }

        [Fact]
        public void RejectsUnknownShapeAndColour()
        {
            Assert.Contains("blob", Assert.Throws<ShipFormatException>(() =>
                ShipLoader.Parse(Json(@", { ""id"": ""x"", ""shape"": ""blob"", ""color"": ""fire_red"" }"), null)).Message);
            Assert.Contains("magenta", Assert.Throws<ShipFormatException>(() =>
                ShipLoader.Parse(Json(@", { ""id"": ""x"", ""shape"": ""circle"", ""radius"": 3, ""color"": ""magenta"" }"), null)).Message);
        }

        [Fact]
        public void RejectsDanglingTether()
        {
            var ex = Assert.Throws<ShipFormatException>(() =>
                ShipLoader.Parse(Json(@", { ""id"": ""tether_x"", ""shape"": ""tether"", ""from"": ""body"", ""to"": ""nowhere"", ""color"": ""fire_red"" }"), null));
            Assert.Contains("tether_x", ex.Message);
            Assert.Contains("nowhere", ex.Message);
        }

        [Fact]
        public void RejectsNonIntersectingCrescent()
        {
            var ex = Assert.Throws<ShipFormatException>(() =>
                ShipLoader.Parse(Json(@", { ""id"": ""maw"", ""shape"": ""crescent"", ""radius"": 12, ""cut_radius"": 3, ""cut_offset"": [0, -40], ""pos"": [0, 0], ""color"": ""fire_red"" }"), null));
            Assert.Contains("intersect", ex.Message);
        }

        [Fact]
        public void RejectsBadTierUnknownParamAndBadPeriod()
        {
            Assert.Contains("tier", Assert.Throws<ShipFormatException>(() =>
                ShipLoader.Parse(Json().Replace("\"tier\": 1", "\"tier\": 6"), null)).Message);
            Assert.Contains("height", Assert.Throws<ShipFormatException>(() =>
                ShipLoader.Parse(Json(@", { ""id"": ""x"", ""shape"": ""circle"", ""radius"": 3, ""height"": 2, ""color"": ""fire_red"" }"), null)).Message);
            Assert.Contains("light_period", Assert.Throws<ShipFormatException>(() =>
                ShipLoader.Parse(Json(@", { ""id"": ""x"", ""shape"": ""circle"", ""radius"": 3, ""light_period"": 1.7, ""color"": ""fire_red"" }"), null)).Message);
        }

        [Fact]
        public void WarnsOnSoftRules()
        {
            var w = new List<string>();
            ShipLoader.Parse(Json(@", { ""id"": ""stub"", ""shape"": ""prong"", ""base"": 4, ""length"": 8, ""pos"": [0, 0], ""color"": ""fire_red"" }
                , { ""id"": ""mystery"", ""shape"": ""circle"", ""radius"": 3, ""pos"": [6, 6], ""color"": ""violet"" }"), w);
            Assert.Contains(w, m => m.Contains("stub") && m.Contains("4x"));
            Assert.Contains(w, m => m.Contains("mystery") && m.Contains("nobody can read"));
        }

        [Fact]
        public void AllAuthoredShipsLoadWithoutWarnings()
        {
            ShipCatalog c = Authored(out List<string> warnings);
            Assert.True(c.Count >= 4, "expected the M1 ships, found " + c.Count);
            Assert.True(warnings.Count == 0, string.Join("\n", warnings));
            Assert.NotNull(c.Find(Element.Fire, 1));
            Assert.NotNull(c.Find(Element.Corruption, 3));
            Assert.Null(c.Find(Element.Void, 1));
        }

        [Fact]
        public void EveryPartHasARunningLight()
        {
            ShipCatalog c = Authored(out _);
            foreach (ShipDefinition s in c.All)
            {
                ShipGeometry g = ShipGeometry.Build(ResolvedShip.From(s));
                Assert.Equal(s.Parts.Count, g.Parts.Count);
                foreach (PartGeometry p in g.Parts)
                {
                    if (p.Dashed) continue;
                    Assert.True(p.PeriodIndex >= 0 && p.PhaseIndex >= 0, s.Id + "/" + p.Id + " has no light schedule");
                    Assert.True(p.Perimeter > 0f, s.Id + "/" + p.Id + " has no edge to run a light on");
                }
            }
        }

        [Fact]
        public void EveryVisiblePartMapsToAnAbility()
        {
            ShipCatalog c = Authored(out _);
            foreach (ShipDefinition s in c.All)
            {
                foreach (PartDefinition p in s.Parts)
                {
                    if (p.IsTether || p.Dashed) continue;
                    Assert.True(!string.IsNullOrEmpty(p.Component) || p.Color == s.ChassisColor, s.Id + "/" + p.Id);
                }
                foreach (string ability in s.Abilities)
                    Assert.Contains(s.Parts, p => p.Component == ability);
            }
        }

        [Fact]
        public void PlayerVariantIsLightBlueMajority()
        {
            ShipCatalog c = Authored(out _);
            foreach (ShipDefinition s in c.All)
            {
                ShipDefinition v = s.AsPlayerVariant();
                int blue = 0;
                foreach (PartDefinition p in v.Parts) if (p.Color == ColorRole.PlayerBlue) blue++;
                Assert.True(blue * 2 > v.Parts.Count, v.Id + ": " + blue + "/" + v.Parts.Count + " light blue");
                Assert.Equal(ColorRole.White, v.CoreColor);
                Assert.Equal(ColorRole.PlayerBlue, v.ChassisColor);
                for (int i = 0; i < s.Parts.Count; i++)
                    if (!string.IsNullOrEmpty(s.Parts[i].Component) && s.Parts[i].Color != s.ChassisColor)
                        Assert.Equal(s.Parts[i].Color, v.Parts[i].Color);   // components keep their colour
                Assert.EndsWith("_player", v.Id);
            }
        }

        [Fact]
        public void TierGrowsByAddition()
        {
            ShipCatalog c = Authored(out _);
            ShipDefinition t1 = c.Find(Element.Corruption, 1), t2 = c.Find(Element.Corruption, 2), t3 = c.Find(Element.Corruption, 3);
            Assert.True(t2.Parts.Count > t1.Parts.Count);
            Assert.True(t3.Parts.Count > t2.Parts.Count);
            foreach (PartDefinition p in t1.Parts) Assert.NotNull(t2.FindPart(p.Id));
            Assert.NotNull(t3.FindPart("blob"));
            Assert.NotNull(t3.FindPart("spore_c"));
        }

        [Fact]
        public void FootprintsMatchSpec()
        {
            ShipCatalog c = Authored(out _);
            foreach (ShipDefinition s in c.All)
            {
                float f = ShipGeometry.Build(ResolvedShip.From(s)).Footprint;
                float expected = ShipLoader.ExpectedFootprint[s.Tier - 1];
                Assert.InRange(f, expected * 0.75f, expected * 1.25f);
            }
        }

        [Fact]
        public void CatalogRejectsTwoDesignsForOneTier()
        {
            var w = new List<string>();
            ShipDefinition a = ShipLoader.Parse(Json(), w);
            ShipDefinition b = ShipLoader.Parse(Json().Replace("\"id\": \"t\"", "\"id\": \"u\""), w);
            var ex = Assert.Throws<ShipFormatException>(() => ShipCatalog.FromShips(new[] { a, b }).Validate(w));
            Assert.Contains("tier 1", ex.Message);
        }
    }
}
