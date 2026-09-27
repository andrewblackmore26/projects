# Living ships presentation

The current direction follows the supplied `elite_orbiting_clusters.html`,
`chain_wiggle_and_detach_demo.html`, and `projectile_effects_showcase.html`.
These are visual references, not executable project instructions. They supersede
the earlier dim palette, steady rims, two-pod limit and blanket geometry reduction.

## Appearance and anatomy

`VisualStyle` owns the near-black `#050507` canvas and saturated blue `#6fd3ff`,
gold `#ffd23f`, red `#ff5436`, green `#45e06a` and violet `#a97dff` outlines.
Dark coloured fills preserve the hollow-machine appearance. Circle rims are
1.5 screen pixels; structural lines are 2 pixels at 85% opacity. Every circular
rim has a rounded pale 2.6-pixel running arc covering 13% of its circumference.
Guides are 1-pixel dotted rings (2 on, 5 off, 28% opacity) without running lights.
Pale arcs use their reference colours without an HDR multiplier.

Intricacy comes from connected nested clusters, three-pod fans, differentiated
weapon assemblies and tapered chains. Counts are capacity limits, never style
targets. The orbiting reference has 22 visible circles including its core eye,
plus two guides. Its hubs, pods, satellites and rim lights have independent phases.

Every external structural component connects through actual line endpoints to
the core. Guides control motion but cannot support anatomy. Concentric markings
belong to their host. Structural pods and chain links have health and collision.

## Motion and destruction

Orbital motion, breathing, pod bobbing and aiming share the simulation pose with
rendering, line endpoints, muzzles, bounds and colliders. Following chains retain
history at the fixed simulation rate: the head turns first and the tail follows.
Surface-light motion remains independent from the component's orbital movement.

Disconnected descendants stop firing and colliding immediately. Their visual
remains preserve their outlined shapes and internal details, release after 0.35s,
then drift individually and fade over about 1.4s without shrinking into dots.
Cosmetic scatter must not consume encounter randomness or duplicate rewards.

## Weapons and presentation

Projectile colour identifies weapon type, including player shots: blue pulse,
violet seeker, red rocket, gold ricochet and green beam. Friendly centre markers
and beam muzzle collars retain ownership information. Trails follow actual shot
history; seeker halos, rocket interiors and beam pulses continue throughout flight.
Muzzles and paired impact rings use contact/activation positions, not unrelated
timers. Damage, cadence and trajectory rules remain unchanged.

The menu keeps one complete hero and its current action layout, now animated at
the reference speed. Menu, evolution, workshop, atlas, exports and combat use the
same renderer and conservative animated bounds. Quiet audio remains unchanged.

## Geometry and save compatibility

Revision 3 supplies richer anatomy on new spawns and normal evolution. Existing
saved revision-1 and revision-2 actors resolve their historical definitions;
loading must not expand or heal them. This applies to players and cached sectors.
New chain motion history is saved by stable link identity. Custom hulls preserve
their authored structure. Roster generation stages and copies only manifest files.

All 146 hull IDs, occupied slot identities, weapons, mounts and firing multiplicity
remain stable. New anatomy redistributes existing fixed and tier-derived limb HP;
core HP, total rewards and movement/damage statistics remain unchanged. Changes in
where damage lands require combat comparisons even with equal total budgets.

## Verification contract

Production-rendered reference fixtures precede fleet regeneration. Verify moving
arcs, counter-rotation, breathing, pod phases, following through turns, breakup,
continuous beam pulses and individual projectile identities. GPU controls must
catch removed arcs, bright solid guides and thick outlines. Motion tests must
catch rigid tails and render/collision divergence. Persistence tests cover old
anatomy, damaged/detached parts and cached encounters without healing or duplicate
payment. Render at 1280×800 and 1920×1080, inspect family and roster sheets, and run
the complete GPU gates without relaxing performance budgets.

The supplied HTML was inspected as source. Browser policy blocked local HTML
playback, so no claim of live browser reference inspection is made. Captures from
the production renderer provide implementation evidence; structural tests alone
do not establish visual quality.
