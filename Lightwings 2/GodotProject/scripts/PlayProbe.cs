using System;
using System.Collections.Generic;
using Godot;
using Lightship.Core;
using Lightship.Core.Sim;

namespace Lightship.View
{
    /// <summary>
    /// Measurements of a captured play frame. Three probes are planted just
    /// before the frame is drawn, in empty space left of and above the player:
    ///   A: an enemy fire bullet exactly on top of a player bullet (draw order:
    ///      spec 15 puts enemy bullets above player bullets, so A must read red);
    ///   B: a lone enemy fire bullet (proves the MultiMesh transform layout puts
    ///      a bullet on exactly its pixel, with playfield a few px beyond it);
    ///   C: a lone fire pickup (hollow: its centre must be playfield, its rim lit).
    /// Then light-blue containment: light blue may appear only on the player's
    /// ship and the player's own bullets (spec 2.5, 11.11).
    /// </summary>
    public sealed class PlayProbe
    {
        private Vec2 _a, _b, _c;
        private int _playerBulletA;
        public bool Planted { get; private set; }

        public void Plant(Arena arena)
        {
            Vec2 p = arena.Player.Pos;
            _a = new Vec2(p.X - 90f, p.Y - 70f);
            _b = new Vec2(p.X + 90f, p.Y - 70f);
            _c = new Vec2(p.X, p.Y - 110f);
            // Clear anything near the probe points so they measure only themselves.
            foreach (Vec2 q in new[] { _a, _b, _c })
            {
                for (int i = 0; i < arena.Bullets.High; i++)
                    if (arena.Bullets.Alive[i] && Vec2.Distance(new Vec2(arena.Bullets.X[i], arena.Bullets.Y[i]), q) < 40f) arena.Bullets.Free(i);
                for (int i = 0; i < arena.Pickups.High; i++)
                    if (arena.Pickups.Alive[i] && Vec2.Distance(new Vec2(arena.Pickups.X[i], arena.Pickups.Y[i]), q) < 40f) arena.Pickups.Free(i);
            }
            // Same shape (circle) and radius for both, so the only thing that decides the colour is draw order.
            _playerBulletA = arena.SpawnBullet(Faction.Player, Lightship.Core.Ships.Element.None, _a, new Vec2(0f, -0.001f), 3f, 0f, 600);
            arena.SpawnBullet(Faction.Enemy, Lightship.Core.Ships.Element.Corruption, _a, new Vec2(0f, -0.001f), 3f, 0f, 600);
            arena.SpawnBullet(Faction.Enemy, Lightship.Core.Ships.Element.Fire, _b, new Vec2(0f, -0.001f), 3f, 0f, 600);
            int pk = arena.SpawnPickup(Lightship.Core.Ships.Element.Fire, 2, _c, false);
            if (pk >= 0) { arena.Pickups.VX[pk] = 0f; arena.Pickups.VY[pk] = 0f; arena.Pickups.DriftX[pk] = 0f; arena.Pickups.DriftY[pk] = 0f; }
            Planted = true;
        }

        private static Vector2I ToScreen(Transform2D canvas, Vec2 w)
        {
            Vector2 s = canvas * new Vector2(w.X, w.Y);
            return new Vector2I(Mathf.RoundToInt(s.X), Mathf.RoundToInt(s.Y));
        }

        public List<string> Measure(Frame f, Transform2D canvas, Game game, ArenaView view, float zoom)
        {
            var lines = new List<string>();
            Arena arena = game.Arena;
            Vector2I a = ToScreen(canvas, _a), b = ToScreen(canvas, _b), c = ToScreen(canvas, _c);

            // A: draw order. A corruption bullet sits exactly on a player bullet of the same
            // shape and size; the enemy's must be on top, so the rim reads green and never blue.
            // (The centre clips to near-white for every element, so it says nothing.)
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
            bool aRed = green >= 4 && blue == 0;
            lines.Add("measure: drawOrder at=" + a + " rimGreen=" + green + "/16 rimBlue=" + blue + "/16 ok=" + (aRed ? 1 : 0));

            // B: transform layout. Bright on the bullet, playfield 16 px away on all four sides.
            double onB = f.Luma(b.X, b.Y);
            double offB = Math.Max(Math.Max(f.Luma(b.X + 16, b.Y), f.Luma(b.X - 16, b.Y)), Math.Max(f.Luma(b.X, b.Y + 16), f.Luma(b.X, b.Y - 16)));
            double bg = f.Luma(6, 6);
            bool bOk = onB > 120 && offB < bg + 20;
            lines.Add("measure: bulletProbe at=" + b + " rgb=" + f.Rgb(b.X, b.Y) + " luma=" + onB.ToString("F0") +
                      " off16=" + offB.ToString("F0") + " bg=" + bg.ToString("F0") + " ok=" + (bOk ? 1 : 0));

            // C: hollow pickup. Centre is playfield-dark; somewhere on its rim is lit.
            double centre = f.Luma(c.X, c.Y);
            float rimR = PickupLayer.SizeScale[2] * 0.72f * zoom;
            double rimMax = 0;
            for (int k = 0; k < 64; k++)
            {
                float ang = Mathf.Tau * k / 64f;
                int x = c.X + Mathf.RoundToInt(Mathf.Cos(ang) * rimR), y = c.Y + Mathf.RoundToInt(Mathf.Sin(ang) * rimR);
                if (f.InBounds(x, y)) rimMax = Math.Max(rimMax, f.Luma(x, y));
            }
            bool cOk = centre < bg + 25 && rimMax > 80;
            lines.Add("measure: pickupProbe at=" + c + " centreLuma=" + centre.ToString("F0") + " rimMaxLuma=" + rimMax.ToString("F0") + " ok=" + (cOk ? 1 : 0));

            // Light-blue containment: player ship box, or within 10 px of a live player bullet.
            var allowed = new List<Vector2I>();
            for (int i = 0; i < arena.Bullets.High; i++)
                if (arena.Bullets.Alive[i] && arena.Bullets.Owner[i] == (byte)Faction.Player)
                    allowed.Add(ToScreen(canvas, new Vec2(arena.Bullets.X[i], arena.Bullets.Y[i])));
            Vector2I ps = ToScreen(canvas, arena.Player.Pos);
            float boxR = arena.Player.BoundRadius * 1.06f * zoom + SheetLayout.Inflate;
            int blueOutside = 0, bluePixels = 0;
            for (int y = 0; y < f.H; y++)
                for (int x = 0; x < f.W; x++)
                {
                    if (f.MinChannel(x, y) > 200) continue;
                    f.Hsv(x, y, out float hue, out float sat, out float val);
                    if (hue < 190f || hue > 210f || sat < 0.25f || val < 0.5f) continue;
                    bluePixels++;
                    if (Math.Abs(x - ps.X) <= boxR && Math.Abs(y - ps.Y) <= boxR) continue;
                    bool nearBullet = false;
                    foreach (Vector2I q in allowed)
                        if (Math.Abs(q.X - x) <= 10 && Math.Abs(q.Y - y) <= 10) { nearBullet = true; break; }
                    if (!nearBullet) blueOutside++;
                }
            lines.Add("measure: play tick=" + arena.Tick + " tier=" + game.Run.Tier + " energy=" + game.Run.Energy.ToString("F0") +
                      " enemies=" + arena.AliveEnemies() + " bullets=" + arena.Bullets.Live + " pickups=" + arena.Pickups.Live +
                      " zoom=" + zoom.ToString("F3") + " bluePixels=" + bluePixels + " lightBlueOutsidePlayer=" + blueOutside +
                      " probes=" + ((aRed ? 1 : 0) + (bOk ? 1 : 0) + (cOk ? 1 : 0)) + "/3");
            return lines;
        }
    }
}
