using Lightship.Core.Ships;

namespace Lightship.Core.Sim
{
    /// <summary>What kind of actor a ship is. Named Faction, never Owner: Node.Owner shadows that name in every Godot node.</summary>
    public enum Faction : byte
    {
        Player = 0,
        Enemy = 1,
        Rival = 2,
    }

    /// <summary>
    /// Who is hostile to whom. The player's team (the player and its drones) is
    /// side 0; every element is its own side, so a fire rival fights beside fire
    /// enemies and against corruption rivals (spec 8: rivals damage each other).
    /// Bullets carry the side that fired them; a bullet hurts any ship of
    /// another side.
    /// </summary>
    public static class Sides
    {
        public const byte Player = 0;

        public static byte Of(Faction faction, Element element) =>
            faction == Faction.Player ? Player : (byte)(1 + (int)element);

        public static bool Hostile(byte a, byte b) => a != b;
    }

    /// <summary>Per-bullet behaviour bits carried from the weapon that fired it.</summary>
    public static class BulletFlags
    {
        public const byte Infect = 1;      // spec 12 corruption T1: infects on hit
        public const byte Spreads = 2;     // spec 12 corruption T2: the infection jumps to neighbours
    }

    /// <summary>Bullets are solid versions of the element's base shape (spec 6).</summary>
    public enum BulletShape : byte
    {
        Circle = 0,
        Triangle = 1,
        Diamond = 2,
        Crescent = 3,
    }

    public static class ElementShapes
    {
        public static BulletShape BulletShapeOf(Element e)
        {
            switch (e)
            {
                case Element.Fire: return BulletShape.Triangle;
                case Element.Lightning: return BulletShape.Diamond;
                case Element.Void: return BulletShape.Crescent;
                default: return BulletShape.Circle;
            }
        }
    }

    /// <summary>One tick of intent, from a human or a pilot. Enemies and rivals use the same struct.</summary>
    public struct PlayerInput
    {
        public Vec2 Move;       // desired direction, length 0..1
        public Vec2 Aim;        // unit vector
        public bool Fire;
        public bool Ability1;
        public bool Ability2;
        public bool Evolve;
        public bool Map;
        public int EvolveChoice;
    }

    /// <summary>Anything that steers a ship: the human's latest input, an enemy behaviour, the test bot, a drone, a rival (M2).</summary>
    public interface IPilot
    {
        PlayerInput Decide(Arena arena, Ship self);
    }
}
