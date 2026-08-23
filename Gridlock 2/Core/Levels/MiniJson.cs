using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Gridlock.Core.Levels
{
    /// <summary>
    /// Minimal recursive-descent JSON reader/writer so Core has zero package
    /// dependencies (System.Text.Json is unavailable in Unity, Newtonsoft would
    /// be an engine-side package). Parses into object/Dictionary/List/double/
    /// string/bool/null. Invariant culture throughout.
    /// </summary>
    public static class MiniJson
    {
        /// <summary>Nesting cap — malformed deep input must throw, not overflow the stack.</summary>
        private const int MaxDepth = 64;

        public static object Parse(string text)
        {
            int pos = 0;
            object value = ParseValue(text, ref pos, 0);
            SkipWhitespace(text, ref pos);
            if (pos != text.Length)
                throw new FormatException("Trailing content at position " + pos);
            return value;
        }

        private static object ParseValue(string s, ref int pos, int depth)
        {
            if (depth > MaxDepth) throw new FormatException("JSON nested deeper than " + MaxDepth);
            SkipWhitespace(s, ref pos);
            if (pos >= s.Length) throw new FormatException("Unexpected end of JSON");
            char c = s[pos];
            switch (c)
            {
                case '{': return ParseObject(s, ref pos, depth);
                case '[': return ParseArray(s, ref pos, depth);
                case '"': return ParseString(s, ref pos);
                case 't': Expect(s, ref pos, "true"); return true;
                case 'f': Expect(s, ref pos, "false"); return false;
                case 'n': Expect(s, ref pos, "null"); return null;
                default: return ParseNumber(s, ref pos);
            }
        }

        private static Dictionary<string, object> ParseObject(string s, ref int pos, int depth)
        {
            var result = new Dictionary<string, object>();
            pos++; // '{'
            SkipWhitespace(s, ref pos);
            if (Peek(s, pos) == '}') { pos++; return result; }
            while (true)
            {
                SkipWhitespace(s, ref pos);
                if (Peek(s, pos) != '"') throw new FormatException("Expected key at " + pos);
                string key = ParseString(s, ref pos);
                SkipWhitespace(s, ref pos);
                if (Peek(s, pos) != ':') throw new FormatException("Expected ':' at " + pos);
                pos++;
                result[key] = ParseValue(s, ref pos, depth + 1);
                SkipWhitespace(s, ref pos);
                char n = Peek(s, pos);
                if (n == ',') { pos++; continue; }
                if (n == '}') { pos++; return result; }
                throw new FormatException("Expected ',' or '}' at " + pos);
            }
        }

        private static List<object> ParseArray(string s, ref int pos, int depth)
        {
            var result = new List<object>();
            pos++; // '['
            SkipWhitespace(s, ref pos);
            if (Peek(s, pos) == ']') { pos++; return result; }
            while (true)
            {
                result.Add(ParseValue(s, ref pos, depth + 1));
                SkipWhitespace(s, ref pos);
                char n = Peek(s, pos);
                if (n == ',') { pos++; continue; }
                if (n == ']') { pos++; return result; }
                throw new FormatException("Expected ',' or ']' at " + pos);
            }
        }

        private static string ParseString(string s, ref int pos)
        {
            pos++; // '"'
            var sb = new StringBuilder();
            while (true)
            {
                if (pos >= s.Length) throw new FormatException("Unterminated string");
                char c = s[pos++];
                if (c == '"') return sb.ToString();
                if (c == '\\')
                {
                    if (pos >= s.Length) throw new FormatException("Unterminated escape");
                    char e = s[pos++];
                    switch (e)
                    {
                        case '"': sb.Append('"'); break;
                        case '\\': sb.Append('\\'); break;
                        case '/': sb.Append('/'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'n': sb.Append('\n'); break;
                        case 'r': sb.Append('\r'); break;
                        case 't': sb.Append('\t'); break;
                        case 'u':
                            if (pos + 4 > s.Length) throw new FormatException("Bad \\u escape");
                            sb.Append((char)ushort.Parse(s.Substring(pos, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
                            pos += 4;
                            break;
                        default: throw new FormatException("Bad escape '\\" + e + "'");
                    }
                }
                else sb.Append(c);
            }
        }

        private static double ParseNumber(string s, ref int pos)
        {
            int start = pos;
            while (pos < s.Length && ("-+.eE0123456789".IndexOf(s[pos]) >= 0)) pos++;
            string token = s.Substring(start, pos - start);
            if (!double.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out double value))
                throw new FormatException("Bad number '" + token + "' at " + start);
            return value;
        }

        private static void Expect(string s, ref int pos, string literal)
        {
            if (pos + literal.Length > s.Length || s.Substring(pos, literal.Length) != literal)
                throw new FormatException("Expected '" + literal + "' at " + pos);
            pos += literal.Length;
        }

        private static char Peek(string s, int pos) =>
            pos < s.Length ? s[pos] : '\0';

        private static void SkipWhitespace(string s, ref int pos)
        {
            while (pos < s.Length && (s[pos] == ' ' || s[pos] == '\t' || s[pos] == '\n' || s[pos] == '\r')) pos++;
        }

        // ---- Writing (used by the level editor export) ----

        public static string Write(object value)
        {
            var sb = new StringBuilder();
            WriteValue(sb, value, 0);
            return sb.ToString();
        }

        private static void WriteValue(StringBuilder sb, object value, int indent)
        {
            if (value == null) { sb.Append("null"); return; }
            switch (value)
            {
                case string s: WriteString(sb, s); break;
                case bool b: sb.Append(b ? "true" : "false"); break;
                case int i: sb.Append(i.ToString(CultureInfo.InvariantCulture)); break;
                case float f: sb.Append(f.ToString("R", CultureInfo.InvariantCulture)); break;
                case double d: sb.Append(d.ToString("R", CultureInfo.InvariantCulture)); break;
                case Dictionary<string, object> obj: WriteObject(sb, obj, indent); break;
                case List<object> arr: WriteArray(sb, arr, indent); break;
                default: throw new ArgumentException("Unsupported JSON value type: " + value.GetType());
            }
        }

        private static void WriteObject(StringBuilder sb, Dictionary<string, object> obj, int indent)
        {
            sb.Append("{\n");
            int i = 0;
            foreach (var kv in obj)
            {
                Indent(sb, indent + 1);
                WriteString(sb, kv.Key);
                sb.Append(": ");
                WriteValue(sb, kv.Value, indent + 1);
                if (++i < obj.Count) sb.Append(',');
                sb.Append('\n');
            }
            Indent(sb, indent);
            sb.Append('}');
        }

        private static void WriteArray(StringBuilder sb, List<object> arr, int indent)
        {
            sb.Append('[');
            for (int i = 0; i < arr.Count; i++)
            {
                if (i > 0) sb.Append(", ");
                WriteValue(sb, arr[i], indent);
            }
            sb.Append(']');
        }

        private static void WriteString(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < ' ') sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }

        private static void Indent(StringBuilder sb, int depth)
        {
            for (int i = 0; i < depth; i++) sb.Append("  ");
        }
    }
}
