using UnityEngine;
using Gridlock.Core;
using Gridlock.Core.Config;
using System.Reflection;
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// Match readout plus the live tuning panel (F1), both on IMGUI. IMGUI draws
    /// after the render pipeline, so the text stays crisp instead of blooming
    /// into mush and the board keeps the whole HDR budget.
    ///
    /// Every constant in Tuning is editable while the match runs, which is an
    /// acceptance criterion and the only sane way to tune a game whose feel
    /// lives in a dozen interacting numbers.
    /// </summary>
    public class UHud : MonoBehaviour
    {
        private UGameController _game;
        private string _levelName = "";
        private MatchResult _result = MatchResult.None;
        private bool _panelOpen;
        private Vector2 _scroll;
        private FieldInfo[] _fields;

        public void Setup(UGameController game, string levelName)
        {
            _game = game;
            _levelName = levelName;
            game.Sim.MatchEnded += r => _result = r;
            _fields = typeof(Tuning).GetFields(BindingFlags.Public | BindingFlags.Instance);
        }

        private void Update()
        {
            if (Input.GetKeyDown(KeyCode.F1)) _panelOpen = !_panelOpen;
        }

        private void OnGUI()
        {
            if (_game == null) return;

            int player = 0, ai = 0, neutral = 0;
            foreach (GameNode n in _game.Sim.Nodes)
            {
                if (n.Owner == CoreOwner.Player) player++;
                else if (n.Owner == CoreOwner.Ai) ai++;
                else neutral++;
            }

            GUI.color = new Color(0.62f, 0.72f, 0.85f, 0.85f);
            GUI.Label(new Rect(22, 14, 900, 22),
                _levelName + "    " + _game.Sim.TimeSeconds.ToString("F1") + "s" +
                "    nodes  you " + player + " / ai " + ai + " / open " + neutral +
                "    [F1] tuning");

            if (_result != MatchResult.None)
            {
                GUI.color = _result == MatchResult.PlayerWin ? UPalette.PlayerBase : UPalette.AiBase;
                string text = _result == MatchResult.PlayerWin ? "CIRCUIT HELD"
                    : _result == MatchResult.AiWin ? "CIRCUIT LOST"
                    : _result.ToString().ToUpperInvariant();
                var style = new GUIStyle(GUI.skin.label) { fontSize = 40, alignment = TextAnchor.MiddleCenter };
                GUI.Label(new Rect(0, Screen.height * 0.42f, Screen.width, 60), text, style);
            }

            GUI.color = Color.white;
            if (_panelOpen) DrawTuningPanel();
        }

        private void DrawTuningPanel()
        {
            var area = new Rect(Screen.width - 340, 0, 340, Screen.height);
            GUI.Box(area, "TUNING");
            GUILayout.BeginArea(new Rect(area.x + 8, 26, area.width - 16, area.height - 34));
            _scroll = GUILayout.BeginScrollView(_scroll);
            foreach (FieldInfo field in _fields)
            {
                if (field.FieldType == typeof(float))
                {
                    float value = (float)field.GetValue(_game.Tuning);
                    GUILayout.Label(field.Name + "  " + value.ToString("F3"));
                    float edited = GUILayout.HorizontalSlider(value, 0f, Mathf.Max(value * 3f, 1f));
                    if (!Mathf.Approximately(edited, value)) field.SetValue(_game.Tuning, edited);
                }
                else if (field.FieldType == typeof(int))
                {
                    int value = (int)field.GetValue(_game.Tuning);
                    GUILayout.Label(field.Name + "  " + value);
                }
            }
            GUILayout.EndScrollView();
            GUILayout.EndArea();
        }
    }
}
