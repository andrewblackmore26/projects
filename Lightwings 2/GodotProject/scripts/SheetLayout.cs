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
    /// zoom, with the running lights frozen at a known simulation time. The
    /// measurements live here because this class knows where every part and
    /// every lit segment must be on screen.
    /// </summary>
    public partial class SheetLayout : Node2D
    {
        public const int CellW = 240;
        public const int CellH = 160;
        public const int OriginX = 200;
        public const int OriginY = 60;
        public const float CaptureTime = 2.0f;
        public const float DiffSeconds = 0.5f;
        /// <summary>Min channel of a lit pixel: the pale tint times 1.8 clips to near white.</summary>
        public const int LitMin = 215;
        /// <summary>Tiny parts: their ribbon quads are 1-2 px, so MSAA coverage leaves the lit pixel short of full white.</summary>
        public const int TinyLitMin = 180;
        /// <summary>Min channel of an unlit stroke pixel (the darkest palette stroke is red at 50, the lightest silver at 142).</summary>
        public const int DarkMax = 190;
        /// <summary>Bloom halo allowed around a player box before light blue counts as leaking.</summary>
        public const int Inflate = 12;
        public const int FootprintTolerancePx = 8;
        /// <summary>Below this perimeter (px) the lit segment plus caps covers a third of the loop; sample exactly.</summary>
        public const float TinyPerimeter = 30f;

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

        public sealed class PartProbe
        {
            public Cell Cell;
            public int PartIndex;
            public PartGeometry Part;
            public Vector2I Lit, Dark;
            public bool Occluded;
            /// <summary>A part so small that a 3x3 window would straddle its own lit segment; sampled at the exact pixel.</summary>
            public bool Tiny;
            public int SampleRadius => Tiny ? 0 : 1;
            public int LitThreshold => Tiny ? TinyLitMin : LitMin;
        }

        public readonly List<Cell> Cells = new List<Cell>();
        public Cell Probe { get; private set; }
        /// <summary>Whether the bloom layer is active for this capture; the summary line records it.</summary>
        public bool BloomOn = true;
        public float Time { get; private set; }
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

        private static bool Occluded(ShipGeometry g, int partIndex, Vec2 local)
        {
            for (int j = partIndex + 1; j < g.Parts.Count; j++)
                if (!g.Parts[j].Dashed && g.Parts[j].ContainsPoint(local)) return true;
            return local.Length() <= g.CoreRadius + 1f;   // the core is drawn last
        }

        private static Vector2I Screen(Cell cell, Vec2 local)
        {
            Vector2 s = cell.View.ToScreen(local);
            return new Vector2I(Mathf.RoundToInt(s.X), Mathf.RoundToInt(s.Y));
        }

        /// <summary>Lit and dark sample points for every part carrying a light, at the given time.</summary>
        public List<PartProbe> Probes(float time)
        {
            var probes = new List<PartProbe>();
            foreach (Cell cell in Cells)
            {
                if (cell.IsProbe) continue;
                ShipGeometry g = cell.View.Geometry;
                var litPoints = new List<Vec2>();
                for (int i = 0; i < g.Parts.Count; i++)
                {
                    PartGeometry p = g.Parts[i];
                    if (p.Dashed) continue;
                    float offset = LightSegment.Offset(p.Period, p.Phase, time);
                    litPoints.Add(p.PointAtU(LightSegment.LitCentreU(offset)));
                }
                int k = 0;
                for (int i = 0; i < g.Parts.Count; i++)
                {
                    PartGeometry p = g.Parts[i];
                    if (p.Dashed) continue;
                    float offset = LightSegment.Offset(p.Period, p.Phase, time);
                    Vec2 lit = litPoints[k++];
                    var probe = new PartProbe { Cell = cell, PartIndex = i, Part = p, Lit = Screen(cell, lit) };
                    probe.Occluded = Occluded(g, i, lit);

                    // The dark point: half a lap away, nudged within +-0.12 of a lap
                    // to a spot that is not covered by a later part and is as far as
                    // possible from every other lit segment. Never nearer than 0.38 of
                    // a lap to this part's own light.
                    float darkU = LightSegment.DarkU(offset);
                    Vec2 best = p.PointAtU(darkU);
                    float bestScore = -1f;
                    for (int c = -2; c <= 2; c++)
                    {
                        Vec2 cand = p.PointAtU(darkU + c * 0.06f);
                        if (Occluded(g, i, cand)) continue;
                        float score = float.MaxValue;
                        for (int m = 0; m < litPoints.Count; m++)
                            if (m != k - 1) score = MathF.Min(score, Vec2.Distance(cand, litPoints[m]));
                        if (score > bestScore) { bestScore = score; best = cand; }
                    }
                    probe.Dark = Screen(cell, best);
                    probe.Tiny = p.Perimeter < TinyPerimeter;
                    probes.Add(probe);
                }
            }
            return probes;
        }

        // ---- measurement ----

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
            Vec2 c = Core.Geometry.Outline.Centroid(body.Outline);
            Vec2[] candidates =
            {
                c, c + new Vec2(4f, 4f), c + new Vec2(-4f, 4f), c + new Vec2(4f, -4f), c + new Vec2(-4f, -4f),
                c + new Vec2(0f, 6f), c + new Vec2(0f, -6f), c + new Vec2(6f, 0f), c + new Vec2(-6f, 0f),
            };
            foreach (Vec2 cand in candidates)
            {
                if (!body.ContainsPoint(cand)) continue;
                if (Occluded(g, bodyIndex, cand)) continue;
                if (cand.Length() < g.CoreRadius + 3f) continue;
                // The stroke ribbon is 1.3 px either side of the outline; stay well inside.
                bool nearEdge = false;
                foreach (Vec2 o in body.Outline) if (Vec2.Distance(o, cand) < 3f) { nearEdge = true; break; }
                if (nearEdge) continue;
                at = Screen(cell, cand);
                return true;
            }
            return false;
        }

        /// <summary>Print-ready lines: one per ship, then the summary "measure: sheet ..." line.</summary>
        public List<string> Measure(Frame f)
        {
            var lines = new List<string>();
            List<PartProbe> probes = Probes(Time);
            int litOk = 0, litTotal = 0, occluded = 0, fillOk = 0, fillTotal = 0, footprintWorst = 0;

            foreach (Cell cell in Cells)
            {
                if (cell.IsProbe) continue;
                ShipGeometry g = cell.View.Geometry;
                var (w, h) = PixelFootprint(f, cell);
                int measured = Math.Max(w, h);
                int geom = Mathf.RoundToInt(g.Footprint);
                footprintWorst = Math.Max(footprintWorst, Math.Abs(measured - geom));

                int ok = 0, total = 0, occ = 0;
                foreach (PartProbe pr in probes)
                {
                    if (pr.Cell != cell) continue;
                    if (pr.Occluded) { occ++; continue; }
                    total++;
                    int litMin = MaxMinChannel(f, pr.Lit, pr.SampleRadius);
                    int darkMin = MaxMinChannel(f, pr.Dark, pr.SampleRadius);
                    bool pass = litMin >= pr.LitThreshold && darkMin <= DarkMax;
                    if (pass) ok++;
                    else lines.Add("sheet-part: ship=" + cell.Ship.Id + " part=" + pr.Part.Id +
                                   " lit=" + pr.Lit + " litMin=" + litMin + " dark=" + pr.Dark + " darkMin=" + darkMin + " FAIL");
                }
                litOk += ok; litTotal += total; occluded += occ;

                string fillText = "none";
                if (FillSample(cell, out Vector2I at, out ColorRole role))
                {
                    Color expected = Palette.FillOf(role);
                    int er = Mathf.RoundToInt(expected.R * 255f), eg = Mathf.RoundToInt(expected.G * 255f), eb = Mathf.RoundToInt(expected.B * 255f);
                    bool pass = Math.Abs(f.R(at.X, at.Y) - er) <= 3 && Math.Abs(f.G(at.X, at.Y) - eg) <= 3 && Math.Abs(f.B(at.X, at.Y) - eb) <= 3;
                    fillTotal++;
                    if (pass) fillOk++;
                    fillText = f.Rgb(at.X, at.Y) + "/" + er + "," + eg + "," + eb + (pass ? "" : "/FAIL");
                }

                lines.Add("sheet: id=" + cell.Ship.Id + " cell=" + cell.Col + "," + cell.Row +
                    " footprintPx=" + w + "x" + h + " geomPx=" + g.Footprint.ToString("F1") +
                    " expectedPx=" + ShipLoader.ExpectedFootprint[Math.Clamp(cell.Ship.Tier - 1, 0, 4)] +
                    " parts=" + g.Parts.Count + " lit=" + ok + "/" + total + " occluded=" + occ + " fill=" + fillText);
            }

            // Light blue belongs to the player alone (spec 2.5, 11.11).
            int blueOutside = 0;
            for (int y = 0; y < f.H; y++)
                for (int x = 0; x < f.W; x++)
                {
                    if (f.MinChannel(x, y) > 200) continue;   // near-white: cores and clipped lights
                    f.Hsv(x, y, out float hue, out float sat, out float val);
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
                double bg = f.Luma(6, 6);
                double prev = double.MaxValue;
                double l6 = 0, l24 = 0;
                haloOk = true;
                foreach (int o in HaloOffsets)
                {
                    double l = f.Luma(cx + o, cy);
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

            lines.Add("measure: sheet bloom=" + (BloomOn ? "on" : "off") + " ships=" + (Cells.Count - (Probe != null ? 1 : 0)) +
                " litParts=" + litOk + "/" + litTotal + " occluded=" + occluded +
                " fillOk=" + fillOk + "/" + fillTotal +
                " footprintErrMaxPx=" + footprintWorst +
                " lightBlueOutsidePlayer=" + blueOutside +
                " halo=" + halo + " haloOk=" + (haloOk ? 1 : 0));
            return lines;
        }

        /// <summary>Every point that was lit in frame A must be dark in frame B, taken DiffSeconds later.</summary>
        public List<string> MeasureDiff(Frame a, Frame b, float timeA)
        {
            var lines = new List<string>();
            int moved = 0, total = 0;
            foreach (PartProbe pr in Probes(timeA))
            {
                if (pr.Occluded) continue;
                total++;
                int aMin = MaxMinChannel(a, pr.Lit, pr.SampleRadius), bMin = MaxMinChannel(b, pr.Lit, pr.SampleRadius);
                if (aMin >= pr.LitThreshold && bMin <= DarkMax) moved++;
                else lines.Add("lightdiff-part: ship=" + pr.Cell.Ship.Id + " part=" + pr.Part.Id + " at=" + pr.Lit +
                               " aMin=" + aMin + " bMin=" + bMin + " FAIL");
            }
            lines.Add("measure: lightdiff bloom=" + (BloomOn ? "on" : "off") + " moved=" + moved + "/" + total + " secondsApart=" + DiffSeconds);
            return lines;
        }
    }
}
