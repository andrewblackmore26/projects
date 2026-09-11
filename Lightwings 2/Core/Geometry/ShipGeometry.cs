using System;
using System.Collections.Generic;
using Lightship.Core.Ships;

namespace Lightship.Core.Geometry
{
    /// <summary>
    /// A resolved ship turned into part geometry in painter's order (spec 11.2:
    /// reference rings, tethers, outer parts, body, components; the core is
    /// drawn last by the mesh builder). Footprint and bounding radius come from
    /// here, so the tier sizes in the spec are testable numbers.
    /// </summary>
    public sealed class ShipGeometry
    {
        public readonly List<PartGeometry> Parts = new List<PartGeometry>();
        public float CoreRadius;
        public ColorRole CoreRole;
        public Vec2 Min, Max;
        /// <summary>Radius around the ship origin containing every part: the broad-phase circle.</summary>
        public float BoundRadius;

        public float Width => Max.X - Min.X;
        public float Height => Max.Y - Min.Y;
        /// <summary>The larger of width and height: what the footprint numbers in the spec mean.</summary>
        public float Footprint => MathF.Max(Width, Height);

        /// <summary>Threshold below which a tweened part is not drawn at all.</summary>
        public const float MinExtent = 0.05f;

        public static PartLayer LayerOf(PartDefinition p)
        {
            if (p.Layer.HasValue) return p.Layer.Value;
            if (p.IsTether) return PartLayer.Tether;
            if (p.Dashed) return PartLayer.Ring;
            if (!string.IsNullOrEmpty(p.Component)) return PartLayer.Component;
            return PartLayer.Body;
        }

        public static ShipGeometry Build(ResolvedShip ship)
        {
            var g = new ShipGeometry { CoreRadius = ship.CoreRadius, CoreRole = ship.CoreRole };

            // Stable sort by layer: JSON order is kept within a layer.
            var order = new List<int>(ship.Parts.Count);
            for (int i = 0; i < ship.Parts.Count; i++) order.Add(i);
            order.Sort((a, b) =>
            {
                int la = (int)LayerOf(ship.Parts[a]), lb = (int)LayerOf(ship.Parts[b]);
                return la != lb ? la.CompareTo(lb) : a.CompareTo(b);
            });

            foreach (int i in order)
            {
                PartDefinition p = ship.Parts[i];
                PartGeometry pg = p.IsTether ? BuildTether(p, ship) : BuildShape(p);
                if (pg != null) g.Parts.Add(pg);
            }

            g.Min = new Vec2(-ship.CoreRadius, -ship.CoreRadius);
            g.Max = new Vec2(ship.CoreRadius, ship.CoreRadius);
            g.BoundRadius = ship.CoreRadius;
            foreach (PartGeometry pg in g.Parts)
            {
                g.Min = new Vec2(MathF.Min(g.Min.X, pg.Min.X), MathF.Min(g.Min.Y, pg.Min.Y));
                g.Max = new Vec2(MathF.Max(g.Max.X, pg.Max.X), MathF.Max(g.Max.Y, pg.Max.Y));
                g.BoundRadius = MathF.Max(g.BoundRadius, pg.Centre.Length() + pg.BoundRadius);
            }
            return g;
        }

        public PartGeometry Find(string id)
        {
            for (int i = 0; i < Parts.Count; i++) if (Parts[i].Id == id) return Parts[i];
            return null;
        }

        /// <summary>Any part polygon contains the ship-local point (enemy body versus player core).</summary>
        public bool ContainsPoint(Vec2 local)
        {
            for (int i = 0; i < Parts.Count; i++) if (Parts[i].ContainsPoint(local)) return true;
            return false;
        }

        private static PartGeometry BuildShape(PartDefinition p)
        {
            if (ShapeParams.Extent(p) < MinExtent) return null;

            Vec2[] local;
            Vec2[] localInner = null;
            switch (p.Shape)
            {
                case Shape.Circle: local = Outline.Circle(p.Param("radius")); break;
                case Shape.Ellipse: local = Outline.Ellipse(p.Param("rx"), p.Param("ry")); break;
                case Shape.Triangle: local = Outline.Triangle(p.Param("base"), p.Param("height")); break;
                case Shape.Prong: local = Outline.Prong(p.Param("base"), p.Param("length")); break;
                case Shape.Diamond: local = Outline.Diamond(p.Param("width"), p.Param("height")); break;
                case Shape.Chevron: local = Outline.Chevron(p.Param("width"), p.Param("height"), p.Param("notch")); break;
                case Shape.Hexagon: local = Outline.Hexagon(p.Param("radius")); break;
                case Shape.Crescent:
                    local = Outline.Crescent(p.Param("radius"), p.Param("cut_radius"), p.Param("cut_dx"), p.Param("cut_dy"));
                    break;
                case Shape.Arc:
                    local = Outline.Arc(p.Param("radius"), p.Param("thickness"), p.Param("start_deg"), p.Param("sweep_deg"));
                    break;
                case Shape.Ring:
                    Outline.Ring(p.Param("radius"), p.Param("thickness"), out local, out localInner);
                    break;
                default:
                    throw new ArgumentException("part " + p.Id + ": unsupported shape " + p.Shape);
            }

            float rot = Outline.Rad(p.RotDeg);
            var pg = new PartGeometry
            {
                Id = p.Id, Layer = LayerOf(p), Role = p.Color, IsTether = false, Dashed = p.Dashed,
                PeriodIndex = p.PeriodIndex, PhaseIndex = p.PhaseIndex, Component = p.Component,
                Outline = Transform(local, rot, p.Pos), Centre = p.Pos,
            };
            if (localInner != null) pg.InnerOutline = Transform(localInner, rot, p.Pos);
            pg.ComputeUAndPerimeter();
            if (pg.InnerOutline != null) pg.InnerPerimeter = Outline.Length(pg.InnerOutline, true);

            if (!p.Dashed)
            {
                if (pg.InnerOutline != null)
                {
                    int n = pg.Outline.Length;
                    var pts = new Vec2[2 * n];
                    Array.Copy(pg.Outline, 0, pts, 0, n);
                    Array.Copy(pg.InnerOutline, 0, pts, n, n);
                    var idx = new int[6 * n];
                    for (int k = 0; k < n; k++)
                    {
                        int o0 = k, o1 = (k + 1) % n, i0 = n + k, i1 = n + (k + 1) % n;
                        idx[6 * k] = o0; idx[6 * k + 1] = o1; idx[6 * k + 2] = i0;
                        idx[6 * k + 3] = i0; idx[6 * k + 4] = o1; idx[6 * k + 5] = i1;
                    }
                    pg.FillPoints = pts;
                    pg.FillIndices = idx;
                }
                else
                {
                    pg.FillPoints = pg.Outline;
                    pg.FillIndices = Triangulator.EarClip(pg.Outline);
                }
            }

            pg.Area = MathF.Abs(Outline.SignedArea(pg.Outline));
            if (pg.InnerOutline != null) pg.Area -= MathF.Abs(Outline.SignedArea(pg.InnerOutline));
            pg.ComputeBounds();
            return pg;
        }

        private static PartGeometry BuildTether(PartDefinition p, ResolvedShip ship)
        {
            PartDefinition a = ship.FindPart(p.From), b = ship.FindPart(p.To);
            if (a == null || b == null) return null;                 // an endpoint tweened away
            if (Vec2.Distance(a.Pos, b.Pos) < MinExtent) return null;
            var pg = new PartGeometry
            {
                Id = p.Id, Layer = LayerOf(p), Role = p.Color, IsTether = true, Dashed = false,
                PeriodIndex = p.PeriodIndex, PhaseIndex = p.PhaseIndex, Component = p.Component,
                Outline = new[] { a.Pos, b.Pos }, Centre = Vec2.Lerp(a.Pos, b.Pos, 0.5f),
            };
            pg.ComputeUAndPerimeter();
            pg.ComputeBounds();
            return pg;
        }

        private static Vec2[] Transform(Vec2[] local, float rot, Vec2 pos)
        {
            var outPts = new Vec2[local.Length];
            for (int i = 0; i < local.Length; i++) outPts[i] = local[i].Rotated(rot) + pos;
            return outPts;
        }
    }
}
