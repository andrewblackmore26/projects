# Lightship — ship design spec, with the approved implementation scope

**Presentation revision (2026-09-27):** [Visual redesign](VISUAL_REDESIGN.md) supersedes this
document's guide-supported spokes and minimum circle-count targets, together with the previous
redesign's dim palette and blanket simplification. The HTML references restore bright travelling
rim lights, intricate connected anatomy and following chains. Orbit guides never provide structural connectivity. The original
specification below remains as historical context for the unchanged gameplay systems.

This file is the supplied ship design spec **v2, verbatim** (from the line `# Lightship — ship design
spec v2` down), preceded by the scope that was approved on 2026-09-21 before any code was written. v2
replaced v1 in full on the same day, before any v1 code existed; the decisions below were made against
v1 and re-checked against v2. Where the spec is silent or contradicts itself, the decisions below win.
The build plan with checkboxes and measured review sections is `tasks/todo.md` (block "Ship design
spec — build plan", phases S0–S15).

The reference image the spec calls "the attached image" is `docs/ship-design-reference.png`; its
measured census is `docs/ship-design-reference.json`. `docs/enemy-design-reference.png` is the older
v0.2-era sheet and is **not** the style target.

## Decisions made by the user (2026-09-21)

1. All 33 catalogue weapons are in scope, staged in batches. A ship only ever mounts a weapon whose
   behaviour exists (`SetPieceCatalog` `implemented` flag).
2. Loadouts stay **fixed per hull**. §6.5's "real loadout decision" is made on the evolution card: the
   four hulls offered per element and tier carry four different loadouts from that element's pool of 7.
3. On **player** hulls the rail carrying the primary is locked to the hull (speed 0), so the primary
   stays on the forward axis and the mirror axis is real at all times. The remaining rails alternate
   sign. Enemies rotate every rail.
4. **Spokes:** rails 1 and 2 run to the core rim, as the reference image shows and §1 says. Rails 3
   and 4 run from the next rail inward, as §4.3 says.
5. Enemy-only components **retire**: egg, deployment ramp, turret ring, sub-cores, the void
   bullet-eating maw and the plasma projectile-orbit ring. The boss keeps its shield generator as
   the spec's "second core stack", so the break-the-shield-first fight survives.
6. **Slots are a cap.** Lightning's pool has only two secondaries, so a lightning T6 hull flies two
   secondaries and an unarmed third hub.
7. No mid-build stops. Captures for each would-be review point are saved and listed in the review
   tables: (1) first radial elite beside the reference, (2) the 33 set-piece sheet, (3) the full
   staging gallery, (4) the two-colour enemy set for the human acceptance protocol. From S6 on they
   are produced by the gallery's own PNG export (§12.7).
8. **No element briefings.** v1 §6.6 asked for them; v2 dropped the sentence. No ECHO lines and no
   DIALECTS page. Evolution-card colour chips and HUD set-piece glyphs stay.

Decision 3 meets v2 §9.1 ("the sign alternation is not" negotiable) like this: speed 0 is legal only on
a player's primary rail; every other rail keeps §9.1's sign for its rail index.

## Interpretations adopted

Measured from the reference image (`tools/measure_reference.py` → `docs/ship-design-reference.json`;
scale 1.2526 px per unit, taking the largest circle as core_1 = 34):

| What | Measured | The spec says | What the build does |
|---|---|---|---|
| Circles | 22: core 3, 4 nodes, 3 hubs, 9 pods, 3 red rings | "roughly twenty" | — |
| Hub radius | 15.00, 15.02, 15.02 | 15 | ladder |
| Pod and inner-rail node radius | 6.95–7.22 | pod 7 (nodes "micro or pod") | nodes declare 4 or 7 |
| Inner rail | dashes at 51.5; four nodes at 51.7, phase 52.4°, worst spacing error 2.2° | 52, order 4 | ladder |
| Outer rail | dashes at 95.4; three hubs at **92.9**, phase 1.8° | 96, order 3 | hubs sit on the rail at 96 |
| Inner core ring | **17.0**, red | ladder offers 22 or 13 | 22 (`core_2`, "second core ring"); the image predates the ladder |
| Core dot | **2.6**, red | 5 | ladder |
| Pods per hub | **3**, at 29.4–30.3 from the hub centre, bearings 0° and ±51–52° from outward | v2 §4.4: 30 px out, 0.78 rad (44.7°) apart, centred on outward; §10 says `pods: 4` | v2's numbers: distance 30 (matches), spacing 0.78 rad (the image is wider, 0.90). The radial-elite fixture compared against the image uses 3 pods |
| `v_rack` | a **red ring, r 5.2**, 21.7–22.0 outward from the hub centre, on a red line from the hub centre; the V is two **amber** lines from the hub centre toward the side pods | "a red V marking inside" | traced as measured: yellow V + red pin, which is what a Yellow + Red piece should be. Set pieces may use the r 5 ladder entry |

Read from the reference image:

- **"Core stack N" counts the dot.** The image is two circles plus the dot for the "stack 3" radial
  elite. Depths: 2 = [34, dot]; 3 = [34, 22, dot]; 4 = [34, 22, 13, dot].
- **Set-piece lines start at the hub's centre and draw over the hub's fill** (the V is visible inside
  the hub). Spokes and pod links are clipped at rims and draw under fills, as in v0.3.
- **Accent colour also appears on circles**, not only on the dot and on lines as §6.1 says: the
  image's inner core ring is red, and the `v_rack` carries a red micro ring. So an enemy's innermost
  core ring takes the accent, and set-piece circles carry the set piece's own colours.
- **Set-piece colours are intrinsic per primitive and never remapped** to the ship's chassis or
  accent. That is what makes a piece "look identical on every ship" (§4.5) and what makes "a third
  colour anywhere" a checkable property of the compiled ship.
- Inner-rail **nodes are pod-size (7)** in the image, so a node slot declares radius 4 or 7.
- Set pieces point **radially outward at rest** and track the aim in play. `v_rack` is traced from
  the image, not from a draft table.

Filling holes in the spec:

- **Passive rings** sit on the ladder at r 15 and r 7, which are always free inside a 34 / 22 / 13 / 5
  stack. Thin style, at most two (the player maximum).
- **Symmetry.** §5's "filled identically" contradicts §7's own T1 row (1 hub + 2 nodes on order 3).
  Player hulls are validated on the mirror axis at rest pose. Non-irregular enemies need a slot
  pattern invariant under some rotation by k slots, 0 < k < order. Irregular elites are exempt.
- **Mirror twins.** An off-axis player weapon needs a mirror twin. Twins share one mount: the muzzle
  alternates between them and damage does not double.
- **"Elites run 2–4× the player's footprint"** cannot hold by diameter on fixed rails (at tier ≥ 3 the
  largest possible ratio is about 1.25). The gate is restated as a solid-circle and set-piece count
  ratio, which is what §3 means by "threat reads as density"; the pixel ratio is recorded beside it.
- **The 128-circle limit.** The outline shader has 128 circle slots and a top-of-range boss (20 hubs,
  4 pods, 4-circle pieces) needs about 195. The validator caps a hull at 128: a boss is 13 hub pieces
  plus the core weapon (14 set pieces); a heavy elite is 7 plus the core weapon (8). Raising the
  limit to 192 is a measured escape hatch, not the default.
- **§7's orders are not monotone** (T4 is 4,5; T5 is 6,4,3), so v0.3's "tier N−1 ids are a subset of
  tier N ids" assertion retires. Positional ids, never-decreasing rail and hub counts, and the
  reshape routes replace it.
- **Green has no primary**, so an enemy `core_weapon` may be of either slot kind. A secondary-kind
  core weapon fires at the ×1.5 enemy cadence, not the ×4.5 primary cadence.
- **Consequences of a blue player chassis.** The ten hybrids without blue are enemy-only, so the
  player loses the rocket launcher and seeker missiles. `homing_beam` and `laser_prong` retire; their
  telegraph machinery becomes `refract_beam`.
- **The ladder binds ships and set pieces only**, not projectiles, pickups or FX.
- **Nothing scales.** v2 §9.3 pumps a rail's radius, not a cluster's scale, so a hub measures 15 px
  at every tick. The one exception the spec itself makes is the core dot's pulse (§9.5), which is
  render-only: the 3 px core collider never changes. The dashed ring stays at the rail's nominal
  radius while its hubs pump ±3% around it.
- **Motion defaults are data, not file content.** §9's tables live in `ShipGrammar.MOTION`; a ship file
  stores only what it overrides.
- **Stateful motion lives in the sim.** Follow-the-leader chains (§9.6) and the 3 rad/s aim slew (§9.7)
  are stepped once per sim tick in the actor's pose. Firing direction stays the sim's aim; the marking
  slews toward it, and the bot census gates the largest marking-to-shot angle at a fire event.
- **Acceptance 3** ("no two rails at the same angle") is tested structurally — no two rails share an
  angular velocity, no two circles share a shine (period, phase) — because counter-rotating rails must
  cross for an instant.
- **Acceptance 7's "arm beyond an inner hub"** is the hub's subtree: its spoke, pods, links and set piece.
- **Chain archetype and the boss's second core** have no field in the §10 schema; the schema gains
  `chain_links` and a `feature` on a slot. It also gains `schema_version`, `role`, a rail `offset`
  and a node `radius`.
- **v1's acceptance tests 4 and 5** (scale a boss to a drone; zero warnings) are gone from v2. The
  scaler is not built; "every library ship validates with no warnings" stays as our own gate.
- **Saves.** Hull ids do not change, so profiles survive. `SchemaVersion` moves to 5 at the cutover,
  which drops stale combat snapshots and keeps the profile.

---

# Lightship — ship design spec v2

**Replaces the previous ship design spec in full.** Supersedes v0.3 sections 14, 17, 18, 21 and 22. Everything else in v0.3 stands.

New in this version: the complete motion system with real numbers (§9), the ship gallery (§12), and a generation recipe so new ships come out on-style without hand-tuning (§13).

---

## 1. The reference model

The reference image is the style target. Every rule below comes from it:

- **Two colours.** Amber chassis, red accent. Nothing else.
- **A core stack.** Concentric circles at the centre, decreasing in radius, ending in a red dot.
- **Two dashed rails** at different radii, marking where things orbit.
- **Four small circles** ringing the core just off its rim — a 4-fold inner rail.
- **Three arms** at 120° — a 3-fold outer rail, each a straight line from core to hub.
- **Each hub carries a cluster**: pods around it and a red V marking inside. The V is the weapon.
- **The two rails have different symmetry orders.** This is what stops it looking machine-generated.

Twenty circles, four radii, two colours, three weapons. That's the whole ship.

## 2. Primitives

Exactly two.

- **Circle** — filled disc or unfilled ring, dark fill at ~10% luminance, 1.5 px bright rim.
- **Line** — straight, a circle at each end, never joining another line, never floating.

Everything else emerges from overlap and arrangement.

## 3. Size comes from count, not scale

Circle radii come from a fixed ladder. No circle in the game may use a radius outside it.

| Name | Radius (px at base zoom) | Use |
|---|---|---|
| `core_1` | 34 | Outermost core circle |
| `core_2` | 22 | Second core ring |
| `core_3` | 13 | Third core ring |
| `core_dot` | 5 | The core dot |
| `hub` | 15 | Cluster anchor on a rail |
| `pod` | 7 | Cluster member |
| `micro` | 4 | Detail, inner rail members |

A bigger ship has **more circles and more rails**, never larger ones. A boss uses the same 15 px hub as a tier-1 drone. Consequences:

- A weapon looks identical everywhere, so players learn it once.
- Threat reads as density, not scale.
- Larger enemies have more rail circumference, so more slots, so **more weapon set pieces**. Empty space on a big enemy is wasted — fill outer rails with weapons, not decoration.

## 4. Construction grammar

Built in this order. There is no free placement.

### 4.1 Core stack

2–4 concentric circles from the ladder, sharing a centre, alternating filled and ring, ending in the core dot.

- Player: core dot is **white**.
- Enemy: core dot is the **accent colour**, and the core carries the main weapon and is the kill target.
- Passives are colourless (§6.4) and appear as thin rings inside the stack, one per passive.

### 4.2 Rails

Dashed rings at fixed radii: **52, 96, 140, 184** px. A ship uses 1–4, always inside out.

| Property | Values |
|---|---|
| `radius` | 52 / 96 / 140 / 184 |
| `order` | 3–8, the number of evenly spaced slots |
| `speed` | Radians/sec, signed (see §9.1) |
| `phase` | Starting rotation |

Rails render at 1 px, dash 2/5, 28% opacity, chassis colour. A rail is deleted when its last cluster dies.

**Adjacent rails must differ in order.** 4-then-3 as in the reference, or 6-then-4, or 3-then-5. Two rails of the same order stack into a wheel and look generated.

### 4.3 Spokes

One straight line per occupied slot, from the core rim (rail 1) or the next rail inward (rails 2+) to the cluster hub. Spokes rotate with their rail.

### 4.4 Clusters

A cluster occupies one slot and is one of:

- **Hub cluster** — a `hub` circle with 1–4 `pod` circles attached by short lines, at **30 px** from the hub centre, spaced **0.78 rad** apart and centred on the outward direction. May carry one weapon set piece.
- **Node cluster** — a single `micro` or `pod` circle. Detail only.
- **Stub** — an empty slot, used deliberately to break symmetry on irregular enemies.

### 4.5 Set pieces

A weapon is a **set piece**: a fixed, named arrangement of circles and accent lines that mounts onto a hub. Set pieces never scale and never rotate with the rail — they track the aim (§9.7). Identical on every ship in the game.

The reference image's red V is `v_rack`, the rocket launcher.

## 5. Symmetry

- **Every rail is rotationally symmetric** at its order. Slots evenly spaced, each filled identically or left as a stub.
- **Player hulls additionally carry a mirror axis on the forward line.** Odd orders with a slot on the forward axis, or even orders straddling it. The primary weapon always sits on the forward axis.
- **Enemies may drop the mirror axis.** Irregular elites also drop slot uniformity — omit clusters at some slots, vary pod counts between clusters, offset a rail's centre from the core by up to 12 px. Rail structure stays; the filling gets messy.
- The hull rotates to face the aim. Rails counter-rotate against the hull so the ship stays alive while turning.

## 6. The two-colour system

### 6.1 The rule

**One chassis colour and at most one accent colour.** No third colour appears anywhere.

- Chassis: every body circle, rail, spoke, hub and pod.
- Accent: the core dot and the accent lines inside set pieces.

### 6.2 Colour gates weapon access

Every set piece is made of one or two colours. **A ship may mount a set piece only if every colour in it is in the ship's pair.** A ship's colours are a readout of what it can do to you.

| Colour | Element |
|---|---|
| Light blue `#6fd3ff` | Player only, never on an enemy |
| Red `#ff5436` | Fire |
| Yellow `#ffd23f` | Lightning |
| Green `#45e06a` | Corruption |
| Violet `#a97dff` | Plasma |
| Silver `#9aa3b3` | Void |

### 6.3 Weapon catalogue

**Mono-colour** — available to any ship carrying that colour.

| Set piece | Colour | Weapon | Slot |
|---|---|---|---|
| `twin_barrel` | Blue | Pulse cannon | Primary |
| `lens_stack` | Blue | Beam | Primary |
| `shell_pair` | Blue | Blocker satellites | Secondary |
| `vent_fan` | Red | Flame cone | Primary |
| `drop_cradle` | Red | Mine layer | Secondary |
| `burst_ring` | Red | Explosives | Secondary |
| `coil_pair` | Yellow | Bolt | Primary |
| `wedge_pair` | Yellow | Ricochet | Primary |
| `hook_node` | Yellow | Arc tether | Secondary |
| `sac_cluster` | Green | Virus | Secondary |
| `bloom_pod` | Green | Poison cloud | Secondary |
| `spore_rack` | Green | Drone hatch | Secondary |
| `spin_ring` | Violet | Spiral shot | Primary |
| `halo_node` | Violet | Pulse ring | Secondary |
| `phase_pair` | Violet | Blink mine | Secondary |
| `well_cup` | Silver | Void orb | Primary |
| `iris_ring` | Silver | Slow field | Secondary |
| `pull_cage` | Silver | Black hole shot | Secondary |

**Two-colour** — require both colours on the ship.

| Set piece | Colours | Weapon | Slot |
|---|---|---|---|
| `v_rack` | Yellow + Red | Rocket launcher *(the reference)* | Secondary |
| `fin_trio` | Yellow + Violet | Seeker missiles | Secondary |
| `storm_crown` | Yellow + Silver | Discharge | Secondary |
| `coil_array` | Yellow + Green | Chain infection | Secondary |
| `split_lance` | Blue + Red | Ignition lance | Primary |
| `shell_ring` | Blue + Silver | Shield | Secondary |
| `web_node` | Blue + Green | Siphon tether | Secondary |
| `node_pair` | Blue + Violet | Phase shot | Primary |
| `rift_pair` | Blue + Yellow | Overcharge | Primary |
| `ember_rack` | Red + Green | Incendiary spores | Secondary |
| `collapse_cage` | Red + Silver | Collapse charge | Secondary |
| `flare_ring` | Red + Violet | Nova pulse | Secondary |
| `leech_arm` | Green + Silver | Siphon | Secondary |
| `mesh_node` | Green + Violet | Drone swarm | Secondary |
| `prism_stack` | Violet + Silver | Refract beam | Primary |

### 6.4 Passives are colourless

Passives are internal, not set pieces. Thin rings inside the core stack in the chassis colour, one per passive. Any ship may take any passive.

### 6.5 Player ships

**Chassis is always light blue. Accent is the element you evolved into.**

| Element | Accent | Weapons available |
|---|---|---|
| Fire | Red | 3 blue + 3 red + `split_lance` = 7 |
| Lightning | Yellow | 3 blue + 3 yellow + `rift_pair` = 7 |
| Corruption | Green | 3 blue + 3 green + `web_node` = 7 |
| Plasma | Violet | 3 blue + 3 violet + `node_pair` = 7 |
| Void | Silver | 3 blue + 3 silver + `shell_ring` = 7 |

Seven weapons for four weapon slots. Switching element genuinely changes how you play.

### 6.6 Enemy ships

Chassis is one element colour, accent a second or none. Mono-colour enemies are the weak ones. A player should be able to tell what an enemy can do from its two colours before it fires.

## 7. Growth by tier

| Tier | Rails | Orders | Clusters | Weapon set pieces |
|---|---|---|---|---|
| 1 | 1 | 3 | 1 hub, 2 nodes | 1 primary |
| 2 | 1 | 4 | 2 hubs, 2 nodes | 1 primary, 1 secondary |
| 3 | 2 | 4, 3 | 3 hubs, 3 nodes | 1 primary, 1 secondary |
| 4 | 2 | 4, 5 | 4 hubs, 4 nodes | 1 primary, 2 secondary |
| 5 | 3 | 6, 4, 3 | 6 hubs, 5 nodes | 1 primary, 2 secondary |
| 6 | 3 | 6, 5, 4 | 8 hubs, 6 nodes | 1 primary, 3 secondary |

*(all tune)* Evolving adds rails and fills slots. The core stack grows one ring every two tiers.

## 8. Enemy archetypes

| Archetype | Core stack | Rails | Orders | Set pieces | Symmetry |
|---|---|---|---|---|---|
| Drone | 2 | 1 | 3 | 0–1 | Full |
| Sentry | 2 | 1 | 4 | 1–2 | Full |
| Radial elite | 3 | 2 | 4, 3 | 3 | Full, mirrored — *the reference* |
| Heavy elite | 4 | 3 | 6, 4, 3 | 8 | Full, no mirror |
| Irregular elite | 3–4 | 3 | mixed, slots omitted, rails offset | 6–12 | Rotational broken deliberately |
| Chain | 2 | 0 | — | 2–4 along the chain | Bilateral only |
| Boss | 4 | 4 | 8, 6, 4, 3 | 14–20 | Full, may have a second core stack |

Elites run 2–4× the player's footprint at the same tier, entirely through rail count and slot count.

---

## 9. Motion system

**This is the part that makes the ships feel alive, and it is not optional.** Every value below is taken from the approved prototype. A ship rendered without motion is not finished.

Six layers run simultaneously. They are deliberately unsynchronised — that's what stops the ship reading as one spinning object.

### 9.1 Rail rotation

Each rail turns at a constant signed angular speed. **Sign alternates by rail index**, so neighbouring rails always counter-rotate. Magnitude falls as radius rises, so rim speed stays roughly constant and outer arms sweep slowly while inner detail spins.

| Rail | Radius | Speed (rad/s) | Direction | Rim speed |
|---|---|---|---|---|
| 1 | 52 | **0.95** | − | 49 px/s |
| 2 | 96 | **0.42** | + | 40 px/s |
| 3 | 140 | **0.26** | − | 36 px/s |
| 4 | 184 | **0.18** | + | 33 px/s |

Per-ship variance of ±15% on magnitude is allowed and encouraged. The sign alternation is not.

Spokes, hubs, pods and set pieces all travel with their rail.

### 9.2 Pod bob

**The small outer circles bob back and forth around their slot.** This is the detail that reads as "alive" more than anything else, so don't drop it as an optimisation.

Each pod's angular position around its hub is:

```
angle = hub_angle + slot_offset + sin(t * 1.9 + pod_index * 1.0) * 0.14
```

| Property | Value |
|---|---|
| Amplitude | **0.14 rad** (~8°) |
| Frequency | **1.9 rad/s** (period 3.3 s) |
| Phase step per pod | **1.0 rad** |
| Distance from hub | 30 px |
| Slot offsets | ±0.78 rad, centred on outward |

Inner-rail node circles bob too, at amplitude 0.10 rad and frequency 2.3 rad/s, phase-stepped by 0.7 rad per slot.

### 9.3 Arm pump (breathing)

Each rail's effective radius oscillates, so arms pump gently in and out.

```
effective_radius = rail.radius * (1 + sin(t * 1.4 + rail_phase) * 0.03)
```

| Property | Value |
|---|---|
| Amplitude | **3%** of rail radius |
| Frequency | **1.4 rad/s** (period 4.5 s) |
| Phase offset per rail | 0.9 rad |

Note this pumps the *radius*, not the scale. Circles never change size (§3).

### 9.4 Running light — the rotating shine

Every circle's rim carries one bright arc travelling around it.

| Property | Value |
|---|---|
| Lit fraction | **13%** of circumference |
| Dark fraction | 87% |
| Width | 2.6 px, round caps |
| Colour | Pale tint of the rim colour (Appendix A) |

**Lap speed scales inversely with radius** — small circles buzz, big circles turn slowly. This is what keeps it lively without becoming overwhelming.

| Radius | Lap period | Rate (laps/s) |
|---|---|---|
| 34 `core_1` | 2.50 s | 0.40 |
| 22 `core_2` | 2.30 s | 0.43 |
| 15 `hub` | 2.00 s | 0.50 |
| 13 `core_3` | 1.90 s | 0.53 |
| 7 `pod` | 1.70 s | 0.59 |
| 5 `core_dot`, gun | 1.50 s | 0.67 |
| 4 `micro` | 1.40 s | 0.71 |

**Phase offset** = `(part index within its cluster) × 0.05 laps + (cluster index) × 0.12 laps`. Nothing starts in sync, ever.

Lines carry the shine too, running outward from the body, one lit segment at 13% of the line's length.

### 9.5 Core pulse

The core dot pulses:

```
radius = 5 * (1 + sin(t * 4.0) * 0.22)
```

Period 1.57 s. This is the one element that stays steady across the whole fleet — it's the heartbeat, and it's how a player picks the kill target out of a busy silhouette.

### 9.6 Chains

Chain archetypes have no rails. Their tails use follow-the-leader plus a travelling wave.

**Follow-the-leader**, every frame, head outward:

```
dir = normalise(p[i] - p[i-1])
p[i] = p[i-1] + dir * rest_length
```

**Travelling wave**, applied perpendicular to the chain direction:

```
offset = sin(t * 3.2 - i * 0.85) * amplitude * (i / N)
```

| Property | Value |
|---|---|
| Rest length | 30 px |
| Wave frequency | **3.2 rad/s** |
| Phase step per link | **0.85 rad** |
| Amplitude ramp | Linear, 0 at the head to full at the tip |
| Amplitude — `rigid` | 0 px |
| Amplitude — `sway` | 6 px |
| Amplitude — `whip` | 14 px |

Keep amplitude at `sway` or below on links carrying weapon set pieces, and fire from where the circle actually is, or aiming stops feeling honest.

### 9.7 Weapon aim override

Set pieces do **not** spin with their rail. Their local frame counter-rotates so the accent marking always points at the current target.

| Property | Value |
|---|---|
| Slew rate | **3.0 rad/s** max |
| Behaviour | Visibly swings to track, never snaps |
| When no target | Returns to outward-facing over 1.0 s |

This is what makes a rotating elite look like it's aiming rather than spinning wildly.

### 9.8 Destruction motion

When a circle dies:

| Stage | Behaviour |
|---|---|
| Collapse | Circle shrinks to 0 over 0.10 s |
| Burst | 5–7 fragment circles thrown along the incoming vector |
| Orphan | Everything connected only through it detaches as a subtree |
| Drift | Detached subtree keeps its rail velocity plus 1.4 px/frame of random spread, drifting outward at 0.02 px/frame² |
| Spin | Detached subtree spins at 0.5–1.5 rad/s |
| Fade | Over 1.0 s. Drops light at 0.5 s |
| Rail | Deleted, dashed ring and all, when its last cluster dies |

### 9.9 Reach rings

Every rail draws its dashed ring so the player can read reach before anything reaches them. 1 px, dash 2/5, 28% opacity, chassis colour. Destroyed with the rail.

---

## 10. Data schema

```json
{
  "id": "elite_lightning_t4_triskel",
  "name": "Triskel",
  "faction": "elite",
  "archetype": "radial_elite",
  "tier": 4,
  "chassis_color": "yellow",
  "accent_color": "red",
  "core_stack": [34, 22, 13],
  "core_dot": "accent",
  "core_weapon": "coil_pair",
  "passives": ["radar"],
  "rails": [
    { "radius": 52, "order": 4, "speed": -0.95, "phase": 0.78,
      "pump_phase": 0.0, "reach_ring": true,
      "slots": ["node", "node", "node", "node"] },
    { "radius": 96, "order": 3, "speed": 0.42, "phase": 0.0,
      "pump_phase": 0.9, "reach_ring": true,
      "slots": [
        { "type": "hub", "pods": 4, "set_piece": "v_rack", "hp": 60 },
        { "type": "hub", "pods": 4, "set_piece": "v_rack", "hp": 60 },
        { "type": "hub", "pods": 4, "set_piece": "v_rack", "hp": 60 }
      ] }
  ]
}
```

**Positions are derived, never authored.** A cluster sits at `effective_radius(rail, t)` at angle `rail.phase + slot_index * 2π / rail.order + rail.speed * t`. Pods derive from their hub, spokes from the parent relationship. Motion parameters not stated in the file come from the tables in §9. This is why detachment is a subtree walk and why nothing can be placed off-style.

## 11. Editor

The designer does not place circles freely.

- **Core tab** — stack depth, core weapon, passives.
- **Rails tab** — add a rail (radius from the four fixed values), set order, speed, phase, pump phase. A ring diagram shows the slots. Speed sign is auto-alternated with a warning if overridden.
- **Slots tab** — click a slot, choose hub / node / stub, set pod count, drop in a set piece from the colour-filtered catalogue.
- **Colours tab** — pick chassis and accent. Changing a colour immediately greys out every set piece no longer legal and flags the ones already mounted.
- **Motion tab** — per-rail speed and pump, per-cluster bob amplitude, chain mode for chain archetypes, with live preview. Defaults come from §9 and should rarely be touched.
- **Set piece library** — read-only. Set pieces are authored once by hand and never edited per ship.

Validation blocks saving on: a third colour anywhere, a set piece whose colours aren't in the ship's pair, a radius outside the ladder, two adjacent rails of the same order, two adjacent rails rotating the same direction, a player hull without a forward mirror axis, a slot pattern breaking rotational symmetry on a non-irregular ship, or a rail with no occupied slots.

---

## 12. Ship gallery

A browser for every ship in the project, so designs can be reviewed without hunting through the game. Opens from the editor's top bar and from the main menu in dev mode.

### 12.1 Contact sheet

A scrollable grid of every ship file. **Each tile renders the ship live and animated** — rails turning, pods bobbing, shine running, core pulsing. A still frame doesn't show whether the motion is right, and the motion is half the design.

Each tile shows:

- The animated ship
- Name and id
- Faction badge (player / enemy / elite / boss)
- Two colour swatches for the pair
- Tier and archetype
- Circle count, rail count, footprint in px
- Set pieces mounted, as small icons
- Validation status — green tick, or red with the failing rule

Performance: tiles animate only while on screen; off-screen tiles freeze. Cap at 24 animating simultaneously, nearest-to-centre first.

### 12.2 True scale toggle

Off by default — all tiles the same size for browsing. **On** — tiles sized to each ship's real footprint, so a drone next to a boss shows the honest size relationship. This is the view to use when checking that §3 is holding.

### 12.3 Filters and sorting

| Filter | Options |
|---|---|
| Faction | Player / enemy / elite / boss |
| Chassis colour | Any of six |
| Accent colour | Any of six, or none |
| Colour pair | Exact pair match |
| Tier | 1–6 |
| Archetype | Any of seven |
| Rail count | 0–4 |
| Set piece | Contains a specific weapon |
| Status | Valid / invalid / warnings |

Sort by tier, footprint, circle count, name, or last modified. Free-text search on name and id.

### 12.4 Detail view

Click a tile for a large animated render plus:

- **Part tree** — core → rails → slots → set pieces, expandable, with per-circle HP.
- **Detach preview** — hover any circle in the tree or on the render to highlight everything that would come off with it, in red. This is the fastest way to check an elite's destruction reads well.
- **Weapon list** with colour requirements, and a flag on anything illegal for the current pair.
- **Motion panel** showing the resolved values from §9 for this ship, with a scrub bar to step through the animation frame by frame.
- **Silhouette check** — the same ship at minimum zoom beside it.

### 12.5 Compare mode

Pin 2–4 ships side by side at matched scale, animated together. Used for checking that a tier's four hulls are distinguishable at a glance, and that an element's ships read as a family.

### 12.6 Roster coverage

A grid of element × tier showing which roster slots are filled and which are empty, with a count. Clicking an empty cell opens the editor pre-seeded with that element, tier and a suggested archetype.

### 12.7 Export and reload

- **PNG contact sheet** of the current filter, for offline review.
- **Single-ship PNG** at a chosen scale, with an option to include the rails or hide them.
- **Live reload** — the gallery watches the ship directory, so anything saved in the editor appears immediately.
- **Invalid ships still appear**, flagged, rather than being hidden. A broken ship you can see is a broken ship you'll fix.

---

## 13. Generating new ships

So new models come out on-style without hand-tuning. Given a faction, colour pair, tier or archetype, and a seed:

1. **Core stack** — depth from the archetype table (§8). Radii from the ladder, outside in.
2. **Rail count** — from the tier table (§7) for player hulls, the archetype table for enemies.
3. **Rail radii** — assign from the inside out: 52, then 96, then 140, then 184.
4. **Orders** — pick per rail from 3–8 such that no two adjacent rails match. For player hulls, ensure a forward mirror axis: odd orders get a slot on the forward axis, even orders straddle it.
5. **Speeds** — from the §9.1 table for the rail's radius, sign alternating by index, magnitude jittered ±15% by the seed.
6. **Phases** — rail phase random; pump phase stepped 0.9 rad per rail.
7. **Slot filling** — weight outer rails toward weapons and inner rails toward node clusters. Distribute set pieces so each rail is either uniformly armed or uniformly unarmed, except on irregular elites.
8. **Set piece selection** — draw only from the colour-legal pool (§6.2). Respect slot counts for player hulls; enemies fill to the archetype's set piece count, duplicates allowed and encouraged.
9. **Pod counts** — 1–4 per hub, uniform within a rail except on irregular elites.
10. **Irregular pass**, elites only — convert 10–25% of slots to stubs, vary pod counts per cluster, offset one rail's centre by up to 12 px.
11. **Validate** against §11.
12. **Style check** — §13.2.

### 13.1 Prompt template

For generation from a text description in the editor, resolve the description into this before building:

```
faction:        enemy
archetype:      radial_elite
tier:           4
chassis_color:  yellow
accent_color:   red
theme:          "artillery platform, heavy rockets, slow"
seed:           81734
```

The theme biases set piece selection and speed jitter only. It never overrides a structural rule.

### 13.2 Style check

A generated ship passes only if all of these hold:

- Two colours, no more.
- Every radius is on the ladder.
- No two adjacent rails share an order or a rotation direction.
- Every rail has at least one occupied slot and a reach ring.
- Every line ends at a circle at both ends.
- Every set piece's colours are within the pair.
- The core dot is present and pulsing.
- No hub carries more than one set piece.
- Player hulls have a forward mirror axis and a primary on the forward line.
- Circle count is within ±20% of the archetype's target.

### 13.3 Never

- Place a circle at an arbitrary position.
- Scale a set piece, a hub or a pod.
- Add a third colour, including for "emphasis".
- Rotate two adjacent rails the same way.
- Ship a model without motion.

---

## 14. Acceptance tests

1. Place the reference image beside a rendered radial elite at the same scale. They should be hard to tell apart in structure.
2. Every 15 px hub in the game measures 15 px, on a drone and on a boss alike.
3. Pause any ship at a random frame: no two circles have their shine in the same place, and no two rails are at the same angle.
4. Watch any ship for ten seconds: the outer pods visibly bob, the arms visibly pump, and adjacent rails visibly turn opposite ways.
5. A tester shown a two-colour enemy for the first time can name at least one thing it can do.
6. The gallery renders every ship in the project, animated, and a designer can find a specific model in under ten seconds.
7. Detach preview on an elite's inner hub highlights the entire arm beyond it.
8. Twenty generated ships pass the style check with no manual edits, and a designer cannot pick the generated ones out of a line-up with the hand-authored ones.

## Appendix A — Palette

| Role | Rim | Fill | Running light |
|---|---|---|---|
| Player light blue | `#6fd3ff` | `#08233a` | `#dcf5ff` |
| Fire red | `#ff5436` | `#2a0b08` | `#ffc6b5` |
| Lightning yellow | `#ffd23f` | `#2a2206` | `#fff3bd` |
| Corruption green | `#45e06a` | `#062a12` | `#caffd5` |
| Plasma violet | `#a97dff` | `#1d1233` | `#e4d6ff` |
| Void silver | `#9aa3b3` | `#000000` | `#ffffff` |
| Player core dot | — | `#ffffff` | — |
| Enemy core dot | — | accent colour | — |
| Playfield | `#050507` | | |
| Reach rings | chassis rim at 28%, 1 px, dash 2/5 | | |
