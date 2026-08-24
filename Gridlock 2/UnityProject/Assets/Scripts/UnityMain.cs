using System;
using System.IO;
using UnityEngine;
using Gridlock.Core;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// Entry point. Put this on a single empty GameObject in an otherwise empty
    /// scene: the camera, the board and the HUD are all built from code, driven
    /// by the level data, exactly as the Godot layer does — the two engines are
    /// meant to differ in how they render and feel, not in how they are wired.
    ///
    /// Levels are read from StreamingAssets/levels.
    /// </summary>
    public class UnityMain : MonoBehaviour
    {
        [Tooltip("Level file in StreamingAssets/levels, without the .json extension.")]
        public string LevelId = "level_06_mirrorlock";

        [Tooltip("Difficulty tier of the opponent, 1..10.")]
        public int AiTier = 5;

        [Tooltip("Watch the AI play itself instead of playing (spec M2 attract mode).")]
        public bool AttractMode;

        [Tooltip("Tier of the AI playing the player's side in attract mode.")]
        public int AttractPlayerTier = 5;

        public ulong Seed = 1;

        private UGameController _game;
        private UBoardView _board;

        private void Start()
        {
            var tuning = new Tuning();
            BuiltLevel level;
            try
            {
                string path = Path.Combine(Application.streamingAssetsPath, "levels", LevelId + ".json");
                level = LevelLoader.LoadFromJson(File.ReadAllText(path), tuning);
            }
            catch (Exception e)
            {
                Debug.LogError("Gridlock: could not load level '" + LevelId + "': " + e.Message);
                enabled = false;
                return;
            }
            foreach (string warning in level.Warnings) Debug.LogWarning("level warning: " + warning);

            _game = new UGameController(level, tuning);
            if (AttractMode) _game.AttachStandardAi(AttractPlayerTier, AiTier, Seed);
            else _game.AddAi(CoreOwner.Ai, AiTier, Seed);

            var layout = new UBoardTransform(level, Screen.width, Screen.height);
            Camera camera = SetupCamera(layout);

            Material wireMaterial = MakeMaterial("Shaders/GridlockWire");
            Material nodeMaterial = MakeMaterial("Shaders/GridlockNode");
            Material sparkMaterial = MakeMaterial("Shaders/GridlockSpark");

            var boardObject = new GameObject("Board");
            boardObject.transform.SetParent(transform, false);
            _board = boardObject.AddComponent<UBoardView>();
            _board.Build(_game, layout, wireMaterial, nodeMaterial, sparkMaterial);

            var hud = gameObject.AddComponent<UHud>();
            hud.Setup(_game, level.Data.Name);

            if (!AttractMode)
            {
                var input = gameObject.AddComponent<UInputController>();
                input.Setup(_game, _board, camera, sparkMaterial);
            }

            Debug.Log("gridlock: level=" + level.Data.Id + " nodes=" + level.Nodes.Count +
                " wires=" + level.Wires.Count + " mode=" + (AttractMode ? "attract" : "play"));
        }

        private Camera SetupCamera(UBoardTransform layout)
        {
            Camera camera = Camera.main;
            if (camera == null)
            {
                var go = new GameObject("Main Camera") { tag = "MainCamera" };
                camera = go.AddComponent<Camera>();
            }
            camera.orthographic = true;
            camera.orthographicSize = layout.OrthographicSize;
            camera.transform.position = new Vector3(layout.Centre.x, layout.Centre.y, -10f);
            camera.clearFlags = CameraClearFlags.SolidColor;
            // The ground, not pure black: the glow needs something to sit against.
            camera.backgroundColor = UPalette.Background;
            // HDR is what lets the shaders write above 1.0 for bloom to catch.
            camera.allowHDR = true;
            return camera;
        }

        private static Material MakeMaterial(string resourcePath)
        {
            // Shaders live under Assets/Resources/Shaders because Shader.Find
            // returns null for anything not referenced by a scene in a player
            // build; Resources.Load always reaches them.
            var shader = Resources.Load<Shader>(resourcePath);
            if (shader == null)
            {
                Debug.LogError("Gridlock: shader not found at Resources/" + resourcePath);
                return null;
            }
            return new Material(shader);
        }

        private void Update()
        {
            if (_game == null) return;
            _game.Advance(Time.deltaTime);
            _board.UpdateViews(Time.deltaTime);
        }
    }
}
