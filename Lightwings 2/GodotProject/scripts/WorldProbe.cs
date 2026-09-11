using System;
using System.Collections.Generic;
using Godot;
using Lightship.Core;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Lightship.Core.World;

namespace Lightship.View
{
    /// <summary>
    /// Capture instruments for M2 (spec 19: "a tester understands lock-in before entering a
    /// gate"). Each scenario stages the world deterministically, then measures pixels at the
    /// places the drawing code itself says things are (MapLayout, EdgeBarriers.Segment,
    /// AimLines.LineOf, Hud.BossBarRect). Every line ends in ok=1/0.
    ///
    ///   map       the full map before the gate falls (padlock, caption, radiation, territory,
    ///             veil, unexplored dark, current sector) and after (checkpoint, no padlock:
    ///             the differential that proves the padlock count is not background)
    ///   approach  next to the gate below its veil: warning text, the gate edge's dashed band,
    ///             the padlock on the minimap
    ///   gate      locked in: barriers on the edges, a rival aim line, the gatekeeper's bar
    /// </summary>
    public sealed class WorldProbe
    {
        public readonly string Scenario;
        public int Stages => Scenario == "map" ? 2 : 1;
        private int _gateRedBefore;

        public WorldProbe(string scenario) { Scenario = scenario; }

        private static readonly SectorCoord Gate = new SectorCoord(2, 0);

        public void Stage(int stage, GameController gc, Hud hud)
        {
            Game game = gc.Game;
            Run run = game.Run;
            Meta meta = game.Meta;
            switch (Scenario)
            {
                case "map":
                    if (stage == 0)
                    {
                        foreach (var c in new[] { new SectorCoord(0, -1), new SectorCoord(1, -1), new SectorCoord(1, 0), new SectorCoord(-1, 0), new SectorCoord(-1, 1) })
                            meta.Explored.Add(c);
                        meta.PlayerTerritory.Add(new SectorCoord(0, -1));
                        meta.PlayerTerritory.Add(new SectorCoord(-1, 0));
                        run.Warp(new SectorCoord(1, 0));
                        run.Arena.SpawnEnemies = false;
                        run.Energy = 150f;
                        gc.AdvanceTicks(2);
                        hud.SetFullMap(true);
                    }
                    else
                    {
                        // The gate falls: the padlock must give way to a checkpoint.
                        meta.BeatenGates.Add(Gate);
                        meta.Checkpoints.Add(Gate);
                        meta.PlayerTerritory.Add(Gate);
                        run.Energy = 320f;
                    }
                    break;
                case "approach":
                    run.Warp(new SectorCoord(1, 0));
                    run.Arena.SpawnEnemies = false;
                    run.Energy = 0f;
                    run.Player.Pos = run.Player.PrevPos = new Vec2(run.Arena.Width - 260f, 675f);
                    run.Player.Facing = new Vec2(1f, 0f);
                    gc.AdvanceTicks(2);
                    break;
                case "gate":
                    run.Energy = 320f;
                    run.Warp(Gate);
                    // Within the gatekeeper's perception (it waits for you otherwise) and close enough to
                    // the west edge that the camera, clamped to the arena, shows that edge's barrier.
                    run.Player.Pos = run.Player.PrevPos = new Vec2(600f, 700f);
                    // Step until the gatekeeper shows its first aim line (it closes to its range first).
                    for (int i = 0; i < 60 * 20; i++)
                    {
                        Ship k = game.Arena.Gatekeeper;
                        if (k == null || !k.Alive || k.AimLineUntil - game.Arena.Tick >= 6) break;
                        gc.AdvanceTicks(1);
                    }
                    break;
            }
        }

        // ---- pixel helpers ----

        private static bool HueNear(Frame f, int x, int y, float hue, float tol, float minSat = 0.45f, float minVal = 0.4f)
        {
            f.Hsv(x, y, out float h, out float s, out float v);
            float d = Mathf.Abs(h - hue);
            d = Mathf.Min(d, 360f - d);
            return s >= minSat && v >= minVal && d <= tol;
        }

        private static float HueOf(Color c)
        {
            c.ToHsv(out float h, out _, out _);
            return h * 360f;
        }

        private static int Count(Frame f, Rect2 screen, Func<int, int, bool> match)
        {
            int n = 0;
            for (int y = (int)screen.Position.Y; y < (int)screen.End.Y; y++)
                for (int x = (int)screen.Position.X; x < (int)screen.End.X; x++)
                    if (match(x, y)) n++;
            return n;
        }

        private static Rect2 ToScreen(Transform2D xf, Rect2 local)
        {
            Vector2 a = xf * local.Position, b = xf * local.End;
            return new Rect2(new Vector2(Mathf.Min(a.X, b.X), Mathf.Min(a.Y, b.Y)), (b - a).Abs());
        }

        private static bool Bright(Frame f, int x, int y) => f.Luma(x, y) > 120;

        public List<string> Measure(int stage, Frame f, Transform2D canvas, GameController gc, Hud hud, ArenaView view)
        {
            switch (Scenario)
            {
                case "map": return stage == 0 ? MeasureMapBefore(f, gc, hud) : MeasureMapAfter(f, gc, hud);
                case "approach": return MeasureApproach(f, canvas, gc, hud, view);
                default: return MeasureGate(f, canvas, gc, hud, view);
            }
        }

        private List<string> MeasureMapBefore(Frame f, GameController gc, Hud hud)
        {
            var lines = new List<string>();
            Game game = gc.Game;
            Run run = game.Run;
            Meta meta = game.Meta;
            MapView map = hud.FullMap;
            MapLayout L = map.Layout;
            Transform2D xf = map.GetGlobalTransformWithCanvas();
            float fireHue = HueOf(Palette.StrokeOf(ColorRole.FireRed));
            float blueHue = HueOf(Palette.StrokeOf(ColorRole.PlayerBlue));

            // The gate's padlock and its caption, before the player has been anywhere near it.
            Color gateColor = Palette.StrokeOf(Palette.RoleOf(game.World[Gate].Owner));
            float gateHue = HueOf(gateColor);
            _gateRedBefore = Count(f, ToScreen(xf, L.GlyphRect(Gate)), (x, y) => HueNear(f, x, y, gateHue, 20f));
            int caption = Count(f, ToScreen(xf, L.LabelRect(Gate)), (x, y) => HueNear(f, x, y, gateHue, 25f, 0.35f, 0.35f));
            bool gateOk = _gateRedBefore >= 40 && caption >= 25 && !meta.Explored.Contains(Gate);
            lines.Add("measure: mapGate explored=" + (meta.Explored.Contains(Gate) ? 1 : 0) + " padlockPx=" + _gateRedBefore +
                      " captionPx=" + caption + " ok=" + (gateOk ? 1 : 0));

            // Radiation: every icon the rules call for, in its light's colour.
            List<Radiation> rads = game.World.RadiationNear(run.Sector, run.Tier, game.Catalog, meta);
            int radOk = 0, radMin = int.MaxValue;
            foreach (Radiation r in rads)
            {
                float hue = HueOf(Palette.StrokeOf(Palette.RoleOf(r.Light)));
                int px = Count(f, ToScreen(xf, L.RadiationRect(r.Coord)), (x, y) => HueNear(f, x, y, hue, 25f, 0.35f, 0.35f));
                radMin = Math.Min(radMin, px);
                if (px >= 12) radOk++;
            }
            lines.Add("measure: mapRadiation icons=" + radOk + "/" + rads.Count + " minPx=" + (rads.Count > 0 ? radMin : 0) +
                      " ok=" + (rads.Count >= 10 && radOk == rads.Count ? 1 : 0));

            // Territory: light blue for the player's, the owner's colour for explored rival sectors, dark otherwise.
            int terrOk = 0, terr = 0, rivalOk = 0, rival = 0, darkOk = 0, dark = 0;
            foreach (Sector s in game.World.SortedSectors())
            {
                if (s.Layer == 0 || s.IsGate) continue;
                Rect2 cell = ToScreen(xf, L.CellRect(s.Coord));
                Rect2 rad = ToScreen(xf, L.RadiationRect(s.Coord));
                bool NotRad(int x, int y) => !rad.HasPoint(new Vector2(x, y));
                int blue = Count(f, cell, (x, y) => NotRad(x, y) && HueNear(f, x, y, blueHue, 15f, 0.4f, 0.5f));
                if (meta.PlayerTerritory.Contains(s.Coord)) { terr++; if (blue >= 60) terrOk++; }
                else if (meta.Explored.Contains(s.Coord) && s.Coord != run.Sector)
                {
                    float hue = HueOf(Palette.StrokeOf(Palette.RoleOf(s.Owner)));
                    int own = Count(f, cell, (x, y) => NotRad(x, y) && HueNear(f, x, y, hue, 20f, 0.4f, 0.5f));
                    rival++;
                    if (own >= 60 && blue <= 3) rivalOk++;
                }
                else if (!meta.Explored.Contains(s.Coord))
                {
                    dark++;
                    if (Count(f, cell, (x, y) => NotRad(x, y) && f.Luma(x, y) > 90) <= 4) darkOk++;
                }
            }
            lines.Add("measure: mapTerritory player=" + terrOk + "/" + terr + " rival=" + rivalOk + "/" + rival + " unexploredDark=" + darkOk + "/" + dark +
                      " ok=" + (terr > 0 && terrOk == terr && rival > 0 && rivalOk == rival && dark > 0 && darkOk == dark ? 1 : 0));

            // The veil ring and its threshold, and the frame on the current sector.
            Rect2 v = L.VeilRect(1);
            Rect2 labelScreen = ToScreen(xf, L.VeilLabelRect(1));
            // Text pixels only: the ring itself runs through the label's box, so its rows do not count
            // (without that, a map with no label read 1052 "label" pixels from the bare ring).
            // And in the label's own pale violet: the cells' strokes just under the ring (light blue for
            // territory) sit inside the same box and read bright too.
            float ringY = (xf * v.Position).Y;
            float veilHue = HueOf(MapView.VeilColor);
            int labelPx = Count(f, labelScreen, (x, y) =>
            {
                if (Mathf.Abs(y - ringY) <= 3f) return false;
                f.Hsv(x, y, out float h, out float sat, out float val);
                float d = Mathf.Abs(h - veilHue);
                return Mathf.Min(d, 360f - d) <= 25f && sat >= 0.08f && sat <= 0.45f && val >= 0.55f;
            });
            int veilHits = 0, veilSamples = 0;
            for (int k = 0; k < 40; k++)
            {
                float t = (k + 0.5f) / 40f;
                Vector2 p = k < 10 ? v.Position + new Vector2(v.Size.X * t * 4f, 0f)
                    : k < 20 ? v.Position + new Vector2(v.Size.X, v.Size.Y * (t * 4f - 1f))
                    : k < 30 ? v.End - new Vector2(v.Size.X * (t * 4f - 2f), 0f)
                    : v.Position + new Vector2(0f, v.Size.Y * (4f - t * 4f));
                Vector2 s = xf * p;
                if (labelScreen.Grow(2f).HasPoint(s)) continue;   // the label's box covers the ring there
                veilSamples++;
                bool hit = false;
                for (int d = -1; d <= 1 && !hit; d++)
                    for (int e = -1; e <= 1 && !hit; e++)
                        hit = f.Luma((int)s.X + d, (int)s.Y + e) > 150;
                if (hit) veilHits++;
            }
            Rect2 cur = ToScreen(xf, L.CellRect(run.Sector).Grow(3f));
            int frame = 0, frameSamples = 0;
            for (int x = (int)cur.Position.X; x < (int)cur.End.X; x += 2)
            {
                frameSamples += 2;
                if (f.MinChannel(x, (int)cur.Position.Y) > 200 || f.MinChannel(x, (int)cur.Position.Y + 1) > 200) frame++;
                if (f.MinChannel(x, (int)cur.End.Y) > 200 || f.MinChannel(x, (int)cur.End.Y - 1) > 200) frame++;
            }
            lines.Add("measure: mapVeil ringHits=" + veilHits + "/" + veilSamples + " thresholdLabelPx=" + labelPx +
                      " currentFrame=" + frame + "/" + frameSamples +
                      " ok=" + (veilSamples >= 30 && veilHits >= veilSamples * 0.85f && labelPx >= 60 && frame >= frameSamples * 0.8f ? 1 : 0));
            return lines;
        }

        private List<string> MeasureMapAfter(Frame f, GameController gc, Hud hud)
        {
            var lines = new List<string>();
            Game game = gc.Game;
            MapView map = hud.FullMap;
            MapLayout L = map.Layout;
            Transform2D xf = map.GetGlobalTransformWithCanvas();
            float gateHue = HueOf(Palette.StrokeOf(Palette.RoleOf(game.World[Gate].Owner)));
            float blueHue = HueOf(Palette.StrokeOf(ColorRole.PlayerBlue));
            Rect2 glyph = ToScreen(xf, L.GlyphRect(Gate));
            int red = Count(f, glyph, (x, y) => HueNear(f, x, y, gateHue, 20f));
            int blue = Count(f, glyph, (x, y) => HueNear(f, x, y, blueHue, 15f, 0.4f, 0.5f));
            int jump = Count(f, ToScreen(xf, L.LabelRect(Gate)), (x, y) => HueNear(f, x, y, blueHue, 20f, 0.35f, 0.35f));
            // The differential: the same rect lit red before the gate fell and holds none now.
            bool ok = red <= 5 && blue >= 40 && jump >= 25 && _gateRedBefore >= 40;
            lines.Add("measure: mapCheckpoint padlockPxBefore=" + _gateRedBefore + " padlockPxAfter=" + red + " diamondPx=" + blue +
                      " jumpCaptionPx=" + jump + " ok=" + (ok ? 1 : 0));
            return lines;
        }

        private List<string> MeasureApproach(Frame f, Transform2D canvas, GameController gc, Hud hud, ArenaView view)
        {
            var lines = new List<string>();
            Game game = gc.Game;
            Run run = game.Run;
            // The warning says what the gate does, in words, before the player is inside.
            string text = hud.WarningText;
            Label w = hud.WarningLabel;
            Rect2 wr = ToScreen(w.GetGlobalTransformWithCanvas(), new Rect2(Vector2.Zero, w.Size));
            float fireHue = HueOf(Palette.StrokeOf(ColorRole.FireRed));
            int warnPx = Count(f, wr, (x, y) => HueNear(f, x, y, fireHue, 20f, 0.35f, 0.4f));
            bool warnOk = text.Contains("LOCKS EVERY EXIT") && text.Contains("NEEDS") && warnPx >= 300 && run.Sector != Gate;
            lines.Add("measure: gateWarning inside=" + (run.Sector == Gate ? 1 : 0) + " textPx=" + warnPx + " says=\"" + text.Replace("\n", " / ") + "\" ok=" + (warnOk ? 1 : 0));

            // The gate edge: a dashed band in the gatekeeper's colour, lit and gapped along its length.
            var (a, b) = EdgeBarriers.Segment(run.Arena, Edge.East, 0f);
            var (color, widthPx, dashed, _) = EdgeBarriers.StyleOf(run, Edge.East);
            float hue = HueOf(color);
            int lit = 0, gap = 0, samples = 0;
            for (float yy = 0f; yy < run.Arena.Height; yy += 4f)
            {
                Vector2 s = canvas * new Vector2(a.X - widthPx / 2f / view.Zoom, yy);
                if (s.Y < 4f || s.Y > f.H - 4f || s.X < 0f || s.X >= f.W) continue;
                samples++;
                if (HueNear(f, (int)s.X, (int)s.Y, hue, 20f, 0.35f, 0.25f) || HueNear(f, (int)s.X - 1, (int)s.Y, hue, 20f, 0.35f, 0.25f)) lit++;
                else gap++;
            }
            float litFrac = samples > 0 ? lit / (float)samples : 0f;
            bool edgeOk = dashed && samples >= 40 && litFrac >= 0.4f && litFrac <= 0.85f;
            lines.Add("measure: gateEdge dashed=" + (dashed ? 1 : 0) + " samples=" + samples + " litFrac=" + litFrac.ToString("F2") + " ok=" + (edgeOk ? 1 : 0));

            // And the minimap marks the gate as a lock-in too.
            // Counted outside the "+N" label's rect, and the layout must keep the two apart at all.
            MapView mini = hud.Minimap;
            Transform2D mxf = mini.GetGlobalTransformWithCanvas();
            Rect2 g = ToScreen(mxf, mini.Layout.GlyphRect(Gate));
            Rect2 radRect = ToScreen(mxf, mini.Layout.RadiationRect(Gate));
            int pad = Count(f, g, (x, y) => !radRect.HasPoint(new Vector2(x, y)) && HueNear(f, x, y, hue, 20f));
            int radPx = Count(f, radRect, (x, y) => HueNear(f, x, y, hue, 25f, 0.35f, 0.35f));
            bool apart = mini.Layout.GlyphClearOfRadiation(Gate) && hud.FullMap.Layout.GlyphClearOfRadiation(Gate);
            lines.Add("measure: minimapGate padlockPx=" + pad + " radiationLabelPx=" + radPx + " apart=" + (apart ? 1 : 0) +
                      " ok=" + (pad >= 12 && radPx >= 6 && apart ? 1 : 0));
            return lines;
        }

        private List<string> MeasureGate(Frame f, Transform2D canvas, GameController gc, Hud hud, ArenaView view)
        {
            var lines = new List<string>();
            Game game = gc.Game;
            Run run = game.Run;
            Arena arena = run.Arena;
            Ship k = arena.Gatekeeper;
            float keeperHue = HueOf(Palette.StrokeOf(Palette.RoleOf(run.CurrentSector.Owner)));

            // Locked in: the west edge (on screen) is a solid band in the gatekeeper's colour.
            var (color, widthPx, dashed, locks) = EdgeBarriers.StyleOf(run, Edge.West);
            int lit = 0, samples = 0;
            for (float yy = 0f; yy < arena.Height; yy += 6f)
            {
                Vector2 s = canvas * new Vector2(widthPx / 2f / view.Zoom, yy);
                if (s.Y < 4f || s.Y > f.H - 4f) continue;
                samples++;
                if (HueNear(f, (int)s.X, (int)s.Y, keeperHue, 20f, 0.4f, 0.4f) || HueNear(f, (int)s.X + 1, (int)s.Y, keeperHue, 20f, 0.4f, 0.4f)) lit++;
            }
            bool barrierOk = run.LockedIn && !dashed && locks && samples >= 40 && lit >= samples * 0.9f;
            lines.Add("measure: lockedBarrier lockedIn=" + (run.LockedIn ? 1 : 0) + " samples=" + samples + " lit=" + lit + " ok=" + (barrierOk ? 1 : 0));

            // The rival's aim line, sampled along the segment the view says it drew.
            Vector2 a = Vector2.Zero, b = Vector2.Zero;
            bool shown = k != null && AimLines.LineOf(k, arena, gc.Alpha, out a, out b);
            int onLine = 0, lineSamples = 0;
            if (shown)
            {
                for (int i = 2; i < 18; i++)
                {
                    Vector2 p = canvas * a.Lerp(b, i / 20f);
                    if (!f.InBounds((int)p.X, (int)p.Y)) continue;
                    lineSamples++;
                    bool hit = false;
                    for (int d = -1; d <= 1 && !hit; d++)
                        for (int e = -1; e <= 1 && !hit; e++)
                            hit = HueNear(f, (int)p.X + d, (int)p.Y + e, keeperHue, 25f, 0.35f, 0.3f);
                    if (hit) onLine++;
                }
            }
            bool aimOk = shown && lineSamples >= 10 && onLine >= lineSamples * 0.8f;
            lines.Add("measure: aimLine shown=" + (shown ? 1 : 0) + " ticksLeft=" + (k != null ? k.AimLineUntil - arena.Tick : -1) +
                      " onLine=" + onLine + "/" + lineSamples + " ok=" + (aimOk ? 1 : 0));

            // The gatekeeper's bar at the top of the HUD.
            Rect2 bar = Hud.BossBarRect(f.W > 0 ? new Vector2(f.W, f.H) : Vector2.Zero);
            float frac = k != null ? k.Hp / k.MaxHp : 0f;
            Rect2 filled = new Rect2(bar.Position, new Vector2(bar.Size.X * frac, bar.Size.Y));
            int barPx = Count(f, filled, (x, y) => HueNear(f, x, y, keeperHue, 20f));
            float area = filled.Size.X * filled.Size.Y;
            lines.Add("measure: bossBar hpFrac=" + frac.ToString("F2") + " px=" + barPx + " area=" + area.ToString("F0") +
                      " ok=" + (k != null && k.Alive && barPx >= area * 0.8f ? 1 : 0));
            return lines;
        }
    }
}
