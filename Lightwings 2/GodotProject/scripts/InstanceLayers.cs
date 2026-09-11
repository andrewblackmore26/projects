using System;
using Godot;
using Lightship.Core.Ships;
using Lightship.Core.Sim;

namespace Lightship.View
{
    /// <summary>
    /// Shared MultiMesh plumbing: one unit quad (-1..1, UV 0..1), Transform2D
    /// instances with custom data and no instance colour. Buffer layout per
    /// instance (Godot 4 2D): 8 transform floats in two rows
    /// [x.x, y.x, 0, origin.x, x.y, y.y, 0, origin.y] then 4 custom floats.
    /// The first capture after any change here must pass the bullet probe in
    /// PlayProbe, which checks that a bullet lights exactly the pixel it should.
    /// </summary>
    public abstract partial class InstanceLayer : MultiMeshInstance2D
    {
        public const int Stride = 12;
        protected MultiMesh Mm;
        protected float[] Buf;
        public int InstanceCountDrawn { get; protected set; }

        private static ArrayMesh _quad;

        public static ArrayMesh UnitQuad()
        {
            if (_quad != null) return _quad;
            var arrays = new Godot.Collections.Array();
            arrays.Resize((int)Mesh.ArrayType.Max);
            arrays[(int)Mesh.ArrayType.Vertex] = new[] { new Vector2(-1, -1), new Vector2(1, -1), new Vector2(1, 1), new Vector2(-1, 1) };
            arrays[(int)Mesh.ArrayType.TexUV] = new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
            arrays[(int)Mesh.ArrayType.Index] = new[] { 0, 1, 2, 0, 2, 3 };
            _quad = new ArrayMesh();
            _quad.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays);
            return _quad;
        }

        protected void Init(int capacity, Shader shader)
        {
            Mm = new MultiMesh
            {
                TransformFormat = MultiMesh.TransformFormatEnum.Transform2D,
                UseColors = false,
                UseCustomData = true,
                Mesh = UnitQuad(),
                InstanceCount = capacity,
                VisibleInstanceCount = 0,
            };
            Multimesh = Mm;
            Buf = new float[capacity * Stride];
            var mat = new ShaderMaterial { Shader = shader };
            mat.SetShaderParameter("stroke_colors", Palette.Stroke);
            mat.SetShaderParameter("light_colors", Palette.Light);
            Material = mat;
        }

        protected static void Put(float[] buf, int k, float x, float y, float dirX, float dirY, float scale,
            float c0, float c1, float c2, float c3)
        {
            // Basis: x axis = (dirY', -dirX')... expressed so local -Y (forward) maps onto dir.
            // Local forward (0,-1) must land on (dirX, dirY): x axis = (-dirY, dirX), y axis = (-dirX, -dirY).
            float xx = -dirY * scale, xy = dirX * scale;
            float yx = -dirX * scale, yy = -dirY * scale;
            int o = k * Stride;
            buf[o] = xx; buf[o + 1] = yx; buf[o + 2] = 0f; buf[o + 3] = x;
            buf[o + 4] = xy; buf[o + 5] = yy; buf[o + 6] = 0f; buf[o + 7] = y;
            buf[o + 8] = c0; buf[o + 9] = c1; buf[o + 10] = c2; buf[o + 11] = c3;
        }

        protected void Commit(int count)
        {
            InstanceCountDrawn = count;
            Mm.Buffer = Buf;
            Mm.VisibleInstanceCount = count;
        }

        public ShaderMaterial ShaderMat => (ShaderMaterial)Material;
    }

    /// <summary>One faction's bullets: the player's under the enemies' (spec 9, 15).</summary>
    public partial class BulletLayer : InstanceLayer
    {
        private Faction _faction;
        public const float QuadScale = 1.6f;   // quad half-size over the collision radius

        public void Setup(int capacity, Faction faction, int zIndex)
        {
            _faction = faction;
            ZIndex = zIndex;
            Init(capacity, GD.Load<Shader>("res://shaders/bullet.gdshader"));
            ShaderMat.SetShaderParameter("emission", Palette.BulletEmission);
        }

        public void Sync(BulletPool b, float alpha, float dt)
        {
            int k = 0;
            bool player = _faction == Faction.Player;
            for (int i = 0; i < b.High; i++)
            {
                if (!b.Alive[i]) continue;
                if ((b.Owner[i] == (byte)Faction.Player) != player) continue;
                float vx = b.VX[i], vy = b.VY[i];
                float len = MathF.Sqrt(vx * vx + vy * vy);
                float dx = len > 1e-3f ? vx / len : 0f, dy = len > 1e-3f ? vy / len : -1f;
                ColorRole role = player ? ColorRole.PlayerBlue : Palette.RoleOf((Element)b.Elem[i]);
                Put(Buf, k++, b.X[i] + vx * alpha * dt, b.Y[i] + vy * alpha * dt, dx, dy, b.Radius[i] * QuadScale,
                    b.Shape[i], (float)role, 0f, 0f);
            }
            Commit(k);
        }
    }

    /// <summary>Light pickups: hollow shapes with running lights, under everything else.</summary>
    public partial class PickupLayer : InstanceLayer
    {
        public static readonly float[] SizeScale = { 5f, 7f, 9.5f };   // quad half-size in world units, by pickup size

        public void Setup(int capacity, int zIndex)
        {
            ZIndex = zIndex;
            Init(capacity, GD.Load<Shader>("res://shaders/pickup.gdshader"));
            ShaderMat.SetShaderParameter("stroke_level", Palette.PickupStrokeLevel);
            ShaderMat.SetShaderParameter("light_emission", Palette.LightEmission);
        }

        public void SetTime(float t) => ShaderMat.SetShaderParameter("sim_time", t);

        public static float ShapeOf(Element e)
        {
            switch (e)
            {
                case Element.Fire: return 1f;
                case Element.Lightning: return 2f;
                case Element.Void: return 3f;
                default: return 0f;
            }
        }

        public void Sync(PickupPool p, float alpha, float dt)
        {
            int k = 0;
            for (int i = 0; i < p.High; i++)
            {
                if (!p.Alive[i]) continue;
                var e = (Element)p.Elem[i];
                Put(Buf, k++, p.X[i] + p.VX[i] * alpha * dt, p.Y[i] + p.VY[i] * alpha * dt, 0f, -1f, SizeScale[p.Size[i]],
                    ShapeOf(e), (float)Palette.RoleOf(e), p.PeriodIndex[i], p.PhaseIndex[i]);
            }
            Commit(k);
        }
    }
}
