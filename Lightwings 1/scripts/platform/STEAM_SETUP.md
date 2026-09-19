# Optional Steam integration

The local game and all local save operations work without Steam. GodotSteam 4.22.1
is bundled for Windows x64 and Linux x64. The repository contains no Steamworks
App ID or partner credentials and never substitutes a sample App ID.

For a Steam build, set `lightship/steam/app_id` in project
settings to the owned App ID. Configure achievement API names and Steam Cloud
storage in the Steamworks partner dashboard; the adapter uses
`lightship_campaign_v2.json` and `lightship_demo_v2.json`. Ship the native libraries
already included with the matching export preset.

Those filenames remain stable for compatibility; their `v2` suffix is not the
payload schema. Current saves use envelope/gameplay version 3 and combat snapshot
version 2. The normal game uploads campaign saves; demo progression remains local
and can be imported into the full campaign.

The current campaign emits `FIRST_EVOLUTION`, `FIRST_RIVAL` (a rival core defeated)
and `CAMPAIGN_COMPLETE` (all five cores defeated). Configure those API names in
Steamworks. Gate progression no longer produces an achievement.

`PlatformService.initialize()` discovers the Steam singleton dynamically. It does
not make the project depend on its class at parse time. Missing configuration,
missing libraries, initialization failure, and disabled cloud storage preserve
offline play. Local snapshots remain the source of truth. Cloud reads return bytes
for `SaveService.decode_snapshot()` validation; the UI must not silently overwrite
an existing local campaign with remote data. Achievement IDs requested offline are
persisted separately in `steam_state.json` and retried on launch and every five
seconds while connected. The queue clears only after a successful Steam stats
callback; local device settings are not uploaded to cloud.

## Native Steam Input

`content/platform/steam_input_manifest.vdf` defines Gameplay and Menu action sets.
The adapter initializes Steam Input, resolves native handles, switches sets,
converts analog movement/aim, consumes component button edges once, and forwards
map/evolve/pause/menu actions into Godot. Disconnecting releases held actions;
unavailable native bindings retain the standard Godot controller fallback.

The native action names retain compatibility with earlier layouts:

| Steam Input action | Current action | Default controller binding |
|---|---|---|
| `Fire` | Fire the primary | RT |
| `ComponentPrimary` | Secondary weapon 1 | LB |
| `ComponentSecondary` | Secondary weapon 2 | RB |
| `ComponentTertiary` | Secondary weapon 3 | X |

Keyboard equivalents are left mouse, Space, Shift and Q. Update official layouts
to include `ComponentTertiary`; a two-component layout omits the third secondary.

Call `set_input_context(true)` for menus, map, dialogue, and pause, and `false` for
unpaused combat. `get_command(last_aim)` returns a `ShipCommand`, or null when the
ordinary Godot input path should be used. `show_input_bindings()` opens Steam's
binding interface for the connected controller. Keep PlatformService processing
while the scene tree is paused.

The manifest is extracted to a real user-data path because Steam cannot read
inside a PCK. Export presets must include `content/platform/*.vdf`. The checked-in
manifest intentionally has an empty `configurations` section: no partner-owned
default layout or hardware verification can be validated without the game's
real App ID and a connected controller. Before release, create and export official
Xbox and Steam Deck layouts in Steam Input Layout Dev Mode, bundle their VDF files
beside the manifest, add their paths to `configurations`, and test both sets with
the owned App ID. The runtime extractor copies all bundled VDF files together.
This is the remaining account/hardware release gate, not
a claim that the game is Steam Deck Verified.

## Cloud UI integration

After a local save succeeds, call `save_cloud(encode_snapshot(snapshot), slot)`.
At startup, `inspect_cloud(slot)` returns `offline`, `missing`, `invalid`, `same`,
`remote_only`, or `conflict`, with readable local/remote summaries for conflicts.
Display the two snapshots and let the player choose. Pass the reviewed bytes to
`resolve_cloud("use_cloud", slot, remote_bytes)` or choose
`resolve_cloud("keep_local", slot)`. Inspection compares a pure migrated preview
while retaining the original `remote_bytes` for the choice. The remote choice
installs those exact bytes through SaveService, retains the prior local backup,
and archives legacy data before returning its compatible profile. This prevents
a resolved legacy save from appearing as a new conflict on every launch.

Inspection never replaces either save. Loading a legacy local snapshot may create
its preservation archive; invalid remote data never overwrites local progress.

Sources: <https://godotsteam.com/classes/main/>,
<https://godotsteam.com/classes/remote_storage/>,
<https://godotsteam.com/classes/user_stats/>.
Upstream API declaration reference:
<https://codeberg.org/godotsteam/godotsteam/src/branch/godot4/doc_classes/Steam.xml>.
Steam Input formats and configuration workflow:
<https://partner.steamgames.com/doc/features/steam_controller/action_manifest_file>
and <https://partner.steamgames.com/doc/features/steam_controller/iga_file>.

`tests/world_steam_api_probe.gd` confirms installed extension signatures through
ClassDB without initializing a Steam account. `tests/world_platform_test.gd`
checks command conversion, disconnects, pending achievements, cloud conflicts,
and failure recovery against a deterministic API double. A real-account cloud
round trip and physical-controller test remain necessary before publication.
