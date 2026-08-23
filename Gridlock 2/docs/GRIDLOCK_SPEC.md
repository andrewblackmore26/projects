# GRIDLOCK — Technical & Design Specification

**Working title:** Gridlock
**Genre:** Real-time strategy puzzle, single-player vs AI
**Platform target:** Steam (Windows/Mac/Linux) first, mobile-capable input model
**Team:** Solo developer + AI coding assistant
**Purpose of this document:** Complete build spec. An implementer should be able to produce a playable game from this document alone, in **both Unity (C#) and Godot 4 (C#)**, for side-by-side visual comparison.

---

## 1. Elevator

A dark hexagonal lattice strung with glowing wires. You own one node. An AI opponent owns another. Charge accumulates in the nodes you hold; you drag it along wires to take more. Wires do not run straight — they zigzag across the lattice, so a node that looks adjacent may be six seconds away. Beams meet *on the wire* and fight there, the contact point shoving back and forth like a tug of war made of light.

Everything is visible. The difficulty is that a board of forty winding wires cannot be held in your head at once.

---

## 2. Design pillars

These are load-bearing. Do not "improve" them without flagging it.

1. **Visual distance lies.** Travel time follows wire length, never straight-line distance. This is the central source of difficulty and the reason the map is readable but not solvable at a glance.
2. **Combat happens on the wire, not on the tile.** The front line is a moving point on a glowing line. It must be legible with zero UI.
3. **Charging is loud.** A node building an overcharge visibly brightens, and the opponent sees it. Power costs concealment of intent.
4. **The glow is post-processing, not art.** Wire cores are 1–2px crisp lines in HDR colours above 1.0. Bloom does the work. Do not paint fat soft lines.
5. **No fog of war.** The whole board is visible at all times. This was considered and deliberately cut.

---

## 3. Architecture — read this before writing any code

The game must be built in Unity and Godot for comparison. **Do not write it twice.**

Write the entire simulation as **plain C# with zero engine dependencies** — no `UnityEngine` imports, no `Godot` imports, no `MonoBehaviour`, no `Node`. Godot 4 supports C# via .NET, so the identical source files drop into both projects unchanged.

```
/Core                    ← plain C#, shared verbatim by both projects
  HexCoord.cs
  GameNode.cs
  Wire.cs
  Beam.cs
  Contest.cs
  Simulation.cs          ← fixed-timestep tick, owns all state
  Ai/
    AiController.cs
    AiDifficulty.cs
    CandidateScorer.cs
  Levels/
    LevelData.cs
    LevelLoader.cs
  Config/
    Tuning.cs            ← every magic number lives here

/UnityProject            ← thin presentation + input layer
/GodotProject            ← thin presentation + input layer
/Levels                  ← JSON level files, shared
```

**Rules for the Core layer:**

- Deterministic. Fixed timestep of **1/60s**, accumulator pattern. Never read frame delta directly.
- No rendering, no input, no file IO beyond level deserialisation.
- Exposes state by read-only queries and emits events (`NodeCaptured`, `BeamSpawned`, `ContestStarted`, `ContestResolved`, `NodeOvercharging`, `NodeDisabled`) that the presentation layer subscribes to.
- Must be unit-testable headless. Include a test that runs a full AI-vs-AI match with no renderer attached and asserts it terminates.

**Rules for the presentation layers:**

- Read simulation state, draw it. Never mutate simulation state directly — send intents (`RequestSend(sourceId, wireId, holdDuration)`).
- Interpolate visually between fixed ticks so movement is smooth at any framerate.

This keeps the Unity/Godot comparison a **pure rendering and feel comparison**, which is the point of building both.

---

## 4. Board model

### 4.1 Hex lattice

Axial coordinates (`q`, `r`), **pointy-top** hexagons. Standard axial-to-pixel conversion.

The lattice serves two roles:
- **Cells** hold nodes.
- **Edges and vertices** are the routing graph that wires follow.

Wires run along hex cell edges and turn at vertices. They never cut through open space. This constraint is mandatory — free-form curves become unreadable past ~40 wires, and lattice-constrained routing reads like a printed circuit board, which is the target aesthetic.

### 4.2 Node

| Field | Type | Notes |
|---|---|---|
| `id` | int | |
| `coord` | HexCoord | |
| `owner` | enum {Neutral, Player, Ai} | |
| `state` | enum {Idle, Overcharging, Disabled, CaptureLocked} | |
| `charge` | float | current stored charge |
| `degree` | int | wire count, **hard max 6** (one per hex face) |
| `wireIds` | int[] | ordered by face index 0–5 |
| `cooldownRemaining` | float | seconds, for Disabled |
| `overchargeProgress` | float | 0→1, drives visual brightness |

**Degree is capped at 6 by the hexagon's six faces.** This is the geometric justification for the hex shape — it is not decoration.

### 4.3 Wire

| Field | Type | Notes |
|---|---|---|
| `id` | int | |
| `nodeA`, `nodeB` | int | endpoints |
| `path` | Vector2[] | lattice vertices from A to B, in order |
| `length` | float | sum of segment lengths, in lattice units |
| `faceA`, `faceB` | int | which face (0–5) it leaves each node from |

`length` is what drives travel time. It is **not** the distance between endpoints. A wire between two visually adjacent nodes may have length 12 while a wire spanning the board has length 4.

---

## 5. Simulation rules

### 5.1 Charge accumulation

Owned nodes accumulate charge continuously:

```
chargeRate = BASE_CHARGE_RATE * degree
charge = min(charge + chargeRate * dt, MAX_CHARGE_PER_DEGREE * degree)
```

Neutral nodes do not accumulate. `Disabled` nodes do not accumulate.

**This is the entire economy.** Wire count → charge rate → how much you can send → power. There is no separate power multiplier.

### 5.2 Anti-snowball rule

High-degree nodes are the prize *and* the obstacle:

```
neutralDefense = NEUTRAL_DEFENSE_PER_DEGREE * degree
```

A 6-wire hub is expensive to take and pays out six times a 1-wire node once held. This is the agreed fix for the snowball problem — hubs are worth racing for but cannot be rushed for free.

### 5.3 Sending charge

Player presses a node they own → the node begins accumulating hold progress *immediately* (this is what makes it visibly brighten). Then:

```
holdProgress = clamp(holdTime / OVERCHARGE_TIME, 0, 1)
sendFraction = lerp(MIN_SEND_FRACTION, 1.0, holdProgress)
```

On release over a valid connected target:

```
power = source.charge * sendFraction
source.charge -= power
speed = BASE_BEAM_SPEED
```

**If `holdTime >= OVERCHARGE_TIME` (overcharge threshold crossed):**

```
speed = BASE_BEAM_SPEED * BURST_SPEED_MULTIPLIER
power = source.charge          // sends everything
source.charge = 0
source.state = Disabled
source.cooldownRemaining = BURST_COOLDOWN
```

A `Disabled` node accumulates no charge, cannot send, and **can be captured normally** — its defense is frozen at whatever charge it had (zero, after a burst). Bursting into enemy territory therefore leaves a dark, vulnerable node behind you. This is the intended gamble.

### 5.4 Speed and power are separate

- **Power** decides who wins a collision and whether a node flips. Comes from stored charge (i.e. from degree).
- **Speed** decides who arrives first and how much warning the defender gets. Comes from burst.

A fast weak burst can grab a contested node before a slow heavy send lands — and then be overwhelmed when it does.

### 5.5 Beams

| Field | Type |
|---|---|
| `id` | int |
| `wireId` | int |
| `owner` | Player / Ai |
| `power` | float |
| `speed` | float |
| `t` | float, 0→1 position along wire |
| `forward` | bool, direction of travel (A→B or B→A) |

Per tick: `t += (forward ? 1 : -1) * (speed / wire.length) * dt`

Two beams of the **same owner** on the same wire in the same direction **merge** on contact: powers sum, speed takes the max.

### 5.6 Contest — the core combat mechanic

When two beams of **opposing owners** on the same wire would cross, destroy both beams and spawn a `Contest`:

```
Contest {
  wireId
  contactT        = midpoint of the two beam positions
  powerPlayer
  powerAi
}
```

Per tick, using **pre-tick values for both sides** (avoid order dependence):

```
burnP = powerAi   * CONTEST_BURN_RATE * dt
burnA = powerPlayer * CONTEST_BURN_RATE * dt
powerPlayer -= burnP
powerAi     -= burnA

push = (powerPlayer - powerAi) / (powerPlayer + powerAi)
contactT += push * CONTEST_PUSH_SPEED * dt * (playerIsForward ? 1 : -1)
```

This is Lanchester-style mutual attrition. A much stronger beam wins fast and cheap; evenly matched beams grind and the contact point oscillates. That oscillation is the "breathing front line" and is the single most important visual in the game.

**Resolution:**
- One side ≤ 0 → the survivor resumes as a normal beam from `contactT` with its remaining power and original speed.
- `contactT` reaches 0 or 1 → the survivor arrives at that node immediately with remaining power.

**Reinforcement (important):** a friendly beam travelling toward an active contest on the same wire is absorbed on contact — its power is added to that side's total and the beam is destroyed. This is what makes mid-fight reinforcement feel good and must work correctly.

### 5.7 Node resolution

Beam reaches a node:

```
if (beam.owner == node.owner)
    node.charge = min(node.charge + beam.power, maxCharge)
else {
    defense = (node.owner == Neutral) ? node.neutralDefense : node.charge
    if (beam.power > defense) {
        node.owner  = beam.owner
        node.charge = beam.power - defense
        node.state  = CaptureLocked      // brief, prevents instant re-send
        node.cooldownRemaining = CAPTURE_LOCK_TIME
        emit NodeCaptured
    } else {
        if (node.owner == Neutral) node.neutralDefense -= beam.power
        else node.charge -= beam.power
    }
}
```

Neutral defense **does not regenerate**. Chipping a hub down over several sends is a valid and intended strategy.

### 5.8 Win condition

A side loses when it owns zero nodes and has zero beams and zero contests in flight. Levels may override with objectives (§10).

---

## 6. Tuning constants

All in `Core/Config/Tuning.cs`. Every one of these must be a named constant, not a literal. Expose them in an in-game debug panel — this game will need heavy tuning.

| Constant | Suggested start | Notes |
|---|---|---|
| `TICK_RATE` | 60 | fixed timestep |
| `BASE_CHARGE_RATE` | 1.2 /s per degree | |
| `MAX_CHARGE_PER_DEGREE` | 12.0 | |
| `NEUTRAL_DEFENSE_PER_DEGREE` | 8.0 | anti-snowball lever |
| `MIN_SEND_FRACTION` | 0.35 | tap-and-drag sends this much |
| `OVERCHARGE_TIME` | 1.4 s | hold duration to reach burst |
| `BURST_SPEED_MULTIPLIER` | 2.5 | |
| `BURST_COOLDOWN` | 5.0 s | |
| `CAPTURE_LOCK_TIME` | 0.5 s | |
| `BASE_BEAM_SPEED` | 4.0 lattice units/s | |
| `CONTEST_BURN_RATE` | 0.30 | higher = faster, more decisive fights |
| `CONTEST_PUSH_SPEED` | 0.55 | how fast the front line moves |
| `MIN_SEND_CHARGE` | 2.0 | below this, sending is disallowed |

---

## 7. Input & controls

Three actions, one input surface. Must work with mouse and touch identically.

### 7.1 Tap a node — inspect

Tap with no drag and release before `OVERCHARGE_TIME`: highlight that node's wires at full brightness and dim every other wire to ~15% opacity for 2 seconds, or until another tap.

This is a **view tool with no cost and no strategic content**. Nothing is hidden; it exists purely to declutter a busy board. Do not add a cost to it.

### 7.2 Press, hold, drag, release — send

The disambiguation problem: hold and drag both begin as "pointer down, stationary," so the system cannot tell them apart at contact.

**Resolution:** the node begins charging the instant it is touched. What happens next decides the outcome.

1. Pointer down on an owned, non-Disabled node with `charge >= MIN_SEND_CHARGE`
2. Node begins accumulating hold progress immediately; brightness scales with `overchargeProgress`
3. A targeting line is drawn from the node to the pointer
4. Drag over a **connected** node → line renders in the owner's colour, target node highlights
5. Drag over anything else → line renders dim grey
6. Release over a valid target → send fires with whatever hold accumulated
7. Crossing `OVERCHARGE_TIME` mid-hold → node visually cracks/flares to signal burst is armed

### 7.3 Cancel

Standard convention, both must work:
- Drag back onto the origin node and release
- Release over empty space or an invalid target

Cancelling costs nothing and consumes no charge. **The opponent still saw the node brighten.** Feinting — lighting a node up, watching the AI commit to a defensive send, then releasing — is an intended and desirable emergent tactic. Do not suppress the visual on cancel.

---

## 8. Visual specification

The look is TRON: neon on near-black. The most common failure is painting glowy art instead of configuring an HDR pipeline.

### 8.1 The rule that matters most

Draw a **thin, crisp line (1–2px core) in a colour with components above 1.0**, and let bloom produce the glow. Fat soft lines read as mush. The core stays sharp; the glow provides the thickness.

### 8.2 Palette

| Element | Colour | Notes |
|---|---|---|
| Background | `#05070D` | dark blue-violet, **not pure black** — glow needs something to sit against |
| Player | Cyan `#00E5FF`, emission ×3.0 | |
| AI | Amber `#FF8A00`, emission ×3.0 | |
| Neutral node | Grey `#5A6070`, emission ×0.8 | |
| Unpowered wire | Grey `#2A3040`, no emission | |
| Contest hot point | White `#FFFFFF`, emission ×6.0 | |

Cyan/amber is TRON canon and happens to be colourblind-safe, which matters because colour *is* the ownership indicator. Do not substitute red/green.

### 8.3 Post-processing stack

In order:
1. **Bloom** — the big one. Threshold ~1.0, high intensity, wide radius.
2. **Vignette** — subtle.
3. **Chromatic aberration** — very subtle, edges only.
4. **Film grain** — optional, low opacity.

Restraint on 2–4. Bloom does the heavy lifting.

### 8.4 Animate shader parameters, never objects

A pulse travelling down a wire is a **float uniform 0→1** fed into the line's shader, not a sprite being moved. Same for the contest contact point — it is a gradient boundary position uniform.

This is cheaper, perfectly smooth at any framerate, and scales to hundreds of wires. Moving sprites along paths will not scale and will judder.

Wire shader needs, at minimum:
- `ownerColorA`, `ownerColorB`
- `boundaryT` — where the colour split sits (contest position)
- `pulsePositions[]` — array of travelling beam positions
- `baseIntensity`

### 8.5 Contest visual — spend disproportionate time here

This one effect carries the feel of the whole game:
- White-hot core at `contactT`, brightest thing on screen
- Sparks emitted **perpendicular to the wire**, both directions, rate proportional to `min(powerPlayer, powerAi)`
- Colour boundary on the wire snaps to `contactT` and visibly shoves back and forth
- Subtle screen-space shake or bloom pulse when a large reinforcement is absorbed

### 8.6 Node visuals

- Idle owned: steady hex outline in owner colour, brightness scales with `charge / maxCharge`
- Overcharging: brightness ramps with `overchargeProgress`, faint pulsing that quickens; at 1.0 the outline flares and fractures
- Disabled: outline goes dark grey, slow dim sweep, clearly "off"
- Neutral: dim grey outline, small stubs drawn on each face that has a wire (this shows degree at a glance)
- Capture: brief radial flash in the capturing colour

---

## 9. AI opponent

The AI is a first-class feature, not a placeholder. It must be beatable, readable, and scale across levels.

### 9.1 Information model

The AI sees exactly what the player sees — the full board, all beams, all contests, all overcharging nodes. There is no fog to hide, so there is nothing to cheat with.

**Difficulty comes from constraints on acting, not on knowing.** Reaction time, decision cadence, evaluation noise, and which behaviours are enabled. Never give the AI extra charge rate or extra information — players notice, and it reads as unfair rather than difficult.

### 9.2 Architecture — utility scoring

Every `decisionInterval` seconds (with ±20% jitter so it doesn't feel metronomic):

1. **Enumerate candidates.** For every owned node with `charge >= MIN_SEND_CHARGE` and `state == Idle`, for every attached wire, the pair (source, wire) is a candidate. Each candidate may be evaluated at both normal send and burst, if burst is enabled at this difficulty.
2. **Score each candidate** (§9.3).
3. **Add noise:** `score *= (1 + randRange(-noiseFactor, +noiseFactor))`
4. **Execute** the highest scorer if it exceeds `actionThreshold`; otherwise do nothing this interval (banking charge is a valid move).

Utility scoring is the right choice here over a behaviour tree: it is transparent, tunable by weight, and its difficulty knobs are continuous.

### 9.3 Scoring factors

```
score = 0

// Capture feasibility — dominant term
projectedPower = source.charge * sendFraction
if (projectedPower > targetDefense)
    score += W_CAPTURE * (projectedPower / targetDefense)
else
    score += W_CHIP * (projectedPower / targetDefense)   // partial chip, much lower weight

// Target value — hubs are worth more
score += W_DEGREE * target.degree

// Travel time penalty — long wires telegraph and can be intercepted
score -= W_TRAVEL * (wire.length / BASE_BEAM_SPEED)

// Reinforcement — feed an active contest we are losing but could win
if (contest on wire && aiSide losing && projectedPower would flip it)
    score += W_REINFORCE

// Threat response  [enabled at difficulty >= 3]
if (enemy beam inbound to a node I own && it would capture)
    score += W_DEFEND * target.degree

// Overcharge read  [enabled at difficulty >= 6]
if (player node is Overcharging && this target is reachable from it)
    score += W_ANTICIPATE * playerNode.overchargeProgress

// Frontier bias — prefer expanding toward contested space over safe interior
score += W_FRONTIER * (target borders enemy or contested territory ? 1 : 0)

// Overextension penalty — don't strip a node that is itself under threat
score -= W_OVEREXTEND * (source is bordering enemy ? source.charge / maxCharge : 0)
```

Suggested weights: `W_CAPTURE 10`, `W_CHIP 2`, `W_DEGREE 3`, `W_TRAVEL 1.5`, `W_REINFORCE 8`, `W_DEFEND 12`, `W_ANTICIPATE 5`, `W_FRONTIER 2`, `W_OVEREXTEND 4`.

### 9.4 Difficulty tiers

| Level | `decisionInterval` | `noiseFactor` | `actionThreshold` | Burst | Threat response | Anticipate |
|---|---|---|---|---|---|---|
| 1 | 3.0 s | 0.50 | 8 | no | no | no |
| 2 | 2.5 s | 0.40 | 7 | no | no | no |
| 3 | 2.2 s | 0.35 | 6 | no | yes | no |
| 4 | 1.8 s | 0.28 | 6 | yes | yes | no |
| 5 | 1.5 s | 0.22 | 5 | yes | yes | no |
| 6 | 1.2 s | 0.18 | 5 | yes | yes | yes |
| 7 | 1.0 s | 0.14 | 4 | yes | yes | yes |
| 8 | 0.85 s | 0.10 | 4 | yes | yes | yes |
| 9 | 0.7 s | 0.07 | 3 | yes | yes | yes |
| 10 | 0.6 s | 0.05 | 3 | yes | yes | yes |

`decisionInterval` is the primary difficulty lever — it is effectively reaction speed, and it is the one players intuitively read as "the opponent is sharper" rather than "the opponent is cheating."

### 9.5 AI acceptance criteria

- Level 1 AI must be beatable by a first-time player on their first attempt on level 1's board.
- Level 10 AI must beat a competent player on a symmetric board more often than not.
- AI-vs-AI at equal difficulty on a symmetric board must be within 45–55% win rate over 1000 headless runs. Include this as an automated test — it is the fastest way to catch a broken scoring weight.
- The AI must never send into a wire where it cannot possibly win the contest, unless `noiseFactor` caused it. Blatant self-destruction reads as broken, not as easy.

---

## 10. Levels

### 10.1 Format — JSON, hand-authored

Procedural generation is explicitly **out of scope for v1**. Hand-authored levels are a solo dev's advantage here: you draw a board, you play it, you tune it. Procgen for this graph structure (guaranteeing both seeds reach comparable territory, no dead-end pockets) is a genuinely hard problem and is not worth solving before the game is proven.

```json
{
  "id": "level_04",
  "name": "Switchback",
  "difficulty": 4,
  "objective": "eliminate",
  "parTime": 180,
  "nodes": [
    { "id": 0, "q": 0,  "r": 0,  "owner": "player" },
    { "id": 1, "q": 4,  "r": -2, "owner": "ai" },
    { "id": 2, "q": 2,  "r": 1,  "owner": "neutral" }
  ],
  "wires": [
    { "id": 0, "a": 0, "b": 2, "path": [[0,0],[0,1],[1,1],[1,2],[2,2]] },
    { "id": 1, "a": 2, "b": 1, "path": [[2,2],[3,2],[3,1],[4,1]] }
  ]
}
```

`path` is a list of lattice vertex coordinates. `length` and `degree` are computed on load, never authored.

**Build a level editor.** An in-engine tool to place nodes and draw wires along the lattice, with JSON export. This is not optional — hand-writing path arrays will not survive past level 3, and the level editor is where the game actually gets designed.

### 10.2 Objectives

- `eliminate` — take all AI nodes (default)
- `survive` — hold at least one node for N seconds
- `capture` — take specific node IDs
- `efficiency` — win using at most N sends (puzzle mode; this is where the "strategy puzzle" identity lives)

### 10.3 Progression

Levels are ordered and gated by completion. Difficulty rises through **board design first, AI tier second** — a nastier wire layout is more interesting than a faster opponent. Later levels introduce boards with deliberately misleading geometry: visually adjacent nodes joined by wires that wander halfway across the map.

---

## 11. Unity implementation notes

- **Unity 6 LTS**, URP, **2D Renderer**
- Personal licence is free below $200k revenue — fine indefinitely at this stage
- Global Volume with **Bloom** override; enable **HDR** on the URP asset; use the HDR colour picker so emission can exceed 1.0
- Wires: custom mesh generated from the path polyline (a `LineRenderer` per wire will not batch well at scale). One material, one shader, per-instance properties via `MaterialPropertyBlock`
- Shader Graph or hand-written HLSL. Needs `boundaryT` and a pulse array as exposed properties
- Sparks: VFX Graph, or Shuriken if simpler
- Input: `EnhancedTouch` / new Input System so mouse and touch share a code path
- Steam: **Steamworks.NET**
- The `/Core` folder drops in as plain scripts; ensure the assembly definition does not reference `UnityEngine`

## 12. Godot implementation notes

- **Godot 4.7+**, .NET build (required for shared C# Core)
- `WorldEnvironment` node with **Glow** enabled; set the Viewport to **HDR 2D**. Glow composites before tonemapping as of 4.6, which is what gives clean neon highlights — this is largely turnkey compared to Unity's setup
- Wires: `Line2D` with a `ShaderMaterial`, or a custom `MeshInstance2D` for large boards. Start with `Line2D`
- Shaders in Godot's shading language; uniforms mirror the Unity list
- Sparks: `GPUParticles2D` with a one-shot emitter per contest
- Input: `_input` / `_gui_input` handles mouse and touch uniformly with `emulate_touch_from_mouse`
- Steam: **GodotSteam** (tracks current Godot releases)
- The `/Core` folder is added to the C# project directly — same files, no changes

---

## 13. Build order

Do not build these out of order. Each milestone must be playable or testable before moving on.

**M1 — Core simulation, headless.** Data model, tick loop, charge accumulation, beams, contests, capture. No rendering. Unit tests for contest resolution, reinforcement absorption, and capture edge cases. *Done when: an AI-vs-AI match runs to completion in a console and prints a winner.*

**M2 — Godot rendering pass.** Lattice, nodes, wires, beams, contests, full post-processing stack. Read-only view of a scripted match. *Done when: watching an AI-vs-AI match is visually satisfying with no input at all.* If it isn't, stop and fix the look before adding input — everything downstream depends on the contest reading well.

**M3 — Input.** Press/hold/drag/release, targeting line, cancel, tap-to-inspect. Play against a fixed mid-tier AI.

**M4 — Unity rendering pass.** Same Core, same levels. Compare side by side. **Pick one and drop the other.** Do not maintain both past this point.

**M5 — AI difficulty tiers.** Full scoring, all tiers, the 1000-run balance test.

**M6 — Level editor.** In-engine, JSON export.

**M7 — Content.** 15–20 levels, progression gating, objectives beyond `eliminate`.

**M8 — Shell.** Menus, settings, save/progress, Steam integration, achievements.

---

## 14. Acceptance criteria for v1

- A match on a 20-node board holds 60fps with 30+ simultaneous beams
- The contest contact point is legible at a glance without reading any UI
- A new player understands press-drag-release without a tutorial prompt
- Overcharging a node is visible to the player as an opponent threat, and reacting to it is a real decision
- Level 1 winnable first try; level 10 loses to most players first try
- All simulation constants tunable at runtime via debug panel
- Simulation is deterministic: same level + same input sequence + same RNG seed = identical outcome

---

## 15. Explicitly out of scope for v1

Cut deliberately, with reasons. Do not add these back without a decision.

- **Fog of war.** Considered at length and cut. Indirect wire routing already produces opacity through complexity rather than concealment, which suits a puzzle game better and makes hand-authored levels and an efficiency mode possible. Fog is additive later if the visible version proves too solvable; going the other direction is much harder.
- **Wires breaking on burst.** Rejected. It degrades the network over a match, which works against the pleasure of reading a rich board, and it stacks a fourth systemic rule on an untested core.
- **Procedural map generation.** See §10.1.
- **Multiplayer.** The Core is deterministic and lockstep-friendly, so this stays possible. Not v1.
- **Narrative, characters, voice, cutscenes.** Not this game.
