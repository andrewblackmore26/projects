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
            // Spec 11.8 / 12: every part of tier n-1 is kept in tier n, or named by a part's "replaces".
            ShipCatalog c = Authored(out _);
            int pairs = 0;
            foreach (ShipDefinition s in c.All)
            {
                ShipDefinition prev = s.Tier > 1 ? c.Find(s.Element, s.Tier - 1) : null;
                if (prev == null) continue;
                pairs++;
                Assert.True(s.Parts.Count > prev.Parts.Count, s.Id);
                foreach (PartDefinition p in prev.Parts)
                    Assert.True(s.FindPart(p.Id) != null || s.Parts.Exists(q => q.Replaces == p.Id), s.Id + " drops " + p.Id);
            }
            Assert.True(pairs >= 2);
        }

        [Fact]
        public void CatalogWarnsWhenAPartIsDroppedWithoutReplacement()
        {
            var w = new List<string>();
            ShipDefinition t1 = ShipLoader.Parse(Json(), w);
            ShipDefinition t2 = t1.Clone();
            t2.Id = "t2";
            t2.Tier = 2;
            t2.Parts.RemoveAll(p => p.Id == "body");
            t2.Parts.Add(GeometryTests.Part("hex_body", Shape.Hexagon, ("radius", 13f)));
            t2.Parts.Add(GeometryTests.Part("wing", Shape.Circle, ColorRole.FireRed, 10f, 0f, 0f, ("radius", 4f)));
            ShipCatalog.FromShips(new[] { t1, t2 }).Validate(w);
            Assert.Contains(w, m => m.Contains("drops tier 1 part 'body'"));
            w.Clear();
            t2.FindPart("hex_body").Replaces = "body";
            ShipCatalog.FromShips(new[] { t1, t2 }).Validate(w);
            Assert.DoesNotContain(w, m => m.Contains("drops"));
        }

        [Fact]
        public void RejectsTethersToTethersToThemselvesAndPartsWithoutGeometry()
        {
            Assert.Contains("two parts", Assert.Throws<ShipFormatException>(() => ShipLoader.Parse(Json(
                @", { ""id"": ""tether_a"", ""shape"": ""tether"", ""from"": ""body"", ""to"": ""ember_c"", ""color"": ""fire_red"" }
                  , { ""id"": ""tether_b"", ""shape"": ""tether"", ""from"": ""tether_a"", ""to"": ""body"", ""color"": ""fire_red"" }"), null)).Message);
            Assert.Contains("different", Assert.Throws<ShipFormatException>(() => ShipLoader.Parse(Json(
                @", { ""id"": ""tether_a"", ""shape"": ""tether"", ""from"": ""body"", ""to"": ""body"", ""color"": ""fire_red"" }"), null)).Message);
            Assert.Contains("no geometry", Assert.Throws<ShipFormatException>(() => ShipLoader.Parse(Json(
                @", { ""id"": ""ghost"", ""shape"": ""circle"", ""pos"": [5, 5], ""color"": ""fire_red"" }"), null)).Message);
        }

        [Fact]
        public void ReplacesRoundTrips()
        {
            var w = new List<string>();
            ShipDefinition s = ShipLoader.Parse(Json(@", { ""id"": ""hex_body"", ""shape"": ""hexagon"", ""radius"": 8, ""pos"": [0, 20], ""color"": ""fire_red"", ""replaces"": ""old_body"" }"), w);
            Assert.Equal("old_body", ShipLoader.Parse(ShipLoader.Serialize(s), w).FindPart("hex_body").Replaces);
        }

        [Fact]
        public void EveryAuthoredAbilityHasBehaviour()
        {
            ShipCatalog c = Authored(out _);
            foreach (ShipDefinition s in c.All)
                foreach (string ability in s.Abilities)
                    Assert.True(Lightship.Core.Sim.Abilities.AbilityLibrary.Known.Contains(ability), s.Id + ": ability '" + ability + "' does nothing");
        }

        [Fact]
        public void SingleForwardComponentsSitOnTheAxisAndPairsMirror()
        {
            // Spec 11.3: bilateral symmetry; the single forward component sits on the axis, pairs mirror.
            ShipCatalog c = Authored(out _);
            foreach (ShipDefinition s in c.All)
                foreach (PartDefinition p in s.Parts)
                {
                    if (p.IsTether) continue;
                    string mirrorId = p.Id.EndsWith("_l") ? p.Id.Substring(0, p.Id.Length - 2) + "_r"
                                    : p.Id.EndsWith("_r") ? p.Id.Substring(0, p.Id.Length - 2) + "_l" : null;
                    if (mirrorId == null)
                    {
                        Assert.True(System.MathF.Abs(p.Pos.X) < 1e-3f, s.Id + "/" + p.Id + " is unpaired but off the axis");
                        continue;
                    }
                    PartDefinition m = s.FindPart(mirrorId);
                    Assert.NotNull(m);
                    Assert.Equal(-p.Pos.X, m.Pos.X, 3);
                    Assert.Equal(p.Pos.Y, m.Pos.Y, 3);
                }
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
