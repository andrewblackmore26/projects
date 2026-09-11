using System.Text;
using Godot;

namespace Lightship.View
{
    /// <summary>
    /// The bloom instrument (--bg --emitter): flat emitter blocks and a size x
    /// emission ladder on an empty playfield. The luma measured beyond each
    /// emitter's edge IS the bloom; this is how Godot's built-in glow was shown
    /// to ignore everything under ~12 px (tasks/lessons.md). Kept in its own
    /// mode because a probe that overlaps the thing being measured lies.
    /// </summary>
    public static class Diagnostics
    {
        private static readonly int[] LadderSizes = { 3, 6, 8, 12, 16, 24 };
        private static readonly float[] LadderLevels = { 1.8f, 4f, 8f, 16f, 32f };
        private const int LadderX0 = 200, LadderY0 = 560, LadderDx = 120, LadderDy = 60;
        private static readonly int[] EdgeOffsets = { -4, 0, 2, 4, 8, 12, 16, 24, 32, 48 };

        public static void BuildEmitters(Node parent)
        {
            var shader = GD.Load<Shader>("res://shaders/emitter_probe.gdshader");
            ColorRect Block(Vector2 pos, Vector2 size, float level)
            {
                var r = new ColorRect { Position = pos, Size = size, MouseFilter = Control.MouseFilterEnum.Ignore };
                var m = new ShaderMaterial { Shader = shader };
                m.SetShaderParameter("level", level);
                r.Material = m;
                parent.AddChild(r);
                return r;
            }
            Block(new Vector2(1200, 100), new Vector2(200, 100), 1.8f);
            // A sub-threshold block: its buffer value says whether the output stage converts.
            Block(new Vector2(1200, 700), new Vector2(200, 100), 0.5f);
            for (int r = 0; r < LadderLevels.Length; r++)
                for (int c = 0; c < LadderSizes.Length; c++)
                {
                    int size = LadderSizes[c];
                    Block(new Vector2(LadderX0 + c * LadderDx - size / 2f, LadderY0 + r * LadderDy - size / 2f), new Vector2(size, size), LadderLevels[r]);
                }
        }

        public static void Measure(Frame frame)
        {
            var sb = new StringBuilder("measure: emitter edgeX=");
            foreach (int o in EdgeOffsets) sb.Append(frame.Luma(1400 + o, 150).ToString("F0")).Append(',');
            sb.Append(" edgeY=");
            foreach (int o in EdgeOffsets) sb.Append(frame.Luma(1300, 200 + o).ToString("F0")).Append(',');
            sb.Append(" hdrAtBlock=").Append(frame.Lin[(150 * frame.W + 1300) * 3].ToString("F2"));
            sb.Append(" hdrAtDim0.5=").Append(frame.Lin[(750 * frame.W + 1300) * 3].ToString("F4"));
            GD.Print(sb.ToString());
            for (int r = 0; r < LadderLevels.Length; r++)
            {
                var ladder = new StringBuilder("measure: ladder level=" + LadderLevels[r]);
                for (int c = 0; c < LadderSizes.Length; c++)
                {
                    int size = LadderSizes[c];
                    int cx = LadderX0 + c * LadderDx, cy = LadderY0 + r * LadderDy, edge = cx + size / 2;
                    float added = frame.Lin[(cy * frame.W + cx) * 3] - LadderLevels[r];
                    ladder.Append(" s").Append(size).Append("=+").Append(added.ToString("F2"))
                          .Append("/").Append(frame.Luma(edge + 3, cy).ToString("F0"))
                          .Append(",").Append(frame.Luma(edge + 6, cy).ToString("F0"))
                          .Append(",").Append(frame.Luma(edge + 12, cy).ToString("F0"));
                }
                GD.Print(ladder.ToString());
            }
        }
    }
}
