# Ship workshop (ship design spec, S5)

Open **Ship workshop** from the game menu or run `scenes/ship_editor.tscn`. As of S5 the workshop
edits **schema-4 rail hulls only** (`ShipDefinition.schema_version >= 4`, `ShipGrammar`/`ShipCompiler`).
Loading a schema-3 `.tres` (the retired v0.3 circle-authoring format) is refused with the message
"retired by the ship design spec" — the working ship is left untouched.

## The designer does not place circles

A rail hull stores only its **grammar**: `chassis_color`, `accent_color`, `core_depth`, `core_weapon`,
`archetype`, `passives`, `rails` (each a `radius`/`order`/`speed`/`phase`/`pump_phase`/`pump_amp`/
`reach_ring`/`offset` and an array of `slots`), `chain_links` and `chain_mode`. Every circle's
position is *derived* by `ShipCompiler.compile()` from that grammar and the ladder in
`ShipGrammar` — never authored, never dragged. `ShipCatalog.refresh(ship)` recompiles `parts` after
every change; `ShipCatalog.save_ship(ship, path)` strips them back out before writing, so a saved
`.tres` never carries compiled geometry.

## The one mutation choke point

Every tab, and every top-bar action that changes the ship, calls `edit(label, mutate)` on the editor:
it duplicates `working`, runs `mutate` on the copy, commits ONE `UndoRedo` step, and refreshes
`compiled` (a `ShipCatalog.refresh`d duplicate of `working`) for the canvas and the two zoom previews
to draw. Nothing else is allowed to touch `working` directly — this is what makes "one edit, one undo
step" true everywhere, including inside a tab's own helper functions.

## The shell

- **Top bar** — Load Ship… (a file dialog; there is no editor-owned library window in this phase — a
  gallery replaces it later), Save, Save and Exit, Exit, a Stats toggle.
- **Header** — Tier, Circles *n*/128 (from `ShipCompiler.budget`), Set pieces mounted, and a
  read-only **Symmetry** label: `Mirror` on a player hull, `Rotational` on a non-irregular enemy,
  `Irregular` on an irregular elite. There is no Symmetric Mode toggle to author around any more —
  symmetry is a property of the grammar, not an authoring mode.
- **Canvas** — a ring diagram over the production `ShipRenderer` (see below).
- **Two zoom previews** at 1.00 and 0.6561, the game's own base/minimum HUD scale.
- **Undo / Redo**, a bullet preview against a dummy, and the elite-preview line (see below).
- **Description box** — still wired to `ShipAuthoring.from_description`, which is a stub in this
  phase ("generation moves to ShipRecipe in S9"); it always returns an error, on purpose.

## The tabs (`scripts/editor/tab_*.gd`, base class `editor_tab.gd`)

- **Core** — header fields (Name, ID, Faction, Archetype, Tier, Role), core depth 2–4, core weapon
  (non-players only, offered from `SetPieceCatalog.legal_for` the current colour pair, filtered to
  `is_implemented`), and passives capped by `GameTuning.slots(tier, role).passive`.
- **Rails** — Add rail always appends the next ladder radius (`ShipGrammar.RAIL_RADII`) with a
  default speed of `ShipGrammar.rail_speed(index)` (the opposite sign from the rail before it);
  Remove outer rail removes the last one. Order (3–8) re-tiles the slot array to exactly that many
  slots, keeping as many existing ones as fit. Speed is a signed spinner with a Flip sign button; a
  warning appears (and the validator's `RAIL-SIGN`) the moment two adjacent rails stop alternating.
  Phase and pump phase are plain spinners. The rail centre offset is only editable on an irregular
  elite (`ShipGrammar.MAX_RAIL_OFFSET` = 12 px).
- **Slots** — pick a rail and a slot (or click one on the canvas), choose hub / node / stub, pods
  1–4, node radius 4 or 7, HP, and a set piece from the pool that is both colour-legal
  (`SetPieceCatalog.legal_for`) and implemented (`SetPieceCatalog.is_implemented`). Player-only mount
  field (`primary` / `secondary_N`). **Apply to symmetric orbit** is on by default: it copies the
  edit to every slot on the rail, so a non-irregular enemy's rotational symmetry holds by
  construction instead of being caught by the validator after the fact. Turning it off and editing
  one slot alone is exactly what triggers `SYM-ROT`.
- **Colours** — chassis and accent pickers (a player's chassis is locked to blue; blue is disabled
  for an enemy in both fields) and a read-only list of all 33 set pieces, with illegal ones for the
  current pair disabled and a tooltip naming the missing colour. **A colour change is never
  blocked and never auto-unmounts anything.** It shows a red "MOUNTED BUT ILLEGAL" block listing
  `ShipGrammar.illegal_mounts(working)` by name and location, each with its own Unmount button plus
  an Unmount all; the status line reports the save as blocked (`COLOUR-GATE`) until it is cleared.
- **Motion** — per-rail speed and pump amplitude (a checkbox reverts to the `ShipGrammar.MOTION`
  default), the selected slot's bob-amplitude override, and chain mode for the chain archetype.
  Nothing here has a default baked into a ship file: an override is the only thing ever stored.
- **Set Pieces** — read-only: id, colours, weapon, slot kind, implemented yes/no, for all 33. Set
  pieces are authored once by hand (`scripts/ships/set_piece_catalog.gd`) and never edited per ship.

## The canvas (`scripts/editor/ship_canvas.gd`)

A ring diagram drawn over the real `ShipRenderer` (kept as a child so the preview is always what the
game actually renders). It fits the outermost rail radius (or the innermost addable one, on an empty
hull) to the panel. The four ladder rails are drawn faint when unused and in the chassis colour when
used; slot markers show hub (a ring with pod ticks), node (a dot) or stub (a faint dashed ring) at
their rest-pose angle plus the rail's offset; a forward arrow and, on a player hull, a mirror-axis
line; illegal mounts (from `ShipGrammar.illegal_mounts`) are ringed red.

**Polar picking** is a static, pure function, `ShipCanvas.pick(point, ship)`, so it is testable
without a scene tree: a click within 34 px of the core selects the core; else the nearest rail
within ±10 px; within that rail, the slot nearest the click's angle if the click lands within 12 px
of that slot's rest-pose centre, else the rail itself. A click that lands near no rail and outside
the core selects nothing.

## Elite preview

Selecting a hub prints `HP n · subtree = N circles, M lines · rail k goes when the last of its
clusters dies`, with N and M read from `ShipMotion.get_rig(compiled).subtree_size` and the rig's
line list for that hub's contiguous subtree range — the actual detachment unit in combat, not a
hand-counted guess.

## JSON (spec §10)

`ShipAuthoring.to_json(ship)` emits the shape spec §10 shows, with a **fixed key order**, the
`"node"` / `"stub"` string shorthand for a plain node of radius 4 or any stub, and every float
snapped to 0.0001 — so export → import → export is byte-identical (a phase nudged by 0.001 changes
the bytes; that is the negative control `ships_editor_test.gd` runs against every fixture in
`tests/fixtures/ships_v4/`). `ShipAuthoring.from_json` delegates parsing to `ShipGrammar.from_dict`,
which is strict: an unknown key is an error, because a rail hull's positions are derived, never
authored, and a file that tries to author one must not be read as though it had. The v2/v3 legacy
importers, mirror-pair regeneration and `rebuild_loadout` retired with the v0.3 editor; a schema-3
hull keeps its own `ShipCatalog.validate` path but no longer opens in this editor.

## What is gone

Symmetric Mode as a toggle, free placement, drag handles, the line tool, the `concentric_rings` /
`crescent` macros, mirror authoring, the per-part inspector, the old Motion-group section, and the
editor's own library window. Set pieces are read-only; a rail hull's structure comes entirely from
the grammar tabs above.

## Verification

`tools/test.ps1 -Only ships_editor_test` covers: `edit()` as the sole mutation path with one edit per
undo step; add-rail's ladder radius and sign; order re-tiling; symmetric-orbit propagation and its
`SYM-ROT` control; the colour-change / illegal-mount / unmount flow and its `COLOUR-GATE` control;
the Slots palette's legal-and-implemented intersection; save refusing an invalid ship and writing no
`parts` for a valid one; the byte-identical JSON round trip for all five §10 fixtures; polar picking
on a known click and its off-rail control; and a schema-3 `.tres` being refused. `tools/test.ps1
-GPU` runs the whole suite, including `golden_trace_test`, unchanged by this phase.
