namespace Lightship.Core.Ships
{
    /// <summary>
    /// Minions that are not tier forms and so do not live in the tier catalog:
    /// the corruption drone hatched from T3 pods. Still built from the same
    /// primitives and drawn by the same renderer (spec 11: every ship follows
    /// the system). Its chassis follows its owner, so the player's drones are
    /// light blue and a rival's are its own colour.
    /// </summary>
    public static class BuiltinShips
    {
        public static ShipDefinition Drone(ColorRole chassis)
        {
            var s = new ShipDefinition
            {
                Id = "drone_" + chassis.ToString().ToLowerInvariant(), Name = "Drone", Element = Element.Corruption, Tier = 1,
                ChassisColor = chassis, CoreColor = chassis == ColorRole.PlayerBlue ? ColorRole.White : chassis, CoreRadius = 1.5f,
                Breathes = true,
            };
            s.Parts.Add(new PartDefinition { Id = "blob", Shape = Shape.Ellipse, Color = chassis, Pos = new Vec2(0f, 0f), Params = { ["rx"] = 4.5f, ["ry"] = 5.5f } });
            s.Parts.Add(new PartDefinition { Id = "nucleus_c", Shape = Shape.Circle, Color = ColorRole.LightningYellow, Pos = new Vec2(0f, -3f), Params = { ["radius"] = 1.6f }, Component = "ram" });
            s.Abilities.Add("ram");
            return s;
        }
    }
}
