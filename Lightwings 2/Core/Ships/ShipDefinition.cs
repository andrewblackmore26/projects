using System.Collections.Generic;

namespace Lightship.Core.Ships
{
    /// <summary>A ship as data (spec 14): identity, colours, core, and its parts.</summary>
    public sealed class ShipDefinition
    {
        public string Id;
        public string Name;
        public Element Element;
        public int Tier;
        public ColorRole ChassisColor;
        public ColorRole CoreColor = ColorRole.White;
        /// <summary>Screen px at base zoom; the hitbox of the player (spec 9).</summary>
        public float CoreRadius = 3f;
        public bool Breathes;
        public List<PartDefinition> Parts = new List<PartDefinition>();
        public List<string> Abilities = new List<string>();

        public PartDefinition FindPart(string id)
        {
            for (int i = 0; i < Parts.Count; i++) if (Parts[i].Id == id) return Parts[i];
            return null;
        }

        public ShipDefinition Clone()
        {
            var c = new ShipDefinition
            {
                Id = Id, Name = Name, Element = Element, Tier = Tier, ChassisColor = ChassisColor,
                CoreColor = CoreColor, CoreRadius = CoreRadius, Breathes = Breathes,
            };
            foreach (PartDefinition p in Parts) c.Parts.Add(p.Clone());
            c.Abilities.AddRange(Abilities);
            return c;
        }

        /// <summary>
        /// Spec 13: the player is built from the same system with light blue as
        /// the chassis colour and a white core. Component parts keep their own
        /// colours, so the element still reads through the shapes and abilities.
        /// </summary>
        public ShipDefinition AsPlayerVariant()
        {
            ShipDefinition c = Clone();
            c.Id = Id + "_player";
            foreach (PartDefinition p in c.Parts)
                if (p.Color == ChassisColor) p.Color = ColorRole.PlayerBlue;
            c.ChassisColor = ColorRole.PlayerBlue;
            c.CoreColor = ColorRole.White;
            return c;
        }
    }
}
