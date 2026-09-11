using System.Collections.Generic;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Xunit;

namespace Lightship.Core.Tests
{
    public class EvolutionTests
    {
        private static readonly Element[] All = { Element.Fire, Element.Lightning, Element.Void, Element.Corruption };

        /// <summary>Four elements, tiers 1..3, except void which stops at tier 2.</summary>
        private static ShipCatalog Synthetic()
        {
            var ships = new List<ShipDefinition>();
            foreach (Element e in All)
                for (int tier = 1; tier <= 3; tier++)
                {
                    if (e == Element.Void && tier == 3) continue;
                    var s = new ShipDefinition { Id = e.ToString().ToLowerInvariant() + "_t" + tier, Element = e, Tier = tier, ChassisColor = ColorRole.FireRed };
                    s.Parts.Add(GeometryTests.Part("body", Shape.Circle, ("radius", 10f)));
                    ships.Add(s);
                }
            return ShipCatalog.FromShips(ships);
        }

        private static float[] Absorbed(float fire = 0, float lightning = 0, float voidL = 0, float corruption = 0)
        {
            var a = new float[8];
            a[(int)Element.Fire] = fire; a[(int)Element.Lightning] = lightning;
            a[(int)Element.Void] = voidL; a[(int)Element.Corruption] = corruption;
            return a;
        }

        private static Element[] Ids(EvolveOffer o)
        {
            var r = new Element[o.Count];
            for (int i = 0; i < o.Count; i++) r[i] = o.Options[i].Element;
            return r;
        }

        [Fact]
        public void TwoMostAbsorbed()
        {
            EvolveOffer o = Evolution.ComputeOffer(Element.Corruption, 2, Absorbed(fire: 50, lightning: 30, voidL: 10, corruption: 5), All, Synthetic());
            Assert.Equal(new[] { Element.Fire, Element.Lightning }, Ids(o));
            Assert.All(o.Options, s => Assert.Equal(3, s.Tier));
        }

        [Fact]
        public void TieGoesToCurrentRoot()
        {
            EvolveOffer o = Evolution.ComputeOffer(Element.Corruption, 2, Absorbed(fire: 30, lightning: 30, corruption: 30), All, Synthetic());
            Assert.Equal(new[] { Element.Corruption, Element.Fire }, Ids(o));
        }

        [Fact]
        public void SingleTypePlusRoot()
        {
            EvolveOffer o = Evolution.ComputeOffer(Element.Corruption, 2, Absorbed(fire: 20), All, Synthetic());
            Assert.Equal(new[] { Element.Fire, Element.Corruption }, Ids(o));
        }

        [Fact]
        public void SingleTypeIsRootGivesOne()
        {
            EvolveOffer o = Evolution.ComputeOffer(Element.Corruption, 2, Absorbed(corruption: 20), All, Synthetic());
            Assert.Equal(new[] { Element.Corruption }, Ids(o));
        }

        [Fact]
        public void NoneAbsorbedGivesRoot()
        {
            EvolveOffer o = Evolution.ComputeOffer(Element.Corruption, 2, Absorbed(), All, Synthetic());
            Assert.Equal(new[] { Element.Corruption }, Ids(o));
        }

        [Fact]
        public void FirstEvolutionUpToThreeRanked()
        {
            EvolveOffer o = Evolution.ComputeOffer(Element.Corruption, 1, Absorbed(fire: 8, lightning: 7, voidL: 9, corruption: 1), All, Synthetic());
            Assert.Equal(new[] { Element.Void, Element.Fire, Element.Lightning }, Ids(o));
            Assert.All(o.Options, s => Assert.Equal(2, s.Tier));
        }

        [Fact]
        public void Tier5NoOffer()
        {
            Assert.Equal(0, Evolution.ComputeOffer(Element.Fire, 5, Absorbed(fire: 100), All, Synthetic()).Count);
        }

        [Fact]
        public void UnauthoredElementsExcluded()
        {
            // Void has no tier 3, so at tier 2 it cannot be offered however much was absorbed.
            EvolveOffer o = Evolution.ComputeOffer(Element.Corruption, 2, Absorbed(voidL: 100, fire: 1), All, Synthetic());
            Assert.Equal(new[] { Element.Fire, Element.Corruption }, Ids(o));
        }

        [Fact]
        public void LockedElementsExcluded()
        {
            var unlocked = new List<Element> { Element.Corruption, Element.Fire };
            EvolveOffer o = Evolution.ComputeOffer(Element.Corruption, 2, Absorbed(lightning: 100), unlocked, Synthetic());
            Assert.Equal(new[] { Element.Corruption }, Ids(o));
        }

        [Fact]
        public void AuthoredCatalogOffersCorruptionOnlyInM1()
        {
            // Only corruption has a tier 2 authored: the first evolution offers exactly that.
            EvolveOffer o = Evolution.ComputeOffer(Element.Corruption, 1, Absorbed(fire: 100), new[] { Element.Corruption, Element.Fire }, SimTestHelpers.Catalog());
            Assert.Equal(new[] { Element.Corruption }, Ids(o));
        }
    }
}
