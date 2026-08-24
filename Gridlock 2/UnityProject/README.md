# Gridlock — Unity presentation layer

Unity 6 (6000.4.6f1), URP. Thin presentation over the shared `/Core` simulation,
mirroring the Godot layer file for file so the M4 comparison is about rendering
and feel rather than about two different designs.

**This layer is compile-verified only.** There is no usable Unity licence on the
machine it was written on, so the editor has never been opened against it. Read
the limits section before trusting anything here.

## Opening it

1. Open `UnityProject` in Unity 6000.4.6f1. URP 17.4.0 ships with the editor, so
   the package resolves without network access.
2. Create an empty scene, add one empty GameObject, and put `UnityMain` on it.
   Everything else — camera, board, HUD — is built from code at `Start`.
3. Pick a level in the `UnityMain` inspector (`LevelId`, default
   `level_06_mirrorlock`), the opponent tier, and whether to watch the AI play
   itself (`AttractMode`).

### Editor-side setup that code cannot do

These are asset and project settings; they cannot be created from a csproj, so
they are the one thing left for whoever opens the editor:

- Create a URP asset with a **2D Renderer**, assign it in Project Settings →
  Graphics and Quality.
- Enable **HDR** on the URP asset. Without it, everything the shaders write
  above 1.0 is clamped and there is nothing for bloom to catch.
- Add a **Global Volume** with a **Bloom** override: threshold ~1.0, high
  intensity, wide scatter. The Godot layer measured out at glow threshold 1.0
  with the two widest mips off; start there and re-measure.
- Set the colour space to **Linear** (Player settings).

## Controls (spec §7)

Press an owned node and it starts charging immediately — that brightening is
what the opponent sees, and what makes feinting real. Drag to a connected node
and release to send; release anywhere else, or back on the origin, to cancel for
free. Hold past 1.4 s and the node flares: releasing then bursts. A tap with no
drag inspects: that node's wires stay lit and the rest dim for two seconds. F1
opens the live tuning panel over every field of `Tuning`.

## Design mirrors the Godot layer

Wires and node rings are generated ribbon meshes whose UVs run 0..1 along the
path, so a beam at simulation `t` maps exactly onto the mesh. Beams, the contest
front, the overcharge pulse and the capture flash are all
`MaterialPropertyBlock` values — nothing is a moving transform, per spec §8.4
and §11 (a `LineRenderer` per wire would not batch).

Shaders live under `Assets/Resources/Shaders` deliberately: `Shader.Find`
returns null in player builds for anything no scene references, and
`Resources.Load` always reaches them.

`MaterialPropertyBlock.SetInteger` is used rather than the deprecated `SetInt`,
which in Unity 6 uploads a float and leaves an `int` shader parameter reading
garbage.

## Verification, and what it does not cover

```powershell
dotnet build Tools/UnityCompileCheck    # must be 0 errors
```

The check compiles `Assets/Scripts` plus the Core sources against the installed
editor's managed assemblies, with an **explicit** reference list rather than a
glob of `Managed/UnityEngine/`. A glob would supply modules this project
excludes and silently pass code Unity rejects — that is exactly how a real
CS1069 once shipped green on this project's ancestor.

Two things keep it honest:

- **A drift guard.** The build fails if `manifest.json`'s module count stops
  matching `_ExpectedModuleCount`, so adding a module without updating the
  reference list cannot turn the check back into a false negative.
- **A verified reference set.** Every module DLL referenced is either
  non-strippable or declared in the manifest; the six declarable modules this
  project does not declare (`adaptiveperformance`, `amd`, `hierarchy`, `nvidia`,
  `uielementsnative`, `vectorgraphics`) are all absent from the list. Confirmed
  with a negative test: a script touching `UnityEngine.NVIDIA.GraphicsDevice`
  fails the check with CS1069, which is the error class that matters.

**It cannot catch**: packaging and asset import (local package layout, build
artifacts inside `/Core`, assembly-identity collisions, `.meta` state), shader
compilation, URP configuration, or anything about how this actually looks and
feels. Only opening the editor proves that side.

## Known deviation

Input uses the legacy `Input` class rather than the new Input System the spec
suggests (§11). It covers mouse and touch in one code path and, unlike the Input
System package, can be compile-verified here. Migrating is a follow-up for
whoever has the editor: the input surface is confined to `UInputController`.
