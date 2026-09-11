using Godot;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;

namespace Lightship.View
{
    /// <summary>
    /// The only place Core mesh buffers meet Godot: MeshData in, ArrayMesh
    /// surface out, plus the one shared ShaderMaterial every ship draws with.
    /// </summary>
    public static class ShipMeshFactory
    {
        public static void Fill(ArrayMesh mesh, MeshData md)
        {
            mesh.ClearSurfaces();
            int n = md.VertexCount;
            if (n == 0 || md.IndexCount == 0) return;

            var verts = new Vector2[n];
            var uvs = new Vector2[n];
            // Packed per-vertex data travels in CUSTOM0 as plain floats: the vertex
            // COLOR channel is a colour to Godot and does not arrive as written
            // (measured: every role decoded to 0 through it), whereas a custom
            // float attribute has no colour semantics at all.
            var custom = new float[n * 4];
            for (int i = 0; i < n; i++)
            {
                verts[i] = new Vector2(md.Xy[i * 2], md.Xy[i * 2 + 1]);
                uvs[i] = new Vector2(md.Uv[i * 2], md.Uv[i * 2 + 1]);
                custom[i * 4] = md.Rgba[i * 4];                                  // role index
                custom[i * 4 + 1] = md.Rgba[i * 4 + 1];                          // flags
                custom[i * 4 + 2] = md.Rgba[i * 4 + 2] * 256 + md.Rgba[i * 4 + 3]; // perimeter px
                custom[i * 4 + 3] = 0f;
            }
            var indices = md.Indices.ToArray();

            var arrays = new Godot.Collections.Array();
            arrays.Resize((int)Mesh.ArrayType.Max);
            arrays[(int)Mesh.ArrayType.Vertex] = verts;
            arrays[(int)Mesh.ArrayType.TexUV] = uvs;
            arrays[(int)Mesh.ArrayType.Custom0] = custom;
            arrays[(int)Mesh.ArrayType.Index] = indices;
            var flags = (Mesh.ArrayFormat)((long)Mesh.ArrayCustomFormat.RgbaFloat << (int)Mesh.ArrayFormat.FormatCustom0Shift);
            mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays, null, null, flags);
        }

        /// <summary>The ship shader with the palette loaded, raw (no transfer).</summary>
        public static ShaderMaterial NewMaterial()
        {
            var mat = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/ship.gdshader") };
            mat.SetShaderParameter("stroke_colors", Palette.Stroke);
            mat.SetShaderParameter("fill_colors", Palette.Fill);
            mat.SetShaderParameter("light_colors", Palette.Light);
            mat.SetShaderParameter("light_emission", Palette.LightEmission);
            mat.SetShaderParameter("stroke_level", Palette.StrokeLevel);
            mat.SetShaderParameter("light_fraction", LightSegment.DefaultFraction);
            mat.SetShaderParameter("sim_time", 0f);
            return mat;
        }
    }
}
