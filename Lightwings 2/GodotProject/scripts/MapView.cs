using System.Collections.Generic;
using Godot;
using Lightship.Core;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Lightship.Core.World;

namespace Lightship.View
{
    /// <summary>
    /// Where every map element sits, in the map control's local pixels. One source for
    /// the drawing and for the capture probe that measures it (the SheetLayout rule).
    /// </summary>
    public readonly struct MapLayout
    {
        public const int N = 2 * WorldGrid.Radius + 1;
        public readonly Rect2 Area;
        public readonly float Cell, Gap;
        public readonly bool Full;

        public MapLayout(Rect2 area, bool full)
        {
            Area = area;
            Full = full;
            Gap = full ? 10f : 3f;
            Cell = (area.Size.X - Gap * (N - 1)) / N;
        }

        public Rect2 CellRect(SectorCoord c) =>
            new Rect2(Area.Position.X + (c.X + WorldGrid.Radius) * (Cell + Gap), Area.Position.Y + (c.Y + WorldGrid.Radius) * (Cell + Gap), Cell, Cell);

        /// <summary>The gate's padlock (or, once beaten, the checkpoint diamond): centred, a little high on the full map.</summary>
        public Rect2 GlyphRect(SectorCoord c)
        {
            // Below the "+N" band on both maps: on the 26 px minimap the label used to sit on the padlock.
            Rect2 r = CellRect(c);
            float s = Cell * (Full ? 0.34f : 0.42f);
            Vector2 centre = r.GetCenter() + new Vector2(0f, Full ? -Cell * 0.04f : Cell * 0.18f);
            return new Rect2(centre - new Vector2(s, s) / 2f, s, s);
        }

        /// <summary>The "+N" radiation label, top-right of the cell.</summary>
        public Rect2 RadiationRect(SectorCoord c)
        {
            Rect2 r = CellRect(c);
            Vector2 size = Full ? new Vector2(Cell * 0.34f, Cell * 0.24f) : new Vector2(Cell * 0.62f, Cell * 0.36f);
            return new Rect2(r.End.X - size.X - 1f, r.Position.Y + 1f, size.X, size.Y);
        }

        /// <summary>Full map only: the caption band at the bottom of a cell ("LOCKS IN", "JUMP").</summary>
        public Rect2 LabelRect(SectorCoord c)
        {
            Rect2 r = CellRect(c);
            return new Rect2(r.Position.X + 3f, r.End.Y - Cell * 0.3f, Cell - 6f, Cell * 0.26f);
        }

        /// <summary>The veil between layer n and n+1: a square ring through the gaps around layer n.</summary>
        public Rect2 VeilRect(int layer)
        {
            Rect2 a = CellRect(new SectorCoord(-layer, -layer)), b = CellRect(new SectorCoord(layer, layer));
            return new Rect2(a.Position - new Vector2(Gap, Gap) / 2f, b.End - a.Position + new Vector2(Gap, Gap));
        }

        /// <summary>The veil's threshold label: a box on the top side of its ring.</summary>
        public Rect2 VeilLabelRect(int layer)
        {
            Rect2 v = VeilRect(layer);
            return new Rect2(v.GetCenter().X - 100f, v.Position.Y - 12f, 200f, 24f);
        }

        /// <summary>The layout's own promise: a cell's padlock and its "+N" never overlap.</summary>
        public bool GlyphClearOfRadiation(SectorCoord c) => !GlyphRect(c).Intersects(RadiationRect(c));

        public SectorCoord? CellAt(Vector2 local)
        {
            for (int y = -WorldGrid.Radius; y <= WorldGrid.Radius; y++)
                for (int x = -WorldGrid.Radius; x <= WorldGrid.Radius; x++)
                {
                    var c = new SectorCoord(x, y);
                    if (CellRect(c).HasPoint(local)) return c;
                }
            return null;
        }
    }

    /// <summary>
    /// Spec 7/16 map: layers, the veil with its threshold, territory colours (light blue is
    /// the player's), explored versus dark sectors, the gate and its lock-in shown BEFORE
    /// entry, checkpoints, and radiation icons ("+N" in the light's colour) within three
    /// sectors. The same control draws the corner minimap and the full map (Tab); on the
    /// full map a checkpoint can be clicked to jump to it.
    /// </summary>
    public partial class MapView : Control
    {
        public const float MiniCell = 26f;
        public const float FullSize = 600f;

        public static readonly Color VeilColor = new Color(0.82f, 0.78f, 1f);
        public static readonly Color DarkFill = new Color(0.035f, 0.035f, 0.045f);
        public static readonly Color DarkStroke = new Color(0.2f, 0.2f, 0.25f);

        private GameController _gc;
        public bool Full { get; private set; }
        /// <summary>Negative control for the map gate: draw everything but the padlock.</summary>
        public bool HideGateGlyph;
        /// <summary>Negative control for the veil: draw the ring without its threshold.</summary>
        public bool HideVeilLabel;
        public System.Action TeleportChosen;

        public void Setup(GameController gc, bool full)
        {
            _gc = gc;
            Full = full;
            MouseFilter = full ? MouseFilterEnum.Stop : MouseFilterEnum.Ignore;
            SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
        }

        public MapLayout Layout
        {
            get
            {
                Vector2 view = GetViewportRect().Size;
                if (Full)
                    return new MapLayout(new Rect2((view.X - FullSize) / 2f, 96f, FullSize, FullSize), true);
                float size = MiniCell * MapLayout.N + 3f * (MapLayout.N - 1);
                return new MapLayout(new Rect2(view.X - 16f - size, 16f, size, size), false);
            }
        }

        public override void _Draw()
        {
            Game game = _gc?.Game;
            WorldGrid world = game?.World;
            if (world == null) return;
            Run run = game.Run;
            Meta meta = game.Meta;
            MapLayout L = Layout;
            Font font = ThemeDB.FallbackFont;

            if (Full) DrawRect(new Rect2(Vector2.Zero, GetViewportRect().Size), new Color(0f, 0f, 0f, 0.82f));
            DrawRect(L.Area.Grow(L.Full ? 14f : 5f), new Color(0.01f, 0.01f, 0.02f, 0.9f));

            float line = L.Full ? 2f : 1f;
            foreach (Sector s in world.SortedSectors())
            {
                Rect2 r = L.CellRect(s.Coord);
                bool explored = meta.Explored.Contains(s.Coord);
                bool mine = meta.PlayerTerritory.Contains(s.Coord);
                Color fill, stroke;
                if (s.Layer == 0) { fill = new Color(0.06f, 0.06f, 0.07f); stroke = new Color(0.62f, 0.62f, 0.66f); }
                else if (mine) { fill = Palette.FillOf(ColorRole.PlayerBlue); stroke = Palette.StrokeOf(ColorRole.PlayerBlue); }
                else if (explored) { ColorRole role = Palette.RoleOf(s.Owner); fill = Palette.FillOf(role); stroke = Palette.StrokeOf(role); }
                else { fill = DarkFill; stroke = DarkStroke; }
                DrawRect(r, fill);
                DrawRect(r, stroke, false, line);
                if (s.IsGate) DrawGate(L, s, meta, run, font);
                else if (meta.Checkpoints.Contains(s.Coord)) DrawCheckpoint(L.GlyphRect(s.Coord));
            }

            // The veils, each with its threshold (spec 7: the requirement is shown on the map).
            for (int layer = 1; layer < world.VeilThreshold.Length; layer++)
            {
                float threshold = world.VeilThreshold[layer];
                if (threshold <= 0f) continue;
                Rect2 v = L.VeilRect(layer);
                DrawRect(v, VeilColor, false, L.Full ? 3f : 1.5f);
                if (L.Full && !HideVeilLabel)
                {
                    string label = "VEIL  " + threshold.ToString("F0") + " ENERGY";
                    Rect2 box = L.VeilLabelRect(layer);
                    Vector2 size = font.GetStringSize(label, HorizontalAlignment.Left, -1, 15);
                    DrawRect(box, new Color(0.01f, 0.01f, 0.02f, 1f));
                    DrawString(font, new Vector2(box.GetCenter().X - size.X / 2f, box.End.Y - 6f), label, HorizontalAlignment.Left, -1, 15, VeilColor);
                }
            }

            // Radiation: a sector above the player's tier within three, with the gap and the light it holds.
            foreach (Radiation rad in world.RadiationNear(run.Sector, run.Tier, _gc.Game.Catalog, meta))
            {
                Rect2 rr = L.RadiationRect(rad.Coord);
                Color c = Palette.StrokeOf(Palette.RoleOf(rad.Light));
                int size = L.Full ? 20 : 11;
                DrawString(font, new Vector2(rr.Position.X + 1f, rr.End.Y - (L.Full ? 3f : 1f)), "+" + rad.Gap, HorizontalAlignment.Left, -1, size, c);
            }

            // Where the player is: a bright frame and a dot at its place in the sector.
            Rect2 cur = L.CellRect(run.Sector);
            DrawRect(cur.Grow(L.Full ? 3f : 2f), new Color(1f, 1f, 1f), false, L.Full ? 3f : 2f);
            if (run.Player != null)
            {
                var rel = new Vector2(run.Player.Pos.X / run.Arena.Width, run.Player.Pos.Y / run.Arena.Height);
                DrawCircle(cur.Position + rel * cur.Size, L.Full ? 5f : 2.5f, Palette.StrokeOf(ColorRole.PlayerBlue));
            }

            if (L.Full) DrawLegend(L, font, run, meta);
        }

        /// <summary>A padlock in the gatekeeper's colour while it stands (the lock-in, visible before entry); a checkpoint once it falls.</summary>
        private void DrawGate(MapLayout L, Sector s, Meta meta, Run run, Font font)
        {
            Rect2 g = L.GlyphRect(s.Coord);
            if (meta.BeatenGates.Contains(s.Coord))
            {
                DrawCheckpoint(g);
                if (L.Full)
                {
                    bool can = run.CanTeleportTo(s.Coord);
                    string text = run.Sector == s.Coord ? "HERE" : can ? "CLICK: JUMP" : "JUMP: " + run.World.ThresholdToEnter(s.Coord).ToString("F0");
                    Caption(L, s.Coord, font, text, Palette.StrokeOf(ColorRole.PlayerBlue));
                }
                return;
            }
            Color c = Palette.StrokeOf(Palette.RoleOf(s.Owner));
            if (!HideGateGlyph)
            {
                // Body in the lower 60 %, shackle above it.
                var body = new Rect2(g.Position.X, g.Position.Y + g.Size.Y * 0.42f, g.Size.X, g.Size.Y * 0.58f);
                DrawRect(body, c);
                float r = g.Size.X * 0.3f;
                DrawArc(new Vector2(g.GetCenter().X, body.Position.Y), r, Mathf.Pi, Mathf.Tau, 16, c, L.Full ? 4f : 2f);
                DrawRect(new Rect2(body.GetCenter() - new Vector2(1.5f, 3f), new Vector2(3f, 6f)), new Color(0.02f, 0.02f, 0.03f));
            }
            if (L.Full) Caption(L, s.Coord, font, "GATE: LOCKS IN", c);
        }

        private void Caption(MapLayout L, SectorCoord c, Font font, string text, Color color)
        {
            Rect2 lr = L.LabelRect(c);
            Vector2 size = font.GetStringSize(text, HorizontalAlignment.Left, -1, 13);
            DrawString(font, new Vector2(lr.GetCenter().X - size.X / 2f, lr.End.Y - 4f), text, HorizontalAlignment.Left, -1, 13, color);
        }

        private void DrawCheckpoint(Rect2 g)
        {
            Vector2 c = g.GetCenter();
            float h = g.Size.X * 0.5f;
            DrawColoredPolygon(new[] { c + new Vector2(0, -h), c + new Vector2(h, 0), c + new Vector2(0, h), c + new Vector2(-h, 0) },
                Palette.StrokeOf(ColorRole.PlayerBlue));
        }

        private void DrawLegend(MapLayout L, Font font, Run run, Meta meta)
        {
            var lines = new List<(string, Color)>
            {
                ("MAP  (Tab closes, the game waits)", new Color(0.86f, 0.96f, 1f)),
                ("Padlock: a GATE. Entering it locks every exit until its gatekeeper falls.", Palette.StrokeOf(ColorRole.FireRed)),
                ("+N: threat N tiers above you, in the colour of the light it holds.", new Color(0.86f, 0.96f, 1f)),
                ("Light blue: your territory. Diamond: a checkpoint (click to jump; needs its layer's veil energy).", Palette.StrokeOf(ColorRole.PlayerBlue)),
                ("Energy " + run.Energy.ToString("F0") + "   deaths " + meta.Deaths, new Color(0.7f, 0.74f, 0.8f)),
            };
            float y = L.Area.End.Y + 40f;
            foreach (var (text, color) in lines)
            {
                DrawString(font, new Vector2(L.Area.Position.X - 60f, y), text, HorizontalAlignment.Left, -1, 15, color);
                y += 22f;
            }
        }

        public override void _GuiInput(InputEvent e)
        {
            if (!Full || !(e is InputEventMouseButton mb) || !mb.Pressed || mb.ButtonIndex != MouseButton.Left) return;
            Run run = _gc.Game.Run;
            if (run.World == null) return;
            SectorCoord? c = Layout.CellAt(mb.Position);
            if (!c.HasValue || !run.CanTeleportTo(c.Value)) return;   // the run's own rule, as the caption says
            _gc.RequestTeleport(c.Value);
            TeleportChosen?.Invoke();
            AcceptEvent();
        }
    }
}
