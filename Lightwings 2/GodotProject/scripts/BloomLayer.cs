using Godot;

namespace Lightship.View
{
    /// <summary>
    /// Screen-space bloom on its own canvas layer: a back-buffer copy of
    /// everything drawn below (playfield and arena), then a full-screen rect
    /// whose shader adds the thresholded, blurred light back on top. The HUD
    /// lives on a higher layer and stays crisp.
    /// </summary>
    public partial class BloomLayer : CanvasLayer
    {
        public const int LayerIndex = 1;
        private ShaderMaterial _material;

        public BloomLayer()
        {
            Layer = LayerIndex;
            Name = "Bloom";
        }

        public override void _Ready()
        {
            AddChild(new BackBufferCopy { CopyMode = BackBufferCopy.CopyModeEnum.Viewport });
            var rect = new ColorRect
            {
                Color = new Color(1, 1, 1, 1),
                MouseFilter = Control.MouseFilterEnum.Ignore,
            };
            rect.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
            _material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/bloom.gdshader") };
            rect.Material = _material;
            AddChild(rect);
        }

        public void Configure(float threshold, float intensity, float radiusPx, float sigmaPx)
        {
            _material.SetShaderParameter("threshold", threshold);
            _material.SetShaderParameter("intensity", intensity);
            _material.SetShaderParameter("radius_px", radiusPx);
            _material.SetShaderParameter("sigma_px", sigmaPx);
        }
    }
}
