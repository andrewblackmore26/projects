# Lightship (working title) — game design spec v0.1

**Audience:** the AI coder building the game. This is a design-requirements document: it says what the game must do and how it must look, not how the project should be structured. Numbers marked *(tune)* are starting values. Section 20 lists the decisions still open; everything else is settled.

---

## 1. Summary

| | |
|---|---|
| Genre | Top-down twin-stick bullet-hell arena shooter with Bubble Tanks 2-style growth |
| Platform | PC via Steam (Windows, Linux). Steam Deck friendly. No console at launch |
| Price target | US$5–10 |
| Players | Single-player only. Multiplayer is not planned |
| Engine | Godot 4.x, 2D renderer with HDR glow. GodotSteam for achievements and cloud saves |
| Pitch | Absorb light to grow and reshape your lightship. Every AI you consume changes what you become |
| References | Bubble Tanks 2 (grow, reshape, sector map). Bullet-hell conventions (core hitbox, telegraphs). TRON for the look only |

## 2. Pillars

1. **Grow by absorbing, reshape at thresholds.** The ship growing and then snapping into a new form is the core feeling. Protect it above everything else.
2. **Light is material.** What you absorb decides what you become. The only menu in a run is a single two-option choice at each evolution.
3. **Rivals are competitors, not scenery.** They grow, make decisions and hold territory. Beating one above your tier is the best thing you can do in the game.
4. **Everything reads from silhouette.** Ships are clusters of lit shapes, and every visible part is an ability.
5. **Light blue is the player.** No other ship, pickup or bullet uses it.

## 3. Setting and IP

- The AI-verse: rival AIs fighting for control at the software level. The player is a lightship, an AI instance. Elements are the rival AIs' code dialects.
- TRON is a visual reference only. Do not use: the name, light cycles, identity discs, circuit-lined suits, the word "derez", or a glowing grid floor. The playfield is near-black with no grid.
- Borrowing Bubble Tanks' mechanics is fine; do not borrow its name, art or sounds.

---

## 4. Core loop

1. Fly a sector, dodge bullets, shoot enemies.
2. Absorb light pickups. Light adds **energy**. Energy is tier progress.
3. At an energy threshold, **evolve**: choose one of two forms, ship reshapes.
4. Explore the sector grid outward. Cross veils, beat gates, unlock checkpoints, take territory.
5. Die and reset (Section 7). Regrow, teleport to the furthest checkpoint your energy allows, push further.

**HP** is separate from energy. HP regenerates when out of combat; energy only goes up until death.

*(Open, settle in M1: whether taking damage also sheds light. v1 default: damage costs HP only.)*

## 5. Energy, tiers and evolution

- Five tiers per element root. Thresholds *(tune)*: T2 100, T3 300, T4 700, T5 1500. Tune so a new player's first evolution lands **within 2 minutes** of starting.
- **Trigger.** On reaching a threshold the ship locks and pulses (step change, not a ramp) and an evolve prompt appears. Evolution is player-triggered and stays available until taken.
- **Choice.** Two forms are offered: the next tier of the two light types absorbed most since the last evolution. Ties go to the current root. If only one type was absorbed, offer that root's next tier plus the current root's next tier.
- **First evolution** (from the starting seed) offers up to three roots, ranked by lights absorbed. This is how a run picks its starting paths.
- **Crossing over.** Because the offer follows what was absorbed, a player can steer into a neighbouring root at any evolution by feeding on that light. No respec menu.
- **Reshape animation** (~0.8 s *(tune)*): parts with matching ids tween from old to new position/size; new parts grow out of the core; removed parts shrink into the core. Tethers stretch to follow. No screen flash. The ship is invulnerable for the duration so evolving mid-fight is safe. Optional: pull nearby pickups in during the reshape.
- **Reshape, never resize.** Tier n+1 is tier n with more parts around it, not a scaled copy. Camera zoom changes at most ~10% per tier *(tune)*. Line widths and bloom radius stay constant in screen space.

## 6. Light pickups

- One light type per element. v1 elements: **Fire** (red), **Lightning** (yellow), **Void** (black with silver rim), **Corruption** (green). Planned later: Plasma/Pulsar (purple) and others, up to 8–10 roots.
- **Sources.** A sector produces light of its owner's type. Enemies shed light of their element when hit and when destroyed. Rival bosses shed a lot.
- **Scarcity.** Each sector has a finite pool that regenerates slowly *(tune)*. Grazing without fighting must not be the best strategy; most light in a sector should come from enemies.
- **Values.** Three sizes worth 1 / 5 / 20 energy *(tune)*.
- **Shape rule.** A pickup is a small version of its element's base shape (fire: triangle, lightning: diamond, void: crescent, corruption: blob), drawn **hollow**, drifting **slowly**, with the running light (Section 11). Bullets are **solid** and **fast**. This difference holds for every pickup and every bullet in the game.
- **Colour rule.** A pickup's colour means exactly one thing: its element.
- **Magnet radius** grows with tier. This is what a bigger ship buys, since the hitbox never grows.
- **Introduction.** New players start with two light types available. The remaining types unlock over the first several runs (meta progression), each arriving with its rival and branch.

## 7. World, map and death

**Structure**
- The world is a grid of **sectors** (use "Sector" in code; avoid "node", which is Godot's word). Each sector is an arena the player can fly out of from any edge into the neighbour, unless locked.
- Sectors are arranged in **layers** outward from the origin. Difficulty scales by layer. Layer 0 is the origin and is safe.

**Map**
- Minimap always visible in a corner; full map on toggle/hold.
- Unexplored sectors are dark. When the player is within **3 sectors** of a high-threat sector, that sector shows an energy-radiation icon on both maps. The icon shows the tier gap (e.g. "+2") and the light type present, so it answers both "can I take this?" and "do I want what it drops?"

**Territory**
- Each rival AI owns a contiguous region. A sector's light type is its owner's. Where you go picks the element; how far out picks the difficulty.
- Borders drift between the player's lives (rivals fight each other off-screen). Clearing a sector flips it to the player (shown light blue on the map). Player territory **persists through death**.

**Veils and gates**
- Layer boundaries are **veils**: crossing requires current energy ≥ the boundary's threshold. A threshold, not a toll; passing costs nothing. The requirement is shown on the map.
- The only ways through a veil are **gates**: lock-in sectors. Entering a gate locks all exits until the gatekeeper (a rival-class boss) is beaten. 2–3 gates per boundary, each held by a different rival/element, so the player chooses the fight and the light. The map marks gates and their lock-in behaviour **before** entry; no surprise traps.
- A beaten gate becomes a **checkpoint**.

**Checkpoints and death**
- Death = full reset: energy 0, tier 1 seed, back at the origin. Kept: unlocked checkpoints, player territory, story progress, meta unlocks (light types discovered, unlocked branches).
- Teleporting to a checkpoint requires energy ≥ that layer's veil threshold. After a death the player regrows in the inner layers, then jumps. Target *(tune)*: a returning player can regrow to the furthest checkpoint threshold in a few minutes, so a death costs minutes, not the run.
- Death is a story beat, not a punishment screen (Section 10).

## 8. Enemies and rivals

**Regular enemies**
- Run fixed bullet patterns. Built from the shape system in their element's colours (Section 12 designs are the enemy and rival designs).
- Enemy tier scales with map layer, not with the clock. Bullet size and density scale with enemy tier. Grown enemies cannot be dodged by weaving to the end: the veils are the justification.
- Enemies carry components from the player tree, so every enemy previews a path the player has not taken.
- **Pattern identity per element** *(tune)*: fire = cones, fans and lingering mines; lightning = fast bolts and instant chains; void = slow pulls and bullet-eating; corruption = spreading infection and drones. A player should recognise an element by how it shoots before registering its colour.

**Rivals** (gatekeepers, territory bosses, roaming)
- Same tree and components as the player, driven by decisions rather than patterns: dodge incoming shots, lead the player's movement, retreat to regenerate when low, grab light mid-fight, use components deliberately.
- Human-like limits *(tune)*: 150–300 ms reaction delay, 2–5° aim error. Challenge comes from decisions, never from perfect aim.
- Visible intent: brief aim lines before firing, obvious retreat behaviour.
- Rivals prefer the biggest target near them. Rivals damage each other.
- Rivals grow with map progress (layer and player tier), not with the clock, so deaths do not leave the player further behind.

**Rewards**
- **Reward by gap.** Destroying anything above the player's tier pays energy scaled by the gap *(tune: ×1.5 per tier above)*.
- **Component steal.** Beating a rival grants one of its components for the rest of the run, mounted on the current form. Thematically the player absorbs its code.
- **Mirrors.** Occasionally the player meets a ship with the same energy total but a different root and one extra buff. The buff is shown before the fight. Winning offers a switch to the mirror's root at the next evolution. Requirement: every player form must be pilotable by a bot, so keep component abilities simple (aimable, no complex input).

## 9. Combat rules

- **Hitbox is the core only.** Bullets damage HP only when they touch the core. Body parts do not collide with bullets. Contact with an enemy body damages the player core.
- **HP** *(tune)*: 100 at T1, +25 per tier. Regenerates 10%/s after 3 s without taking damage.
- **Telegraphs.** Any attack that cannot be dodged on reaction shows a warning ≥ 0.5 s before it lands.
- **Laser prong** (component, any element): a yellow prong with a red tip. On fire: a thin red line extends from the tip along the aim over 0.8 s, holds, then a 0.25 s beam follows the line exactly, then 0.5 s cooldown *(tune)*.
- **Minimum visible lifetime.** Any hit, absorb or short event is drawn for at least 0.25 s so it registers.
- Player bullets are light blue, solid, and never hidden behind enemy bullets (draw enemy bullets on top).

## 10. Companion and narrative

- **Companion:** a visual-novel style portrait with a text box. Speaks only between fights; lines queue until the current sector is clear. Explains the map, veils, elements and gates; reacts to the first evolution, each death (a "reboot", and the story advances each time), the first gate and each new rival.
- **Rival AIs as characters:** portrait plus a line on gate entry, on defeat, and occasionally when a border shifts.
- Portraits are 2D stills. No animation required in v1.

---

## 11. Lightship visual system

These are the rules that produced the approved designs in Section 12. They apply to every ship in the game, player and enemy.

**Construction**
1. A lightship is a **cluster of separate primitive shapes**, Bubble Tanks style. Never a single traced outline. Primitives: circle, ellipse, triangle, prong (thin triangle, length ≥ 4× base), diamond, chevron (four-point kite), hexagon, crescent (circle minus an offset circle), arc segment, ring, and **tether** (a straight line joining two parts).
2. Each part has a **dark fill** (its colour at roughly 10% luminance) and a **1.5 px bright stroke** in its role colour. Parts overlap freely. Draw order: reference rings → tethers → outer parts → body → components → core.
3. **Symmetry.** Bilateral around the forward axis. Satellites and wings come in mirrored pairs; the single forward component (ember, needle prong, crescent, spore bud) sits on the axis.
4. **Core.** A small filled circle (radius ≈ 3 px at base zoom) at the body's centre. Player core is **white**; enemy core is a dot in the ship's chassis colour. The core is the hitbox.

**Life**
5. **Running light.** Every part's edge carries one bright segment covering about **13% of its perimeter**, in the pale tint of its stroke colour, travelling around the edge continuously at **one lap per 2.0 s** (every fourth part runs at 1.6 s). Parts carry phase offsets (0, −0.7 s, −1.3 s, distributed across parts) so the lights never move in sync. Tethers carry the light too, running from body to satellite. Segment width ≈ 2.6 px with round caps. This replaces Bubble Tanks' moving parts as the thing that makes a ship look alive; a ship with static edges is wrong.
6. **Breathing.** Living elements (corruption) scale the whole ship 1.00 → 1.05 → 1.00 over 2 s, ease in-out, with a per-ship phase offset. Void does not breathe. Fire and lightning do not breathe in v1.

**Meaning**
7. **Every visible part is an ability.** Each tier adds parts, and each added part corresponds to the new ability. Nothing is decorative. A player should be able to read any ship's moves from its outline, including a rival's.
8. **Growth by addition.** Tier n+1 keeps tier n's body and adds around it: satellites, prongs, pods, rings, wings. Never scale the whole ship. Footprint at base zoom *(tune)*: T1 ≈ 30 px, T2 ≈ 45 px, T3 ≈ 65 px, T4 ≈ 85 px, T5 ≈ 100 px.
9. **Silhouette must be discrete.** Tiers are recognisable steps. Design every tier at its smallest on-screen size first; it has to read on a screen full of bullets.

**Colour**
10. Each ship has a **chassis colour** (body parts and tethers) and one or two **component colours** (weapons and abilities). Choosing an element does not exclude other colours: fire uses yellow embers, lightning uses violet capacitors, void uses red weapons and gold satellites, corruption uses yellow nuclei. Components with the same function look the same on every ship that carries them, whoever owns it. The chassis and core say whose ship it is.
11. **Light blue is reserved for the player** (Section 13). It appears on no enemy, pickup or enemy bullet.
12. **Void exception.** Void parts are pure black with a silver rim. The void hull is a black disc that widens each tier while components build up inside it. Because the disc occludes glow, bullets and pickups behind it, it reads as a hole in the light. A faint dashed silver ring outside the hull shows the reach of its area abilities.

**Line and light**
13. Stroke weights, constant in screen space: base stroke 1.5 px, tethers 2 px, running light 2.6 px, reference/reach rings 1 px dashed (2 on, 4 off) at 40–60% opacity. No other weights.
14. Hard edges. No hand-drawn glow, no gradients, no drop shadows, no rounded corners on geometric parts. Bloom supplies all glow (Section 15). Only running lights, cores and bullets push above the bloom threshold; base strokes sit just under it.
15. **Base shape language per element**: fire = stacked triangles, hexagon chassis from T3; lightning = diamond body, thin prongs, chevron fins; void = black circles and crescents on a silver rim; corruption = blobs (circles and ellipses) of different sizes tied together with tethers.

## 12. Element design sheets (enemy and rival designs, approved)

Each row: parts added at that tier and the ability they carry. Earlier parts remain. Coordinates are up to the editor; the placement described is what was approved.

### Fire — chassis red, components yellow

| Tier | Name | New parts | Ability |
|---|---|---|---|
| 1 | Ember | Three stacked red triangles (tall centre, two lower flanking); yellow ember circle at the nose | **Flame spray**: short-range cone of fire bullets |
| 2 | Flare | Two red tail-vent triangles behind; flanking triangles enlarge | **Burning trail**: leaves damaging fire behind the ship briefly |
| 3 | Scorch | Body becomes a red hexagon chassis; triple crown of three flame triangles above it, each tipped with a yellow ember | **Wide flame cone**: three overlapping sprays |
| 4 | Overclock | Two swept red wing triangles ending in yellow cinder pods (r ≈ 5) | **Cinder pods**: drop lingering mines |
| 5 | Meltdown | Second outer wing pair; five-flame crown; yellow hexagon reactor core inside the red hexagon | **Heat aura**: continuous damage in a radius |

### Lightning — chassis yellow, components violet

| Tier | Name | New parts | Ability |
|---|---|---|---|
| 1 | Spark | Yellow diamond body; one needle prong forward with a violet charge diamond at the tip | **Precise bolts**: fast, accurate single shots |
| 2 | Arc | Twin prongs replace the needle; two small chevron tail fins | **Chain lightning**: bolts jump to a second target |
| 3 | Fork | Centre needle returns (three prongs, violet tips); chevron fins out sideways | **Short blink**: brief dash |
| 4 | Surge | Chevron wings extend and end in violet capacitor diamonds | **Charged bolt**: hold to fire a piercing bolt |
| 5 | Tempest | Five prongs (storm crown); second wing pair; violet diamond inside the body | **Discharge**: hits everything within a radius |

### Void — chassis black with silver rim, weapons red, satellites gold

| Tier | Name | New parts | Ability |
|---|---|---|---|
| 1 | Null | Black crescent open forward, silver rim, on the void disc; red orb in the crescent's maw | **Orbs eat bullets**: the orb absorbs bullets that touch it (capped) and fires them back |
| 2 | Eclipse | Gold corona ring around the crescent; disc widens | **Bullets to energy**: absorbed bullets become light |
| 3 | Umbra | Two gold satellites on a dashed reach ring; two red fangs on the crescent tips | **Satellites**: block bullets and can be rammed into enemies |
| 4 | Horizon | Four silver arc segments form an outer ring; three gold satellites; central red orb | **Slow field**: anything inside the ring slows |
| 5 | Singularity | Six red spikes pointing inward around a central black disc with a red orb; four satellites | **Black hole shot**: a slow orb that pulls bullets and enemies in |

Design rule: the void disc widens every tier and the build happens inside it. Void pays for eating bullets with the lowest raw damage of the elements *(tune)*.

### Corruption — chassis green, components yellow, breathes

| Tier | Name | New parts | Ability |
|---|---|---|---|
| 1 | Glitch | One green blob (ellipse) with a small trailing bud; yellow spore bud forward | **Infects on hit**: damage over time |
| 2 | Worm | Tail of two blobs on tethers, yellow nucleus in the first | **Infection spreads** between nearby enemies |
| 3 | Trojan | Two tethered side blobs with yellow nuclei (pods); small rear blob; larger body | **Hatch drones** from the pods |
| 4 | Rootkit | Four tethered anchor blobs (forward pair with nuclei, rear pair); second body blob; two shoulder blobs | **Drain**: tendrils pull energy from enemies in range |
| 5 | Botnet | Six satellite blobs on a hexagonal frame of tethers (faint hex reference ring); three with nuclei; twin shoulder blobs | **Hijack**: infected enemies fight for the player briefly |

### Shared component catalogue (v1)

Any element can mount these; they look identical wherever they appear.

| Component | Look | Behaviour |
|---|---|---|
| Laser prong | Yellow prong, red tip circle | Section 9: red path line 0.8 s, then 0.25 s beam along it |
| Ember gun | Small yellow circle | Fires the element's basic bullet |
| Cinder pod | Yellow circle r ≈ 5 on a wing tip | Drops mines |
| Capacitor | Violet diamond | Charge-and-release shot |
| Satellite | Gold circle on a dashed reach ring | Orbits; blocks bullets |
| Spore bud / nucleus | Yellow circle inside or in front of a blob | Infection source; pod hatches drones |

## 13. Player ship scheme

- The player ship is built from the same system, with **light blue as the chassis colour**: body parts and tethers are light blue and make up the majority of the ship's shapes.
- The chosen element shows through the **base shape language** (triangles, diamonds, crescents, blobs) and through the **ability components**, which use their own colours (the element's, or the component's).
- Core is white. Player bullets are light blue.
- **Exact player tier designs are not yet approved.** They are to be authored in-engine with the ship editor (Section 14) once the prototype is playable, following the rules in Section 11. Do not use the Section 12 designs as player ships except as placeholders in M1.

## 14. Ships as data, and the ship editor

Ships are **data-driven**. One reshape tween works between any two ship definitions by matching part ids. Suggested schema (JSON or a Godot resource; the shape of the data matters, not the format):

```json
{
  "id": "fire_t3_scorch",
  "element": "fire",
  "tier": 3,
  "chassis_color": "red",
  "core": { "color": "white", "radius": 3 },
  "breathes": false,
  "parts": [
    { "id": "hex_body", "shape": "hexagon", "radius": 13, "pos": [0, 2], "rot": 0,
      "color": "red", "light_period": 2.0, "light_phase": 0.0 },
    { "id": "crown_c", "shape": "triangle", "base": 12, "height": 27, "pos": [0, -22],
      "color": "red", "light_period": 2.0, "light_phase": -0.7, "component": "flame_spray" },
    { "id": "ember_c", "shape": "circle", "radius": 3.4, "pos": [0, -38],
      "color": "yellow", "light_period": 1.6, "light_phase": -1.3, "component": "flame_spray" },
    { "id": "tether_l", "shape": "tether", "from": "hex_body", "to": "pod_l", "color": "red" }
  ],
  "abilities": ["flame_spray", "burning_trail", "wide_cone"]
}
```

**Editor requirements** (in-engine, dev-only, but robust enough for the designer to use daily)
- Add, move, scale, rotate and delete parts; choose primitive, colour role, running-light period and phase; assign a component; parent tethers.
- Live preview with running lights, breathing and bloom exactly as in-game, at base zoom and at minimum zoom (silhouette check).
- Preview the reshape tween between any two saved ships.
- Save/load ship files; duplicate a ship as the starting point for the next tier.
- Optional but valuable: preview the ship's bullet pattern.

## 15. Rendering, bloom and performance

- Godot 4 with **2D HDR** enabled on the game viewport and a WorldEnvironment glow. Starting values *(tune)*: threshold 1.0, small radius / high intensity (start at half whatever radius looks right and raise intensity, never widen), bloom on the low mip levels only.
- Elements meant to glow (running lights, cores, bullets, pickups' running light) are drawn with colour values above 1.0 (e.g. the palette colour × 1.8). Base strokes sit just below 1.0. Fills stay dark.
- Playfield colour `#050507`; no vignette, noise, starfield, gradient wash or background grid. The void hull is `#000000`, which must read darker than the field.
- **Bullets** are not one scene node each. Draw them in batches (MultiMesh or direct canvas drawing) and run collisions in code with a spatial hash. Budget: **2000 live bullets at 60 fps on Steam Deck**.
- Ship parts drawn with custom draw calls or polygon/line nodes; the running light is expected to be a shader on the outline (uniforms: perimeter position, segment length, phase).
- Line widths, bloom radius and the core radius are constant in **screen space**, whatever the camera zoom.
- Enemy bullets are drawn above player bullets and above pickups.

## 16. HUD

Keep it minimal; the ship itself carries most information.
- Minimap (corner). Full map on toggle/hold, showing layers, veils with thresholds, gates, territory colours, checkpoints, radiation icons.
- Energy: a thin ring or bar showing progress to the next threshold, with the two leading light types indicated by colour. Locks and pulses at threshold with the evolve prompt.
- HP bar near the ship or in a corner.
- Companion/rival dialogue box with portrait, bottom of screen, between fights only.
- Damage numbers off by default.

## 17. Controls

| Action | Keyboard/mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Aim | Mouse | Right stick |
| Fire | Hold LMB (auto-fire toggle in options) | Hold RT |
| Component ability | Space / Shift | LB / RB |
| Evolve | E | A |
| Map | Tab (hold or toggle) | Back |
| Teleport to checkpoint | From map | From map |

Full rebinding. Steam Input support via GodotSteam.

## 18. Steam

- GodotSteam for achievements, cloud saves and Steam Input.
- Steam Deck: verified-friendly targets (controller-complete, readable text at 1280×800, 60 fps at the bullet budget).
- A free demo is required early; the concept has no direct competitor on Steam, so player feedback is the only proof it sells. Plan the demo as the first two layers and two elements.

## 19. Milestones and acceptance tests

**M1 — Prototype (does the loop feel good?)**
- One arena. Player as a light-blue-chassis corruption placeholder, T1–T3. Absorb, energy, evolve with the reshape tween. One regular enemy type (fire T1) with a pattern. Bloom. Ships as data plus a minimal editor.
- Accept when: first evolution within 2 minutes; every part has a running light; a tester can point at each part and say what it does; 1000 bullets at 60 fps; the team can answer the open question on whether damage should shed light.

**M2 — World**
- 5×5 grid, two layers, one veil, one gate with a rival boss (fire T3 using decision AI), death reset, one checkpoint, minimap and full map with radiation icons.
- Accept when: a tester understands lock-in before entering a gate; a death costs minutes, not the run.

**M3 — Elements**
- All four elements as enemies and rivals with distinct patterns; typed pickups; three-way first choice and two-way later choices; territory colouring; reward by gap; component steal; laser prong.
- Accept when: testers steer toward an element on purpose by chasing its light, and can name an enemy's element from its pattern alone.

**M4 — Character**
- Companion and rival portraits and lines; death beats; mirrors.

**M5 — Demo**
- Steam build with GodotSteam, Deck check, two layers and two elements polished, store page free of TRON references.

## 20. Open decisions

1. Whether taking damage sheds light, or only costs HP (settle in M1).
2. Final player tier designs (author in-engine after M1; light-blue-majority rule stands).
3. Whether to allow dropping back a tier to change roots mid-run, or leave crossing over to evolutions only.
4. Number of elements at launch (four is the v1 floor; 8–10 is the long-term target, with the rest as free updates).
5. Whether the reshape should also swallow nearby bullets as light.
6. Colour for the fifth-plus elements beyond purple; every element needs a hue that stays distinct from the others and from light blue, including for colourblind players. Motion signatures (fire flickers, lightning jumps, corruption breathes, void pulls) are the backup channel.

---

## Appendix A — Palette

| Role | Stroke | Fill | Running light |
|---|---|---|---|
| Player light blue | `#6fd3ff` | `#08233a` | `#dcf5ff` |
| Fire red | `#ff5436` | `#2a0b08` | `#ffc6b5` |
| Lightning yellow | `#ffd23f` | `#2a2206` | `#fff3bd` |
| Corruption green | `#45e06a` | `#062a12` | `#caffd5` |
| Violet (components) | `#a97dff` | `#1d1233` | `#e4d6ff` |
| Void silver | `#9aa3b3` | `#000000` | `#ffffff` |
| Void gold (on black) | `#ffd23f` | `#000000` | `#fff3bd` |
| Player core | — | `#ffffff` | — |
| Playfield | `#050507` | | |
| Void hull | `#000000` | | |
| Reach/reference rings | element stroke at 40–60% opacity, 1 px, dash 2/4 | | |

Match element hues for perceived luminance, not just contrast against black. If one element is inherently brighter it will feel stronger regardless of the numbers.

## Appendix B — Running light and telegraph, as prototyped

The approved previews used these exact timings; reproduce the feel, not the technique.

- **Running light:** perimeter normalised to 100 units; 13 lit, 87 dark; offset advances one full perimeter per 2.0 s, linear, looping. Every fourth part uses 1.6 s. Every third part starts at −0.7 s, every third-plus-one at −1.3 s.
- **Breathing (corruption):** uniform scale 1.00 → 1.05 → 1.00, 2.0 s, ease in-out, per-ship phase offset.
- **Laser telegraph:** thin red line (60–90% opacity) draws from the prong tip along the aim over the first 40% of the cycle and holds; then the beam: a wide faint red band (~7 px, 35% opacity) under a bright 2.6 px near-white core, for ~12% of the cycle; then fade. In-game timings: 0.8 s warn, 0.25 s beam, 0.5 s cooldown.
