using System;
using System.Collections.Generic;
using Godot;
using Lightship.Core;
using Lightship.Core.Ships;
using Lightship.Core.Sim;

namespace Lightship.View
{
    /// <summary>
    /// Measurements of a captured play frame. Three probes are planted just
    /// before the frame is drawn, on the side of the player facing the arena
    /// interior (so they are always on screen):
    ///   A: a corruption bullet exactly on top of a player bullet of the same
    ///      shape and size (draw order: spec 15 puts enemy bullets above the
    ///      player's, so its rim must read green, never blue);
    ///   B: a lone fire bullet (the MultiMesh transform layout puts it on exactly
    ///      its pixel, with playfield 16 px beyond it);
    ///   C: a lone fire pickup (hollow: centre is playfield, the rim is lit).
    /// Then light-blue containment: light blue may appear only on the player's
    /// team (its ship and drones) and the player's own bullets (spec 2.5, 11.11).
    /// Positions are taken where they are DRAWN (the previous tick at alpha 0).
    /// </summary>
    public sealed class PlayProbe
    {
        private Vec2 _a, _b, _c;
        private Vec2 _riderOffset = new Vec2(0f, -40f);
        private float _playerSpeed;
        public bool Planted { get; private set; }

        /// <summary>
        /// D, the interpolation probe: a lightning bullet riding with the player at a fixed
        /// offset, same velocity. Ships lerp PrevPos to Pos; bullets draw at X + V (alpha - 1) dt.
        /// If the two schemes agree, D sits at exactly the offset on screen at any alpha; a
        /// bullet drawn one tick ahead would sit V dt further along (measured at alpha 0.5).
        /// </summary>
        public void PlantRider(Arena arena)
        {
            Ship p = arena.Player;
            // The probe needs motion to see a lead: if the player happens to be idle, give the
            // frozen frame a known velocity (the drawn player lerps PrevPos to Pos, the rider matches).
            // 200 u/s is a 2.7 px one-tick lead at the tier-3 zoom (0.81), over the 2 px sensitivity floor;
            // a slower real velocity (measured 130 u/s at 150 s of world play) gave an insensitive probe.
            if (p.Vel.Length() < 200f)
            {
                p.Vel = new Vec2(200f, 0f);
                p.PrevPos = p.Pos - p.Vel * arena.T.Dt;
            }
            _playerSpeed = p.Vel.Length();
            // Clear of the ship's own parts: Scorch's yellow crown embers sat inside the search
            // window at a fixed 40-unit offset and pulled the rider's centroid a tick ahead.
            // Above the player, unless that would leave the arena (a world bot pushing out of a north edge).
            float side = p.Pos.Y > p.BoundRadius + 60f ? -1f : 1f;
            _riderOffset = new Vec2(0f, side * (p.BoundRadius + 30f));
            Vec2 at = p.Pos + _riderOffset;
            for (int i = 0; i < arena.Bullets.High; i++)
                if (arena.Bullets.Alive[i] && Vec2.Distance(new Vec2(arena.Bullets.X[i], arena.Bullets.Y[i]), at) < 30f) arena.Bullets.Free(i);
            arena.SpawnBullet(Sides.Of(Faction.Enemy, Element.Lightning), Element.Lightning, at, p.Vel, 3f, 0f, 600);
        }

        public string MeasureRider(Frame f, Transform2D canvas, Arena arena, float zoom, float alpha, float dt)
        {
            Ship p = arena.Player;
            Vec2 drawn = Vec2.Lerp(p.PrevPos, p.Pos, alpha);
            Vector2I expected = ToScreen(canvas, drawn + _riderOffset);
            Vector2I ship = ToScreen(canvas, drawn);
            float shipPx = (p.BoundRadius + 4f) * zoom;
            double sx = 0, sy = 0, n = 0;
            for (int y = expected.Y - 12; y <= expected.Y + 12; y++)
                for (int x = expected.X - 12; x <= expected.X + 12; x++)
                {
                    if ((x - ship.X) * (x - ship.X) + (y - ship.Y) * (y - ship.Y) <= shipPx * shipPx) continue;   // the ship's own pixels
                    f.Hsv(x, y, out float h, out float sat, out float val);
                    if (h < 35f || h > 60f || sat < 0.4f || val < 0.5f) continue;   // lightning yellow
                    sx += x; sy += y; n++;
                }
            float lead = _playerSpeed * dt * zoom;   // what a one-tick lead would look like, px
            if (n < 3) return "measure: interp alpha=" + alpha.ToString("F2") + " riderPixels=0 ok=0";
            double ex = sx / n - expected.X, ey = sy / n - expected.Y;
            double err = Math.Sqrt(ex * ex + ey * ey);
            bool sensitive = lead >= 2f;
            bool ok = err <= 1.5 && sensitive;   // an insensitive probe proves nothing, so it does not pass
            return "measure: interp alpha=" + alpha.ToString("F2") + " riderErrPx=" + err.ToString("F2") +
                   " oneTickLeadPx=" + lead.ToString("F2") + " sensitive=" + (sensitive ? 1 : 0) + " ok=" + (ok ? 1 : 0);
        }

        public void Plant(Arena arena)
        {
            Vec2 p = arena.Player.Pos;
            float sy = p.Y > 260f ? -1f : 1f;                                  // above the player unless near the top wall
            float cx = Math.Clamp(p.X, 160f, arena.Width - 160f);              // keep both sides on screen near a side wall
            _a = new Vec2(cx - 90f, p.Y + sy * 70f);
            _b = new Vec2(cx + 90f, p.Y + sy * 70f);
            _c = new Vec2(cx, p.Y + sy * 115f);
            // Clear anything near the probe points so they measure only themselves.
            foreach (Vec2 q in new[] { _a, _b, _c })
            {
                for (int i = 0; i < arena.Bullets.High; i++)
                    if (arena.Bullets.Alive[i] && Vec2.Distance(new Vec2(arena.Bullets.X[i], arena.Bullets.Y[i]), q) < 40f) arena.Bullets.Free(i);
                for (int i = 0; i < arena.Pickups.High; i++)
                    if (arena.Pickups.Alive[i] && Vec2.Distance(new Vec2(arena.Pickups.X[i], arena.Pickups.Y[i]), q) < 40f) arena.Pickups.Free(i);
            }
            // Same shape (circle) and radius for both, so the only thing that decides the colour is draw order.
            Vec2 still = new Vec2(0f, -0.001f);
            arena.SpawnBullet(Sides.Player, Element.None, _a, still, 3f, 0f, 600);
            arena.SpawnBullet(Sides.Of(Faction.Enemy, Element.Corruption), Element.Corruption, _a, still, 3f, 0f, 600);
            arena.SpawnBullet(Sides.Of(Faction.Enemy, Element.Fire), Element.Fire, _b, still, 3f, 0f, 600);
            int pk = arena.SpawnPickup(Element.Fire, 2, _c, false);
            if (pk >= 0) { arena.Pickups.VX[pk] = 0f; arena.Pickups.VY[pk] = 0f; arena.Pickups.DriftX[pk] = 0f; arena.Pickups.DriftY[pk] = 0f; }
            Planted = true;
        }

        private static float DistanceToSegment(Vector2 p, Vector2 a, Vector2 b)
        {
            Vector2 ab = b - a;
            float t = ab.LengthSquared() > 1e-6f ? Mathf.Clamp((p - a).Dot(ab) / ab.LengthSquared(), 0f, 1f) : 0f;
            return p.DistanceTo(a + ab * t);
        }

        private static Vector2I ToScreen(Transform2D canvas, Vec2 w)
        {
            Vector2 s = canvas * new Vector2(w.X, w.Y);
            return new Vector2I(Mathf.RoundToInt(s.X), Mathf.RoundToInt(s.Y));
        }

        public List<string> Measure(Frame f, Transform2D canvas, Game game, ArenaView view, float zoom, float alpha)
        {
            var lines = new List<string>();
            Arena arena = game.Arena;
            float back = (alpha - 1f) * game.T.Dt;   // the drawn moment (see BulletLayer)
            Vector2I a = ToScreen(canvas, _a), b = ToScreen(canvas, _b), c = ToScreen(canvas, _c);
            bool onScreen = f.InBounds(a.X, a.Y) && f.InBounds(b.X, b.Y) && f.InBounds(c.X, c.Y);

            // A: draw order. The rim reads green (the enemy bullet on top) and never blue.
            int green = 0, blue = 0;
            float rimPx = 3f * BulletLayer.QuadScale * 0.8f * zoom * 0.75f;
            for (int k = 0; k < 16; k++)
            {
                float ang = Mathf.Tau * k / 16f;
                int x = a.X + Mathf.RoundToInt(Mathf.Cos(ang) * rimPx), y = a.Y + Mathf.RoundToInt(Mathf.Sin(ang) * rimPx);
                f.Hsv(x, y, out float h, out float sat, out float val);
                if (sat < 0.15f || val < 0.3f) continue;
                if (h >= 100f && h <= 160f) green++;
                if (h >= 185f && h <= 215f) blue++;
            }
            bool aOk = green >= 4 && blue == 0;
            lines.Add("measure: drawOrder at=" + a + " rimGreen=" + green + "/16 rimBlue=" + blue + "/16 ok=" + (aOk ? 1 : 0));

            // B: transform layout. Bright on the bullet, playfield 16 px away on all four sides.
            double onB = f.Luma(b.X, b.Y);
            double offB = Math.Max(Math.Max(f.Luma(b.X + 16, b.Y), f.Luma(b.X - 16, b.Y)), Math.Max(f.Luma(b.X, b.Y + 16), f.Luma(b.X, b.Y - 16)));
            double bg = f.Luma(6, 6);
            bool bOk = onB > 120 && offB < bg + 20;
            lines.Add("measure: bulletProbe at=" + b + " rgb=" + f.Rgb(b.X, b.Y) + " luma=" + onB.ToString("F0") +
                      " off16=" + offB.ToString("F0") + " bg=" + bg.ToString("F0") + " ok=" + (bOk ? 1 : 0));

            // C: hollow pickup. Centre is playfield-dark; its rim carries light.
            double centre = f.Luma(c.X, c.Y);
            float rimR = PickupLayer.SizeScale[2] * 0.72f * zoom;
            double rimMax = 0;
            for (int k = 0; k < 64; k++)
            {
                float ang = Mathf.Tau * k / 64f;
                int x = c.X + Mathf.RoundToInt(Mathf.Cos(ang) * rimR), y = c.Y + Mathf.RoundToInt(Mathf.Sin(ang) * rimR);
                rimMax = Math.Max(rimMax, f.Luma(x, y));
            }
            bool cOk = centre < bg + 25 && rimMax > 80;
            lines.Add("measure: pickupProbe at=" + c + " centreLuma=" + centre.ToString("F0") + " rimMaxLuma=" + rimMax.ToString("F0") + " ok=" + (cOk ? 1 : 0));

            // Light-blue containment: the player's team's ships (drawn at the lerped position) or its bullets.
            var boxes = new List<(Vector2I at, float r)>();
            foreach (Ship s in arena.Ships)
                if (s.Alive && s.Side == Sides.Player)
                    boxes.Add((ToScreen(canvas, Vec2.Lerp(s.PrevPos, s.Pos, alpha)), s.BoundRadius * 1.06f * zoom + SheetLayout.Inflate));
            var allowed = new List<Vector2I>();
            for (int i = 0; i < arena.Bullets.High; i++)
                if (arena.Bullets.Alive[i] && arena.Bullets.Side[i] == Sides.Player)
                    allowed.Add(ToScreen(canvas, new Vec2(arena.Bullets.X[i] + arena.Bullets.VX[i] * back, arena.Bullets.Y[i] + arena.Bullets.VY[i] * back)));
            // The world's edge bands into player territory are light blue by design (the player's land):
            // allowed where the drawing itself puts them (EdgeBarriers.Segment / StyleOf).
            var bands = new List<(Vector2 a, Vector2 b, float tol)>();
            if (game.World != null)
                foreach (Lightship.Core.World.Edge e in Lightship.Core.World.Edges.All)
                {
                    var (color, widthPx, _, _) = EdgeBarriers.StyleOf(game.Run, e);
                    Color pb = Palette.StrokeOf(ColorRole.PlayerBlue);
                    if (Mathf.Abs(color.R - pb.R) > 0.01f || Mathf.Abs(color.G - pb.G) > 0.01f || Mathf.Abs(color.B - pb.B) > 0.01f) continue;
                    var (sa, sb) = EdgeBarriers.Segment(arena, e, widthPx / 2f / zoom);
                    bands.Add((canvas * sa, canvas * sb, widthPx * 1.8f / 2f + 2f));
                }
            int blueOutside = 0, bluePixels = 0;
            for (int y = 0; y < f.H; y++)
                for (int x = 0; x < f.W; x++)
                {
                    if (f.MinChannel(x, y) > 200) continue;
                    f.Hsv(x, y, out float hue, out float sat, out float val);
                    if (hue < 190f || hue > 210f || sat < 0.25f || val < 0.5f) continue;
                    bluePixels++;
                    bool ok = false;
                    foreach (var (at, r) in boxes)
                        if (Math.Abs(x - at.X) <= r && Math.Abs(y - at.Y) <= r) { ok = true; break; }
                    if (!ok)
                        foreach (Vector2I q in allowed)
                            if (Math.Abs(q.X - x) <= 10 && Math.Abs(q.Y - y) <= 10) { ok = true; break; }
                    if (!ok)
                        foreach (var (ba, bb, tol) in bands)
                            if (DistanceToSegment(new Vector2(x, y), ba, bb) <= tol) { ok = true; break; }
                    if (!ok) blueOutside++;
                }
            lines.Add("measure: play tick=" + arena.Tick + " tier=" + game.Run.Tier + " energy=" + game.Run.Energy.ToString("F0") +
                      " enemies=" + arena.AliveEnemies() + " drones=" + arena.AliveDrones() + " bullets=" + arena.Bullets.Live +
                      " pickups=" + arena.Pickups.Live + " infectedMarkers=" + view.Fx.InfectedMarkers + " zoom=" + zoom.ToString("F3") +
                      " bluePixels=" + bluePixels + " lightBlueOutsidePlayer=" + blueOutside +
                      " probesOnScreen=" + (onScreen ? 1 : 0) + " probes=" + ((aOk ? 1 : 0) + (bOk ? 1 : 0) + (cOk ? 1 : 0)) + "/3" +
                      " ok=" + (onScreen && blueOutside == 0 ? 1 : 0));
            return lines;
        }

        /// <summary>
        /// Bright light-blue pixels in the player's box: the player's own strokes, which the
        /// lock pulse lifts above the bloom threshold on its bright step. Counting only the
        /// player's hue keeps passing pickups and bullets out of the comparison.
        /// </summary>
        public static int PlayerBrightPixels(Frame f, Transform2D canvas, Arena arena, float zoom, float alpha)
        {
            Ship p = arena.Player;
            Vector2I at = ToScreen(canvas, Vec2.Lerp(p.PrevPos, p.Pos, alpha));
            int r = (int)(p.BoundRadius * 1.1f * zoom) + 4;
            int n = 0;
            for (int y = at.Y - r; y <= at.Y + r; y++)
                for (int x = at.X - r; x <= at.X + r; x++)
                {
                    if (!f.InBounds(x, y)) continue;
                    f.Hsv(x, y, out float hue, out float sat, out float val);
                    if (hue >= 185f && hue <= 215f && sat > 0.2f && f.Luma(x, y) > 195) n++;
                }
            return n;
        }
    }
}
