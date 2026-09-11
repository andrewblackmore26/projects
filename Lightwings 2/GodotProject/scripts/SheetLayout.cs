using System;
using System.Collections.Generic;
using System.Text;
using Godot;
using Lightship.Core;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;

namespace Lightship.View
{
    /// <summary>
    /// Every authored ship laid out in a grid (rows per element, a row of
    /// player variants, columns per tier) plus a bare-core probe, at base
    /// zoom. The lights are captured at several simulation times, and EVERY
    /// part carrying a light is measured at the first time its lit segment is
    /// visible and clear of other parts' lights. A part that is never visible
    /// at any sampled time fails the gate: M1 acceptance is "every part has a
    /// running light", and a light no one can see does not count.
    /// </summary>
    public partial class SheetLayout : Node2D
    {
        public const int CellW = 240;
        public const int CellH = 160;
        public const int OriginX = 200;
        public const int OriginY = 60;
        /// <summary>Capture times: eight frames 0.25 s apart. A part measured at Times[k] is checked for motion at Times[k + DiffStep].</summary>
        public static readonly float[] Times = { 2.0f, 2.25f, 2.5f, 2.75f, 3.0f, 3.25f, 3.5f, 3.75f };
        public const int DiffStep = 2;   // 0.5 s later
        public const float CaptureTime = 2.0f;
        public const float DiffSeconds = 0.5f;
        /// <summary>Min channel of a lit pixel: the pale tint times 1.8 clips to near white.</summary>
        public const int LitMin = 215;
        /// <summary>Tiny parts: their ribbon quads are 1-2 px, so MSAA coverage leaves the lit pixel short of full white.</summary>
        public const int TinyLitMin = 180;
        /// <summary>Min channel of an unlit stroke pixel (the darkest palette stroke is red at 50, the lightest silver at 154).</summary>
        public const int DarkMax = 190;
        /// <summary>Bloom halo allowed around a player box before light blue counts as leaking.</summary>
        public const int Inflate = 12;
        /// <summary>Below this perimeter (px) the lit segment plus caps covers a third of the loop; sample exactly.</summary>
        public const float TinyPerimeter = 30f;
        /// <summary>
        /// A probe point must be this far (px) from every other part's lit segment:
        /// the sampling window's reach plus the lit ribbon's half-width (1.3) and
        /// anti-aliasing. 3x3 window: 1 + 1.3 + 0.7; single pixel: 0 + 1.3 + 0.7.
        /// </summary>
        public static float SeparationPx(bool tiny) => tiny ? 2.0f : 3.0f;

        private static readonly Element[] Rows = { Element.Fire, Element.Lightning, Element.Void, Element.Corruption };
        private static readonly int[] HaloOffsets = { 0, 3, 6, 10, 16, 24 };

        public sealed class Cell
        {
            public ShipDefinition Ship;
            public ShipView View;
            public Vector2 Centre;
            public int Col, Row;
            public bool IsPlayer;
            public bool IsProbe;
        }

        public readonly List<Cell> Cells = new List<Cell>();
        public Cell Probe { get; private set; }
        public float Time { get; private set; }
        /// <summary>Whether the bloom layer is active for this capture; the summary line records it.</summary>
        public bool BloomOn = true;
        private ShaderMaterial _material;

        public void Build(ShipCatalog catalog, ShaderMaterial material)
        {
            _material = material;
            for (int row = 0; row < Rows.Length; row++)
                for (int tier = 1; tier <= 5; tier++)
                {
                    ShipDefinition def = catalog.Find(Rows[row], tier);
                    if (def != null) AddCell(def, tier - 1, row, false, false);
                }
            // Player row: the M1 placeholders are the corruption designs in light blue (spec 13).
            for (int tier = 1; tier <= 5; tier++)
            {
                ShipDefinition def = catalog.Find(Element.Corruption, tier);
                if (def == null) foreach (Element e in Rows) { def = catalog.Find(e, tier); if (def != null) break; }
                if (def != null) AddCell(def.AsPlayerVariant(), tier - 1, Rows.Length, true, false);
            }
            // The halo probe: a bare white core in an otherwise empty cell, so the
            // glow falloff can be measured against plain playfield.
            var probe = new ShipDefinition { Id = "probe_core", Name = "probe", Element = Element.None, Tier = 1, ChassisColor = ColorRole.PlayerBlue, CoreColor = ColorRole.White, CoreRadius = 3f };
            Probe = AddCell(probe, 4, Rows.Length, false, true);
            SetTime(CaptureTime);
        }

        private Cell AddCell(ShipDefinition def, int col, int row, bool isPlayer, bool isProbe)
        {
            var view = new ShipView { Material = _material };
            view.Position = new Vector2(OriginX + col * CellW + CellW / 2f, OriginY + row * CellH + CellH / 2f);
            view.Rebuild(ResolvedShip.From(def), 1f);
            AddChild(view);
            var cell = new Cell { Ship = def, View = view, Centre = view.Position, Col = col, Row = row, IsPlayer = isPlayer, IsProbe = isProbe };
            Cells.Add(cell);
            return cell;
        }

        public void SetTime(float t)
        {
            Time = t;
            _material.SetShaderParameter("sim_time", t);
        }

        // ---- where the lights are ----

        /// <summary>
        /// Covered by anything drawn later: a later part's fill, a later part's stroke
        /// ribbon (1.3 px either side of its outline, plus anti-aliasing), or the core.
        /// Ignoring later strokes put a tether's probe under the blob's rim.
        /// </summary>
        private static bool Occluded(ShipGeometry g, int partIndex, Vec2 local)
        {
            const float strokeReach = ShipMeshBuilder.StrokeHalfPx + 0.7f;
            for (int j = partIndex + 1; j < g.Parts.Count; j++)
            {
                PartGeometry later = g.Parts[j];
                if (later.Dashed) continue;
                if (later.ContainsPoint(local) || later.DistanceToOutline(local) <= strokeReach) return true;
            }
            return local.Length() <= g.CoreRadius + 1f;   // the core is drawn last
        }

        private static Vector2I Screen(Cell cell, Vec2 local)
        {
            Vector2 s = cell.View.ToScreen(local);
            return new Vector2I(Mathf.RoundToInt(s.X), Mathf.RoundToInt(s.Y));
        }

        private static float OffsetAt(PartGeometry p, float t) => LightSegment.Offset(p.Period, p.Phase, t);

        /// <summary>Distance from a point to the lit segment of every OTHER part at time t (sampled along each segment).</summary>
        private static float ClearanceFromOtherLights(ShipGeometry g, int self, Vec2 at, float t)
        {
            float best = float.MaxValue;
            for (int j = 0; j < g.Parts.Count; j++)
            {
                if (j == self || g.Parts[j].Dashed) continue;
                PartGeometry o = g.Parts[j];
                float off = OffsetAt(o, t);
                for (int s = 0; s <= 6; s++)
                    best = MathF.Min(best, Vec2.Distance(at, o.PointAtU(off + LightSegment.DefaultFraction * s / 6f)));
            }
            return best;
        }

        private static float ClearanceFromOwnLight(PartGeometry p, Vec2 at, float t)
        {
            float off = OffsetAt(p, t), best = float.MaxValue;
            for (int s = 0; s <= 6; s++)
                best = MathF.Min(best, Vec2.Distance(at, p.PointAtU(off + LightSegment.DefaultFraction * s / 6f)));
            return best;
        }

        private static int MaxMinChannel(Frame f, Vector2I at, int radius)
        {
            int best = 0;
            for (int dy = -radius; dy <= radius; dy++)
                for (int dx = -radius; dx <= radius; dx++)
                {
                    int x = at.X + dx, y = at.Y + dy;
                    if (!f.InBounds(x, y)) continue;
                    best = Math.Max(best, f.MinChannel(x, y));
                }
            return best;
        }

        /// <summary>The dark sample for part i at time t: near the antipode of its light, unoccluded, clear of other lights.</summary>
        private static bool DarkPoint(ShipGeometry g, int i, float t, float separation, out Vec2 best)
        {
            PartGeometry p = g.Parts[i];
            float darkU = LightSegment.DarkU(OffsetAt(p, t));
            best = p.PointAtU(darkU);
            float bestScore = -1f;
            for (int c = -2; c <= 2; c++)
            {
                Vec2 cand = p.PointAtU(darkU + c * 0.06f);
                if (Occluded(g, i, cand)) continue;
                float score = ClearanceFromOtherLights(g, i, cand, t);
                if (score > bestScore) { bestScore = score; best = cand; }
            }
            return bestScore >= separation;
        }

        // ---- measurement ----

        private static (int w, int h) PixelFootprint(Frame f, Cell cell)
        {
            int x0 = (int)(cell.Centre.X - CellW / 2f), y0 = (int)(cell.Centre.Y - CellH / 2f);
            int minX = int.MaxValue, minY = int.MaxValue, maxX = -1, maxY = -1;
            for (int y = y0; y < y0 + CellH; y++)
                for (int x = x0; x < x0 + CellW; x++)
                {
                    if (!f.InBounds(x, y) || f.Luma(x, y) <= 40) continue;
                    if (x < minX) minX = x; if (x > maxX) maxX = x;
                    if (y < minY) minY = y; if (y > maxY) maxY = y;
                }
            return maxX < 0 ? (0, 0) : (maxX - minX + 1, maxY - minY + 1);
        }

        private static bool FillSample(Cell cell, out Vector2I at, out ColorRole role)
        {
            ShipGeometry g = cell.View.Geometry;
            int bodyIndex = -1;
            float bestArea = 0f;
            for (int i = 0; i < g.Parts.Count; i++)
            {
                PartGeometry p = g.Parts[i];
                if (p.Dashed || p.IsTether || p.FillIndices.Length == 0) continue;
                if (p.Area > bestArea) { bestArea = p.Area; bodyIndex = i; }
            }
            at = default;
            role = ColorRole.White;
            if (bodyIndex < 0) return false;
            PartGeometry body = g.Parts[bodyIndex];
            role = body.Role;
            // The point of the body with the most clearance: from its own stroke, from anything
            // drawn after it (fills and strokes), and from the core. Earlier parts are covered by
            // this fill, so they cannot touch the sample.
            Vec2 bestPoint = default;
            float bestClear = -1f;
            for (float y = body.Min.Y; y <= body.Max.Y; y += 0.5f)
                for (float x = body.Min.X; x <= body.Max.X; x += 0.5f)
                {
                    var cand = new Vec2(x, y);
                    if (!body.ContainsPoint(cand)) continue;
                    bool covered = false;
                    for (int j = bodyIndex + 1; j < g.Parts.Count && !covered; j++)
                        if (!g.Parts[j].Dashed && g.Parts[j].ContainsPoint(cand)) covered = true;
                    if (covered) continue;
                    float clear = MathF.Min(body.DistanceToOutline(cand), cand.Length() - g.CoreRadius);
                    for (int j = bodyIndex + 1; j < g.Parts.Count; j++)
                        if (!g.Parts[j].Dashed) clear = MathF.Min(clear, g.Parts[j].DistanceToOutline(cand));
                    if (clear > bestClear) { bestClear = clear; bestPoint = cand; }
                }
            if (bestClear < 2.5f) return false;
            at = Screen(cell, bestPoint);
            return true;
        }

        /// <summary>
        /// Print-ready lines from frames captured at Times[0..]. Per ship, then the
        /// summary "measure: sheet ..." and "measure: lightdiff ..." lines.
        /// </summary>
        public List<string> Measure(List<Frame> frames)
        {
            var lines = new List<string>();
            Frame f0 = frames[0];
            int litOk = 0, moved = 0, total = 0, never = 0, fillOk = 0, fillTotal = 0, footprintWorst = 0;
            var neverList = new List<string>();
            int usable = frames.Count - DiffStep;

            foreach (Cell cell in Cells)
            {
                if (cell.IsProbe) continue;
                ShipGeometry g = cell.View.Geometry;
                var (w, h) = PixelFootprint(f0, cell);
                footprintWorst = Math.Max(footprintWorst, Math.Abs(Math.Max(w, h) - Mathf.RoundToInt(g.Footprint)));

                int ok = 0, mv = 0, parts = 0;
                for (int i = 0; i < g.Parts.Count; i++)
                {
                    PartGeometry p = g.Parts[i];
                    if (p.Dashed) continue;
                    parts++;
                    total++;
                    bool tiny = p.Perimeter < TinyPerimeter;
                    int radius = tiny ? 0 : 1;
                    int threshold = tiny ? TinyLitMin : LitMin;
                    float sep = SeparationPx(tiny);
                    int chosen = -1;
                    bool hasDark = false;
                    Vec2 lit = default, dark = default;
                    // First time the lit centre is visible and clear of other lights, now and 0.5 s later.
                    // Prefer a time that also has a clean dark point on this part; a part whose only
                    // visible stretch is short (a tether's gap) is proven by the motion check alone:
                    // lit now, dark at the same pixel 0.5 s later, which a static stroke cannot pass.
                    for (int pass = 0; pass < 2 && chosen < 0; pass++)
                        for (int k = 0; k < usable && chosen < 0; k++)
                        {
                            float t = Times[k];
                            Vec2 l = p.PointAtU(LightSegment.LitCentreU(OffsetAt(p, t)));
                            if (Occluded(g, i, l)) continue;
                            if (ClearanceFromOtherLights(g, i, l, t) < sep) continue;
                            if (ClearanceFromOtherLights(g, i, l, Times[k + DiffStep]) < sep) continue;
                            // ...and from its OWN light 0.5 s later: on a sharp apex the segment rounds the
                            // corner and runs back down the other edge within 2 px of where it was.
                            if (ClearanceFromOwnLight(p, l, Times[k + DiffStep]) < sep) continue;
                            bool d = DarkPoint(g, i, t, sep, out Vec2 dp);
                            if (pass == 0 && !d) continue;
                            chosen = k; lit = l; dark = dp; hasDark = d;
                        }
                    if (chosen < 0)
                    {
                        never++;
                        neverList.Add(cell.Ship.Id + "/" + p.Id);
                        continue;
                    }
                    Vector2I ls = Screen(cell, lit), ds = Screen(cell, dark);
                    int litMin = MaxMinChannel(frames[chosen], ls, radius);
                    int darkMin = hasDark ? MaxMinChannel(frames[chosen], ds, radius) : -1;
                    int laterMin = MaxMinChannel(frames[chosen + DiffStep], ls, radius);
                    bool isLit = litMin >= threshold && (!hasDark || darkMin <= DarkMax);
                    bool hasMoved = isLit && laterMin <= DarkMax;
                    if (isLit) ok++;
                    if (hasMoved) mv++;
                    if (!isLit || !hasMoved)
                        lines.Add("sheet-part: ship=" + cell.Ship.Id + " part=" + p.Id + " t=" + Times[chosen] + " lit=" + ls + " litMin=" + litMin +
                                  " dark=" + ds + " darkMin=" + darkMin + " at+0.5s=" + laterMin + " FAIL");
                }
                litOk += ok;
                moved += mv;

                string fillText = "none";
                if (FillSample(cell, out Vector2I at, out ColorRole role))
                {
                    Color expected = Palette.FillOf(role);
                    int er = Mathf.RoundToInt(expected.R * 255f), eg = Mathf.RoundToInt(expected.G * 255f), eb = Mathf.RoundToInt(expected.B * 255f);
                    bool pass = Math.Abs(f0.R(at.X, at.Y) - er) <= 3 && Math.Abs(f0.G(at.X, at.Y) - eg) <= 3 && Math.Abs(f0.B(at.X, at.Y) - eb) <= 3;
                    fillTotal++;
                    if (pass) fillOk++;
                    // Fills are exact only without bloom (a nearby light legitimately adds to them).
                    fillText = f0.Rgb(at.X, at.Y) + "/" + er + "," + eg + "," + eb + (pass ? "" : BloomOn ? "/bloomed" : "/FAIL");
                }

                lines.Add("sheet: id=" + cell.Ship.Id + " cell=" + cell.Col + "," + cell.Row +
                    " footprintPx=" + w + "x" + h + " geomPx=" + g.Footprint.ToString("F1") +
                    " expectedPx=" + ShipLoader.ExpectedFootprint[Math.Clamp(cell.Ship.Tier - 1, 0, 4)] +
                    " parts=" + parts + " lit=" + ok + "/" + parts + " moved=" + mv + "/" + parts + " fill=" + fillText);
            }

            // Light blue belongs to the player alone (spec 2.5, 11.11).
            int blueOutside = 0;
            for (int y = 0; y < f0.H; y++)
                for (int x = 0; x < f0.W; x++)
                {
                    if (f0.MinChannel(x, y) > 200) continue;   // near-white: cores and clipped lights
                    f0.Hsv(x, y, out float hue, out float sat, out float val);
                    if (hue < 190f || hue > 210f || sat < 0.25f || val < 0.5f) continue;
                    bool inside = false;
                    foreach (Cell cell in Cells)
                    {
                        if (!cell.IsPlayer) continue;
                        ShipGeometry g = cell.View.Geometry;
                        if (x >= cell.Centre.X + g.Min.X - Inflate && x <= cell.Centre.X + g.Max.X + Inflate &&
                            y >= cell.Centre.Y + g.Min.Y - Inflate && y <= cell.Centre.Y + g.Max.Y + Inflate) { inside = true; break; }
                    }
                    if (!inside) blueOutside++;
                }

            // Bloom: luma falling away from a bare core over plain playfield.
            string halo = "none";
            bool haloOk = false;
            if (Probe != null)
            {
                var sb = new StringBuilder();
                int cx = Mathf.RoundToInt(Probe.Centre.X), cy = Mathf.RoundToInt(Probe.Centre.Y);
                double bg = f0.Luma(6, 6);
                double prev = double.MaxValue;
                double l6 = 0, l24 = 0;
                haloOk = true;
                foreach (int o in HaloOffsets)
                {
                    double l = f0.Luma(cx + o, cy);
                    if (l > prev + 2) haloOk = false;
                    prev = l;
                    if (o == 6) l6 = l;
                    if (o == 24) l24 = l;
                    if (sb.Length > 0) sb.Append(',');
                    sb.Append(l.ToString("F0"));
                }
                if (!(l6 > bg + 10) || !(l24 < bg + 8)) haloOk = false;
                halo = sb.ToString();
            }

            if (neverList.Count > 0) lines.Add("sheet-never-visible: " + string.Join(" ", neverList));
            int shipCount = Cells.Count - (Probe != null ? 1 : 0);
            // The gate: every part lit and visible, light blue only on the player, and then either the
            // halo (bloom on) or exact palette fills with every ship sampled (bloom off). Footprints are
            // checked with bloom off only (the halo widens them).
            bool sheetOk = litOk == total && never == 0 && blueOutside == 0 &&
                           (BloomOn ? haloOk : fillOk == fillTotal && fillTotal == shipCount && footprintWorst <= 3);
            lines.Add("measure: sheet bloom=" + (BloomOn ? "on" : "off") + " ships=" + shipCount +
                " litParts=" + litOk + "/" + total + " neverVisible=" + never +
                " fillOk=" + fillOk + "/" + fillTotal +
                " footprintErrMaxPx=" + footprintWorst +
                " lightBlueOutsidePlayer=" + blueOutside +
                " halo=" + halo + " haloOk=" + (haloOk ? 1 : 0) + " ok=" + (sheetOk ? 1 : 0));
            lines.Add("measure: lightdiff bloom=" + (BloomOn ? "on" : "off") + " moved=" + moved + "/" + total + " secondsApart=" + DiffSeconds +
                " ok=" + (moved == total && never == 0 ? 1 : 0));
            return lines;
        }
    }
}
