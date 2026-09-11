using System;
using System.Text;
using Godot;

namespace Lightship.View
{
    /// <summary>
    /// A captured frame in both the forms that matter: the LINEAR HDR floats
    /// the glow pass saw (proves shaders write above 1.0) and the sRGB bytes a
    /// person sees (what the palette is checked against).
    ///
    /// With hdr_2d the viewport texture is the linear buffer: a canvas shader's
    /// output is linearised on the way in, and SavePng would write those linear
    /// floats to 8 bits without re-encoding, crushing the dark end (#050507
    /// lands on 0,0,1). Encoding back to sRGB here makes the round trip exact.
    /// Never eyedrop a raw viewport capture and conclude anything about a colour.
    /// </summary>
    public sealed class Frame
    {
        public readonly int W, H;
        /// <summary>Linear HDR rgb, 3 floats per pixel, row-major.</summary>
        public readonly float[] Lin;
        /// <summary>sRGB rgba8, 4 bytes per pixel, what a viewer sees.</summary>
        public readonly byte[] Srgb;

        private Frame(int w, int h, float[] lin)
        {
            W = w; H = h; Lin = lin;
            Srgb = new byte[w * h * 4];
            for (int i = 0, p = 0; i < w * h; i++, p += 3)
            {
                Srgb[i * 4] = (byte)Mathf.RoundToInt(LinearToSrgb(lin[p]) * 255f);
                Srgb[i * 4 + 1] = (byte)Mathf.RoundToInt(LinearToSrgb(lin[p + 1]) * 255f);
                Srgb[i * 4 + 2] = (byte)Mathf.RoundToInt(LinearToSrgb(lin[p + 2]) * 255f);
                Srgb[i * 4 + 3] = 255;
            }
        }

        public static Frame Grab(Viewport viewport)
        {
            Image img = viewport.GetTexture().GetImage();
            int w = img.GetWidth(), h = img.GetHeight();
            var lin = new float[w * h * 3];
            byte[] data = img.GetData();
            Image.Format fmt = img.GetFormat();
            if (fmt == Image.Format.Rgbah)
            {
                // Fast path: 4 halves per pixel, read once instead of 1.4M GetPixel calls.
                for (int i = 0, p = 0; i < w * h; i++, p += 3)
                {
                    int o = i * 8;
                    lin[p] = (float)BitConverter.ToHalf(data, o);
                    lin[p + 1] = (float)BitConverter.ToHalf(data, o + 2);
                    lin[p + 2] = (float)BitConverter.ToHalf(data, o + 4);
                }
            }
            else if (fmt == Image.Format.Rgbh)
            {
                // What the hdr_2d viewport actually returns on this machine: 3 halves per pixel.
                for (int i = 0, p = 0; i < w * h; i++, p += 3)
                {
                    int o = i * 6;
                    lin[p] = (float)BitConverter.ToHalf(data, o);
                    lin[p + 1] = (float)BitConverter.ToHalf(data, o + 2);
                    lin[p + 2] = (float)BitConverter.ToHalf(data, o + 4);
                }
            }
            else if (fmt == Image.Format.Rgbf)
            {
                for (int i = 0, p = 0; i < w * h; i++, p += 3)
                {
                    int o = i * 12;
                    lin[p] = BitConverter.ToSingle(data, o);
                    lin[p + 1] = BitConverter.ToSingle(data, o + 4);
                    lin[p + 2] = BitConverter.ToSingle(data, o + 8);
                }
            }
            else if (fmt == Image.Format.Rgbaf)
            {
                for (int i = 0, p = 0; i < w * h; i++, p += 3)
                {
                    int o = i * 16;
                    lin[p] = BitConverter.ToSingle(data, o);
                    lin[p + 1] = BitConverter.ToSingle(data, o + 4);
                    lin[p + 2] = BitConverter.ToSingle(data, o + 8);
                }
            }
            else
            {
                // Proven slow path (Gridlock 2): whatever the format, GetPixel decodes it.
                GD.Print("capture: slow path for format " + fmt);
                for (int y = 0, p = 0; y < h; y++)
                {
                    for (int x = 0; x < w; x++, p += 3)
                    {
                        Color c = img.GetPixel(x, y);
                        lin[p] = c.R; lin[p + 1] = c.G; lin[p + 2] = c.B;
                    }
                }
            }
            return new Frame(w, h, lin);
        }

        public Error SavePng(string path)
        {
            Image png = Image.CreateFromData(W, H, false, Image.Format.Rgba8, Srgb);
            return png.SavePng(path);
        }

        public int R(int x, int y) => Srgb[(y * W + x) * 4];
        public int G(int x, int y) => Srgb[(y * W + x) * 4 + 1];
        public int B(int x, int y) => Srgb[(y * W + x) * 4 + 2];
        public string Rgb(int x, int y) => R(x, y) + "," + G(x, y) + "," + B(x, y);
        public double Luma(int x, int y) => 0.2126 * R(x, y) + 0.7152 * G(x, y) + 0.0722 * B(x, y);
        public bool InBounds(int x, int y) => x >= 0 && y >= 0 && x < W && y < H;

        public float HdrPeak()
        {
            float peak = 0f;
            for (int i = 0; i < Lin.Length; i++) if (Lin[i] > peak) peak = Lin[i];
            return peak;
        }

        /// <summary>HSV hue in degrees and saturation/value of a viewed pixel.</summary>
        public void Hsv(int x, int y, out float hue, out float sat, out float val)
        {
            float r = R(x, y) / 255f, g = G(x, y) / 255f, b = B(x, y) / 255f;
            float max = Mathf.Max(r, Mathf.Max(g, b)), min = Mathf.Min(r, Mathf.Min(g, b));
            val = max;
            float d = max - min;
            sat = max > 0f ? d / max : 0f;
            if (d <= 1e-6f) { hue = 0f; return; }
            if (max == r) hue = 60f * (((g - b) / d) % 6f);
            else if (max == g) hue = 60f * ((b - r) / d + 2f);
            else hue = 60f * ((r - g) / d + 4f);
            if (hue < 0f) hue += 360f;
        }

        /// <summary>
        /// The frame-wide numbers every capture prints. The corner samples are
        /// the playfield; the peak proves the HDR pipeline is live.
        /// </summary>
        public string BasicMeasureLine()
        {
            double lumaSum = 0;
            int samples = 0, bright = 0, nearWhite = 0, peak = 0;
            for (int y = 0; y < H; y += 2)
            {
                for (int x = 0; x < W; x += 2)
                {
                    int r = R(x, y), g = G(x, y), b = B(x, y);
                    double luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
                    lumaSum += luma;
                    samples++;
                    peak = Math.Max(peak, Math.Max(r, Math.Max(g, b)));
                    if (luma > 90) bright++;
                    if (luma > 220) nearWhite++;
                }
            }
            var sb = new StringBuilder();
            sb.Append("measure: size=").Append(W).Append('x').Append(H);
            sb.Append(" bg=").Append(Rgb(6, 6));
            sb.Append(" bgCorners=").Append(Rgb(6, 6)).Append('|').Append(Rgb(W - 7, 6))
              .Append('|').Append(Rgb(6, H - 7)).Append('|').Append(Rgb(W - 7, H - 7));
            sb.Append(" meanLuma=").Append((lumaSum / Math.Max(samples, 1)).ToString("F1"));
            sb.Append(" peak=").Append(peak);
            sb.Append(" hdrPeak=").Append(HdrPeak().ToString("F2"));
            sb.Append(" brightPct=").Append((bright * 100.0 / Math.Max(samples, 1)).ToString("F2"));
            sb.Append(" nearWhitePct=").Append((nearWhite * 100.0 / Math.Max(samples, 1)).ToString("F3"));
            return sb.ToString();
        }

        public static float LinearToSrgb(float c)
        {
            if (c <= 0f) return 0f;
            if (c >= 1f) return 1f;
            return c <= 0.0031308f ? 12.92f * c : 1.055f * Mathf.Pow(c, 1f / 2.4f) - 0.055f;
        }
    }
}
