using System.Collections.Generic;
using Godot;
using Lightship.Core;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;

namespace Lightship.View.Editor
{
    /// <summary>
    /// --editor --selftest: drives the editor through the operations a designer
    /// uses (add, move, scale, rotate, mirror, delete, next tier, tween, save)
    /// and checks each result against Core, printing one "measure: editor" line.
    /// Saves go to user:// so the canonical ship files are never touched.
    /// </summary>
    public static class EditorSelfTest
    {
        public static List<string> Run(ShipEditor ed)
        {
            var fails = new List<string>();
            int checks = 0;
            void Check(bool ok, string what) { checks++; if (!ok) fails.Add(what); }

            ed.Load(ed.Catalog.Get("corruption_t1_glitch").Clone());
            int before = ed.Ship.Parts.Count;

            ed.AddPart(Shape.Circle);
            Check(ed.Ship.Parts.Count == before + 1, "add");
            string added = ed.SelectedPart.Id;
            ed.MoveSelected(new Vec2(14.26f, 3.1f));
            Check(ed.SelectedPart.Pos.X == 14.5f && ed.SelectedPart.Pos.Y == 3f, "move snaps to 0.5: " + ed.SelectedPart.Pos);
            float r0 = ed.SelectedPart.Param("radius");
            ed.ScaleSelected(1.5f);
            Check(System.MathF.Abs(ed.SelectedPart.Param("radius") - r0 * 1.5f) < 0.02f, "scale");
            ed.RotateSelected(-5f);
            Check(ed.SelectedPart.RotDeg == -5f, "rotate wraps to -5: " + ed.SelectedPart.RotDeg);

            // Rename to a left-hand id and mirror it: the pair must land at -x with _r.
            ed.SelectedPart.Id = "pod_l";
            ed.Changed();
            ed.MirrorSelected();
            PartDefinition right = ed.Ship.FindPart("pod_r");
            Check(right != null && right.Pos.X == -14.5f && right.RotDeg == 5f, "mirror");

            // Selection by point: the working view's hit test finds the part under its centre.
            int hit = ed.PartAt(new Vec2(-14.5f, 3f));
            Check(hit >= 0 && ed.Ship.Parts[hit].Id == "pod_r", "pick by point: " + hit);

            // Delete removes the part and every tether attached to it.
            ed.Select(ed.Ship.Parts.FindIndex(p => p.Id == "pod_r"));
            ed.Ship.Parts.Add(new PartDefinition { Id = "tether_pod_r", Shape = Shape.Tether, From = "blob", To = "pod_r", Color = ColorRole.CorruptionGreen });
            ed.Changed();
            ed.DeleteSelected();
            Check(ed.Ship.FindPart("pod_r") == null && ed.Ship.FindPart("tether_pod_r") == null, "delete takes its tethers");

            // A broken ship refuses to save.
            ed.Ship.Parts.Add(new PartDefinition { Id = "tether_bad", Shape = Shape.Tether, From = "blob", To = "nowhere", Color = ColorRole.CorruptionGreen });
            string dir = ProjectSettings.GlobalizePath("user://");
            bool savedBroken = ed.Save(dir, out _);
            Check(!savedBroken && ed.LastError != null, "save refuses an invalid ship");
            ed.Ship.Parts.RemoveAll(p => p.Id == "tether_bad");

            // Next tier, save, reload through the loader: the file round-trips.
            ed.DuplicateAsNextTier();
            Check(ed.Ship.Tier == 2 && ed.Ship.Id == "corruption_t2_new", "next tier id: " + ed.Ship.Id);
            bool saved = ed.Save(dir, out string path);
            Check(saved, "save: " + ed.LastError);
            int partsSaved = ed.Ship.Parts.Count;
            ShipDefinition back = saved ? ShipLoader.LoadFile(path, new List<string>()) : null;
            Check(back != null && back.Parts.Count == partsSaved && back.FindPart("pod_l") != null, "reload");

            // Tween preview between the catalog's T1 and T2 at the midpoint builds geometry.
            ed.Load(ed.Catalog.Get("corruption_t1_glitch").Clone());
            ed.TweenTarget = ed.Catalog.Get("corruption_t2_worm");
            ed.TweenT = 0.5f;
            ed.Changed();
            ShipGeometry mid = ShipGeometry.Build(ShipTween.Blend(ed.Ship, ed.TweenTarget, 0.5f));
            Check(ed.LastError == null && mid.Parts.Count > ed.Ship.Parts.Count, "tween preview");

            GD.Print("measure: editor checks=" + (checks - fails.Count) + "/" + checks + " savedTo=" + path + (fails.Count > 0 ? " FAIL=" + string.Join(";", fails) : ""));
            return fails;
        }
    }
}
