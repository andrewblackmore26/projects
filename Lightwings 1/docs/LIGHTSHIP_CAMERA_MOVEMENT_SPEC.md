# Lightship camera and movement — approved implementation scope

The document below is the supplied camera and movement specification, verbatim. It supersedes v0.3 §13 and the camera behaviour in §11/§12 of `LIGHTSHIP_GAME_SPEC_V3.md`; everything else in v0.3 stands. The decisions in this preamble were approved on 2026-09-21 and take precedence wherever the source is silent, ambiguous, or inconsistent with itself.

**Decisions**

- **Speed anchor is the crossing time, not the literal pixel value.** The source's pixel values assume 1920×1080; this game's logical viewport is 1280×800 and the node stays 1600 px across (`ARENA_RADIUS = 800`, v0.3 preamble). `player_top_speed = 460 px/s`, from 1600 px / 3.5 s (§2 "the pace to tune against", acceptance test 5). Every other speed derives from that one value by the §2 ratios.
- **No hands-on stops; live-tunable.** Work follows the §9 tuning order. Every timing is gated by a measurement. Every layer has a dev-console toggle and tunables (`tune`, `cam`) so the feel pass can be run in order afterwards. Acceptance test 1 is human-only and is recorded as unverified.

**Defaults taken where the source is ambiguous or silent** (every one is a `GameTuning.FEEL_DEFAULTS` value)

| Question | Default |
|---|---|
| What a duration means | "Smoothing time" is a time constant τ (63 %). "Over X s" and "recentre time" are 95 % settle times, τ = X/3 |
| Recentre 0.30 s, "slightly faster than the lag" | τ = 0.10, blended continuously with the 0.22 lag τ by ship speed so there is no kink |
| "90 % in 0.16 s", "reversal 0.22 s" | One exponential approach, τ = 0.16/ln 10 = 0.0695 s; reversal to 90 % is then ln 20·τ = 0.208 s |
| "Coasts to a stop in 0.40 s" | Below 5 % of top speed at 0.40 s (τ = 0.1335); snaps to zero below 2 % |
| Drift "18° for 0.15 s" | Velocity lags input by 18° at 0.15 s after a 90° step at top speed; perpendicular component decays with its own τ ≈ 0.12 |
| Heavy hull handling | τ ≈ 0.085 (mirrors the Compact ratio) |
| Rim "speed × 0.55" | Applied once on the first contact tick of an episode, then a 0.55 × cap while sliding; never a per-tick multiplier |
| Chain enemies (absent from §2) | Ratio 0.22 |
| Percent-of-viewport values | Of the 640 px logical half-width: 14 % = 89.6 px, 6 % = 38.4 px, 18 % = 115.2 px, 8 % = 51.2 px |
| Where the camera steps | On the sim tick. There is no physics interpolation, so a render-rate camera would make the ship judder against the world. Acceptance test 7 is therefore tick-rate independence of the maths, tested at 1/30, 1/60, 1/120 and 1/144 s |
| Arrival zoom "back to 1.00×" | Eases to the speed-zoom target (0.96 at cruise), avoiding a second zoom change |
| Invulnerability through the transition | 0.56 s from commit: Break + Warp + Arrival |
| Reduced-warp accessibility option | Kept (0.25 s fade); it also keeps the camera calm: no zoom, no whip, no overshoot |

**Known tension, surfaced rather than hidden.** At these defaults cruise lag is 460 × 0.22 = 101 px, above the 89.6 px clamp, so the ship rests on the clamp at cruise and the §6.4 dash moment has no headroom. The source values stay the defaults; `cam preset dashroom` is the labelled alternative.

---

# Supplied reference
# Lightship — camera and movement spec

**Supersedes** v0.3 section 13 (movement and handling) and the camera behaviour described in sections 11 and 12. Everything else in v0.3 stands.

---

## 1. The feel target

Bubble Tanks 3. Your ship is *fast* — it crosses a node in a couple of seconds and turns on a coin. Everything else in the world is slow by comparison, so speed is the player's advantage rather than a shared property of the game.

Right now it isn't quick or dynamic enough. Three things fix that, and they compound:

1. The ship is too slow in absolute terms.
2. The camera is glued to the ship, which removes every cue that speed is happening.
3. Enemies move at comparable speeds, which flattens the contrast.

## 2. Speed budget

Everything in the game is priced relative to the player's top speed. Tune the player first, then set everything else as a ratio.

| Thing | Speed | Ratio to player |
|---|---|---|
| **Player, base hull** | **560 px/s** | 1.00 |
| Player, Compact hull | 700 px/s | 1.25 |
| Player, Heavy hull | 476 px/s | 0.85 |
| Player dash peak | 1400 px/s | 2.50 |
| Drone | 160 px/s | 0.29 |
| Sentry | 0 (static) | — |
| Radial / irregular elite | 90 px/s | 0.16 |
| Boss | 60 px/s | 0.11 |
| Seeker missile | 320 px/s | 0.57 |
| Enemy projectile | 280–400 px/s | 0.50–0.71 |
| Player projectile | 800–950 px/s | 1.43–1.70 |

*(all tune)*

Two rules that fall out and must hold at every tier:

- **The player can always outrun everything except seekers.** Disengaging is always available. That's what makes charging in reasonable.
- **The player's projectiles travel at least twice as fast as the enemy's.** Enemy fire must be dodgeable on reaction; player fire must feel instant.

Node diameter is 1.4× viewport, so at base speed a player crosses a node in about 3.5 seconds. That's the pace to tune against.

## 3. Player movement model

Momentum-based, but tight. The ship should feel like it has weight without feeling like it has inertia you fight.

| Property | Value | Notes |
|---|---|---|
| Acceleration | Reaches 90% of top speed in **0.16 s** | Snappy |
| Drag | Coasts to a stop in **0.40 s** | Slight slide, not skating |
| Turn response | Full direction reversal in **0.22 s** at top speed | Compact hulls 0.17 s |
| Drift | Turning at speed carries the ship wide by up to **18°** of the input direction for 0.15 s | This is what makes movement expressive |
| Rim contact | Speed × 0.55, wall arc flashes | Edges feel physical |

*(all tune)*

The hull rotates to face the aim direction independently of travel, so strafing reads correctly.

## 4. Dash

| Property | Value |
|---|---|
| Burst duration | 0.18 s |
| Peak speed | 2.5× top speed |
| Cooldown | 1.1 s |
| Invulnerable | No |

Dash emits a compression ring at the start point, kinks the lightstream trail hard, and briefly stretches the ship's running lights into streaks. The camera treatment is in §6.4.

## 5. Trails

The player leaves a persistent lightstream. It is the single cheapest source of speed feel after the camera.

- Length scales with current speed: 0 px at rest, **180 px at top speed**, 320 px during a dash.
- Tapers in width and opacity toward the tail. Never blurred.
- Bends with the path, so turns leave visible arcs on screen.
- Enemies leave trails at 30% length. Bosses leave none — they're meant to feel immovable.

## 6. The camera

### 6.1 Trailing camera — the core trick

The camera **lags behind the ship** and is always catching up. At speed the ship sits ahead of screen centre, and the world appears to be racing past it. It is subtle enough that players never notice it and always feel it.

```
camera_target = ship_position
camera_position = damp(camera_position, camera_target, smoothing)
```

| Property | Value | Notes |
|---|---|---|
| Smoothing time | **0.22 s** | Time to close ~63% of the gap |
| Max lag offset | **14% of viewport half-width** | Clamped. At 1920×1080 that's ~134 px |
| Recentre time when stopping | 0.30 s | Slightly faster than the lag, so stopping feels like settling |
| Vertical / horizontal | Identical | No axis weighting |

Clamp the offset with a hard limit rather than letting damping alone bound it, so a long straight run doesn't push the ship to the screen edge.

### 6.2 Speed zoom

Zoom out slightly as speed rises. Small — if it's noticeable it's too much.

| Speed | Zoom |
|---|---|
| Rest | 1.00× |
| Top speed | 0.96× |
| Dash | 0.93× |

Ease in over 0.40 s, ease out over 0.25 s.

### 6.3 Aim influence

Shift the camera a small amount toward the aim direction so the player sees more of where they're shooting.

- Max offset: **6% of viewport half-width**
- Smoothing: 0.30 s, slower than the lag so it doesn't fight it

Total camera offset is `lag_offset + aim_offset`, clamped to 18% of half-width combined.

### 6.4 Dash camera

The dash is where the lag pays off. Do nothing special — just let the existing lag run.

At 2.5× speed the ship rockets toward the clamp and sits at the screen edge for the duration, then the camera hauls itself forward over the following 0.3 s. That single moment sells the whole system. Add only a 2 px, 0.1 s shake at the burst.

### 6.5 Shake budget

Keep it small; this is a game about reading bullets.

| Event | Amplitude | Duration |
|---|---|---|
| Dash | 2 px | 0.10 s |
| Player hit | 4 px | 0.12 s |
| Regression | 7 px | 0.25 s |
| Elite limb detach | 3 px | 0.10 s |
| Boss death | 10 px | 0.5 s, decaying |

## 7. Node transition camera

The transition uses the same trailing camera rather than a bespoke animation. The choreography is a deliberate abuse of the lag, and it's what makes the warp feel like being fired out of something.

| Phase | Duration | Camera |
|---|---|---|
| Push | 0.20 s | Smoothing raised to **0.45 s** so the camera falls further behind than usual. The ship pulls toward the screen edge as it presses into the rim. Zoom eases to 1.02× |
| Break | 0.06 s | Ship accelerates to 3× top speed. Camera is still on the old smoothing, so it's left behind hard. Zoom snaps to 0.94× |
| Warp | 0.30 s | Camera whips forward past the ship with a **0.10 s** smoothing and overshoots by 8% of half-width. Streaks run from the vanishing point ahead |
| Arrival | 0.20 s | Overshoot unwinds. Smoothing returns to 0.22 s. Zoom eases back to 1.00×. The ship's momentum carries it into the new node and the camera catches up behind it |

Total locked time **0.76 s** *(tune, and shorter is better)*. Control returns at the start of Arrival, not at the end, so the last fifth of the transition is already playable.

The visual side of the transition is in the improvements spec.

## 8. Enemy movement

- Enemies accelerate slowly and turn slowly. No drift, no dash.
- Elites and bosses should read as **ponderous**: they reposition, they don't chase. The threat is their fire, not their pursuit.
- Drones are the only enemies that close distance meaningfully, and at 0.29× the player's speed they still can't corner anyone.
- Seekers are the exception and should feel like it — they're the one thing you can't simply outrun, so keep their count low and their turn rate limited so weaving beats them.

## 9. Tuning order

Do this in sequence. Changing one out of order will send you in circles.

1. Player top speed, acceleration and drag, with no camera lag at all. Get the ship feeling right in isolation.
2. Enemy speeds as ratios of it.
3. Camera smoothing and clamp. Tune until a tester says the game feels fast without being able to say why.
4. Speed zoom. Halve whatever value looks right.
5. Aim influence.
6. Transition choreography.
7. Shake, last, and less than you think.

## 10. Acceptance tests

1. A tester describes the ship as fast without being prompted, and cannot identify the camera lag when asked what makes it feel that way.
2. Pause during a full-speed run: the ship is visibly off-centre, ahead of the middle.
3. Stopping dead recentres the camera without any visible snap.
4. The player can disengage from any enemy except a seeker by holding a direction.
5. A node crossing at base speed takes about 3.5 seconds.
6. The transition returns control in under 0.6 s from the moment of commitment.
7. At 60 fps and at 144 fps the camera behaves identically — all damping is frame-rate independent.
