# Lightship v0.3 — approved implementation scope

The document below is the supplied v0.3 product specification, verbatim. It is reference material for game requirements. The decisions in this preamble were approved on 2026-09-20 and take precedence wherever the source is silent or ambiguous. Where v0.3 speaks, v0.3 wins over everything approved for v0.2.

**Kept from the v0.2 approved scope, because v0.3 does not contradict them**

- **Fixed loadouts per hull.** Evolution picks a complete preset. There is no in-run loadout screen and no component inventory. The editor authors and validates the preset slots.
- **Shield** is bounded by duration plus cooldown (open decision 1).
- **No voluntary regression** (open decision 5). **Reshape does not convert nearby projectiles to light** (open decision 6).

**Dropped from the v0.2 approved scope, because v0.3 replaces them**

- Five tiers and 81 hulls → **six tiers, 101 player hulls**.
- Three starting elements and unlock-on-region-entry → **Lightning only at the start; an element unlocks the first time its light is absorbed**.
- Five radial core objectives, Euclidean distance, four exits everywhere → **five bounded levels on a Chebyshev lattice, one perimeter boss each, variable membranes**.
- Origin-only waypoint jumps → **removed**. §12 mentions "waypoint jumps", but v0.3 defines no waypoints and layouts re-roll every life. The short inverted warp plays on death and on level travel; level select is the skip-ahead.
- The old demo (three elements, T3 cap, Fire core) → **the demo build flavour is campaign levels 1–2 (Lightning and Fire), no tier cap**. Demo progress imports into the full campaign.

**Defaults taken where v0.3 is ambiguous** (every one is a `GameTuning` value or a one-line change)

| Question | Default |
|---|---|
| "1.4× the viewport" for a circular node | `ARENA_RADIUS = 800`, the same area as the v0.2 1792×1120 arena |
| T6 bar maximum (there is no next threshold) | 2300 |
| Light decay base, "current tier's threshold" | 0.4 % of the bar's current maximum per second |
| Can decay regress or kill? | It can regress a tier. It can never kill: it floors at 10 light |
| Combo "decays" | After 2.5 s without a kill the count drains by 1 every 0.25 s |
| Player "core only" hitbox | The 3 px core dot |
| "Bounded disc of radius R" | Every cell with Chebyshev ring ≤ R. `in_bounds` is one function, so a round disc is a one-line change |
| Level radii | 6, 8, 9, 11, 12 |
| Rival AIs | They are the five level bosses: L1 Lightning, L2 Fire, L3 Corruption, L4 Void, L5 Plasma |
| v0.2 (schema 3) saves | Exact bytes archived as `.legacy-v3`; deaths and story flags carried over; unlocks reset to Lightning |
| Enemy roster | 40 hulls: per element two drones, two sentries, one chain, one radial elite, one irregular elite, plus one boss per level |

`GameTuning` is the numeric source of truth. The milestone acceptance tests below remain acceptance criteria, not a declaration that human playtesting is complete. Verification and its limits are recorded in `VALIDATION.md` and `tasks/todo.md`.

---

# Supplied v0.3 reference
# Lightship (working title) — game design spec v0.3

**Replaces v0.2 entirely.** Section 28 lists what changed so nothing already built gets silently invalidated. Numbers marked *(tune)* are starting values. Section 29 lists what is still open.

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
| References | Bubble Tanks 2 and 3 (growth, node map, tank editor). Bullet-hell conventions. TRON for the look only |

## 2. Pillars

1. **Grow by absorbing, lose it the same way.** HP *is* progress. The ship regresses. This is the core tension.
2. **Fast, hard, and cheap to die.** Players should push until they break, then restart immediately with a different build. Camping on a strong ship must be the worst option available.
3. **Everything is circles and lines.** Every ship in the game is a graph of circles joined by lines. Nothing else.
4. **Everything moves.** Running lights, orbiting arms, whipping chains, lightstream trails. A still frame should look unfinished.
5. **Light blue is the player.** No other ship, pickup or enemy projectile uses it.

## 3. Setting and IP

- The AI-verse: rival AIs fighting for control at the software level. The player is a lightship, an AI instance. Elements are rival code dialects.
- TRON is a visual reference only. Do not use the name, light cycles, identity discs, circuit-lined suits, the word "derez", or a glowing grid floor.
- Bubble Tanks' mechanics are fine to build on. Its name, art and sounds are not.

## 4. Modes

Both appear on the main menu.

**Campaign.** Five levels. Elements are revealed one level at a time (Section 8). Enemy element types are limited to those revealed. This is the shipping experience.

**Dev mode.** Every element unlocked from the start, every enemy element in the node pool, all hulls available at every evolution. Difficulty scales with distance exactly as in campaign. Level select and a tier-set console command. This is a development and testing tool that stays in the shipped build.

Saves are separate per mode. Dev mode earns no achievements.

---

## 5. Core loop

1. Fly a node. Dodge, shoot, absorb.
2. Light restores the bar. The bar is both HP and tier progress.
3. Cross a threshold, evolve: pick one of three hulls, ship reshapes.
4. Push into a node's membrane, warp to the next node (Section 12). Outward is harder.
5. Take damage, fall below a threshold, regress a tier.
6. Fall below tier 1 and you're back at the origin on a fresh seed, flying again within a second.
7. Reach the level's boss node at the perimeter, beat it, unlock the next element and level.

## 6. HP as the progress bar

- One bar. Light fills it, damage drains it, tier is read off the total.
- **Thresholds** *(tune)*: T2 100, T3 250, T4 500, T5 900, T6 1500. Maximum fill is the next threshold. A full bar triggers the evolve prompt.
- **First evolution must land within 2 minutes** for a new player.
- **No passive regeneration.** Absorbing is the only heal. Standing still never recovers anything.
- **Regression buffer.** A tier is lost at **85%** of the threshold that granted it *(tune)*, not at 100%, so the bar doesn't flicker across the line.
- **Regression grace.** 1.0 s invulnerable while the ship reshapes down *(tune)*.
- **Re-choice on regrowth.** Re-crossing a lost threshold offers three hulls again, not the one you had. A bad build is recoverable without dying.
- **Death** is falling below the tier 1 floor.
- **Difficulty shape.** Early game is tight, because low HP means real dodging. T4–T6 is the power fantasy. Scale enemy density upward with distance so late tiers have crowds to clear.

## 7. Pace — encouraging fast, aggressive play

The whole point is that a player pushes until they break rather than nursing a strong ship. Six mechanisms, all of which should be in by M1 so pacing can be tuned as one system.

1. **Light decay.** The bar bleeds continuously — you're an AI instance and your allocation drains back to the system. Rate *(tune)*: 0.4% of the current tier's threshold per second, suppressed for 3 s after any kill or absorb. Fighting keeps you level; idling and backtracking cost you.
2. **Kills pay, chains pay more.** An enemy's light is worth several times a floating pickup of the same size. A combo multiplier rises with consecutive kills and decays 2.5 s after the last one *(tune: ×1.0 → ×2.5 at 10 kills)*. Aggression is the fastest growth route by a wide margin.
3. **Node pools deplete.** Each node has a finite light pool that refills slowly *(tune: 20% per minute)*. Enemies respawn on a cooldown; the pool does not follow. Re-clearing the same node is a losing strategy within about a minute.
4. **Frictionless death.** No confirmation, no menu, no loading screen. A death screen shows for 1.2 s with the run's stats and dismisses on any input, straight into a new run.
5. **A fresh seed every life.** New node layout, new enemy mix, new hull offers. Restarting is a different run, not a repeat.
6. **The number on the death screen.** "Ring reached: 14 · best 19." Players set their own speed goals if you show them the metric.

Deliberately not included: a hard run timer. It creates anxiety instead of aggression and punishes the exploration the map is built for.

## 8. Evolution, elements and unlocking

**Energy is universal.** All light fills the same bar and counts the same toward thresholds. What differs is the **type**, and type only does one thing: the first time you absorb a light type, that element's branch unlocks permanently for the save.

**Campaign reveal.** Each level introduces one new element into its node pool. The player starts level 1 with one element available and finishes level 5 with all five. Nobody is ever shown more options than they've earned.

| Level | New element in the pool | Elements available by the end |
|---|---|---|
| 1 | Lightning (starting) | 1 |
| 2 | Fire | 2 |
| 3 | Corruption | 3 |
| 4 | Void | 4 |
| 5 | Plasma | 5 |

*(order is tune)*

**Six tiers.** T1 is a shared, element-neutral seed hull. T2–T6 each have a **roster of 4 hulls per element**. Total buildable: 1 + (4 × 5 tiers × 5 elements) = **101 hulls**.

**Offers.** Each evolution presents **3 hulls** from the next tier's roster:
- First evolution: one hull each from the top three *unlocked* elements by light absorbed. With fewer than three unlocked, fill from the current element's roster.
- Later evolutions: three of the four hulls in the current element's roster for that tier. If a different unlocked element accounts for more than 40% of light absorbed since the last evolution *(tune)*, one offer is swapped for that element's hull. This is how a player changes element mid-run.
- Never repeat the same three consecutively where the roster allows otherwise.

**Roles are tags, not the menu.** Every hull is tagged Compact, Standard or Heavy, and a tier's four hulls should span at least two roles. A bigger tier does not mean a bigger ship — a Compact T5 can be physically smaller than a Standard T4.

| Role | Speed | Turn | HP buffer | Damage | Secondary slots |
|---|---|---|---|---|---|
| Compact | +25% | +25% | −20% | baseline | −1 (floor 1) |
| Standard | baseline | baseline | baseline | baseline | baseline |
| Heavy | −15% | −20% | +30% | +15% | +1 |

*(all tune)*

**Reshape** (~0.8 s *(tune)*): parts with matching ids tween position and radius, new parts grow out of the core, removed parts detach and drift off, lines stretch to follow. Invulnerable throughout. Regression runs the same tween in reverse.

## 9. Slots

| Tier | Primary | Secondary | Passive |
|---|---|---|---|
| 1 | 1 | 0 | 0 |
| 2 | 1 | 1 | 0 |
| 3 | 1 | 1 | 0 |
| 4 | 1 | 2 | 1 |
| 5 | 1 | 2 | 1 |
| 6 | 1 | 3 | 2 |

Role modifiers from Section 8 apply on top. Loadout is chosen at evolution; mounted components carry over where slots allow.

## 10. Light pickups

- One light type per element: **Fire** (red), **Lightning** (yellow), **Void** (black with silver rim), **Corruption** (green), **Plasma** (violet).
- **Sources.** A node produces light of its element. Enemies shed light when hit and when destroyed. Most light in a node should come from fighting.
- **Values** *(tune)*: three sizes worth 1 / 5 / 20. Enemy-dropped light is worth 3× a floating pickup of the same size.
- **Shape rule.** Pickups are **hollow, slow-drifting circles** with a running light. Projectiles are **solid and fast**. This holds everywhere, so a pickup is never mistaken for a bullet.
- **Colour rule.** A pickup's colour means exactly one thing: its element.
- **Magnet radius** is a hull stat, not a tier stat.

---

## 11. Levels, nodes and the map

**Node geometry**
- A node is a circular arena, **1.4× the viewport** in each dimension *(tune)*. Bigger than what's visible, but not by much.
- **Camera is locked to the player.** No lookahead, no zoom-to-fit. Camping the rim means you cannot see most of the node — fewer angles to watch, no idea where anything is. That trade is intended.
- **Rim margin.** A visible boundary wall with ~80 px of dead space beyond it *(tune)*, so the player sees the edge instead of guessing. The wall flashes at the contact point.
- **Membranes.** Up to four exits on the rim at N/E/S/W, aligned to grid neighbours. A membrane is a brighter arc of the rim. Some nodes have fewer, which makes dead ends and corridors.
- **Projectiles die at the rim.** That is their maximum range. Ricochet rounds bounce off it.

**The map**
- A **square lattice**. Every cell is one circular node; neighbours connect through membranes. Origin at (0,0), centre of the grid.
- **Difficulty is grid distance from the origin** (Chebyshev). Enemy tier, count and elite frequency all rise with the ring index. Roughly one enemy tier per 2 rings *(tune)*.
- **Each level is a bounded disc** of radius R nodes *(tune: L1 R=6, L5 R=12)*. The outermost ring is a hard perimeter — sealed rim, no membrane, drawn as a solid wall on the minimap. The wall is a visible boundary, not something inferred from dying.
- **The boss node** sits on the perimeter. It is marked on the minimap from the start with direction and distance, so there is always a destination. Beating it completes the level.
- **Minimap** always visible: a grid of small circles. Explored nodes filled, unexplored dark, current node highlighted, perimeter drawn, boss marker shown. Unexplored nodes reveal nothing about their contents.
- **Generation** is a deterministic hash of (level seed, x, y), so a node you flee and return to is the same node. Node archetypes rolled by ring: transit, skirmish, dense, elite lair, boss.

## 12. Node transition — the warp

Moving between nodes is a set piece, not a fade. It should feel like being squeezed through a membrane and flung down a pipe.

**Phases** *(all tune)*

| Phase | Duration | What happens |
|---|---|---|
| Push | 0.30 s | The player presses into the membrane. The rim arc deforms outward at the contact point and resists — ship speed drops to ~40%. The arc brightens as push depth builds. Releasing before the threshold springs the ship back. |
| Commit | — | Push depth passes threshold. Control locks, player becomes invulnerable, all enemy projectiles in the old node are discarded. |
| Zoom in | 0.12 s | Camera pushes to 1.30× zoom, centred slightly ahead of the ship in the travel direction. |
| Warp | 0.55 s | Background traces stretch into radial streaks running from a vanishing point in the travel direction. Streak length ramps up, holds, then collapses. The ship's running lights stretch into lines; its trail becomes a long ribbon. The membrane snaps shut behind. |
| Arrival | 0.15 s | Streaks decelerate and contract back to points. The new node's rim expands into view. A light burst at the ship as it clears the membrane. |
| Zoom out | 0.20 s | Camera returns to 1.00×. Control returns. |

Total locked time ≈ **1.0 s**. Keep it there — a longer warp fights Section 7.

**Details**
- The player enters the new node just inside the opposite membrane, moving at entry speed, so momentum carries through.
- Enemies do not follow between nodes in v1.
- Subtle per-channel offset on the streaks is fine in-engine. No motion blur.
- An accessibility option reduces the warp to a 0.25 s fade with no zoom and no streaks.
- The same effect, shorter and inverted, plays on death and on waypoint jumps.

## 13. Movement and handling

Handling needs to feel fast and loose, because Section 7 is asking players to charge into things.

- **Momentum-based.** Acceleration and drag rather than instant velocity. Hulls differ in top speed, acceleration and drag; Compact hulls turn far tighter.
- **Drift.** Turning while at speed carries the ship wide. The lightstream trail bends with the turn, which is most of what sells the movement.
- **Dash.** Short burst on a cooldown *(tune: 0.18 s burst, 1.2 s cooldown)*. Emits a compression ring at the start point and a hard kink in the trail. Not invulnerable.
- **Trail.** The player leaves a fading lightstream behind them at all times, longer at higher speed. Enemies leave shorter ones.
- **Rim contact** slows the ship slightly and flashes the wall, so edges feel physical.

## 14. Enemies and enemy models

### Construction

Enemies are built from the same system as player ships (Section 17) with a looser ruleset.

- **A ship is a graph.** Circles are nodes, lines are edges. Every line ends at a circle at both ends. Lines never join other lines and never float.
- **The core** is the central circle. It carries the main weapon and it is the kill target — destroy the core and the enemy dies.
- **Peripheral circles** carry secondary weapons or act as armour. Each has its own HP and can be shot off individually.
- **Detachment.** Destroying a circle removes its lines. Anything connected to the ship only through that circle detaches — it drifts off, fades and drops light. So a hub with three pods and a gun is one satisfying shot away from losing all five parts. This is the fight's progress bar; no boss health bar needed.
- **Symmetry is optional for enemies.** Player hulls are always bilaterally symmetrical. Enemies may be radially symmetrical, bilaterally symmetrical, or completely irregular.
- **Density.** Enemies may use many more circles than player hulls, in mixed sizes, Bubble Tanks 3 style. Elites run 2–4× the player's footprint at the same tier and are exempt from player size budgets.

### Reference model

The attached reference is the canonical **radial elite**: a large dark core circle with a concentric inner ring and a red core dot, three arms on straight lines out to hub circles, each hub ringed with small pods and carrying a red weapon marking, and two dashed reach rings showing the orbit radii. Build the archetype list around it rather than treating it as the only shape.

### Archetypes

| Archetype | Structure | Motion | Notes |
|---|---|---|---|
| Drone | 1 core + 2–4 pods | Small orbit, breathing | Swarm fodder, dies fast |
| Sentry | 1 core + a weapon prong cluster | Static, weapon tracks | Telegraphed long-range shot |
| Radial elite | Core + 3–6 arms, each a hub with pods and a gun | Arms orbit, inner satellites counter-rotate | The reference image |
| Irregular elite | 15–40 circles of mixed size, asymmetric, no repeating pattern | Independent drift per cluster, slow overall rotation | The Bubble Tanks 3 look. Feels hand-built and unpredictable |
| Chain | A head cluster with a tail chain of shrinking circles | Follow-the-leader plus a travelling wave (Section 18) | Worms. Tail can be severed mid-chain |
| Boss | Any of the above at 3–4× scale, multiple cores or a shielded core | All of the above layered | One per level, on the perimeter |

### Behaviour

- Regular enemies run fixed patterns. Elites and bosses make decisions: lead the player's movement, retreat when limbs are lost, protect the core when exposed.
- Human-like limits on decision-driven enemies *(tune)*: 150–300 ms reaction delay, 2–5° aim error. Challenge from decisions, never from perfect aim.
- **Pattern identity per element** *(tune)*: fire = cones, fans, lingering mines; lightning = fast bolts and instant chains; void = slow pulls and projectile-eating; corruption = spreading infection and drones; plasma = orbiting shots and rotating spirals.
- Standard directional audio cue on every shot. No visual off-screen warnings by default — Radar is an opt-in passive.
- **Reward by gap.** Anything above the player's tier pays scaled by the gap *(tune: ×1.5 per tier above)*.

### Enemy-only components

Never available to the player.

| Component | Behaviour |
|---|---|
| Egg | Large circle. Bursts into a spread of seeker missiles when damaged |
| Droid bay | Releases seeker droids: larger, tankier seekers that do more damage |
| Deployment ramp | Periodically releases small regular units |
| Turret ring | A ring of small weapon circles rotating around the body, each firing outward |

## 15. Weapons and abilities

### Primaries (1 slot, always filled)

| Name | Behaviour | Notes |
|---|---|---|
| Pulse cannon | Basic aimed shots | Starting weapon |
| Beam | Piercing straight beam, constant damage while held | Highest damage; aiming is the cost |
| Homing beam | Piercing beam that curves into the nearest enemy, retargeting instantly when a closer one appears at the point of contact | **60% of Beam's DPS** *(tune)* |
| Ricochet | Bounces off the node rim | Rewards rim play, which the camera otherwise punishes |
| Flame cone | Short-range spreading cone | Fire |
| Bolt | Fast accurate shots, chains to a second target | Lightning |

### Secondaries

| Name | Behaviour | Balance notes |
|---|---|---|
| Virus | Latches onto the nearest enemy at very high DPS until it dies, then splits into two at half DPS which do the same | **Hard cap at two generations**: gen 0 → gen 1 (×2, 50%) → gen 2 (×4, 25%) → stop |
| Seeker missiles | Homing missiles | See the T4 passive |
| Rocket launcher | A volley of rockets on curved, wandering paths | Slow, high total damage |
| Shield | Blocks all incoming projectiles in a radius | **Needs a limit**: duration plus cooldown, or a hit budget before it breaks |
| Explosives | Red circles on the ground with a growing inner circle; detonates when inner meets outer | Same warn-then-fire idiom as the laser prong |
| Laser prong | Red path line draws 0.8 s, then a 0.25 s beam along exactly that line, 0.5 s cooldown *(tune)* | The reference telegraph |
| Poison cloud | Damage over time plus a movement slow | **Slow caps at 30%** *(tune)*, clearly marked on the player when active |
| Mine layer | Drops proximity mines behind the ship | Fire affinity |
| Orbital blockers | Satellites that orbit and absorb projectiles | Void affinity |

### Passives (T4+)

| Name | Behaviour |
|---|---|
| Orbital seekers | Seeker missiles idle in orbit around the ship until an enemy enters a radius, then launch |
| Radar | Off-screen enemies show as rim blips |
| Health readout | Numeric bar values and enemy HP |
| Magnet | Larger pickup radius |
| Siphon | Light absorbed restores more of the bar |
| Thrusters | Speed and turn rate |
| Forcefield | Constant small damage aura at contact range |

## 16. Combat rules

- **The player's hitbox is the core only.** Projectiles damage the bar only when they touch the core. Body parts do not collide. Contact with an enemy body damages the core.
- **Enemies have per-circle hitboxes.** Core plus every peripheral circle, each with its own HP.
- **Telegraphs.** Any attack that cannot be dodged on reaction shows a warning ≥ 0.5 s before it lands.
- **Minimum visible lifetime.** Any hit, absorb or short event is drawn for at least 0.25 s.
- Player projectiles are light blue. Enemy projectiles draw above player projectiles, which draw above pickups.

---

## 17. Visual system — circles and lines

### Primitives

**There are exactly two.**

- **Circle** — filled disc or unfilled ring, with a bright rim.
- **Line** — straight, with a circle at each end.

Everything else emerges from overlap. A crescent is a black circle over a rimmed one. An organic blob is overlapping circles of unequal radius. Concentric detail is circles sharing a centre. No polygons, no ellipses, no arcs as primitives.

### Rules

1. **Fill and rim.** Each circle has a dark fill (its colour at ~10% luminance) and a **1.5 px bright rim** in its role colour. Circles overlap freely.
2. **Lines connect circles.** Both ends terminate at a circle centre, clipped at the rims. Lines never join other lines. A line whose circle is destroyed is destroyed with it.
3. **Draw order.** Reach rings → lines → outer circles → body → components → core.
4. **Symmetry.** Player hulls are bilaterally symmetrical about the forward axis, always. Enemies are unrestricted.
5. **Core.** A small filled circle (radius ≈ 3 px at base zoom) at the body centre. Player core is white. Enemy core is a coloured dot — red on the reference model — and carries the main weapon.
6. **Every visible circle is an ability or a stat.** Nothing is decorative.
7. **Growth by addition.** A higher tier keeps the lower tier's arrangement and adds around or inside it. Camera zoom changes at most ~10% per tier.
8. **Silhouette must be discrete.** Design every hull at its smallest on-screen size first.

### Weights

Constant in screen space at any zoom: rim 1.5 px, lines 2 px, running light 2.6 px, reach and reference rings 1 px dashed (2 on, 4 off) at 40–60% opacity. No other weights. Hard edges only — bloom supplies all glow.

### Element language, without polygons

| Element | Chassis | Arrangement | Components |
|---|---|---|---|
| Fire | Red | Dense clusters of small circles fanning outward, radius decreasing outward, short lines | Yellow ember circles, cinder pods |
| Lightning | Yellow | Few circles on long straight spokes, tight small circles at the ends | Violet capacitor circles |
| Void | Black with silver rim | A black disc that widens each tier with the build happening inside it, concentric rings, satellites on dashed reach rings | Red weapon orbs, gold satellites |
| Corruption | Green | Irregular clusters of unequal circles joined by lines, off-axis buds | Yellow nuclei and spore buds |
| Plasma | Violet | Concentric orbital rings with circles riding on them | White-hot core circles |

**Colour rule.** An element does not exclude other colours. Chassis colour and core say whose ship it is; components keep their own colours and look identical wherever mounted. **Light blue is the player's chassis and appears nowhere else.**

**Player hulls** are majority light blue — body circles and lines. The element shows through arrangement and component colours.

## 18. Motion system

Every ship carries motion. A static ship is a bug.

**Running lights.** Every circle's rim carries one bright segment covering **13% of its circumference**, in the pale tint of its rim colour, travelling at **one lap per 2.0 s** (every fourth circle at 1.6 s). Phase offsets distributed across circles (0, −0.7 s, −1.3 s) so nothing moves in sync. Lines carry the light too, running outward from the body.

**Per-group motion.** A *group* is a subtree hanging off a parent circle. Each group carries:

| Property | Effect |
|---|---|
| `orbit_radius` | Distance from the parent |
| `orbit_speed` | Radians/sec. **Signed** — negative counter-rotates. Sibling groups at different radii should differ in sign, or the ship reads as one spinning wheel |
| `drift_amp` / `drift_freq` | Per-child wobble around its slot, so arms aren't rigid |
| `breathe_amp` | Whole-group scale pulse, 1.00 → 1.05 → 1.00 over 2 s, per-group phase |
| `chain_mode` | `rigid`, `sway` or `whip` |

**Chains.** A chain is a group whose children follow the leader: each circle holds a fixed distance from its parent and swings free, so turning whips the tail. Stacked on top is a travelling sine wave down the chain, amplitude growing toward the tip. Lines stay straight between neighbours, so the chain bends at each circle.

- Keep amplitude low on chains carrying weapon circles, and fire shots from where the circle actually is, or aiming stops feeling honest.
- Void's concentric discs and lightning's spokes stay `rigid`. Corruption `whip`s.

**Reach rings.** Every orbiting group draws a faint dashed ring at its orbit radius, so the player can read an elite's reach before anything reaches them. The ring is destroyed with the group.

## 19. Attack and impact animation

All of it in circles and lines. This is where the game's identity lives — budget real time for it.

**Every shot has three beats.**

1. **Muzzle.** A ring at the emitter snapping outward and fading over ~0.15 s.
2. **Travel.** See below.
3. **Impact.** Two rings expanding at different speeds and fading, plus 5–7 fragment circles thrown along the incoming vector, decelerating and fading.

**Trails (lightstreams).** Every projectile leaves one. Width and opacity both taper toward the tail — no blur, no gradient, just segments stepping down. Trail length is a per-weapon property: a pulse leaves a stub, a seeker leaves a long ribbon. Trails bend with the projectile's path.

**Projectile interiors.** Anything above ~7 px radius gets internal structure: a rotating inner ring, a spoke, a pulsing centre. Rotation tells the player it's live before it does anything. Small projectiles stay plain.

**Paths carry identity.** A player should name an incoming attack from its path shape before registering its colour.

| Weapon | Path | Trail | Interior |
|---|---|---|---|
| Pulse | Straight, fast | Short stub | None |
| Seeker | Weaving sine, tightening near the target | Long ribbon | Pulsing halo ring |
| Rocket | Slow wallow, wide curve | Thick, long | Rotating inner ring and spoke |
| Ricochet | Hard bounces off the rim, fragments thrown on each bounce | Medium, kinks at each bounce | None |
| Beam | Instant line | — | Wide faint band under a bright core, both jittering in width, with pulses running along it and impact sparking continuously at the far end |
| Virus | Latches, then a line to the host that pulses | — | Host circle's rim flares on the infection tick |

**Impact on the target.** Flare the target circle's own rim, don't just spawn a ring in front of it. On large hits, darken a collar around the impact point below the playfield value — a bright thing in a dark hole reads as more violent than a brighter flash, and it costs no bloom headroom.

**Movement effects.** Player trail bends on turns; dash emits a compression ring and kinks the trail; rim contact flashes the wall arc; absorbing a pickup pulls a short line from the pickup into the core as it's consumed.

**Destruction.** A destroyed circle collapses inward for 0.1 s, then bursts into fragment circles. Its lines snap from both ends. Anything orphaned detaches, keeps its velocity, spins slowly, fades over ~1 s and drops light.

## 20. Background and playfield

- Playfield base `#050507`.
- **Two parallax layers of dim circuit traces** — thin lines and small nodes, no grid. Layer A at 0.15× player speed, layer B at 0.35× *(tune)*. Parallax is the point; a static pattern barely helps.
- Brightness 10–15% of a lit rim, **always below the bloom threshold**. A glowing background competes with projectiles.
- Trace density and hue intensity rise with ring index, so the background tells you how deep you are.
- No vignette, noise, starfield, gradient wash or grid floor.
- The warp (Section 12) is the one time the background stretches; it returns to normal on arrival.

## 21. Ship editor

In-engine, dev-facing, modelled on the Bubble Tanks 3 tank editor, TRON-themed. The designer uses it daily — it is an M2 deliverable, not a debug panel.

**Top bar:** `Symmetric Mode` (forced on for player hulls) · `Load Ship…` · `Save` · `Save and Exit` · `Exit` · `Stats`

**Canvas:** concentric guide rings every 20 px; horizontal facing centreline with a forward arrow; origin marker at the core. Overlay header shows `Tier N` with a fill bar and `Max Tier: 6`, a `Complexity` bar, and `TP: n / Max TP: m`. `Undo Last` bottom right.

**Right column:** Stats panel (speed, HP buffer, footprint, role tag, primary, secondaries, passives, slots used, TP used) · vertical tabs `Body` / `Primary` / `Secondary` / `Passive` / `Motion` · a preview pane labelled "Click and drag object" · a scrollable component list with a TP cost badge per row, greyed when unaffordable or tier-locked, highlighted when selected.

**Body tab** lists exactly two things: circle and line. Placing a line requires picking two existing circles.

**Motion tab** edits the group properties from Section 18 on the selected subtree, with live preview.

**Budgets.** Slots are a hard cap (Section 9). TP is a build-cost budget that keeps hulls from being visually overloaded. *(tune)* Max TP by tier: T1 6, T2 10, T3 15, T4 21, T5 28, T6 36. Elites get ~2.5× the player budget at the same tier.

**Ship library.** Every ship in the project: thumbnail, name, element, tier, role, faction (player / enemy / elite / boss). Filter and sort by any field. Open, duplicate as the next tier's starting point, rename, delete. A "missing" view shows empty roster slots.

**Generate from description.** A text field takes a plain-language ship description and produces a valid ship file that loads straight into the canvas for hand-editing. The editor is the source of truth and validates before saving.

**Validation.** Blocks saving on: slot overflow, TP overflow, a line with a free end, a circle disconnected from the core, a non-primitive shape, light blue on a non-player ship, asymmetry on a player hull. Warns on: footprint outside the role band, unreadable silhouette at minimum zoom.

**Preview modes.** Live running lights, group motion and bloom exactly as in-game · base zoom and minimum zoom side by side · reshape tween between any two saved ships · bullet pattern preview against a dummy · elite mode showing per-circle HP, firing timers and what detaches when each circle dies.

## 22. Ships as data

```json
{
  "id": "elite_lightning_t4_triskel",
  "name": "Triskel",
  "faction": "elite",
  "element": "lightning",
  "tier": 4,
  "symmetry": "radial",
  "core": { "id": "core", "radius": 34, "color": "yellow",
            "inner_rings": [17], "eye": "red",
            "component": "burst_cannon", "hp": 400 },
  "circles": [
    { "id": "hub_a", "radius": 15, "parent": "core", "color": "yellow",
      "hp": 60, "light_phase": 0.0 },
    { "id": "pod_a1", "radius": 7, "parent": "hub_a", "color": "yellow",
      "hp": 20, "light_phase": -0.7 },
    { "id": "gun_a", "radius": 5, "parent": "hub_a", "color": "red",
      "hp": 25, "component": "seeker_missiles", "light_phase": -1.3 }
  ],
  "lines": [
    { "from": "core", "to": "hub_a", "color": "yellow" },
    { "from": "hub_a", "to": "pod_a1", "color": "yellow" },
    { "from": "hub_a", "to": "gun_a", "color": "yellow" }
  ],
  "groups": [
    { "root": "hub_a", "orbit_radius": 96, "orbit_speed": 0.42,
      "drift_amp": 0.14, "drift_freq": 1.9, "breathe_amp": 0.03,
      "chain_mode": "rigid", "reach_ring": true }
  ]
}
```

Every circle names its parent, so the graph is implicit and detachment is a subtree walk. Mirrored parts on player hulls are authored once and generated on the other side.

## 23. Rendering and performance

- Godot 4 with **2D HDR** on the game viewport and a WorldEnvironment glow. Starting values *(tune)*: threshold 1.0, small radius, high intensity — start at half the radius that looks right and raise intensity rather than widening. Bloom on low mips only.
- Glowing elements draw above 1.0 (palette colour × 1.8). Rims sit just below. Fills stay dark.
- **Projectiles are not scene nodes.** Batch them (MultiMesh or direct canvas draw) with collision in code against a spatial hash. Budget: **2000 live projectiles at 60 fps on Steam Deck**.
- **Trails** are pooled segment buffers, not nodes. Budget 40 simultaneous trails.
- The running light is a shader on the rim (uniforms: perimeter position, segment length, phase).
- Line widths, bloom radius and core radius are constant in **screen space** at any zoom, including during the warp.
- Elites with many independent weapon circles need per-circle aim and fire timers with no per-frame allocation. Pool everything.

## 24. HUD

- Minimap (corner): grid of circles, explored/unexplored, perimeter, boss marker, current node.
- **One bar** for HP and progress, with tier ticks and the next threshold marked. Pulses at threshold with the evolve prompt. Flashes at the regression buffer so the player knows they're about to drop.
- Combo multiplier near the bar, decaying visibly.
- Slot icons with cooldowns.
- Poison/slow state clearly marked on the player.
- Death screen: ring reached, best ring, kills, time. 1.2 s, dismisses on any input.
- Damage numbers off by default.

## 25. Companion and narrative

- Visual-novel portrait and text box. Speaks only between fights; lines queue until the node is clear.
- Reacts to the first evolution, the first regression, each death (a "reboot" — the story advances each time), the first elite, each new element unlocked, and each level boss.
- Rival AIs get a portrait and a line on encounter and defeat.
- 2D stills, no animation in v1.

## 26. Controls

| Action | Keyboard/mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Aim | Mouse | Right stick |
| Fire primary | Hold LMB (auto-fire toggle in options) | Hold RT |
| Secondary 1 / 2 / 3 | Space / Shift / Q | LB / RB / X |
| Dash | Right mouse | LT |
| Evolve | E | A |
| Map | Tab | Back |

Full rebinding. Steam Input via GodotSteam.

## 27. Milestones

**M1 — Prototype.** One node with rim and membranes. Player as a light-blue placeholder, T1–T3, circles and lines only. Bar-as-HP with regression, buffer and grace. Light decay, kill combo, frictionless death. Absorb, evolve, reshape. One enemy archetype. Warp transition between two nodes. Trails and three-beat shots. Parallax background. Bloom. Ships as data plus a first-pass editor.
*Accept when:* first evolution within 2 minutes; testers push out rather than camping; a death-to-flying-again cycle takes under 2 seconds; 1000 projectiles at 60 fps.

**M2 — Editor and roster.** Full editor per Section 21 including library, motion tab and validation. Lightning and fire authored end to end: six tiers, four hulls each, roles spanning.
*Accept when:* the designer can author a hull, see it in the library and play it without touching code.

**M3 — World.** Grid lattice, level perimeter, boss node, minimap, deterministic generation, node pools and respawn, campaign and dev modes.
*Accept when:* a tester always knows which way the boss is; running from a node into an unknown neighbour feels tense.

**M4 — Enemies.** All six archetypes including the radial elite and the irregular elite. Per-circle HP, detachment, group motion, reach rings. Enemy-only components. Full weapon catalogue and slots.
*Accept when:* a tester works out "shoot the limbs off" without being told; elites are what kills them.

**M5 — Elements and character.** All five elements, element unlocking, five campaign levels, companion and rival portraits.
*Accept when:* testers chase a light type on purpose to unlock its branch.

**M6 — Demo.** Steam build, Deck check, levels 1–2 polished, store page clear of TRON references.

## 28. Changes from v0.2

| v0.2 | v0.3 |
|---|---|
| Primitives: circle, ellipse, ring, crescent, arc, tether | **Two only: circle and line.** Crescents and blobs emerge from overlap |
| Lines as one primitive among several | **Every line ends at a circle at both ends**; destroying a circle destroys its lines and detaches anything orphaned |
| Radial map with angular element wedges and distance rings | **Square lattice, every cell a circular node**, Bubble Tanks 3 style |
| Difficulty wall made of enemies | **Visible level perimeter.** Each level is a bounded disc with a boss node on the outer ring |
| Infinite single map with five rival cores | **Five levels**, one boss each, one element revealed each |
| Elements available by region | **Elements unlock by absorbing their light type**, gated by campaign level |
| One mode | **Campaign and dev mode** |
| Node exits as plain transitions | **Warp transition**: membrane push, zoom in, streak warp, arrival, zoom out |
| No pacing mechanics | **Light decay, kill combo, node pool depletion, frictionless death, fresh seed, run stats** |
| Enemy core exposed after N weapons destroyed | **Core carries the main weapon and is the kill target** from the start |
| Enemy motion unspecified | **Per-group orbit, counter-rotation, drift, breathing, chains** with a Motion tab in the editor |
| Movement unspecified | Momentum, drift, dash, persistent lightstream trail |
| Projectiles as plain shapes | **Full animation language**: three-beat shots, tapering trails, projectile interiors, path identity, collar impacts |
| No enemy archetypes | Six archetypes; symmetry optional for enemies; irregular many-circle elites explicitly supported |

## 29. Open decisions

1. Shield's limit: duration plus cooldown, or a hit budget. Prototype both.
2. Whether enemies can pursue through a warp.
3. Whether light decay should pause entirely during a boss fight.
4. Element reveal order across the five levels.
5. Whether a player can voluntarily regress to re-roll a hull.
6. Whether the reshape should swallow nearby projectiles as light.

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
| Void gold | `#ffd23f` | `#000000` | `#fff3bd` |
| Weapon red | `#ff5436` | `#2a0b08` | `#ffc6b5` |
| Player core | — | `#ffffff` | — |
| Enemy core eye | — | `#ff5436` | — |
| Playfield | `#050507` | | |
| Background traces | element hue at 10–15%, 1 px | | |
| Reach rings | element rim at 40–60%, 1 px, dash 2/4 | | |

Match element hues for perceived luminance, not just contrast against black. An inherently brighter element feels stronger regardless of its numbers.

## Appendix B — Timings

- **Running light:** circumference normalised to 100; 13 lit, 87 dark; one lap per 2.0 s, linear. Every fourth circle 1.6 s. Phase offsets −0.7 s and −1.3 s distributed across circles.
- **Breathing:** scale 1.00 → 1.05 → 1.00, 2.0 s, ease in-out, per-group phase.
- **Laser telegraph:** red path line (60–90% opacity) draws from the emitter over 0.8 s and holds; then a wide faint red band (~7 px, 35% opacity) under a bright 2.6 px near-white core for 0.25 s; then 0.5 s cooldown.
- **Explosive telegraph:** outer ring appears; inner ring grows to the outer radius over 1.2 s; detonation damage for 0.25 s.
- **Muzzle ring:** 10 px → 23 px, fading over 0.15 s.
- **Impact:** ring A 4 → 30 px over 0.30 s; ring B 4 → 48 px over 0.30 s at half opacity; 5–7 fragments at 1.4–3.6 px/frame, drag 0.95, fading over 0.55 s.
- **Reshape:** 0.8 s, invulnerable throughout. Regression adds 1.0 s grace after it completes.
- **Warp:** push 0.30 s, zoom in 0.12 s, streaks 0.55 s, arrival 0.15 s, zoom out 0.20 s.
- **Death:** screen 1.2 s, dismisses on any input.
