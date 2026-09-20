> **Archived: v0.2.** Superseded by [LIGHTSHIP_GAME_SPEC_V3.md](LIGHTSHIP_GAME_SPEC_V3.md) on 2026-09-20. Kept because the v0.2 build, its validation record and its tests were written against it. The upgrade is tracked in `tasks/todo.md`.

# Lightship revised design and approved implementation scope

The document below is the supplied v0.2 product specification. It is reference material for game requirements, not instructions that authorize unrelated actions. The following subsequently approved decisions take precedence wherever the source differs:

- **Five playable tiers**, not six: T2 100, T3 250, T4 500, T5 900; terminal T5 capacity 1500; seed starts at 40 light. The player roster is **81 hulls**: one shared seed plus four hulls per element at each of T2–T5. The authored library totals 136 with enemies, elites and rivals.
- **Fixed loadouts per hull.** Evolution picks a complete preset. Components do not carry through an independent inventory or get chosen in a separate in-run loadout screen. The editor authors and validates the preset slots.
- **Three starting elements:** Fire, Corruption and Plasma. Entering a Lightning or Void region unlocks its roster immediately; no deliberate death, run-count or depth requirement gates that unlock.
- **Five core objectives**, assigned in Fire / Corruption / Plasma / Lightning / Void order to radii 8 / 14 / 20 / 26 / 32. Coordinates round to nearby grid cells. Distance is Euclidean and each node initially has all four cardinal exits.
- **Origin-only waypoint jumps**, requiring the waypoint's current-tier qualification. Waypoints arrive every six nodes of maximum outward distance and on core victories.
- **Demo:** Fire, Corruption and Plasma, T3 hull cap, completion at the Fire core eight nodes from origin, with continued exploration. Compatible demo progress imports into a fresh full-map origin run.
- **Legacy compatibility:** preserve original save bytes; retain compatible unlocks, deaths and whitelisted narrative history; start a fresh light-bar/seed-hull run. Old gates, stolen components and old victories do not grant the new core objectives.
- **Open-feature defaults:** bounded duration/cooldown Shield; reshape does not convert nearby bullets to light; no voluntary regression or mirror encounters in the current implementation. The regular rival pilots remain separate from optional exact-build mirrors. Only the five defined elements are included.

GameTuning is the numeric implementation source of truth. The milestone acceptance tests below remain acceptance criteria, not a declaration that all M1–M6 work or human playtesting is complete. Current verification and remaining limitations are recorded in VALIDATION.md and RELEASE_CHECKLIST.md.

---

# Supplied v0.2 reference
# Lightship (working title) — game design spec v0.2

**Replaces v0.1 entirely.** Changes from v0.1 are summarised in Section 21 so nothing already built gets silently invalidated. Numbers marked *(tune)* are starting values. Section 22 lists what is still open.

---

## 1. Summary

| | |
|---|---|
| Genre | Top-down twin-stick bullet-hell arena shooter with Bubble Tanks-style growth |
| Platform | PC via Steam (Windows, Linux). Steam Deck friendly. No console at launch |
| Price target | US$5–10 |
| Players | Single-player only |
| Engine | Godot 4.x, 2D renderer with HDR glow. GodotSteam for achievements and cloud saves |
| Pitch | Absorb light to grow and reshape your lightship. Every AI you consume changes what you become |
| References | Bubble Tanks 2 and 3 (grow, reshape, node map, tank editor). Bullet-hell conventions. TRON for the look only |

## 2. Pillars

1. **Grow by absorbing, reshape at thresholds — and lose it the same way.** HP *is* progress. The ship can regress. This is the core tension.
2. **Light is material.** What you absorb decides what you become. The only menu in a run is the evolution choice.
3. **Elites are the difficulty.** Large, multi-weapon, destructible. Rivals are set-piece encounters; elites are the wall.
4. **Everything is circles and lines.** Every ship in the game is built from circles, rings and the lines connecting them.
5. **Light blue is the player.** No other ship, pickup or enemy bullet uses it.

## 3. Setting and IP

- The AI-verse: rival AIs fighting for control at the software level. The player is a lightship, an AI instance. Elements are the rival AIs' code dialects.
- TRON is a visual reference only. Do not use the name, light cycles, identity discs, circuit-lined suits, the word "derez", or a glowing grid floor.
- Bubble Tanks' mechanics are fine to build on; its name, art and sounds are not.

---

## 4. Core loop

1. Fly a node, dodge, shoot.
2. Absorb light. Light restores HP and adds progress — they are the same bar.
3. Cross a threshold, **evolve**: pick one of three hulls, ship reshapes.
4. Fly out through a node exit into an unknown neighbour. Outward is harder.
5. Take damage, fall below a threshold, **regress** a tier. Fall below tier 1 and you're sent to the origin.
6. Push out to a rival core, beat it. Five cores beaten ends the game.

## 5. HP as the progress bar

**This replaces the separate HP and energy systems in v0.1.**

- One bar. Light absorbed fills it; damage drains it. Tier is read off the bar's total.
- **Thresholds** *(tune)*: T2 100, T3 250, T4 500, T5 900, T6 1500. Max fill is the next threshold; a full bar at tier n triggers the evolve prompt.
- **First evolution must land within 2 minutes** for a new player. Tune T2 to that.
- **No passive regeneration.** The only heal is absorbing light. This is what keeps light valuable and the early game tense.
- **Regression buffer.** Dropping a tier happens at **85%** of the threshold that granted it *(tune)*, not at 100%, so the player doesn't flicker across the line.
- **Regression grace.** 1.0 s of invulnerability while the ship reshapes down *(tune)*, so a losing player isn't chain-hit through the animation.
- **Re-choice on regrowth.** When the player re-crosses a threshold they lost, offer three hulls again, not the one they had. A bad build is recoverable.
- **Death** is falling below the tier 1 floor. Back to the origin at tier 1. Kept: waypoints reached, rival cores beaten, story progress, meta unlocks.
- **Difficulty shape.** Early game is tight — low HP means real dodging. T4–T6 is the power fantasy: heavy slots, strong weapons, crowds cleared. Tune enemy density upward with distance so late tiers have something to mow.

## 6. Evolution and the hull roster

- **Six tiers.** T1 is a shared, element-neutral seed hull. T2–T6 each have a **roster of 4 hulls per element**.
- **Total buildable hulls: 1 seed + (4 hulls × 5 tiers × 5 elements) = 101.**
- **Offers.** Each evolution presents **3 hulls** drawn from the next tier's roster:
  - First evolution (T1→T2): one hull each from the top three elements absorbed so far.
  - Later evolutions: three of the four hulls in the current element's roster for that tier. If a different element accounts for more than 40% of light absorbed since the last evolution *(tune)*, one offer is swapped for that element's tier hull. **This is how a player changes element mid-run.**
  - Never offer the same three twice in a row where the roster allows otherwise.
- **Roles are tags, not the menu.** Every hull is tagged Compact, Standard or Heavy. A tier's four hulls should span at least two roles so the choice is a real trade-off.

| Role | Speed | Turn | HP buffer | Damage | Secondary slots |
|---|---|---|---|---|---|
| Compact | +25% | +25% | −20% | baseline | −1 (floor 1) |
| Standard | baseline | baseline | baseline | baseline | baseline |
| Heavy | −15% | −20% | +30% | +15% | +1 |

*(all tune)*

- **A bigger tier does not mean a bigger ship.** A Compact T5 can be physically smaller than a Standard T4. Footprint is a property of the hull, not the tier.
- **Reshape animation** (~0.8 s *(tune)*): parts with matching ids tween position and radius; new parts grow out of the core; removed parts shrink into it; tethers stretch to follow. No screen flash. Invulnerable for the duration, so evolving mid-fight is safe. Regression uses the same tween in reverse.

## 7. Slots

| Tier | Primary | Secondary | Passive |
|---|---|---|---|
| 1 | 1 | 0 | 0 |
| 2 | 1 | 1 | 0 |
| 3 | 1 | 1 | 0 |
| 4 | 1 | 2 | 1 |
| 5 | 1 | 2 | 1 |
| 6 | 1 | 3 | 2 |

Role modifiers from the table in Section 6 apply on top. Slot loadout is chosen at evolution alongside the hull; components already mounted carry over where slots allow.

## 8. Light pickups

- One light type per element. v1 elements: **Fire** (red), **Lightning** (yellow), **Void** (black with silver rim), **Corruption** (green), **Plasma** (violet).
- **Sources.** A node produces light of its region's element. Enemies shed light when hit and when destroyed; most light in a node should come from fighting, not grazing.
- **Values** *(tune)*: three sizes worth 1 / 5 / 20.
- **Shape rule.** Pickups are **hollow, slow-drifting circles** with the running light. Bullets are **solid and fast**. This difference holds everywhere in the game, so a pickup is never mistaken for a bullet.
- **Colour rule.** A pickup's colour means exactly one thing: its element.
- **Magnet radius** scales with hull, not tier — a stated stat on every hull.
- **Introduction.** New players start with two light types available; the rest unlock over the first several runs, each arriving with its region and roster.

## 9. Nodes, arena geometry and the map

**Node geometry**
- A node is a circular or rounded arena, **1.4× the viewport** in each dimension *(tune)* — bigger than what's visible, but not by much.
- **Camera is locked to the player.** No lookahead, no zoom-out to fit. Vision is centred on the ship, Bubble Tanks 3 style. Camping the edge means you cannot see most of the node, which is the intended trade: fewer angles to worry about, no idea where the enemies are.
- **Boundary margin.** A visible boundary wall with roughly 80 px of dead space beyond it *(tune)*, so the player sees the edge instead of guessing. The wall flashes at the contact point.
- **Exits.** 2–4 marked openings on the node edge. Flying into one transitions to the adjacent node. No locks, no requirements — you can always run.
- **Projectiles die at the boundary.** That is their max range. Ricochet rounds bounce off it instead.

**Map**
- Infinite procedural grid, generated on demand from a run seed. No hand-authored layout.
- **Difficulty is distance from the origin.** Enemy tier, count and elite frequency all scale with radius. Your own strength is the only gate — there is nothing to unlock a passage with.
- **Regions are angular.** Each element owns a wedge of the map, so direction picks the element and distance picks the difficulty.
- **Rival cores** sit at fixed distances in their element's wedge *(tune: 8, 14, 20, 26, 32 nodes out)*. Beating all five ends the game. Cores are ringed by elite-heavy nodes.
- **Minimap** always visible, showing explored nodes, current position, distance ring, and the direction of known cores. Unexplored nodes are dark and give away nothing.
- **Waypoints** unlock every 6 nodes of distance reached *(tune)* and at every core beaten. After death the player restarts at the origin and may jump to the deepest waypoint whose tier requirement they currently meet.

## 10. Enemies

**Regular enemies**
- Fixed bullet patterns. One element each. Tier scales with distance.
- **Pattern identity per element** *(tune)*: fire = cones, fans, lingering mines; lightning = fast bolts and instant chains; void = slow pulls and bullet-eating; corruption = spreading infection and drones; plasma = orbiting shots and rotating spirals. A player should name the element from the pattern before registering the colour.
- Standard directional audio cue on every shot fired. No visual off-screen warnings by default; Radar is an opt-in passive (Section 12).

**Elites — the core difficulty**
- Significantly larger than the player: **2–4× the player's footprint at the same tier** *(tune)*. Elites are exempt from player size constraints.
- **Multiple attack points.** An elite carries 3–8 weapon circles, each firing independently on its own timer and each aiming separately. This is what makes them hard: you cannot read one pattern, you read several at once.
- **Destructible weapon circles.** Each attack point has its own HP. Destroying one removes that attack permanently for the fight and drops light. The ship visibly degrades as you break it, which is the fight's progress bar — no boss health bar needed.
- **Core exposure.** The elite's core takes reduced damage until a set number of weapon circles are destroyed *(tune: half of them)*, then takes full damage. This makes "shoot the guns off" the correct strategy without stating it.
- Asymmetry is allowed and encouraged.

**Rivals and cores**
- Rivals are set-piece encounters, not the difficulty backbone. Decision-driven rather than pattern-driven: dodge incoming shots, lead the player, retreat to absorb when low, use components deliberately.
- Human-like limits *(tune)*: 150–300 ms reaction delay, 2–5° aim error. Challenge from decisions, never from perfect aim.
- Rivals prefer the largest target near them and will damage each other.
- **Reward is energy only.** Anything above the player's tier pays scaled by the gap *(tune: ×1.5 per tier above)*. There is no component stealing.
- **Mirrors** (optional, M4): a ship at the player's exact bar total on a different element with one extra buff, shown before the fight. Requires every player hull to be bot-pilotable, so component abilities stay simple to aim.

**Enemy-only components** — never available to the player:

| Component | Behaviour |
|---|---|
| Egg | Large circle. When damaged, bursts into a spread of seeker missiles |
| Droid bay | Releases seeker droids: larger, tankier seekers that do more damage |
| Deployment ramp | Periodically releases small regular units |
| Turret ring | A ring of small weapon circles rotating around the elite's body, each firing outward |

## 11. Weapons and abilities

### Primaries (1 slot, always filled)

| Name | Behaviour | Notes |
|---|---|---|
| Pulse cannon | Basic aimed shots | Starting weapon |
| Beam | Piercing beam in a straight line, constant damage while held | Highest damage of the beams; aiming is the cost |
| Homing beam | Piercing beam that curves into the nearest enemy; retargets instantly when a closer enemy appears at the point of contact | **Lower DPS than Beam** *(tune: 60%)* |
| Ricochet | Bullets bounce off the node boundary | Rewards edge play, which the camera otherwise punishes |
| Flame cone | Short-range spreading cone | Fire |
| Bolt | Fast, accurate single shots, chains to a second target | Lightning |

### Secondaries

| Name | Behaviour | Balance notes |
|---|---|---|
| Virus | Latches onto the nearest enemy, very high DPS until it dies, then splits into two viruses at half DPS which do the same | **Hard cap at two generations.** Gen 0 latch → gen 1 (×2, 50%) → gen 2 (×4, 25%) → stop |
| Seeker missiles | Homing missiles | See the T4 passive below |
| Rocket launcher | A volley of rockets on curved, wandering paths | Slow, high total damage |
| Shield | Blocks all incoming projectiles within a radius | **Needs a limit**: duration + cooldown, or a hit budget before it breaks. Strongest thing on this list |
| Explosives | Red circles appear on the ground with a growing inner circle; when inner meets outer, it detonates | Same warn-then-fire idiom as the laser prong |
| Laser prong | Red path line draws for 0.8 s, then a 0.25 s beam along exactly that line, 0.5 s cooldown *(tune)* | The reference telegraph |
| Poison cloud | Damage over time plus a movement slow | **Slow caps at 30%** *(tune)*, and must be clearly marked on the player when active |
| Mine layer | Drops proximity mines behind the ship | Fire affinity |
| Orbital blockers | Satellites that orbit and absorb bullets | Void affinity |

### Passives (T4+)

| Name | Behaviour |
|---|---|
| Orbital seekers | Seeker missiles idle in orbit around the ship until an enemy enters a radius, then launch at it |
| Radar | Off-screen enemies show as edge blips |
| Health readout | Numeric bar values and enemy HP |
| Magnet | Larger pickup radius |
| Siphon | Light absorbed restores more of the bar |
| Thrusters | Speed and turn rate |
| Forcefield | Constant small damage aura at contact range |

---

## 12. Visual system — circles and lines only

**This section replaces v0.1 Section 11. All previous designs containing triangles, diamonds, chevrons or hexagons are scrapped.**

### Construction

1. **The only primitives are:**
   - **Circle** — dark fill, bright rim
   - **Ellipse** — corruption only
   - **Ring** — unfilled circle
   - **Concentric rings** — circles within circles, sharing a centre
   - **Crescent** — a circle minus an offset circle
   - **Arc segment** — a partial ring
   - **Tether** — a straight line joining two circle centres, clipped at both rims
   
   Nothing else. No polygons of any kind.

2. **Fill and stroke.** Each part has a dark fill (its colour at roughly 10% luminance) and a **1.5 px bright rim** in its role colour. Parts overlap freely. Draw order: reach rings → tethers → outer circles → body → components → core.

3. **Symmetry.** Player lightships are **bilaterally symmetrical** about the forward axis, always. Enemies may be asymmetric.

4. **Core.** A small filled circle (radius ≈ 3 px at base zoom) at the body centre. Player core is white; enemy core is a dot in the ship's chassis colour. The core is the hitbox.

### Life

5. **Running light.** Every part's rim carries one bright segment covering about **13% of its circumference**, in the pale tint of its rim colour, travelling continuously at **one lap per 2.0 s** (every fourth part at 1.6 s). Phase offsets are distributed across parts (0, −0.7 s, −1.3 s) so nothing moves in sync. Tethers carry the light too, running body-to-satellite. Segment width ≈ 2.6 px, round caps. This is what makes a ship look alive; a ship with static rims is wrong.

6. **Motion signatures** — the backup channel for element identity when colour fails:

| Element | Signature |
|---|---|
| Fire | Running lights flicker in speed rather than running smoothly |
| Lightning | Lights snap around the rim in jumps rather than sliding |
| Void | Circles drift slightly inward toward the core, then reset |
| Corruption | Whole ship breathes: scale 1.00 → 1.05 → 1.00 over 2 s, ease in-out, per-ship phase |
| Plasma | Concentric rings counter-rotate |

### Meaning

7. **Every visible part is an ability.** Each tier adds circles, and each added circle is a mounted component or a body segment that grants a stat. Nothing is decorative. A player should read any ship's moves from its silhouette, including an elite's.
8. **Growth by addition, not scaling.** A higher tier keeps the lower tier's arrangement and adds around or inside it. Camera zoom changes at most ~10% per tier *(tune)*.
9. **Silhouette must be discrete.** Design every hull at its smallest on-screen size first.

### Element shape language, without polygons

| Element | Chassis | Arrangement | Components |
|---|---|---|---|
| Fire | Red | Dense clusters of small circles fanning outward from the body, radius decreasing outward, short tethers | Yellow ember circles, cinder pods |
| Lightning | Yellow | Few circles on long straight tether spokes, tight small circles at the ends | Violet capacitor circles |
| Void | Black with silver rim | A black disc that widens each tier with the build happening inside it; crescent forward; concentric rings; satellites on a dashed reach ring | Red weapon orbs, gold satellites |
| Corruption | Green | Irregular blob clusters of unequal ellipses tied by tethers, off-axis buds | Yellow nuclei and spore buds |
| Plasma | Violet | Concentric orbital rings with circles riding on them | White-hot core circles |

**Colour rule.** Choosing an element does not exclude other colours. Chassis colour and core say whose ship it is; components keep their own colours and look identical wherever they are mounted. **Light blue is the player's chassis and appears nowhere else.**

**Void exception.** Void parts are pure black with a silver rim, and the hull disc occludes glow, bullets and pickups behind it, so it reads as a hole in the light. A faint dashed silver ring outside the hull shows the reach of area abilities.

### Line and light

10. Weights, constant in screen space: rim 1.5 px, tethers 2 px, running light 2.6 px, reach and reference rings 1 px dashed (2 on, 4 off) at 40–60% opacity. No other weights.
11. Hard edges. No hand-drawn glow, no gradients, no drop shadows. Bloom supplies all glow.
12. Only running lights, cores and projectiles push above the bloom threshold. Rims sit just under it.

### Player-specific

13. **Light blue is the majority of a player hull's shapes** — body circles, rings and tethers. The element shows through arrangement (the table above) and through component colours.
14. Player projectiles are light blue.

## 13. Background and playfield

- Playfield base `#050507`.
- **Two parallax layers of dim circuit or data-flow traces** — thin lines and small nodes, no grid. Layer A at 0.15× player speed, layer B at 0.35× *(tune)*. Parallax is the point: a static pattern barely helps you feel movement.
- Brightness 10–15% of a lit rim, **always below the bloom threshold**. If the background glows, it competes with bullets.
- No vignette, noise, starfield or gradient wash. No glowing grid floor.
- Each element's region tints its trace pattern slightly toward the element hue, so the background tells you whose territory you're in.

## 14. Ship editor

An in-engine, dev-facing tool, modelled on the Bubble Tanks 3 tank editor, TRON-themed. The designer uses this daily, so it needs to be solid, not a debug panel.

### Layout

**Top bar:** `Symmetric Mode` (toggle, forced on for player hulls) · `Load Ship…` · `Save` · `Save and Exit` · `Exit` · `Stats` (toggle)

**Main canvas (left, largest area):**
- Concentric guide rings every 20 px from the centre, thin and dim
- A horizontal facing centreline with a forward arrow at the right edge
- Origin marker at the centre showing where the core sits
- Overlay header: `Tier N` with a fill bar and `Max Tier: 6`; `Complexity` bar; `TP: n` with `Max TP: m`
- `Undo Last` at bottom right

**Right column, top — Stats panel:** Speed, Max HP buffer, Footprint (px), Role tag, Primary, Secondaries, Passives, Slots used / available, TP used / max.

**Right column, middle — vertical tabs:** `Body` · `Primary` · `Secondary` · `Passive`

**Right column — preview pane:** shows the selected component with the label "Click and drag object". Dragging it onto the canvas places it (mirrored automatically when Symmetric Mode is on).

**Right column — component list:** scrollable, each row a TP cost badge plus a name. Rows are greyed when unaffordable or tier-locked, and highlighted when selected. Body tab lists circle, ellipse, ring, concentric rings, crescent, arc, tether.

### Budgets

Two limits, both enforced:
- **Slots** (Section 7) — a hard cap on mounted primaries, secondaries and passives.
- **TP (tier points)** — a budget for total build cost, which keeps hulls from being visually overloaded. Body parts cost TP by size; components cost TP by power.

*(tune)* Max TP by tier: T1 6, T2 10, T3 15, T4 21, T5 28, T6 36. Elites get their own budget, roughly 2.5× the player budget at the same tier.

### Ship library

A browsable list of every ship in the project, opened from `Load Ship…` or its own tab:
- Thumbnail, name, element, tier, role, faction (player / enemy / elite / rival)
- Filter and sort by any of those fields
- Open, duplicate as a starting point for the next tier, rename, delete
- A "missing" view showing which roster slots are still empty (e.g. Fire T4 has 3 of 4 hulls)

### Generate from description

A text field that takes a plain-language ship description and produces a valid ship file which loads straight into the canvas for hand-editing. The editor is the source of truth: whatever generates the file, the editor validates it against the rules below before it can be saved.

### Validation and warnings

- Symmetry enforced for player hulls; asymmetry allowed for enemies
- Slot overflow and TP overflow block saving
- Warn when footprint is outside the hull's role band
- Warn when any part is not one of the allowed primitives
- Warn when a body part is not connected to the body by overlap or a tether
- Warn when light blue appears on a non-player ship, or when an element's reserved colour is misused

### Preview modes

- Live running lights, motion signature and bloom exactly as in-game
- Base zoom and minimum zoom side by side, for the silhouette check
- Reshape tween preview between any two saved ships
- Bullet pattern preview, firing the mounted components at a dummy target
- Elite mode: shows each weapon circle's independent HP and firing timer

## 15. Ships as data

Ships are data-driven so one reshape tween works between any two definitions by matching part ids.

```json
{
  "id": "fire_t3_stoker",
  "name": "Stoker",
  "faction": "player",
  "element": "fire",
  "tier": 3,
  "role": "standard",
  "chassis_color": "player_blue",
  "core": { "color": "white", "radius": 3 },
  "motion_signature": "flicker",
  "footprint": 62,
  "tp_used": 14,
  "parts": [
    { "id": "body", "shape": "circle", "radius": 16, "pos": [0, 0],
      "color": "player_blue", "light_period": 2.0, "light_phase": 0.0 },
    { "id": "body_inner", "shape": "ring", "radius": 9, "pos": [0, 0],
      "color": "player_blue", "light_period": 1.6, "light_phase": -0.7 },
    { "id": "fan_l", "shape": "circle", "radius": 7, "pos": [-18, -8],
      "color": "red", "light_period": 2.0, "light_phase": -1.3, "mirror": "fan_r" },
    { "id": "tether_fan_l", "shape": "tether", "from": "body", "to": "fan_l",
      "color": "player_blue" },
    { "id": "ember_l", "shape": "circle", "radius": 3.4, "pos": [-24, -14],
      "color": "yellow", "component": "flame_cone", "slot": "primary", "mirror": "ember_r" }
  ],
  "slots": { "primary": ["flame_cone"], "secondary": ["laser_prong"], "passive": [] }
}
```

Mirrored parts are authored once and generated on the other side when Symmetric Mode is on.

## 16. Rendering and performance

- Godot 4 with **2D HDR** on the game viewport and a WorldEnvironment glow. Starting values *(tune)*: threshold 1.0, small radius, high intensity — start at half the radius that looks right and raise intensity rather than widening. Bloom on low mips only.
- Glowing elements are drawn above 1.0 (palette colour × 1.8). Rims sit just below. Fills stay dark.
- **Bullets are not scene nodes.** Batch them (MultiMesh or direct canvas draw) with collision in code against a spatial hash. Budget: **2000 live projectiles at 60 fps on Steam Deck**.
- The running light is a shader on the rim (uniforms: perimeter position, segment length, phase).
- Line widths, bloom radius and core radius are constant in **screen space** at any zoom.
- Enemy projectiles draw above player projectiles, which draw above pickups.
- Elites with many independent weapon circles need each circle's aim and fire timers to run without per-frame allocation; pool everything.

## 17. HUD

- Minimap (corner): explored nodes, position, distance ring, known core directions.
- **One bar** for HP and progress, with tier ticks and the next threshold marked. Locks and pulses at threshold with the evolve prompt. Flashes at the regression buffer point so the player knows they are about to drop.
- Slot icons showing mounted components and cooldowns.
- Poison/slow state clearly marked on the player when active.
- Companion and rival dialogue box with portrait, bottom of screen, between fights only.
- Damage numbers off by default.

## 18. Companion and narrative

- Visual-novel style portrait and text box. Speaks only between fights; lines queue until the node is clear.
- Explains the map, regions, elements and elites. Reacts to the first evolution, the first regression, each death (a "reboot" — the story advances each time), each first elite, and each rival core.
- Rival AIs get a portrait and a line on encounter, on defeat, and occasionally when the map shifts.
- Portraits are 2D stills. No animation in v1.

## 19. Controls

| Action | Keyboard/mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Aim | Mouse | Right stick |
| Fire primary | Hold LMB (auto-fire toggle in options) | Hold RT |
| Secondary 1 / 2 / 3 | Space / Shift / Q | LB / RB / X |
| Evolve | E | A |
| Map | Tab | Back |
| Waypoint jump | From map | From map |

Full rebinding. Steam Input via GodotSteam.

## 20. Milestones and acceptance tests

**M1 — Prototype (does the loop feel good?)**
- One node with boundary wall and margin. Player as a light-blue corruption placeholder, T1–T3, circles-only. HP-as-progress with regression and buffer. Absorb, evolve, reshape tween. One regular enemy type with a pattern. Parallax background. Bloom. Ships as data plus a first-pass editor.
- Accept when: first evolution within 2 minutes; regressing feels tense rather than unfair; every part has a running light; a tester can point at any part and say what it does; 1000 projectiles at 60 fps.

**M2 — Editor and roster**
- Full editor per Section 14, including the library, validation and preview modes. Fire and corruption authored end to end: all six tiers, four hulls each, roles spanning.
- Accept when: the designer can author a new hull, see it in the library and play it without touching code; the three roles feel distinct in play.

**M3 — World**
- Infinite procedural map, angular regions, distance difficulty, node exits, minimap, waypoints, death and restart.
- Accept when: a tester who dies is back in the fight within a few minutes; running from a node into an unknown neighbour feels tense.

**M4 — Elites and combat depth**
- Elites with multiple destructible weapon circles and core exposure. Enemy-only components. The full weapon catalogue. Slots.
- Accept when: a tester works out "shoot the guns off" without being told; elites, not rivals, are what kills them.

**M5 — Elements and character**
- All five elements as enemies and hulls; typed pickups; element switching by absorption; rival cores; companion and rival portraits; mirrors.
- Accept when: testers steer toward an element on purpose by chasing its light, and can name an element from its pattern alone.

**M6 — Demo**
- Steam build with GodotSteam, Deck check, two elements polished, store page clear of TRON references.

## 21. Changes from v0.1

| v0.1 | v0.2 |
|---|---|
| Separate HP (regenerating) and energy | One bar. Light heals and progresses. No passive regen. Ship regresses |
| Death = full reset to origin | Death = falling below the tier 1 floor; regression is the normal failure |
| 5 tiers | 6 tiers |
| Two hull offers per evolution | Three, drawn from a four-hull roster per tier per element |
| Veils gating layer travel | **Scrapped.** Free node-to-node travel everywhere |
| Gates as lock-in boss sectors | **Scrapped.** Elites are the difficulty; rival cores are the objectives |
| Checkpoints from beaten gates | Waypoints by distance reached |
| Fixed layered grid map | Infinite procedural map, angular element regions, distance difficulty |
| Shape language per element (triangles, diamonds, hexagons, crescents) | **Circles, ellipses, rings, crescents, arcs and tethers only** |
| Component steal on rival defeat | **Removed.** Energy reward only |
| Off-screen enemy warnings and edge blips | **Removed** as a default. Radar is an opt-in passive |
| Projectiles with arbitrary lifetimes | Projectiles die at the node boundary |
| Small component catalogue | Full catalogue in Section 11, plus enemy-only components |
| Editor as a dev afterthought | Editor is a first-class M2 deliverable with a library and validation |
| 4 elements | 5 (Plasma added) |

## 22. Open decisions

1. Shield's limit: duration plus cooldown, or a hit budget. Prototype both.
2. Whether the reshape should swallow nearby projectiles as light.
3. Whether mirrors survive contact with the roster system, since every hull must be bot-pilotable.
4. Elite frequency curve by distance.
5. Whether elements beyond the fifth ever ship, and what hues stay distinct from each other and from light blue for colourblind players.
6. Whether a player can voluntarily regress to re-choose a hull.

---

## Appendix A — Palette

| Role | Rim | Fill | Running light |
|---|---|---|---|
| Player light blue | `#6fd3ff` | `#08233a` | `#dcf5ff` |
| Fire red | `#ff5436` | `#2a0b08` | `#ffc6b5` |
| Lightning yellow | `#ffd23f` | `#2a2206` | `#fff3bd` |
| Corruption green | `#45e06a` | `#062a12` | `#caffd5` |
| Plasma violet | `#a97dff` | `#1d1233` | `#e4d6ff` |
| Void silver | `#9aa3b3` | `#000000` | `#ffffff` |
| Void gold (satellites) | `#ffd23f` | `#000000` | `#fff3bd` |
| Weapon red (components) | `#ff5436` | `#2a0b08` | `#ffc6b5` |
| Player core | — | `#ffffff` | — |
| Playfield | `#050507` | | |
| Void hull | `#000000` | | |
| Background traces | element hue at 10–15%, 1 px | | |
| Reach rings | element rim at 40–60%, 1 px, dash 2/4 | | |

Match element hues for perceived luminance, not just contrast against black. An inherently brighter element will feel stronger regardless of its numbers.

## Appendix B — Timings, as prototyped

- **Running light:** circumference normalised to 100; 13 lit, 87 dark; advances one full lap per 2.0 s, linear, looping. Every fourth part uses 1.6 s. Phase offsets −0.7 s and −1.3 s distributed across parts.
- **Breathing (corruption):** uniform scale 1.00 → 1.05 → 1.00, 2.0 s, ease in-out, per-ship phase offset.
- **Laser telegraph:** red path line (60–90% opacity) draws from the emitter along the aim over 0.8 s and holds; then the beam, a wide faint red band (~7 px, 35% opacity) under a bright 2.6 px near-white core, for 0.25 s; then 0.5 s cooldown.
- **Explosive telegraph:** outer red ring appears; inner ring grows from 0 to the outer radius over 1.2 s *(tune)*; detonation on contact, damage for 0.25 s.
- **Reshape:** 0.8 s, invulnerable throughout. Regression adds 1.0 s of grace after it completes.

