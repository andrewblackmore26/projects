# Lightship

A Godot twin-stick arena shooter about absorbing light, choosing a new hull and surviving five rival AIs. Light is both health and progress: damage can shrink your ship, and regrowth gives you another choice.

This workspace implements the revised design with the approved **five-tier**, **fixed-loadout** scope. Fire, Corruption and Plasma start unlocked; entering Lightning or Void territory unlocks that element. The source specification and approved overrides are in [docs/LIGHTSHIP_GAME_SPEC.md](docs/LIGHTSHIP_GAME_SPEC.md). Current evidence and remaining gaps are in [docs/VALIDATION.md](docs/VALIDATION.md).

## Run

Open `project.godot` in the pinned Godot 4.7.2 engine, or run:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run.ps1
```

Add `-Demo` for the demo or `-Editor` for the Godot editor. Steam is optional for local play. The local runtime, settings and saves continue without an owned Steam App ID; partner configuration is described in [scripts/platform/STEAM_SETUP.md](scripts/platform/STEAM_SETUP.md).

## Controls

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Aim | Mouse | Right stick |
| Fire primary | Hold left mouse | Hold RT |
| Secondary 1 / 2 / 3 | Space / Shift / Q | LB / RB / X |
| Evolve | E | A |
| Map | Tab | Back / View |
| Pause | Escape | Menu / Start |

Options include rebinding and auto fire. Evolution chooses a complete hull with its authored primary, secondaries and passives. There is no in-run component inventory or component stealing. Map and evolution menus pause combat.

## Progress and world

Start at the origin in a shared neutral seed hull with 40 light. The T2–T5 thresholds are 100, 250, 500 and 900; T5 holds up to 1500. Damage drains this same bar with no passive regeneration. Falling below 85% of the threshold that granted a tier regresses to the preceding hull, followed by reshape protection. Reaching the threshold again offers three hulls anew.

The player roster contains 81 hulls: one seed plus four choices per element at T2–T5 across five elements. The full authored library contains 136 ships including enemy, elite and rival definitions. Each hull carries a complete fixed loadout; role changes footprint, movement and slot budget.

The map generates nodes on demand. Direction chooses an angular element region; Euclidean distance controls enemy tier, density and elites. All four cardinal exits stay open during fights. The minimap reveals explored nodes and bearings to known cores, without exposing unknown encounter details. Cores lie near radii 8, 14, 20, 26 and 32; defeating all five completes the campaign.

Waypoints are earned every six nodes of outward distance and at beaten cores. After death, restart at the origin with the seed and 40 light. Discoveries, waypoints, beaten cores, unlocks and compatible story progress persist. Regular encounters reset for the new life. From the origin, jump to an earned waypoint when your current tier meets its requirement.

The demo uses Fire, Corruption and Plasma, caps hull growth at T3 with a 500-light bar and completes at the Fire core eight nodes from origin. It permits continued exploration. Importing a demo into an empty campaign preserves compatible progress and starts safely at the full map's origin.

## Author ships

Development menus expose the Ship Workshop and Ship Atlas. Ship definitions live under `content/ships`; components live under `content/ships/abilities`. The workshop and game use the same renderer and resources. Player hulls are mirrored and use the reserved light-blue chassis; ships use circle-family primitives and tethers. Save validation enforces slot and tier-point budgets.

See [docs/SHIP_WORKSHOP_V2.md](docs/SHIP_WORKSHOP_V2.md) for authoring controls, supported generator vocabulary and preview modes, and [docs/INTERFACES.md](docs/INTERFACES.md) for runtime contracts. Review the remaining editor and visual acceptance criteria against the source spec; an implemented preview is not evidence that a human designer has completed the authoring acceptance test.

## Saves and verification

Snapshots use envelope version 3, typed payloads, checksums, atomic replacement and verified backups. Device settings remain separate. Loading a legacy campaign preserves an exact `.legacy-v1` or `.legacy-v2` copy before translating compatible unlocks, deaths and story flags. Obsolete gates and old victories remain history; they do not mark the new cores beaten. Old combat entities and stolen components do not resume in the new ruleset.

```powershell
powershell -ExecutionPolicy Bypass -File tools/test.ps1
powershell -ExecutionPolicy Bypass -File tools/test.ps1 -GPU
powershell -ExecutionPolicy Bypass -File tools/export.ps1
powershell -ExecutionPolicy Bypass -File tools/export.ps1 -Demo
powershell -ExecutionPolicy Bypass -File tools/verify_exports.ps1 -LinuxContainer
python tools/package.py
powershell -ExecutionPolicy Bypass -File tools/run.ps1 -Benchmark
```

Only builds and measurements explicitly recorded in [docs/VALIDATION.md](docs/VALIDATION.md) establish current verification. Earlier archives and benchmark numbers predate the rules rewrite. A headless simulation cannot establish rendered frame rate or Steam Deck performance. Human pacing, physical-controller testing, Steam Deck qualification and real-account Steam checks remain release work in [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md).
