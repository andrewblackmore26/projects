using Lightship.Core.Ships;

namespace Lightship.Core.Sim
{
    /// <summary>Who a ship or bullet belongs to. Named Faction, never Owner: Node.Owner shadows that name in every Godot node.</summary>
    public enum Faction : byte
    {
        Player = 0,
        Enemy = 1,
        Rival = 2,
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

    /// <summary>One tick of intent, from a human or a pilot. Enemies use the same struct.</summary>
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

    /// <summary>Anything that steers a ship: the human's latest input, an enemy behaviour, the test bot, a rival (M2).</summary>
    public interface IPilot
    {
        PlayerInput Decide(Arena arena, Ship self);
    }
}
