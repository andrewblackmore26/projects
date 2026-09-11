using System.Collections.Generic;

namespace Lightship.Core.Ships
{
    /// <summary>
    /// A ship ready to be built into geometry: parts cloned, light schedule
    /// assigned. Also the output of the reshape tween at any t, so the renderer
    /// never needs to know whether it is drawing a rest pose or a blend.
    /// </summary>
    public sealed class ResolvedShip
    {
        public ShipDefinition Source;
        public List<PartDefinition> Parts = new List<PartDefinition>();
        public ColorRole ChassisColor;
        public ColorRole CoreRole;
        public float CoreRadius;
        public bool Breathes;

        public static ResolvedShip From(ShipDefinition def)
        {
            var r = new ResolvedShip
            {
                Source = def, ChassisColor = def.ChassisColor, CoreRole = def.CoreColor,
                CoreRadius = def.CoreRadius, Breathes = def.Breathes,
            };
            foreach (PartDefinition p in def.Parts) r.Parts.Add(p.Clone());
            LightSchedule.Assign(r.Parts);
            return r;
        }

        public PartDefinition FindPart(string id)
        {
            for (int i = 0; i < Parts.Count; i++) if (Parts[i].Id == id) return Parts[i];
            return null;
        }
    }
}
