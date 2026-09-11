using System.Collections.Generic;
using Godot;
using Lightship.Core;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Lightship.Core.Sim.Abilities;
using Lightship.Core.World;

namespace Lightship.View
{
    /// <summary>
    /// Every arena edge says what crossing it does (spec 7: no surprise traps):
    ///   open           a thin line in the neighbour's colour (where that light is)
    ///   into a gate    a dashed band in the gatekeeper's colour with padlocks; dim until the veil allows it
    ///   veil           a pale double line: only a gate crosses here
    ///   locked in      a solid band in the gatekeeper's colour with padlocks, on every edge
    ///   world's edge   grey
    /// The edge being pushed brightens where the ship presses it. Everything stays under
    /// 1.0 so the bloom leaves it alone. Widths are screen pixels (divided by the zoom).
    /// </summary>
    public partial class EdgeBarriers : Node2D
    {
        public static readonly Color WorldEdgeColor = new Color(0.4f, 0.4f, 0.46f);
        private Game _game;
        private float _zoom = 1f;
        private float _alpha;

        public void Sync(Game game, float zoom, float alpha)
        {
            _game = game;
            _zoom = zoom;
            _alpha = alpha;
            QueueRedraw();
        }

        /// <summary>What the edge looks like, for the drawing and the probe alike.</summary>
        public static (Color color, float widthPx, bool dashed, bool locks) StyleOf(Run run, Edge e)
        {
            if (run.World == null) return (WorldEdgeColor, 3f, false, false);
            if (run.LockedIn)
                return (Palette.StrokeOf(Palette.RoleOf(run.CurrentSector.Owner)) * new Color(1, 1, 1, 0.95f), 6f, false, true);
            CrossResult r = run.EdgeResult(e);
            if (run.EdgeIntoGate(e))
            {
                Sector gate = run.World[run.Sector.Step(e)];
                float a = r == CrossResult.Ok ? 0.95f : 0.6f;
                return (Palette.StrokeOf(Palette.RoleOf(gate.Owner)) * new Color(1, 1, 1, a), 5f, true, true);
            }
            switch (r)
            {
                case CrossResult.Ok:
                {
                    Sector n = run.World[run.Sector.Step(e)];
                    Color c = run.Meta.PlayerTerritory.Contains(n.Coord) ? Palette.StrokeOf(ColorRole.PlayerBlue)
                        : n.Layer == 0 ? new Color(0.8f, 0.8f, 0.84f) : Palette.StrokeOf(Palette.RoleOf(n.Owner));
                    return (c * new Color(1, 1, 1, 0.45f), 2f, false, false);
                }
                case CrossResult.VeilNeedsEnergy:
                case CrossResult.VeilOnlyGates:
                    return (MapView.VeilColor * new Color(1, 1, 1, 0.7f), 4f, false, false);
                default:
                    return (WorldEdgeColor * new Color(1, 1, 1, 0.6f), 3f, false, false);
            }
        }

        /// <summary>The edge as a world-space segment, pulled in by half its width so all of it is on the playfield.</summary>
        public static (Vector2 a, Vector2 b) Segment(Arena arena, Edge e, float inset)
        {
            float w = arena.Width, h = arena.Height;
            switch (e)
            {
                case Edge.West: return (new Vector2(inset, 0f), new Vector2(inset, h));
                case Edge.East: return (new Vector2(w - inset, 0f), new Vector2(w - inset, h));
                case Edge.North: return (new Vector2(0f, inset), new Vector2(w, inset));
                default: return (new Vector2(0f, h - inset), new Vector2(w, h - inset));
            }
        }

        public const float DashOn = 26f, DashOff = 14f, LockSpacing = 260f;

        public override void _Draw()
        {
            if (_game == null) return;
            Run run = _game.Run;
            Arena arena = run.Arena;
            foreach (Edge e in Edges.All)
            {
                var (color, widthPx, dashed, locks) = StyleOf(run, e);
                float width = widthPx / _zoom;
                var (a, b) = Segment(arena, e, width / 2f);
                if (dashed)
                {
                    Vector2 dir = (b - a).Normalized();
                    float len = a.DistanceTo(b), step = (DashOn + DashOff) / _zoom;
                    for (float t = 0f; t < len; t += step)
                        DrawLine(a + dir * t, a + dir * Mathf.Min(t + DashOn / _zoom, len), color, width);
                }
                else if (color.A > 0f && run.World != null && (run.EdgeResult(e) == CrossResult.VeilNeedsEnergy || run.EdgeResult(e) == CrossResult.VeilOnlyGates) && !run.LockedIn)
                {
                    // The veil: two thin lines, so it never reads as a gate's band (the second always inward).
                    Vector2 n = (b - a).Normalized().Orthogonal();
                    if (n.Dot(new Vector2(arena.Width / 2f, arena.Height / 2f) - a) < 0f) n = -n;
                    n *= width * 0.9f;
                    DrawLine(a, b, color, width * 0.4f);
                    DrawLine(a + n, b + n, color, width * 0.4f);
                }
                else DrawLine(a, b, color, width);

                if (locks)
                {
                    Vector2 dir = (b - a).Normalized();
                    Vector2 inward = dir.Orthogonal();
                    if (inward.Dot(new Vector2(arena.Width / 2f, arena.Height / 2f) - a) < 0f) inward = -inward;
                    for (float t = LockSpacing / 2f; t < a.DistanceTo(b); t += LockSpacing)
                        DrawPadlock(a + dir * t + inward * (18f / _zoom), 12f / _zoom, new Color(color.R, color.G, color.B, 1f));
                }

                // Pressing into the edge: a brighter stretch where the ship pushes, growing with the dwell.
                if (run.PushEdge == (int)e && run.PushTicks > 0 && arena.Player != null)
                {
                    Vec2 p = Vec2.Lerp(arena.Player.PrevPos, arena.Player.Pos, _alpha);
                    Vector2 dir = (b - a).Normalized();
                    float along = dir.Dot(new Vector2(p.X, p.Y) - a);
                    float half = 60f / _zoom;
                    float k = Mathf.Clamp(run.PushTicks / (float)_game.T.CrossDwellTicks, 0f, 1f);
                    var bright = new Color(Mathf.Min(color.R * 1.1f, 0.98f), Mathf.Min(color.G * 1.1f, 0.98f), Mathf.Min(color.B * 1.1f, 0.98f), 1f);
                    DrawLine(a + dir * (along - half * k), a + dir * (along + half * k), bright, width * 1.8f);
                }
            }
        }

        private void DrawPadlock(Vector2 at, float size, Color c)
        {
            var body = new Rect2(at.X - size / 2f, at.Y - size * 0.1f, size, size * 0.7f);
            DrawRect(body, c);
            DrawArc(new Vector2(at.X, body.Position.Y), size * 0.3f, Mathf.Pi, Mathf.Tau, 12, c, size * 0.16f);
        }
    }

    /// <summary>
    /// Spec 8 "visible intent": a rival's aim line, from its weapon along its aim, from
    /// RivalAimLineTicks (0.5 s) before each burst until it ends. Drawn in the rival's
    /// colour, under 1.0 (no bloom), 1.6 px.
    /// </summary>
    public partial class AimLines : Node2D
    {
        public const float WidthPx = 1.6f;
        public const float LengthOverReach = 1.15f;
        private readonly List<(Vector2 a, Vector2 b, Color c)> _lines = new List<(Vector2, Vector2, Color)>();
        private float _zoom = 1f;
        public int Count => _lines.Count;
        public IReadOnlyList<(Vector2 a, Vector2 b, Color c)> Lines => _lines;

        /// <summary>The line a rival shows right now, if any (interpolated like its ship).</summary>
        public static bool LineOf(Ship s, Arena arena, float alpha, out Vector2 a, out Vector2 b)
        {
            a = b = Vector2.Zero;
            Weapon w = s.Loadout?.Primary;
            if (!s.Alive || s.Faction != Faction.Rival || arena.Tick >= s.AimLineUntil || w == null) return false;
            Vec2 p = Vec2.Lerp(s.PrevPos, s.Pos, alpha);
            Vec2 mount = w.Barrels.Count > 0 ? w.Barrels[0].Mount : Vec2.Zero;
            Vec2 muzzle = p + mount.Rotated(s.Rotation);
            Vec2 end = muzzle + s.Facing * (w.Reach(arena.T) * LengthOverReach);
            a = new Vector2(muzzle.X, muzzle.Y);
            b = new Vector2(end.X, end.Y);
            return true;
        }

        public void Sync(Game game, float zoom, float alpha)
        {
            _zoom = zoom;
            _lines.Clear();
            Arena arena = game.Arena;
            foreach (Ship s in arena.Ships)
                if (LineOf(s, arena, alpha, out Vector2 a, out Vector2 b))
                    _lines.Add((a, b, Palette.StrokeOf(Palette.RoleOf(s.Element)) * new Color(1, 1, 1, 0.9f)));
            QueueRedraw();
        }

        public override void _Draw()
        {
            foreach (var (a, b, c) in _lines) DrawLine(a, b, c, WidthPx / _zoom, true);
        }
    }
}
