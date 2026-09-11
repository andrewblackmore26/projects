using System.Collections.Generic;
using Godot;
using Lightship.Core;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;

namespace Lightship.View.Editor
{
    /// <summary>
    /// --editor --selftest: drives the editor through the operations a designer
    /// uses (add, move, scale, rotate, mirror, pick, delete, rename, next tier,
    /// save, reload, tween) and checks each result against Core and against what
    /// the editor actually drew, printing one "measure: editor" line. Every check
    /// is built so the broken behaviour it guards against would fail it. Saves go
    /// to user:// so the canonical ship files are never touched.
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

            // Mirroring an arc with no start_deg written reflects its angular range too.
            ed.AddPart(Shape.Arc);
            ed.SelectedPart.Params.Remove("start_deg");
            ed.SelectedPart.Params["sweep_deg"] = 60f;
            ed.SelectedPart.Id = "arc_l";
            ed.Changed();
            ed.MirrorSelected();
            PartDefinition arcR = ed.Ship.FindPart("arc_r");
            Check(arcR != null && arcR.Param("start_deg") == -60f, "arc mirror: start " + arcR?.Param("start_deg"));
            ed.Ship.Parts.RemoveAll(p => p.Id == "arc_l" || p.Id == "arc_r");
            ed.Changed();

            // Pick through the drawn geometry: a point inside pod_r (radius 9) but 7 units from its
            // centre, beyond the 6-unit nearest-centre fallback, so only the real hit test finds it.
            int hit = ed.PartAt(new Vec2(-21.5f, 3f));
            Check(hit >= 0 && ed.Ship.Parts[hit].Id == "pod_r", "pick by geometry: " + hit);

            // Delete removes the part and every tether attached to it.
            ed.Select(ed.Ship.Parts.FindIndex(p => p.Id == "pod_r"));
            ed.Ship.Parts.Add(new PartDefinition { Id = "tether_pod_r", Shape = Shape.Tether, From = "blob", To = "pod_r", Color = ColorRole.CorruptionGreen });
            ed.Changed();
            ed.DeleteSelected();
            Check(ed.Ship.FindPart("pod_r") == null && ed.Ship.FindPart("tether_pod_r") == null, "delete takes its tethers");

            // An added tether never uses a tether as an end.
            ed.Ship.Parts.Insert(0, new PartDefinition { Id = "tether_x", Shape = Shape.Tether, From = "blob", To = "tail_1", Color = ColorRole.CorruptionGreen });
            ed.Changed();
            ed.AddPart(Shape.Tether);
            PartDefinition added = ed.SelectedPart;
            Check(added.IsTether && !ed.Ship.FindPart(added.From).IsTether && !ed.Ship.FindPart(added.To).IsTether, "tether ends");
            ed.Ship.Parts.RemoveAll(p => p.IsTether);
            ed.Changed();

            // A broken ship refuses to save.
            ed.Ship.Parts.Add(new PartDefinition { Id = "tether_bad", Shape = Shape.Tether, From = "blob", To = "nowhere", Color = ColorRole.CorruptionGreen });
            string dir = ProjectSettings.GlobalizePath("user://");
            bool savedBroken = ed.Save(dir, out _);
            Check(!savedBroken && ed.LastError != null, "save refuses an invalid ship");
            ed.Ship.Parts.RemoveAll(p => p.Id == "tether_bad");

            // Next tier of the glitch is corruption tier 2, which the worm already is: refused, not written.
            ed.DuplicateAsNextTier();
            Check(ed.Ship.Tier == 2 && ed.Ship.Id == "corruption_t2_new", "next tier id: " + ed.Ship.Id);
            bool dup = ed.Save(dir, out _);
            Check(!dup && ed.LastError != null && ed.LastError.Contains("corruption_t2_worm"), "duplicate tier refused: " + ed.LastError);

            // Free (element, tier): saved, reloaded through the loader, and listed in the catalog.
            ed.Ship.Element = Element.None;
            bool saved = ed.Save(dir, out string path);
            Check(saved, "save: " + ed.LastError);
            int partsSaved = ed.Ship.Parts.Count;
            ShipDefinition back = saved ? ShipLoader.LoadFile(path, new List<string>()) : null;
            Check(back != null && back.Parts.Count == partsSaved && back.FindPart("pod_l") != null, "reload");
            Check(ed.Catalog.Get("corruption_t2_new") != null, "catalog lists the saved ship");

            // Tween preview: the working view draws exactly the midpoint blend.
            ed.Load(ed.Catalog.Get("corruption_t1_glitch").Clone());
            ed.TweenTarget = ed.Catalog.Get("corruption_t2_worm");
            ed.TweenT = 0.5f;
            ed.Changed();
            ShipGeometry mid = ShipGeometry.Build(ShipTween.Blend(ed.Ship, ed.TweenTarget, 0.5f));
            ShipGeometry drawn = ed.WorkGeometry;
            Check(ed.LastError == null && drawn.Parts.Count == mid.Parts.Count && System.MathF.Abs(drawn.Footprint - mid.Footprint) < 0.01f &&
                  drawn.Parts.Count > ed.Ship.Parts.Count, "tween preview drawn " + drawn.Parts.Count + " vs blend " + mid.Parts.Count);
            ed.TweenT = -1f;
            ed.TweenTarget = null;
            ed.Changed();

            GD.Print("measure: editor checks=" + (checks - fails.Count) + "/" + checks + " savedTo=" + path +
                     (fails.Count > 0 ? " FAIL=" + string.Join(";", fails) : "") + " ok=" + (fails.Count == 0 ? 1 : 0));
            return fails;
        }
    }
}
