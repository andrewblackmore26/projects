using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using Lightship.Core.Geometry;

namespace Lightship.Core.Ships
{
    public sealed class ShipFormatException : Exception
    {
        public ShipFormatException(string message) : base(message) { }
    }

    /// <summary>
    /// JSON in, ShipDefinition out, and back (spec 14). Parsing is explicit
    /// rather than reflective so every error names the ship and the part, and
    /// so the shape parameters can live as plain keys on the part object the
    /// way the spec writes them ("radius": 13, "base": 12, "height": 27).
    ///
    /// Errors throw ShipFormatException. Soft rule violations (a prong that is
    /// not thin, a footprint off the tier size, a part nobody can read) are
    /// appended to the warnings list; the validate command gates on zero.
    /// </summary>
    public static class ShipLoader
    {
        public static readonly float[] ExpectedFootprint = { 30f, 45f, 65f, 85f, 100f };
        public const float FootprintTolerance = 0.25f;

        private static readonly HashSet<string> PartKeys = new HashSet<string>
        {
            "id", "shape", "pos", "rot", "color", "from", "to", "light_period", "light_phase",
            "component", "layer", "dashed", "cut_offset",
        };

        public static ShipDefinition LoadFile(string path, List<string> warnings) =>
            Parse(File.ReadAllText(path), warnings);

        public static ShipDefinition Parse(string json, List<string> warnings)
        {
            var options = new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip };
            using JsonDocument doc = JsonDocument.Parse(json, options);
            JsonElement root = doc.RootElement;

            var ship = new ShipDefinition();
            ship.Id = RequireString(root, "id", "ship");
            string ctx = "ship '" + ship.Id + "'";
            ship.Name = OptString(root, "name", ship.Id);
            ship.Element = ParseEnum<Element>(OptString(root, "element", "none"), ctx + " element");
            ship.Tier = OptInt(root, "tier", 1);
            if (ship.Tier < 1 || ship.Tier > 5) throw new ShipFormatException(ctx + ": tier must be 1..5, got " + ship.Tier);
            ship.ChassisColor = ParseEnum<ColorRole>(RequireString(root, "chassis_color", ctx), ctx + " chassis_color");
            if (root.TryGetProperty("core", out JsonElement core))
            {
                ship.CoreColor = ParseEnum<ColorRole>(OptString(core, "color", "white"), ctx + " core color");
                ship.CoreRadius = OptFloat(core, "radius", 3f);
            }
            ship.Breathes = OptBool(root, "breathes", false);
            if (root.TryGetProperty("abilities", out JsonElement abilities))
                foreach (JsonElement a in abilities.EnumerateArray()) ship.Abilities.Add(a.GetString());

            if (root.TryGetProperty("parts", out JsonElement parts))
                foreach (JsonElement pe in parts.EnumerateArray()) ship.Parts.Add(ParsePart(pe, ctx));

            Validate(ship, warnings);
            return ship;
        }

        private static PartDefinition ParsePart(JsonElement e, string shipCtx)
        {
            var p = new PartDefinition();
            p.Id = RequireString(e, "id", shipCtx + " part");
            string ctx = shipCtx + " part '" + p.Id + "'";
            p.Shape = ParseEnum<Shape>(RequireString(e, "shape", ctx), ctx + " shape");
            p.Color = ParseEnum<ColorRole>(RequireString(e, "color", ctx), ctx + " color");
            if (e.TryGetProperty("pos", out JsonElement pos))
            {
                if (pos.ValueKind != JsonValueKind.Array || pos.GetArrayLength() != 2)
                    throw new ShipFormatException(ctx + ": pos must be [x, y]");
                p.Pos = new Vec2(pos[0].GetSingle(), pos[1].GetSingle());
            }
            p.RotDeg = OptFloat(e, "rot", 0f);
            p.From = OptString(e, "from", null);
            p.To = OptString(e, "to", null);
            p.Component = OptString(e, "component", null);
            p.Dashed = OptBool(e, "dashed", false);
            string layer = OptString(e, "layer", null);
            if (layer != null) p.Layer = ParseEnum<PartLayer>(layer, ctx + " layer");

            if (e.TryGetProperty("light_period", out JsonElement lp))
                p.PeriodIndex = IndexOf(LightSchedule.Periods, lp.GetSingle(), ctx + " light_period");
            if (e.TryGetProperty("light_phase", out JsonElement lph))
                p.PhaseIndex = IndexOf(LightSchedule.Phases, lph.GetSingle(), ctx + " light_phase");

            if (e.TryGetProperty("cut_offset", out JsonElement co))
            {
                if (co.ValueKind != JsonValueKind.Array || co.GetArrayLength() != 2)
                    throw new ShipFormatException(ctx + ": cut_offset must be [dx, dy]");
                p.Params["cut_dx"] = co[0].GetSingle();
                p.Params["cut_dy"] = co[1].GetSingle();
            }

            var allowed = new HashSet<string>(ShapeParams.Keys(p.Shape));
            foreach (JsonProperty prop in e.EnumerateObject())
            {
                if (PartKeys.Contains(prop.Name)) continue;
                if (prop.Value.ValueKind != JsonValueKind.Number)
                    throw new ShipFormatException(ctx + ": unknown key '" + prop.Name + "'");
                if (!allowed.Contains(prop.Name))
                    throw new ShipFormatException(ctx + ": '" + prop.Name + "' is not a parameter of shape " + p.Shape.ToString().ToLowerInvariant());
                p.Params[prop.Name] = prop.Value.GetSingle();
            }

            if (p.IsTether && (p.From == null || p.To == null))
                throw new ShipFormatException(ctx + ": a tether needs 'from' and 'to'");
            return p;
        }

        /// <summary>Hard rules throw; soft rules warn. Builds the geometry once, which is also the crescent check.</summary>
        public static void Validate(ShipDefinition ship, List<string> warnings)
        {
            string ctx = "ship '" + ship.Id + "'";
            var ids = new HashSet<string>();
            foreach (PartDefinition p in ship.Parts)
            {
                if (!ids.Add(p.Id)) throw new ShipFormatException(ctx + ": duplicate part id '" + p.Id + "'");
            }
            foreach (PartDefinition p in ship.Parts)
            {
                if (!p.IsTether) continue;
                if (!ids.Contains(p.From)) throw new ShipFormatException(ctx + " part '" + p.Id + "': tether from unknown part '" + p.From + "'");
                if (!ids.Contains(p.To)) throw new ShipFormatException(ctx + " part '" + p.Id + "': tether to unknown part '" + p.To + "'");
            }

            ShipGeometry geometry;
            try
            {
                geometry = ShipGeometry.Build(ResolvedShip.From(ship));
            }
            catch (ArgumentException ex)
            {
                throw new ShipFormatException(ctx + ": " + ex.Message);
            }

            if (warnings == null) return;
            foreach (PartDefinition p in ship.Parts)
            {
                string pctx = ctx + " part '" + p.Id + "'";
                if (p.Shape == Shape.Prong && p.Param("length") < 4f * p.Param("base"))
                    warnings.Add(pctx + ": a prong should be at least 4x as long as its base");
                bool visible = !p.IsTether && !p.Dashed;
                if (visible && string.IsNullOrEmpty(p.Component) && p.Color != ship.ChassisColor)
                    warnings.Add(pctx + ": neither chassis-coloured nor a component, so nobody can read it (spec 11.7)");
                if (!string.IsNullOrEmpty(p.Component) && !ship.Abilities.Contains(p.Component))
                    warnings.Add(pctx + ": component '" + p.Component + "' is not listed in abilities");
            }
            foreach (string ability in ship.Abilities)
            {
                bool carried = false;
                foreach (PartDefinition p in ship.Parts) if (p.Component == ability) { carried = true; break; }
                if (!carried) warnings.Add(ctx + ": ability '" + ability + "' has no part carrying it (spec 11.7: every ability is a visible part)");
            }
            float expected = ExpectedFootprint[ship.Tier - 1];
            float f = geometry.Footprint;
            if (f < expected * (1f - FootprintTolerance) || f > expected * (1f + FootprintTolerance))
                warnings.Add(ctx + ": footprint " + f.ToString("F1") + " px is outside " + expected + " +-25 % for tier " + ship.Tier);
        }

        // ---- serialisation ----

        public static string Serialize(ShipDefinition ship)
        {
            using var stream = new MemoryStream();
            using (var w = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true }))
            {
                w.WriteStartObject();
                w.WriteString("id", ship.Id);
                w.WriteString("name", ship.Name ?? ship.Id);
                w.WriteString("element", Snake(ship.Element.ToString()));
                w.WriteNumber("tier", ship.Tier);
                w.WriteString("chassis_color", Snake(ship.ChassisColor.ToString()));
                w.WriteStartObject("core");
                w.WriteString("color", Snake(ship.CoreColor.ToString()));
                w.WriteNumber("radius", ship.CoreRadius);
                w.WriteEndObject();
                w.WriteBoolean("breathes", ship.Breathes);
                w.WriteStartArray("abilities");
                foreach (string a in ship.Abilities) w.WriteStringValue(a);
                w.WriteEndArray();
                w.WriteStartArray("parts");
                foreach (PartDefinition p in ship.Parts) WritePart(w, p);
                w.WriteEndArray();
                w.WriteEndObject();
            }
            return Encoding.UTF8.GetString(stream.ToArray()) + "\n";
        }

        private static void WritePart(Utf8JsonWriter w, PartDefinition p)
        {
            w.WriteStartObject();
            w.WriteString("id", p.Id);
            w.WriteString("shape", Snake(p.Shape.ToString()));
            if (p.IsTether)
            {
                w.WriteString("from", p.From);
                w.WriteString("to", p.To);
            }
            else
            {
                bool cutWritten = false;
                foreach (string key in ShapeParams.Keys(p.Shape))
                {
                    if (key == "cut_dx" || key == "cut_dy")
                    {
                        if (cutWritten) continue;
                        cutWritten = true;
                        w.WriteStartArray("cut_offset");
                        w.WriteNumberValue(p.Param("cut_dx", 0f));
                        w.WriteNumberValue(p.Param("cut_dy", 0f));
                        w.WriteEndArray();
                        continue;
                    }
                    if (p.Params.TryGetValue(key, out float v)) w.WriteNumber(key, v);
                }
                w.WriteStartArray("pos");
                w.WriteNumberValue(p.Pos.X);
                w.WriteNumberValue(p.Pos.Y);
                w.WriteEndArray();
                if (p.RotDeg != 0f) w.WriteNumber("rot", p.RotDeg);
            }
            w.WriteString("color", Snake(p.Color.ToString()));
            if (p.PeriodIndex >= 0) w.WriteNumber("light_period", LightSchedule.Periods[p.PeriodIndex]);
            if (p.PhaseIndex >= 0) w.WriteNumber("light_phase", LightSchedule.Phases[p.PhaseIndex]);
            if (!string.IsNullOrEmpty(p.Component)) w.WriteString("component", p.Component);
            if (p.Layer.HasValue) w.WriteString("layer", Snake(p.Layer.Value.ToString()));
            if (p.Dashed) w.WriteBoolean("dashed", true);
            w.WriteEndObject();
        }

        // ---- helpers ----

        public static string Snake(string pascal)
        {
            var sb = new StringBuilder();
            for (int i = 0; i < pascal.Length; i++)
            {
                char c = pascal[i];
                if (char.IsUpper(c) && i > 0) sb.Append('_');
                sb.Append(char.ToLowerInvariant(c));
            }
            return sb.ToString();
        }

        private static T ParseEnum<T>(string text, string ctx) where T : struct, Enum
        {
            string wanted = text.Replace("_", "").ToLowerInvariant();
            foreach (T value in Enum.GetValues<T>())
                if (value.ToString().ToLowerInvariant() == wanted) return value;
            throw new ShipFormatException(ctx + ": unknown value '" + text + "'");
        }

        private static int IndexOf(float[] table, float value, string ctx)
        {
            for (int i = 0; i < table.Length; i++) if (MathF.Abs(table[i] - value) < 1e-3f) return i;
            throw new ShipFormatException(ctx + ": " + value + " is not one of " + string.Join("/", table));
        }

        private static string RequireString(JsonElement e, string key, string ctx)
        {
            if (!e.TryGetProperty(key, out JsonElement v) || v.ValueKind != JsonValueKind.String)
                throw new ShipFormatException(ctx + ": missing '" + key + "'");
            return v.GetString();
        }

        private static string OptString(JsonElement e, string key, string fallback) =>
            e.TryGetProperty(key, out JsonElement v) && v.ValueKind == JsonValueKind.String ? v.GetString() : fallback;

        private static float OptFloat(JsonElement e, string key, float fallback) =>
            e.TryGetProperty(key, out JsonElement v) && v.ValueKind == JsonValueKind.Number ? v.GetSingle() : fallback;

        private static int OptInt(JsonElement e, string key, int fallback) =>
            e.TryGetProperty(key, out JsonElement v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : fallback;

        private static bool OptBool(JsonElement e, string key, bool fallback) =>
            e.TryGetProperty(key, out JsonElement v) && (v.ValueKind == JsonValueKind.True || v.ValueKind == JsonValueKind.False)
                ? v.GetBoolean() : fallback;
    }
}
