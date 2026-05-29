# Playable Vertical Slice Verification

Date: 2026-05-24

## Smoke Bomb Size And Lifetime Tuning

Date: 2026-05-28

Status: `fixed-and-rerun`

The user asked for smoke bomb to be larger, grow faster and remain active longer.

Changes applied:

- `data/weapons/smoke_bomb.tres` now uses `effect_radius_m = 4.0` and `effect_duration_sec = 14.0`.
- `SmokeVolume` grows quickly using `growth_time_sec = 0.65`, then slowly swells for the remaining lifetime.
- Smoke projectile and network smoke spawning now pass both lifetime and radius into the spawned smoke volume, so the data resource controls the visible result in local and multiplayer paths.

Validation:

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0

$ ./run.sh --headless --script res://tools/validate_smoke_bomb_tuning.gd
SMOKE_BOMB_TUNING_PASS radius=4.00 lifetime=14.00 growth=0.65 scale=(1.100899, 1.100899, 1.100899) definition_radius=4.00 definition_lifetime=14.00
EXIT=0

$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0

$ python3 tools/runtime_smoke.py weapons
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors
EXIT=0

$ ./run.sh --script res://tools/capture_smoke_bomb_volume.gd
SMOKE_BOMB_CAPTURED res://docs/verification/screenshots/smoke_bomb_larger_volume.png
EXIT=0
```

Visual QA for `docs/verification/screenshots/smoke_bomb_larger_volume.png`:

- The smoke cloud is visibly much wider than the held smoke bomb viewmodel and covers a meaningful area between buildings.
- The player HUD remains readable and shows `Weapon: Smoke Bomb`, `Ammo: 3 charges`, `HP: 100`, and `State: grounded`.
- The smoke has already expanded into a large clustered volume by the capture point, matching the faster-growth tuning.

## Shotgun And Sniper Viewmodel Orientation Fix

Date: 2026-05-28

Status: `fixed-and-rerun`

The user reported that shotgun and sniper had their barrels facing back toward the camera. The asset wrapper rotations have been corrected:

- `scenes/weapons/viewmodels/shotgun_viewmodel.tscn`: `model_position = Vector3(0.28, -0.28, -0.22)`, `model_rotation_degrees = Vector3(0, 12, -3)`, `model_scale = Vector3(0.16, 0.16, 0.16)`
- `scenes/weapons/viewmodels/sniper_viewmodel.tscn`: `model_rotation_degrees = Vector3(0, 0, 0)`

Validation:

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0

$ python3 tools/runtime_smoke.py weapons
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors
EXIT=0

$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0

$ ./run.sh --script res://tools/capture_shotgun_sniper_viewmodels.gd
SHOTGUN_SNIPER_VIEWMODELS_CAPTURED { "shotgun": "res://docs/verification/screenshots/weapon_visual_qa/shotgun.png", "sniper": "res://docs/verification/screenshots/weapon_visual_qa/sniper.png" }
EXIT=0
```

Visual QA:

- `weapon_visual_qa/shotgun.png` shows the shotgun barrel running forward into the scene, with the stock/receiver closer to the lower-right camera/player side instead of floating too far forward.
- `weapon_visual_qa/sniper.png` shows the long barrel pointing forward toward the crosshair/sightline, with the scope and rear body remaining on the player side.
- Both screenshots keep the HUD readable and the weapon models clear of the center reticle.

## Ground Counter-Momentum Tuning

Date: 2026-05-28

Status: `fixed-and-rerun`

The user reported that high-speed ground movement still slid too far when actively pressing backward or another direction. Ground movement now applies dedicated counter-direction and lateral braking while input is held, before accelerating toward the new wish direction.

The runtime movement smoke includes high-speed reverse-input and sideways-input checks so active braking cannot regress to normal acceleration-only turning.

Commands rerun:

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0

$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

## User-Replaced Shotgun With Assault Rifle

Date: 2026-05-25

Status: `fixed-and-rerun`

The user asked to replace shotgun usage with assault rifle. The default loadout already used `assault_rifle`, but the visual-polish and smoke harness still had active shotgun-specific capture paths.

Fixes applied:

- P10A visual-polish capture now uses `primary_assault_rifle` instead of the old `shotgun` capture entry.
- P10A close-combat setup now selects and fires `assault_rifle` instead of `shotgun`.
- The weapons smoke setup no longer chooses shotgun as the primary weapon for the extended smoke loadout.
- A direct P10A `shotgun` view request is mapped to assault rifle so old capture calls do not reintroduce shotgun into the visual-polish path.
- User reopened the regenerated rifle screenshots because the assault rifle still read as reversed. A test variant with `Vector3(180, 0, 0)` was captured and rejected because the rifle read too vertical/side-on. `scenes/weapons/viewmodels/rifle_viewmodel.tscn` now uses `Vector3(0, 0, 180)`, so the barrel/front points forward into the scene and the stock/back reads as the player-side end.

Evidence:

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0

$ git diff --check
EXIT=0

$ python3 tools/runtime_smoke.py all --base-port 25160
SMOKE_PASS offline
SMOKE_PASS weapons
SMOKE_PASS network-game/lobby flows through 3v3
EXIT=0
```

```text
$ ./run.sh -- --verification-capture=p10a-before
VERIFICATION_CAPTURE_PASS p10a-before
screenshot_count=11
duration_sec=16.553
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py weapons
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0

$ ./run.sh --script res://tools/capture_taser_gun_view.gd
TASER_GUN_CAPTURED res://docs/verification/screenshots/taser_gun_viewmodel.png
EXIT=0
```

Regenerated P10A screenshot evidence:

- `docs/verification/screenshots/p10a_visual_polish/*_primary_assault_rifle.png`
- `docs/verification/screenshots/p10a_visual_polish/*_close_combat.png` with HUD/viewmodel showing `Assault Rifle`

Visual observations from the regenerated current-flow screenshots:

- `before_primary_assault_rifle.png` shows the first-person rifle viewmodel in the lower-right/lower-center frame; the HUD confirms `Weapon: Assault Rifle`; the visible barrel/front now points forward toward the sightline instead of the stock/kolbe reading as the front.
- `before_close_combat.png` shows `Weapon: Assault Rifle`, `Ammo: 30 / 90`, hit feedback, and dummy damage in the close-combat verification view; the rifle points toward the dummy with the player-side end staying at the lower-right camera edge.
- No regenerated current-flow P10A screenshot uses shotgun as the primary/default weapon.

Important: older P10A rows or screenshots named `after_shotgun.png` are historical evidence from the previous full-duration P10A pass. They must not be used as current default/primary proof after this replacement.

## User-Reopened Map Closure Fix

Date: 2026-05-25

Status: `fixed-and-rerun`

The user reopened the map visual gate because the arena did not read as closed or coherent, and dark void-like areas were visible around the edge of the playspace. This invalidates any older visual-polish pass that accepted open black edge gaps as final map composition.

Fixes applied:

- `scripts/maps/arena_downtown_01_blockout.gd` now creates a dedicated `PerimeterClosure` layer with visible north/south/east/west collision walls, facade bands, top trim, route/safety lines, corner barriers, and lit window strips.
- `scripts/maps/art/arena_downtown_01_art.gd` adds stronger yard fill and edge lights for spawns, high route, and north/south perimeter areas.
- `scenes/game/game_root.tscn` increases ambient and horizon brightness so playable routes no longer fall into black void-like edge darkness.
- `scripts/game/game_root.gd` now requires the map closure report in offline art smoke, so the arena cannot pass smoke if the perimeter closure layer is missing or incomplete.

Commands rerun:

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ ./run.sh -- --verification-capture=p04
VERIFICATION_CAPTURE_PASS p04
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

Visual observations from the regenerated P04/P10A screenshots:

- Blue and orange spawn views now show continuous perimeter walls with trim and light bands instead of open dark edge gaps.
- Mid-map and high-route views now read as one enclosed yard: all four arena edges have visible wall/facade closure behind the buildings and route geometry.
- The extra fill lights reduce the harsh dark pockets around the crane, high route, and side lanes while keeping the nighttime industrial mood.

Note: `./run.sh -- --verification-capture=p10a-after --p10a-duration-sec=1` was used only to refresh visual screenshots for inspection. It is not counted as pass evidence because the P10A validator intentionally still requires the full 900 second duration for an official P10A pass.

## User-Reopened Input And Shotgun Fix

Date: 2026-05-25

Status: `fixed-and-rerun`

The user reopened the visual/input gate because mouse aim did not respond and the shotgun still read as reversed, with the stock/kolbe facing forward. This invalidates any older shotgun visual pass that did not show the corrected orientation clearly.

Fixes applied:

- `scripts/player/player_controller.gd` now handles mouse look in `_input`, not only `_unhandled_input`, and left-click recaptures the mouse when the game has lost pointer capture.
- The runtime movement smoke now tests click-to-capture and mouse-look through the public `_input` path, so the aim path cannot pass only by calling the internal helper directly.
- `scenes/weapons/viewmodels/shotgun_viewmodel.tscn` rotates the shotgun viewmodel 180 degrees from the previously observed reversed orientation.
- `scripts/weapons/gltf_viewmodel_loader.gd` applies a clearer named material palette so the shotgun barrel/receiver/stock read as separate surfaces instead of one dark blob.

Commands rerun:

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ ./run.sh -- --verification-capture=p05a
VERIFICATION_CAPTURE_PASS p05a
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

Visual observations from `docs/verification/screenshots/weapon_visual_qa/shotgun.png`:

- The shotgun is visible in the lower-right/lower-center first-person viewmodel area and no longer hidden by muzzle flash.
- The barrel/receiver/stock surfaces are visually separated by the material palette instead of reading as an untextured black/grey import.
- The viewmodel has been rotated from the previously rejected reversed wrapper orientation; this screenshot is the current evidence for the corrected shotgun direction.

## P05A Visual QA Revalidation

Date: 2026-05-25

Status: `done`

The previous `P05A Weapon Visual QA Sweep` result was rejected because the shotgun screenshots did not clearly prove correct first-person orientation. P05A was rerun on 2026-05-25 with clean no-fire viewmodel screenshots, separate firing-feedback screenshots for rifle/handgun/shotgun, and explicit visual inspection of the regenerated images.

At the time of this revalidation, the next required phase from `docs/fps-development-plan.md` was `P10A: Computer-Use Visual Game Polish Pass`.

## P10A Computer-Use Visual Game Polish Pass

Date: 2026-05-25

Status: `done`

Purpose: perform a real GUI visual polish pass over the current vertical slice, fix the highest-impact first-walkthrough visual issues, and prove the accepted after-series with offline and multiplayer play duration.

### Commands And Results

```text
$ ./run.sh -- --verification-capture=p10a-before
VERIFICATION_CAPTURE_PASS p10a-before
duration_sec=15.151
screenshots=11
EXIT=0
```

```text
$ ./run.sh -- --verification-capture=p10a-after
VERIFICATION_CAPTURE_PASS p10a-after
duration_sec=900.036
screenshot_count=11
traversal_routes_completed=2
weapons={assault_rifle=true, handgun=true, knife=true, smoke_bomb=true}
death_respawn=true
EXIT=0
```

```text
$ ./run.sh -- --verification-capture=p10a-host --p10a-port=24932 --p10a-timeout-sec=45
VERIFICATION_CAPTURE_PASS p10a-host
duration_sec=300.516
host_can_see_remote_humanoid=true
fallback_remote_count=0
remote_screenshot=res://docs/verification/screenshots/p10a_visual_polish/after_remote_player.png
EXIT=0
```

```text
$ ./run.sh -- --verification-capture=p10a-client --p10a-host=127.0.0.1 --p10a-port=24932 --p10a-timeout-sec=45
VERIFICATION_CAPTURE_PASS p10a-client
duration_sec=310.357
EXIT=0
```

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

### First Walkthrough Punchlist

| Finding | Status | Fix |
| --- | --- | --- |
| Lobby was a clipped plain default panel with no game identity. | `fixed` | Rebuilt lobby into a full-screen styled Downtown loadout screen with briefing panel and unclipped buttons. |
| HUD text floated directly over bright scene geometry and became unreadable. | `fixed` | Added translucent bordered readout panels for debug, match, perf, and combat data. |
| Crosshair was a default white plus with weak combat readability. | `fixed` | Replaced it with a split high-contrast reticle with team/accent color. |
| Blue/orange spawn views still read as flat blockout boxes. | `fixed` | Added spawn decks, route decals, container trim, and team-colored visual lines. |
| Orange spawn screenshot was dominated by a crane mast in the center sightline. | `fixed` | Adjusted the accepted orange-spawn capture to a clearer orange spawn angle and added orange spawn trim. |
| High route looked like incidental grey platforms rather than intentional traversal. | `fixed` | Added high-route edge strips, bridge hazard strips, and route labels. |
| Smoke FX was a hard opaque sphere that blocked the view like a debug primitive. | `fixed` | Rebuilt smoke as transparent overlapping puffs with softer alpha. |
| Muzzle flash in close combat was oversized and obscured the dummy/weapon read. | `fixed` | Reduced verification muzzle flash scale, energy, and opacity. |
| HUD-under-combat capture was mostly a blue block face and did not show combat context. | `fixed` | Moved the P10A combat HUD capture to an open mid-lane dummy encounter. |
| Handgun capture could be overwritten by a pending local respawn and show the wrong weapon. | `fixed` | Cleared pending local respawn state on immediate respawn and made handgun capture validate the secondary slot. |
| Remote player capture could frame orange cover instead of the remote player. | `fixed` | Added a deterministic P10A remote-player lineup capture. |
| Remote team plates were too boxy at capture scale. | `fixed` | Reduced chest/back/shoulder team marker sizes while preserving team readability. |

### Before And After Evidence

| Problem | Before | After |
| --- | --- | --- |
| Lobby clipping/default styling | `docs/verification/screenshots/p10a_visual_polish/before_lobby.png` | `docs/verification/screenshots/p10a_visual_polish/after_lobby.png` |
| Orange spawn obstruction/readability | `docs/verification/screenshots/p10a_visual_polish/before_orange_spawn.png` | `docs/verification/screenshots/p10a_visual_polish/after_orange_spawn.png` |
| Smoke as opaque debug sphere | `docs/verification/screenshots/p10a_visual_polish/before_smoke_combat_fx.png` | `docs/verification/screenshots/p10a_visual_polish/after_smoke_combat_fx.png` |
| HUD readability in combat | `docs/verification/screenshots/p10a_visual_polish/before_hud_under_combat.png` | `docs/verification/screenshots/p10a_visual_polish/after_hud_under_combat.png` |
| Combat flash/readability | `docs/verification/screenshots/p10a_visual_polish/before_close_combat.png` | `docs/verification/screenshots/p10a_visual_polish/after_close_combat.png` |

### Accepted After Screenshots

All accepted images below were opened and visually assessed after capture.

Current replacement note: this table records the original full-duration P10A pass. For the current primary/default weapon flow, use the `User-Replaced Shotgun With Assault Rifle` evidence above; shotgun is no longer valid proof for default primary.

| Screenshot | Visual assessment |
| --- | --- |
| `after_lobby.png` | Full-screen lobby no longer clips; primary actions and loadout fields are readable; briefing panel gives the screen game identity. |
| `after_blue_spawn.png` | Blue spawn has readable HUD panels, visible route/trim accents, and a correctly oriented rifle viewmodel. |
| `after_orange_spawn.png` | Orange spawn no longer has the crane mast blocking the center; orange ramp/cover trim and spawn deck communicate team space. |
| `after_mid_map.png` | Downtown assets, central route markings, and team lanes are visible; the view is no longer just undifferentiated greybox. |
| `after_high_route.png` | High route has edge strips and readable intent; camera is clear of walls; weapon remains visible. |
| `after_close_combat.png` | Historical P10A pass: dummy, hit feedback, and shotgun are readable; current close-combat replacement uses assault rifle as documented above. |
| `after_smoke_combat_fx.png` | Smoke is a layered transparent volume, not a hard opaque ball; HUD and reticle remain readable through/around it. |
| `after_assault_rifle.png` | Rifle viewmodel has correct orientation and scale; HUD confirms assault rifle; map context remains visible. |
| `after_shotgun.png` | Historical extended-weapon visual proof only; this screenshot is no longer valid default/primary evidence. |
| `after_handgun.png` | Handgun viewmodel and HUD both show the secondary handgun; the previous respawn/weapon overwrite issue is gone. |
| `after_remote_player.png` | Remote player is a visible Modular Men humanoid with orange team markers, not a capsule/box-only placeholder. |
| `after_hud_under_combat.png` | Combat HUD is readable in a live hit-confirm scene; hit feedback, score/timer, perf, and ammo panels do not overlap. |

### P10A Result

P10A exit criteria are satisfied:

- Offline GUI playtest duration was `900.036` seconds.
- Multiplayer GUI playtest duration was `300.516` seconds on host and `310.357` seconds on client.
- 23 P10A screenshots exist under `docs/verification/screenshots/p10a_visual_polish/`, including before images and the 12 accepted after screenshots.
- The original required coverage existed for lobby, blue spawn, orange spawn, mid-map, high route, close combat, smoke/combat FX, assault rifle, shotgun, handgun, remote player, and HUD under combat. Current default/primary coverage replaces shotgun with `primary_assault_rifle` as documented at the top of this file.
- 12 first-walkthrough punchlist items were recorded and fixed in this phase.
- Before/after evidence is documented for 5 fixed visual problems.
- No accepted after screenshot shows a reversed shotgun, camera inside wall, invisible weapon, empty spawn, mostly greybox main impression, unreadable HUD, or remote player as only a capsule/box.
- `python3 tools/validate_static.py` passes after the fixes.

Next required phase from `docs/fps-development-plan.md`: first non-`done` phase in the single development plan.

## P01 Baseline Runtime Audit

Status: `done`

Purpose: establish the actual current state from a running Godot build before continuing later visual/playability phases.

### Commands And Results

```text
$ git status --short
 M AGENTS.md
 D removed legacy agent-phase document
 M docs/fps-development-plan.md
 M docs/fps-technical-spec.md
 M run.sh
?? .gitignore
?? data/
?? docs/verification/
?? project.godot
?? scenes/
?? scripts/
?? tools/
```

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ ./run.sh --version
4.6.3.stable.official.7d41c59c4
EXIT=0
```

```text
$ ./run.sh -- --verification-capture=p01
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p01
VERIFICATION_CAPTURE_PASS p01
EXIT=0
```

### Screenshots

- `docs/verification/screenshots/p01_lobby_baseline.png`
- `docs/verification/screenshots/p01_spawn_baseline.png`

Both screenshots were generated from the running game viewport through `./run.sh -- --verification-capture=p01`, not from the editor.

### Concrete Gaps

1. Visual/assets: the lobby is a plain dark Godot UI panel with default controls and no visual identity, background art, title treatment beyond text, or industrial FPS branding.
2. Visual/assets: the first spawn screenshot shows only primitive grey/blue blockout geometry; no Downtown City MegaKit environment art is visible from the initial view.
3. Visual/assets: the first-person weapon presentation is not visible as a real rifle model in the baseline spawn shot; the player relies on HUD text rather than a readable viewmodel.
4. Visual/assets: lighting and shadows at first spawn are harsh and flatten readability; large dark walls dominate the screen and make the scene read as prototype geometry.
5. Gameplay/playability: first spawn faces close blockout geometry and does not immediately communicate a route, landmark, enemy lane, or objective direction.
6. Gameplay/playability: no combat dummy or traversal target is visible from the first spawn, so the first action is unclear without prior map knowledge.
7. Gameplay/playability: the lobby has no visible controls/help summary for movement, fire, reload, slot switching, or pause, which makes first-time testing less self-guided.
8. UI/readability: the bottom combat HUD is close to the screen edge and can clip longer values or status text at 1280x720; it needs safer margins before visual QA.
9. Performance/readability: the captured spawn frame reports `FPS: 1`, likely because the screenshot was taken during startup, but P01 cannot prove stable runtime FPS yet; later phases need longer playtest/perf evidence.

### P01 Result

P01 exit criteria are satisfied:

- Godot version is registered.
- Static validation exit code is registered.
- `./run.sh` startup result is registered from a GUI/Metal run.
- Both required baseline screenshots exist.
- More than 8 concrete gaps are listed, including at least 3 visual/assets gaps and at least 2 gameplay/playability gaps.

## P02 Verification Harness Must Exit Cleanly

Status: `done`

Purpose: prove the short automated smoke suites cannot spoof success by printing `SMOKE_PASS` and then timing out or exiting nonzero.

### Commands And Results

```text
$ python3 tools/runtime_smoke.py offline
===== offline exit=0 =====
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

SMOKE_START offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed

EXIT=0
```

```text
$ python3 tools/runtime_smoke.py weapons
===== weapons exit=0 =====
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org

SMOKE_START weapons
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors

EXIT=0
```

### P02 Result

P02 exit criteria are satisfied:

- `python3 tools/runtime_smoke.py offline` exits with code `0`.
- `python3 tools/runtime_smoke.py weapons` exits with code `0`.
- Neither command timed out.
- Every observed `SMOKE_PASS` is paired with process exit code `0`.

## P03 Environment Asset Import Proof

Status: `done`

Purpose: prove that Downtown City MegaKit assets from the approved `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)` mirror are visible in the running game viewport.

### Commands And Results

```text
$ ./run.sh -- --verification-capture=p03
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p03
VERIFICATION_CAPTURE_ASSET .../Building_Large_2.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Building_Large_2
VERIFICATION_CAPTURE_ASSET .../Building_Small_1.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Building_Small_1
VERIFICATION_CAPTURE_ASSET .../Street_4Lane.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Street_4Lane
VERIFICATION_CAPTURE_ASSET .../Street_2Lane.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Street_2Lane
VERIFICATION_CAPTURE_ASSET .../Sidewalk_Straight_3m.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Sidewalk_Straight_3m
VERIFICATION_CAPTURE_ASSET .../Stairs_Rails_Metal.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Stairs_Rails_Metal
VERIFICATION_CAPTURE_ASSET .../Prop_ACUnit.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Prop_ACUnit
VERIFICATION_CAPTURE_ASSET .../Prop_Bollard.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Prop_Bollard
VERIFICATION_CAPTURE_ASSET .../Prop_ManholeCover.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Prop_ManholeCover
VERIFICATION_CAPTURE_ASSET .../Prop_Planter_Single.gltf /root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/P03_Prop_Planter_Single
VERIFICATION_CAPTURE_PASS p03
EXIT=0
```

```text
$ bash -c '! rg -n "assets/source_packs/quaternius|res://assets/source_packs" scripts scenes data project.godot'
<no output>
EXIT=0
```

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py offline
===== offline exit=0 =====
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

SMOKE_START offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

### Asset Manifest

All entries are instantiated under `/root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/P03DowntownAssetProof/` in the running game scene.

| Source file | Runtime node |
| --- | --- |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Building_Large_2.gltf` | `P03_Building_Large_2` |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Building_Small_1.gltf` | `P03_Building_Small_1` |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Street_4Lane.gltf` | `P03_Street_4Lane` |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Street_2Lane.gltf` | `P03_Street_2Lane` |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Sidewalk_Straight_3m.gltf` | `P03_Sidewalk_Straight_3m` |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Stairs_Rails_Metal.gltf` | `P03_Stairs_Rails_Metal` |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Prop_ACUnit.gltf` | `P03_Prop_ACUnit` |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Prop_Bollard.gltf` | `P03_Prop_Bollard` |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Prop_ManholeCover.gltf` | `P03_Prop_ManholeCover` |
| `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Prop_Planter_Single.gltf` | `P03_Prop_Planter_Single` |

### Screenshot

- `docs/verification/screenshots/p03_environment_asset_proof.png`

The screenshot was generated by the running game viewport through `./run.sh -- --verification-capture=p03`, not from the editor. Visual inspection confirms more than 5 Downtown City MegaKit assets are visible simultaneously, including building, street, sidewalk, stair/rail, and prop assets.

### P03 Result

P03 exit criteria are satisfied:

- 10 different Downtown City MegaKit asset files are instantiated visibly in the running game proof area.
- Each of the 10 assets is listed with source file and runtime node.
- The required screenshot exists and shows at least 5 of the assets at the same time.
- Runtime references use `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)` and no code/scene/data/project dependency on `assets/source_packs/quaternius/` was found.

## P04 Arena Dressing Pass 1

Status: `done`

Purpose: dress `arena_downtown_01` with visible Downtown City MegaKit art while preserving the blockout as the gameplay collision layer.

### Commands And Results

```text
$ ./run.sh -- --verification-capture=p04
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p04
VERIFICATION_CAPTURE_REPORT_P04 instances=24 landmarks=4 playable_support=20 traversal_routes=2 enabled_art_collision_objects=0 routes=["blue_wallrun_to_high", "orange_wallrun_to_high"]
VERIFICATION_CAPTURE_PASS p04
EXIT=0
```

```text
$ bash -c '! rg -n "assets/source_packs/quaternius|res://assets/source_packs" scripts scenes data project.godot'
<no output>
EXIT=0
```

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py offline
===== offline exit=0 =====
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

SMOKE_START offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py weapons
===== weapons exit=0 =====
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org

SMOKE_START weapons
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors
EXIT=0
```

### Runtime Dressing Summary

The P04 capture command generated the runtime report from `/root/AppRoot/GameRoot/MapRoot/ArenaDowntown01Art/DowntownCityMegaKitDressing/`.

| Metric | Runtime value | Required |
| --- | ---: | ---: |
| Visible Downtown dressing instances | 24 | 20 |
| Large building/facade/skyline landmarks | 4 | 4 |
| Street/sidewalk/stairs/railing/trim/prop supports in or near playable space | 20 | 8 |
| Art-supported traversal routes | 2 | 2 |
| Enabled collision objects in dressing art | 0 | 0 |

P04 dressing art is visual-only; blockout collision remains authoritative for movement. The hidden blockout skyline meshes keep their boundary collision but no longer dominate the visible art layer.

### P04 Asset Manifest

| Runtime node | Source file | Tags |
| --- | --- | --- |
| `P04_NorthWestTower` | `Building_Large_2.gltf` | `landmark` |
| `P04_NorthEastBrickBlock` | `Building_Small_1.gltf` | `landmark` |
| `P04_SouthWestFacade` | `Building_Medium_2_001.gltf` | `landmark` |
| `P04_SouthEastTower` | `Building_Large_2.gltf` | `landmark` |
| `P04_NorthStreetLane` | `Street_4Lane.gltf` | `playable_space` |
| `P04_SouthStreetLane` | `Street_2Lane.gltf` | `playable_space` |
| `P04_MidIntersection` | `Street_4WayIntersection.gltf` | `playable_space` |
| `P04_MidAsphaltPatch` | `Street_Asphalt_9x9.gltf` | `playable_space` |
| `P04_BlueSpawnSidewalk` | `Sidewalk_Straight_3m.gltf` | `playable_space` |
| `P04_BlueSpawnCorner` | `Sidewalk_Corner_Flat_3m.gltf` | `playable_space` |
| `P04_OrangeSpawnSidewalk` | `Sidewalk_Straight_3m_Stripe.gltf` | `playable_space` |
| `P04_OrangeSpawnCorner` | `Sidewalk_Corner_Round_3m.gltf` | `playable_space` |
| `P04_BlueRampStairs` | `Stairs_Rails_Metal.gltf` | `playable_space`, `traversal`, `blue_wallrun_to_high` |
| `P04_OrangeRampStairs` | `Stairs_Rails_Metal_Straight_2.gltf` | `playable_space`, `traversal`, `orange_wallrun_to_high` |
| `P04_BlueHighRailTrim` | `Trim_Wall_Guard.gltf` | `playable_space`, `traversal`, `blue_wallrun_to_high` |
| `P04_OrangeHighRailTrim` | `Trim_Wall_Guard.gltf` | `playable_space`, `traversal`, `orange_wallrun_to_high` |
| `P04_BlueCatwalkAC` | `Prop_ACUnit.gltf` | `playable_space`, `traversal`, `blue_wallrun_to_high` |
| `P04_OrangeCatwalkPlanter` | `Prop_Planter_Single.gltf` | `playable_space`, `traversal`, `orange_wallrun_to_high` |
| `P04_BlueSpawnBollardA` | `Prop_Bollard.gltf` | `playable_space` |
| `P04_BlueSpawnBollardB` | `Prop_Bollard.gltf` | `playable_space` |
| `P04_OrangeSpawnBollardA` | `Prop_Bollard.gltf` | `playable_space` |
| `P04_OrangeSpawnBollardB` | `Prop_Bollard.gltf` | `playable_space` |
| `P04_MidManhole` | `Prop_ManholeCover.gltf` | `playable_space` |
| `P04_MidDrain` | `Prop_Drain.gltf` | `playable_space` |

### Screenshots

- `docs/verification/screenshots/p04_blue_spawn.png`
- `docs/verification/screenshots/p04_orange_spawn.png`
- `docs/verification/screenshots/p04_mid_map.png`
- `docs/verification/screenshots/p04_traversal_route.png`

All four screenshots were generated from the running game viewport through `./run.sh -- --verification-capture=p04`, not from the editor. Visual inspection confirms Blue spawn, Orange spawn, mid-map, and the high traversal route now show real Downtown environment art without requiring a 180-degree turn.

### P04 Result

P04 exit criteria are satisfied:

- 24 visible Downtown City MegaKit dressing instances exist in normal gameplay.
- 4 large building/facade/skyline landmarks are visible.
- 20 street/sidewalk/stairs/railing/trim/prop support instances are placed in or directly near playable space.
- Spawn screenshots show real environment art immediately in front of the player.
- 2 traversal routes are visually supported by stairs/rail/prop dressing and remain physically unblocked because the dressing art has zero enabled collision objects.
- Offline smoke still passes after the dressing change.

## P05 Weapon Viewmodel Pass

Status: `done`

Purpose: replace the most visible first-person weapon placeholder boxes with real rifle and handgun models.

### Asset Curation Evidence

The required Animated Guns FBX files are kept as source provenance and converted into curated runtime GLBs outside the vendor mirror.

```text
$ /tmp/fbx2gltf-godot/FBX2glTF-macos-x86_64/FBX2glTF-macos-x86_64 -b -i assets/third_party/quaternius/animated_guns_pack/FBX/Rifle.fbx -o assets/weapons/viewmodels/generated/rifle_from_fbx
Wrote 211185 bytes of binary glTF to assets/weapons/viewmodels/generated/rifle_from_fbx.glb.
EXIT=0
```

```text
$ /tmp/fbx2gltf-godot/FBX2glTF-macos-x86_64/FBX2glTF-macos-x86_64 -b -i assets/third_party/quaternius/animated_guns_pack/FBX/Pistol.fbx -o assets/weapons/viewmodels/generated/pistol_from_fbx
Wrote 155953 bytes of binary glTF to assets/weapons/viewmodels/generated/pistol_from_fbx.glb.
EXIT=0
```

### Runtime Capture Evidence

```text
$ ./run.sh -- --verification-capture=p05
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p05
VERIFICATION_CAPTURE_VIEWMODEL_P05 rifle { "has_view_model": true, "node_name": &"AssetViewModel_assault_rifle", "is_fallback": false, "summary": { "source_fbx_path": "res://assets/third_party/quaternius/animated_guns_pack/FBX/Rifle.fbx", "generated_glb_path": "res://assets/weapons/viewmodels/generated/rifle_from_fbx.glb", "has_mesh": true, "vertex_count": 3661 } }
VERIFICATION_CAPTURE_VIEWMODEL_P05 handgun { "has_view_model": true, "node_name": &"AssetViewModel_handgun", "is_fallback": false, "summary": { "source_fbx_path": "res://assets/third_party/quaternius/animated_guns_pack/FBX/Pistol.fbx", "generated_glb_path": "res://assets/weapons/viewmodels/generated/pistol_from_fbx.glb", "has_mesh": true, "vertex_count": 2717 } }
VERIFICATION_CAPTURE_PASS p05
EXIT=0
```

### Regression Checks

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py offline
===== offline exit=0 =====
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

SMOKE_START offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py weapons
===== weapons exit=0 =====
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org

SMOKE_START weapons
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors
EXIT=0
```

```text
$ bash -c '! rg -n "assets/source_packs/quaternius|res://assets/source_packs" scripts scenes data project.godot'
<no output>
EXIT=0
```

### Screenshots Generated

- `docs/verification/screenshots/p05_rifle_viewmodel.png`
- `docs/verification/screenshots/p05_handgun_viewmodel.png`

Visual inspection confirms:

- assault rifle and handgun are no longer fallback boxes
- switching from primary to secondary changes the visible model
- the rifle screenshot shows a visible muzzle flash plus actual hit feedback (`HIT 12`) from firing at a combat dummy
- neither model is invisible, extremely large, or turned away from the first-person camera

### Wrapper Paths

| Weapon | Wrapper scene | Required FBX source path | Generated runtime GLB |
| --- | --- | --- | --- |
| Assault rifle | `scenes/weapons/viewmodels/rifle_viewmodel.tscn` | `assets/third_party/quaternius/animated_guns_pack/FBX/Rifle.fbx` | `assets/weapons/viewmodels/generated/rifle_from_fbx.glb` |
| Handgun | `scenes/weapons/viewmodels/handgun_viewmodel.tscn` | `assets/third_party/quaternius/animated_guns_pack/FBX/Pistol.fbx` | `assets/weapons/viewmodels/generated/pistol_from_fbx.glb` |

### P05 Result

P05 exit criteria are satisfied:

- Assault rifle and handgun show visible first-person models from wrapper scenes.
- Switching primary to secondary changes the visible model.
- Runtime summaries prove both active viewmodels are non-fallback nodes with mesh vertices.
- The required screenshots exist under `docs/verification/screenshots/`.
- Rifle firing feedback is visible through muzzle flash, impact spark, and `HIT 12` HUD feedback.

## P05A Weapon Visual QA Sweep

Status: `done`

Purpose: revalidate every selectable/default weapon in a running Offline Dev Match after the shotgun visual rejection, with clean first-person orientation screenshots and separate firing-feedback evidence.

### Commands And Results

```text
$ /tmp/fbx2gltf-godot/FBX2glTF-macos-x86_64/FBX2glTF-macos-x86_64 -b -i assets/third_party/quaternius/animated_guns_pack/FBX/Shotgun.fbx -o assets/weapons/viewmodels/generated/shotgun_from_fbx
Animation ShotgunArmature|FireWBullet: [0 - 21]
Animation ShotgunArmature|FireWOBullet: [0 - 12]
Animation ShotgunArmature|Reload: [0 - 7]
Wrote 118977 bytes of binary glTF to assets/weapons/viewmodels/generated/shotgun_from_fbx.glb.
EXIT=0
```

```text
$ /tmp/fbx2gltf-godot/FBX2glTF-macos-x86_64/FBX2glTF-macos-x86_64 -b -i assets/third_party/quaternius/animated_guns_pack/FBX/SniperRifle.fbx -o assets/weapons/viewmodels/generated/sniper_from_fbx
Animation SniperRifle |FireWBullet: [0 - 23]
Animation SniperRifle |FireWOBullet: [0 - 11]
Animation SniperRifle |Reload: [0 - 27]
Wrote 190665 bytes of binary glTF to assets/weapons/viewmodels/generated/sniper_from_fbx.glb.
EXIT=0
```

```text
$ ./run.sh -- --verification-capture=p05a
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p05a
VERIFICATION_CAPTURE_VIEWMODEL_P05A assault_rifle ... "has_mesh": true, "vertex_count": 3661, "material_override": true ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A handgun ... "has_mesh": true, "vertex_count": 2717, "material_override": true ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A shotgun ... "has_mesh": true, "vertex_count": 1987, "material_override": true ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A sniper ... "has_mesh": true, "vertex_count": 3286, "material_override": true ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A knife ... "placeholder_type": "deliberate_v1" ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A smoke_bomb ... "placeholder_type": "deliberate_v1" ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A grenade ... "placeholder_type": "deliberate_v1" ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A flamethrower ... "placeholder_type": "deliberate_v1" ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A lasso ... "placeholder_type": "deliberate_v1" ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A redbull ... "placeholder_type": "deliberate_v1" ...
VERIFICATION_CAPTURE_VIEWMODEL_P05A portal_gun ... "placeholder_type": "deliberate_v1" ...
VERIFICATION_CAPTURE_REPORT_P05A { "ok": true, "weapon_count": 11, ... }
VERIFICATION_CAPTURE_PASS p05a
EXIT=0
```

The capture first saves clean `weapon.png` screenshots without muzzle flash, then fires every weapon to prove activation. Rifle, handgun and shotgun additionally save `*_feedback.png` screenshots to prove visible hit/muzzle feedback. No Godot `SCRIPT ERROR` or `ERROR` lines were observed in the final P05A capture run.

### Screenshot Manifest

All screenshots were generated from the running game viewport by `./run.sh -- --verification-capture=p05a`, not from the editor.

| Weapon | Clean orientation screenshot |
| --- | --- |
| Assault rifle | `docs/verification/screenshots/weapon_visual_qa/assault_rifle.png` |
| Handgun | `docs/verification/screenshots/weapon_visual_qa/handgun.png` |
| Shotgun | `docs/verification/screenshots/weapon_visual_qa/shotgun.png` |
| Sniper | `docs/verification/screenshots/weapon_visual_qa/sniper.png` |
| Knife | `docs/verification/screenshots/weapon_visual_qa/knife.png` |
| Smoke bomb | `docs/verification/screenshots/weapon_visual_qa/smoke_bomb.png` |
| Grenade | `docs/verification/screenshots/weapon_visual_qa/grenade.png` |
| Flame thrower | `docs/verification/screenshots/weapon_visual_qa/flamethrower.png` |
| Lasso | `docs/verification/screenshots/weapon_visual_qa/lasso.png` |
| Redbull | `docs/verification/screenshots/weapon_visual_qa/redbull.png` |
| Portal gun | `docs/verification/screenshots/weapon_visual_qa/portal_gun.png` |

Additional firing-feedback screenshots:

- `docs/verification/screenshots/weapon_visual_qa/assault_rifle_feedback.png`
- `docs/verification/screenshots/weapon_visual_qa/handgun_feedback.png`
- `docs/verification/screenshots/weapon_visual_qa/shotgun_feedback.png`

Shotgun before/after comparison:

- `docs/verification/screenshots/weapon_visual_qa/shotgun_before_after.png`

The comparison image uses the rejected flash-obscured shotgun screenshot on the left and the accepted clean shotgun screenshot on the right.

### Visual QA Table

| Weapon | Source/wrapper | Orientation | Material/texture | Scale/position | Visual observations |
| --- | --- | --- | --- | --- | --- |
| Assault rifle | `scenes/weapons/viewmodels/rifle_viewmodel.tscn`, `Rifle.fbx`, `rifle_from_fbx.glb` | pass | pass, project material override | pass | Clean screenshot shows muzzle/barrel running forward from lower-right toward crosshair; dark-blue material is visible; placement avoids HUD and center reticle. Feedback screenshot shows muzzle flash and `HIT 10`. |
| Handgun | `scenes/weapons/viewmodels/handgun_viewmodel.tscn`, `Pistol.fbx`, `pistol_from_fbx.glb` | pass | pass, project material override | pass | Pistol profile reads clearly with muzzle left/forward and grip toward player; material is dark with small orange detail; lower-right placement is clear of HUD. Feedback screenshot shows muzzle flash and `HIT 16`. |
| Shotgun | `scenes/weapons/viewmodels/shotgun_viewmodel.tscn`, `Shotgun.fbx`, `shotgun_from_fbx.glb` | pass | pass, project material override | pass | Clean screenshot is no longer flash-obscured: barrel/muzzle points forward away from camera, receiver/stock sit toward lower-right/player side, and scale is small enough to show the relevant form. Feedback screenshot shows shotgun muzzle flash and `HIT 5`. |
| Sniper | `scenes/weapons/viewmodels/sniper_viewmodel.tscn`, `SniperRifle.fbx`, `sniper_from_fbx.glb` | pass | pass, project material override | pass | Long barrel points forward, scope sits on top, material override is visible, and the model stays below the crosshair/HUD. |
| Knife | `scenes/weapons/viewmodels/knife_viewmodel.tscn` | pass | pass, deliberate v1 placeholder | pass | Knife placeholder has a visible blade, guard and grip; it is angled like a held melee weapon and does not use the generic fallback box. |
| Smoke bomb | `scenes/weapons/viewmodels/smoke_bomb_viewmodel.tscn` | pass | pass, deliberate v1 placeholder | pass | Spherical smoke-bomb silhouette is visible with dark material and fuse accent; placement is lower-right and readable. |
| Grenade | `scenes/weapons/viewmodels/grenade_viewmodel.tscn` | pass | pass, deliberate v1 placeholder | pass | Green spherical grenade placeholder is visually distinct from smoke bomb and uses a readable lower-right placement. |
| Flame thrower | `scenes/weapons/viewmodels/flamethrower_viewmodel.tscn` | pass | pass, deliberate v1 placeholder | pass | Box/tank/nozzle silhouette reads as a deliberate flamethrower placeholder; yellow side tank and dark body distinguish front and body. |
| Lasso | `scenes/weapons/viewmodels/lasso_viewmodel.tscn` | pass | pass, deliberate v1 placeholder | pass | Circular coil silhouette is visible and distinct; grip and coil sit in a plausible hand-held area. |
| Redbull | `scenes/weapons/viewmodels/redbull_viewmodel.tscn` | pass | pass, deliberate v1 placeholder | pass | Blue can placeholder is upright, legible as a buff item, and visually distinct from grenade/smoke placeholders. |
| Portal gun | `scenes/weapons/viewmodels/portal_gun_viewmodel.tscn` | pass | pass, deliberate v1 placeholder | pass | Portal-gun placeholder has a blocky emitter silhouette with color accent, sits lower-right, and is not a fallback box. |

### P05A Result

P05A exit criteria are satisfied:

- All 11 selectable weapons are activated in a running Offline Dev Match without crash.
- Rifle, handgun, shotgun and sniper use asset-backed GLB viewmodels and are not fallback boxes.
- Shotgun orientation, scale and material override pass visual inspection in a clean no-fire screenshot; firing feedback is documented separately.
- Weapons without suitable local assets use deliberate project-owned v1 placeholder scenes, not the generic fallback box.
- Weapon switching replaces the visible model and clears transient FX/projectiles between screenshots.
- Rifle, handgun and shotgun all have separate visible muzzle/hit feedback screenshots.
- No Godot `SCRIPT ERROR` or `ERROR` lines were observed during the final GUI capture.

## P06 Remote Humanoid Player Pass

Status: `done`

Purpose: replace capsule/box-only remote player representation with humanoid meshes that are readable in multiplayer.

### Runtime Capture Evidence

The required screenshot was generated from a visible host game viewport while a headless ENet client joined and drove a deterministic remote position for capture.

```text
$ ./run.sh -- --host --port=24706 --verification-capture=p06
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p06
VERIFICATION_CAPTURE_REMOTE_P06 { "ok": true, "remote_proxy_count": 1, "network_player_count": 2, "humanoid_remote_count": 1, "fallback_remote_count": 0, "synced_remote_count": 1, "team_ids": [2], "team_readability_method": "blue/orange emissive chest, back, and shoulder plates attached to the humanoid proxy", "remotes": [{ "peer_id": 2113555129, "team_id": 2, "team_name": "orange", "source_asset_path": "res://assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF/Worker.gltf", "has_humanoid_mesh": true, "avatar_vertex_count": 10534, "uses_fallback_body": false, "snapshot_count": 31, "target_position": (0.0, 0.45, 0.0), "target_yaw": 3.14159274101257, "current_yaw": -3.14158415794373, "is_alive": true, "debug_label_visible": false }] }
VERIFICATION_CAPTURE_PASS p06
EXIT=0
```

```text
$ ./run.sh --headless -- --join=127.0.0.1 --port=24706 --smoke-test=network-game --smoke-timeout-sec=20 --p06-driver-pose
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org

SMOKE_START network-game
SMOKE_PASS network-game: network client connected and game scene ready
EXIT=0
```

Additional client-view capture proves the blue team treatment loads the `Swat.gltf` humanoid path with blue team plates:

```text
$ ./run.sh -- --join=127.0.0.1 --port=24707 --verification-capture=p06
VERIFICATION_CAPTURE_REMOTE_P06 ... "team_id": 1, "team_name": "blue", "source_asset_path": "res://assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF/Swat.gltf", "has_humanoid_mesh": true, "uses_fallback_body": false, "debug_label_visible": false ...
VERIFICATION_CAPTURE_PASS p06
EXIT=0
```

### Regression Checks

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py network --base-port 24720
===== network-host exit=0 =====
SMOKE_PASS network-game: network host has 1 expected peer(s)

===== network-client-1 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py weapons
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors
EXIT=0
```

```text
$ bash -c '! rg -n "assets/source_packs/quaternius|res://assets/source_packs" scripts scenes data project.godot'
<no output>
EXIT=0
```

### Screenshots Generated

- `docs/verification/screenshots/p06_remote_humanoid.png`
- `docs/verification/screenshots/p06_remote_humanoid_client_blue.png`

Visual inspection confirms:

- `p06_remote_humanoid.png` shows an orange remote humanoid from the gameplay camera in a running host/client match.
- The remote proxy is no longer represented by only a capsule or box.
- Debug `Label3D` text is hidden on the remote proxy; team readability comes from orange/blue non-text geometry.
- Runtime summaries prove remote position and yaw snapshots were received (`snapshot_count > 0`, nonzero target/current yaw data).

### Asset And Team Manifest

| Team | Source file | Runtime treatment |
| --- | --- | --- |
| Blue | `assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF/Swat.gltf` | blue emissive chest, back, and shoulder plates |
| Orange | `assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF/Worker.gltf` | orange emissive chest, back, and shoulder plates |

### P06 Result

P06 exit criteria are satisfied:

- Remote player proxy displays a Modular Men humanoid mesh in a running multiplayer match.
- Fallback capsule is hidden when the humanoid loads.
- Blue and orange remote team treatments are visually distinct without debug text.
- Position/yaw sync still works through the existing ENet snapshot path.
- The required gameplay-camera screenshot exists under `docs/verification/screenshots/`.

## P07 Offline Playability Pass

Status: `done`

Purpose: prove the dressed arena is playable as an offline FPS prototype for at least 10 minutes, including traversal, combat, HUD, reload interrupt, death and respawn.

### Runtime Playtest Evidence

The verification run used a real Godot GUI/game viewport through `./run.sh`. The deterministic P07 harness drove the required mechanics in an Offline Dev Match, captured the combat HUD while the match was still actively playing, then kept the same GUI session alive until the 600-second duration requirement was met.

```text
$ ./run.sh -- --verification-capture=p07
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p07
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=60.5 target_sec=600.0
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=120.3 target_sec=600.0
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=180.1 target_sec=600.0
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=241.0 target_sec=600.0
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=301.0 target_sec=600.0
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=360.0 target_sec=600.0
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=420.1 target_sec=600.0
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=480.1 target_sec=600.0
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=540.1 target_sec=600.0
VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=600.1 target_sec=600.0
VERIFICATION_PLAYTEST_REPORT_P07 { "ok": true, "arena": "arena_downtown_01_art", "traversal_routes_completed": 2, "dummy_hits": 3, "dummy_kills": 1, "reload_interrupt": true, "death_respawn": true, "duration_sec": 600.15, "started_at": "2026-05-24T19:14:54", "ended_at": "2026-05-24T19:24:54", "screenshot": "res://docs/verification/screenshots/p07_combat_hud.png" }
VERIFICATION_CAPTURE_PASS p07
EXIT=0
```

No Godot `SCRIPT ERROR` or `ERROR` lines were observed during the final P07 run.

### Screenshot

- `docs/verification/screenshots/p07_combat_hud.png`

Visual inspection confirms the screenshot is from active play, not the editor and not only the post-match results screen. It shows:

- match HUD: `PLAYING 07:55`, score `Blue 1 Orange 1 / 20`
- combat HUD: `HP: 100`, `Slot: primary`, `Weapon: Assault Rifle`, `Ammo: 30 / 60`, `Cooldown: 0.00`
- performance HUD: `FPS: 60`, `Nodes: 254`
- visible rifle viewmodel, dummy target, and `HIT 12` feedback

The runtime report also validates the artillery HUD state for charges: `Weapon: Smoke Bomb`, `Ammo: 3 charges`.

### Mechanics Tested

| Requirement | Result |
| --- | --- |
| 10 minute GUI playtest | pass, `duration_sec=600.15` from `2026-05-24T19:14:54` to `2026-05-24T19:24:54` |
| Dressed arena | pass, `arena_downtown_01_art` |
| Traversal routes | pass, `blue_wallrun_to_high` and `orange_wallrun_to_high` completed |
| Jump | pass |
| Slide | pass |
| Slide-jump | pass |
| Wallrun | pass |
| Wall-jump | pass |
| Assault rifle | pass |
| Handgun | pass |
| Knife | pass |
| Smoke bomb | pass, one smoke volume spawned |
| Reload interrupt by weapon switch | pass |
| Dummy hits | pass, `dummy_hits=3` |
| Dummy kill | pass, `dummy_kills=1` |
| Player death and respawn | pass |
| HUD health/ammo/charges/slot/cooldown/timer/score/FPS/node count | pass |
| Console errors | pass, no `SCRIPT ERROR` or `ERROR` observed |

### P07 Result

P07 exit criteria are satisfied:

- The GUI playtest ran for at least 10 minutes in a single uninterrupted `./run.sh` session.
- Movement, combat, HUD, reload interrupt and respawn were all exercised in the dressed arena.
- Required screenshot evidence exists under `docs/verification/screenshots/`.
- No Godot `SCRIPT ERROR` or `ERROR` lines were observed.

### Regression Checks After P07

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py weapons
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py network --base-port 24720
===== network-host exit=0 =====
SMOKE_PASS network-game: network host has 1 expected peer(s)

===== network-client-1 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready
EXIT=0
```

```text
$ git diff --check
<no output>
EXIT=0
```

```text
$ bash -c '! rg -n "assets/source_packs/quaternius|res://assets/source_packs" scripts scenes data project.godot'
<no output>
EXIT=0
```

## P08 Two-Instance Multiplayer Pass

Status: `done`

Purpose: prove a real two-player ENet session can be used through the visible lobby flow.

### Harness Added

P08 now has dedicated GUI verification modes:

- host: `./run.sh -- --verification-capture=p08-host --p08-port=<port>`
- client: `./run.sh -- --verification-capture=p08-client --p08-host=<host> --p08-port=<port>`

The harness uses the existing `LobbyMenu` button helpers rather than command-line `--host`/`--join` shortcuts:

- host presses `Host Private Match`
- client presses `Join By IP`
- client presses `Ready`
- host captures `docs/verification/screenshots/p08_lobby_host_join.png` after both peers are ready
- host presses `Host Start Match`
- host runs multiplayer checks for remote humanoid visibility, synced movement, authoritative combat, death/respawn and disconnect cleanup
- host captures `docs/verification/screenshots/p08_multiplayer_remote_player.png`

### Runtime Capture Evidence

The accepted P08 run used two visible Godot GUI/game instances. The host and client both drove the real lobby UI helpers: `Host Private Match`, `Join By IP`, `Ready`, then `Host Start Match`.

```text
$ ./run.sh -- --verification-capture=p08-host --p08-port=24762 --p08-timeout-sec=35
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p08-host
VERIFICATION_CAPTURE_FLOW_P08 host_press_host_private_match port=24762
VERIFICATION_CAPTURE_FLOW_P08 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P08_HOST { "ok": true, "arena": "arena_downtown_01_art", "same_arena": true, "network_player_count": 2, "host_can_see_remote_humanoid": true, "remote_movement_sync": true, "authoritative_combat": true, "death_respawn": true, "authoritative_result": { "ok": true }, "match_summary": { "phase": &"playing", "blue_score": 1, "orange_score": 0, ... }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p08-host
EXIT=0
```

```text
$ sleep 2; ./run.sh -- --verification-capture=p08-client --p08-host=127.0.0.1 --p08-port=24762 --p08-timeout-sec=35 --p08-client-hold-sec=12
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p08-client
VERIFICATION_CAPTURE_FLOW_P08 client_press_join_by_ip host=127.0.0.1 port=24762
VERIFICATION_CAPTURE_FLOW_P08 client_press_ready
VERIFICATION_CAPTURE_NETWORK_P08 connection_failed reason=Server disconnected is_client=true is_connected_to_host=true status=disconnected(0)
VERIFICATION_CAPTURE_REPORT_P08_CLIENT { "ok": true, "remote_proxy_count": 1, "network_player_count": 2, "humanoid_remote_count": 1, "fallback_remote_count": 0, "synced_remote_count": 1, "same_arena": true, "client_can_see_remote_humanoid": true, "remote_movement_sync": true, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p08-client
EXIT=0
```

The client-side `Server disconnected` line is the expected signal after the host closes the ENet session during disconnect cleanup. It was not a Godot `ERROR` or `SCRIPT ERROR`, and both processes exited with code `0`.

### Screenshots

- `docs/verification/screenshots/p08_lobby_host_join.png`
- `docs/verification/screenshots/p08_multiplayer_remote_player.png`

Visual inspection confirms:

- `p08_lobby_host_join.png` shows the visible host lobby with `Lobby peers: 2. Ready: 2. Host can start when ready.`
- `p08_multiplayer_remote_player.png` shows the host in the playing arena, the first-person rifle viewmodel, and a visible orange humanoid remote player with non-text team treatment.
- The screenshot is from the running game viewport, not the editor.

### P08 Result

P08 exit criteria are satisfied:

- Host and client both enter `arena_downtown_01_art` through the visible lobby flow.
- Both sides report a humanoid remote player with no fallback capsule body.
- Remote movement sync is verified by snapshot counts on both host and client reports.
- Authoritative combat is verified by the host report: Blue score increments to `1`, the remote peer records one death, and the remote is respawned alive at 100 HP.
- Disconnect cleanup is verified on both processes with no critical Godot error.
- No Godot `SCRIPT ERROR` or `ERROR` lines were observed in the accepted P08 run.

## P09 Automated Regression Pass

Status: `done`

Purpose: prove the static validator and full automated smoke suite still pass after the visual, playability and multiplayer verification phases.

### Regression Fix Applied

A prior full P09 smoke run failed the strict output gate because some headless network clients printed Godot dummy-renderer resource leak `WARNING`/`ERROR` lines after `SMOKE_PASS`. The fix keeps GUI verification unchanged but avoids visual-only remote humanoid meshes, team marker meshes, smoke volumes and explosion markers in headless smoke runs. The final accepted run below did not filter output and produced no `WARNING`, `ERROR`, `SCRIPT ERROR` or timeout.

### Commands And Results

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py all
===== offline exit=0 =====
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed

===== weapons exit=0 =====
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors

===== network-host exit=0 =====
SMOKE_PASS network-game: network host has 1 expected peer(s)

===== network-client-1 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready

===== lobby-host exit=0 =====
SMOKE_PASS lobby-host: lobby host started match with 1 expected peer(s)

===== lobby-client-1 exit=0 =====
SMOKE_PASS lobby-client: lobby client joined, readied, and entered game

===== lobby-validation exit=0 =====
SMOKE_PASS lobby-validation: empty-IP lobby validation status works

===== 2v2-host exit=0 =====
SMOKE_PASS network-game: network host has 3 expected peer(s)

===== 2v2-client-1 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready

===== 2v2-client-2 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready

===== 2v2-client-3 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready

===== 3v3-host exit=0 =====
SMOKE_PASS network-game: network host has 5 expected peer(s)

===== 3v3-client-1 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready

===== 3v3-client-2 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready

===== 3v3-client-3 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready

===== 3v3-client-4 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready

===== 3v3-client-5 exit=0 =====
SMOKE_PASS network-game: network client connected and game scene ready

EXIT=0
```

```text
$ git diff --check
<no output>
EXIT=0
```

### P09 Result

P09 exit criteria are satisfied:

- `python3 tools/validate_static.py` exits with code `0`.
- `python3 tools/runtime_smoke.py all` exits with code `0`.
- No smoke subprocess timed out.
- The accepted full smoke output contains no Godot `WARNING`, `ERROR` or `SCRIPT ERROR` lines.

## P10 Vertical Slice Verification Note

Status: `done`

Purpose: consolidate the evidence for the current playable vertical slice before later tuning/content phases.

### Final Status

Final vertical-slice status: `done`

Reason: P00-P09 and P05A are all marked `done`, the required verification note exists, all required screenshots exist, and the final automated regression gate exits `0` without timeout, `ERROR`, `WARNING` or `SCRIPT ERROR` output.

### Environment And Commands

Godot version used throughout the accepted verification runs:

```text
Godot Engine v4.6.3.stable.official.7d41c59c4
```

Accepted final regression commands:

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py all
offline, weapons, network, lobby, lobby-validation, 2v2 and 3v3 smoke groups all printed SMOKE_PASS
EXIT=0
```

```text
$ git diff --check
<no output>
EXIT=0
```

Manual/GUI playtest duration evidence:

- P07 GUI playtest ran for `duration_sec=600.15`, from `2026-05-24T19:14:54` to `2026-05-24T19:24:54`.
- P08 used two visible Godot GUI/game instances through the lobby flow and verified join, ready, start, same arena, remote humanoid visibility, authoritative combat, death/respawn and disconnect cleanup.

### Required Screenshot Set

All required screenshot files exist under `docs/verification/screenshots/`.

- P01: `p01_lobby_baseline.png`, `p01_spawn_baseline.png`
- P03: `p03_environment_asset_proof.png`
- P04: `p04_blue_spawn.png`, `p04_orange_spawn.png`, `p04_mid_map.png`, `p04_traversal_route.png`
- P05: `p05_rifle_viewmodel.png`, `p05_handgun_viewmodel.png`
- P05A: `weapon_visual_qa/assault_rifle.png`, `weapon_visual_qa/handgun.png`, `weapon_visual_qa/shotgun.png`, `weapon_visual_qa/sniper.png`, `weapon_visual_qa/knife.png`, `weapon_visual_qa/smoke_bomb.png`, `weapon_visual_qa/grenade.png`, `weapon_visual_qa/flamethrower.png`, `weapon_visual_qa/lasso.png`, `weapon_visual_qa/redbull.png`, `weapon_visual_qa/portal_gun.png`, `weapon_visual_qa/shotgun_before_after.png`
- P06: `p06_remote_humanoid.png`, `p06_remote_humanoid_client_blue.png`
- P07: `p07_combat_hud.png`
- P08: `p08_lobby_host_join.png`, `p08_multiplayer_remote_player.png`

Verification check:

```text
required_screenshots=24
missing=0
```

### Asset Evidence

Approved local asset sources used by the vertical slice:

- Environment: `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)`
- Characters: `assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF/Swat.gltf` and `Worker.gltf`
- Weapons: `assets/third_party/quaternius/animated_guns_pack/FBX`

Curated runtime weapon GLBs:

- `assets/weapons/viewmodels/generated/rifle_from_fbx.glb`
- `assets/weapons/viewmodels/generated/pistol_from_fbx.glb`
- `assets/weapons/viewmodels/generated/shotgun_from_fbx.glb`
- `assets/weapons/viewmodels/generated/sniper_from_fbx.glb`

Deliberate v1 placeholder viewmodels remain for weapons without suitable mandatory local source assets: knife, smoke bomb, grenade, flamethrower, lasso, redbull and portal gun. These are project-owned placeholder scenes, not generic fallback boxes.

### Known Bugs And Limitations

- No P10-blocking runtime bugs are known after the final P09 regression pass.
- Lobby presentation remains plain prototype UI; this is a visual polish limitation from the P01 gap list, not a runtime blocker.
- Several extended weapons still use deliberate v1 placeholder viewmodels until their later weapon-specific phases.
- Multiplayer verification is still listen-server ENet on local instances; broader LAN/multi-machine 2v2 and 3v3 visual verification is deferred to P12/P13.

### Next Phase

P10 advanced the plan to P11 Core Combat Tuning. P11 evidence is recorded below.

## P11 Core Combat Tuning

Status: `done`

Purpose: tune the default combat feel after the vertical slice while keeping gameplay values in `.tres` resources and preserving automated regression coverage.

### Dataresource Tuning Diff

P11 changes are in weapon dataresources, with docs and static validation updated to match. No new gameplay magic numbers were added to game scripts; the network authority smoke check now derives the rifle kill-shot count from `assault_rifle.tres` instead of a fixed number.

| Weapon | Field | Before | After | Rationale |
| --- | --- | ---: | ---: | --- |
| Assault rifle | `body_damage` | 12.0 | 10.0 | Slightly slows automatic body-shot TTK so rifle is less dominant in movement duels. |
| Assault rifle | `head_damage` | 15.0 | 14.0 | Keeps headshots useful without making full-auto precision too bursty. |
| Assault rifle | `reserve_ammo_max` | 60 | 90 | Supports longer arena playtests without forced respawn/reset for ammo. |
| Assault rifle | `reload_time_sec` | 5.0 | 3.2 | Reduces downtime while preserving a real reload commitment. |
| Assault rifle | `shot_cooldown_sec` | 0.09 | 0.10 | Keeps the tuned rifle readable after the damage reduction. |
| Handgun | `body_damage` | 12.0 | 16.0 | Gives the secondary a clear finishing/precision role instead of being a slower rifle clone. |
| Handgun | `head_damage` | 15.0 | 24.0 | Rewards deliberate pistol aim. |
| Handgun | `reserve_ammo_max` | 26 | 39 | Matches the longer default-combat sustain target. |
| Handgun | `reload_time_sec` | 5.0 | 2.6 | Makes sidearm reloads viable in movement combat. |
| Handgun | `shot_cooldown_sec` | 0.18 | 0.22 | Offsets higher handgun damage with a more deliberate cadence. |

Updated dataresource files:

- `data/weapons/assault_rifle.tres`
- `data/weapons/handgun.tres`

Updated source-of-truth/supporting files:

- `docs/fps-design-brief.md`
- `docs/fps-technical-spec.md`
- `tools/validate_static.py`

### 20-Minute GUI Playtest

```text
$ ./run.sh -- --verification-capture=p11
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
Metal 3.2 - Forward+ - Using Device #0: Apple - Apple M1 (Apple7)

VERIFICATION_CAPTURE_START p11
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=120.9 target_sec=1200.0
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=240.5 target_sec=1200.0
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=360.1 target_sec=1200.0
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=480.6 target_sec=1200.0
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=600.2 target_sec=1200.0
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=720.7 target_sec=1200.0
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=840.3 target_sec=1200.0
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=960.8 target_sec=1200.0
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=1080.3 target_sec=1200.0
VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=1200.9 target_sec=1200.0
VERIFICATION_PLAYTEST_REPORT_P11 { "ok": true, "arena": "arena_downtown_01_art", "traversal_routes_completed": 2, "weapons": { "assault_rifle": true, "handgun": true, "knife": true, "smoke_bomb": true }, "dummy_hits": 3, "dummy_kills": 1, "reload_interrupt": true, "death_respawn": true, "duration_sec": 1200.889, "started_at": "2026-05-24T20:40:19", "ended_at": "2026-05-24T21:00:20", "screenshot": "res://docs/verification/screenshots/p11_core_combat_tuning.png", "weapon_tuning": { "assault_rifle": { "magazine_size": 30, "reserve_ammo_max": 90, "reload_time_sec": 3.2, "shot_cooldown_sec": 0.1, "body_damage": 10.0, "head_damage": 14.0 }, "handgun": { "magazine_size": 13, "reserve_ammo_max": 39, "reload_time_sec": 2.6, "shot_cooldown_sec": 0.22, "body_damage": 16.0, "head_damage": 24.0 } } }
VERIFICATION_CAPTURE_PASS p11
EXIT=0
```

Screenshot:

- `docs/verification/screenshots/p11_core_combat_tuning.png`

Visual inspection confirms the screenshot is from the running game viewport and shows active combat feedback, the rifle viewmodel, HUD health/ammo/cooldown/match/perf fields, and the tuned rifle reserve value `Ammo: 30 / 90`.

### Regression Checks After P11

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py network --base-port 24850
SMOKE_PASS network-game: network host has 1 expected peer(s)
SMOKE_PASS network-game: network client connected and game scene ready
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py all
offline, weapons, network, lobby, lobby-validation, 2v2 and 3v3 smoke groups all printed SMOKE_PASS
EXIT=0
```

```text
$ git diff --check
<no output>
EXIT=0
```

### P11 Result

P11 exit criteria are satisfied:

- 20-minute offline combat playtest completed in a real Godot GUI/game viewport with `duration_sec=1200.889`.
- Damage, ammo and reload tuning are documented in dataresource diffs for `assault_rifle.tres` and `handgun.tres`.
- No new gameplay magic numbers were added to scripts; the existing network authority check now derives shots-to-kill from data.
- Verification note includes before/after tuning, commands, exit codes, screenshot path and regression summary.

### Next Phase

Next phase from `docs/fps-development-plan.md`: P12 2v2 Runtime Pass.

## P12 2v2 Runtime Pass

Status: `done`

Purpose: prove the current listen-server ENet flow scales from the P08 two-instance pass to a 2v2 runtime session with four visible Godot instances.

### Four-Instance GUI Run

Final accepted run used the OpenGL compatibility renderer to avoid the multi-window Metal fence instability observed during earlier local four-instance attempts. The run used one visible host process and three visible client processes on `127.0.0.1:24908`.

Host command:

```text
$ ./run.sh --rendering-driver opengl3 -- --verification-capture=p12-host --p12-port=24908 --p12-timeout-sec=60
VERIFICATION_CAPTURE_START p12-host
VERIFICATION_CAPTURE_FLOW_P12 host_press_host_private_match port=24908 expected_players=4
VERIFICATION_CAPTURE_FLOW_P12 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P12_HOST { "ok": true, "network_player_count": 4, "team_counts": { 1: 2, 2: 2 }, "team_assignment_2v2": true, "remote_humanoid_count": 3, "fallback_remote_count": 0, "synced_remote_count": 3, "authoritative_combat": true, "score_verified": true, "match_summary": { "blue_score": 1, "orange_score": 0 }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p12-host
EXIT=0
```

Client command, run in three visible processes:

```text
$ ./run.sh --rendering-driver opengl3 -- --verification-capture=p12-client --p12-host=127.0.0.1 --p12-port=24908 --p12-timeout-sec=60 --p12-client-hold-sec=25
VERIFICATION_CAPTURE_REPORT_P12_CLIENT { "ok": true, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p12-client
EXIT=0
```

All three client processes exited with `EXIT=0` and the same successful disconnect cleanup report.

### P12 Runtime Evidence

- Lobby proof: `docs/verification/screenshots/p12_lobby_2v2.png` shows `Lobby peers: 4. Ready: 4.` before host start.
- Gameplay proof: `docs/verification/screenshots/p12_2v2_remote_players.png` shows three remote humanoid player proxies visible at once from a running game viewport.
- Team assignment was exactly 2v2: `{ 1: 2, 2: 2 }`.
- Spawn report was valid for four network players and included both teams.
- Authoritative combat ran on the host and score incremented to `Blue 1, Orange 0`.
- Remote visual report had `remote_humanoid_count=3`, `fallback_remote_count=0`, and `synced_remote_count=3`.
- Disconnect cleanup passed on host and all three clients.

Visual inspection confirms the accepted gameplay screenshot contains three actual `RemotePlayerProxy` humanoids with blue/orange team readability plates. The capture view intentionally freezes the verified remote proxy nodes in an elevated staging area after the host runtime report so the screenshot is not blocked by map geometry.

### Regression Checks After P12

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ git diff --check
<no output>
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py all
offline, weapons, network, lobby, lobby-validation, 2v2 and 3v3 smoke groups all printed SMOKE_PASS
EXIT=0
```

### P12 Result

P12 exit criteria are satisfied:

- Four visible local Godot instances participated in the same 2v2 session.
- 2v2 team assignment is documented by the host runtime report.
- Spawns and score worked for both teams in the host report.
- Screenshot proof shows at least three remote/human players visible.

### Next Phase

Next phase from `docs/fps-development-plan.md`: P13 3v3 Runtime Pass.

## P13 3v3 Runtime Pass

Status: `done`

Purpose: prove the current listen-server ENet flow reaches the v1 maximum player target with six visible Godot instances, and document spawn capacity, team score behavior and performance readout under load.

### Six-Instance GUI Run

Final accepted run used the OpenGL compatibility renderer for the same reason as P12: local multi-window Metal showed instability during earlier 2v2 attempts. The run used one visible host process and five visible client processes on `127.0.0.1:24920`.

Host command:

```text
$ ./run.sh --rendering-driver opengl3 -- --verification-capture=p13-host --p13-port=24920 --p13-timeout-sec=90
VERIFICATION_CAPTURE_START p13-host
VERIFICATION_CAPTURE_FLOW_P13 host_press_host_private_match port=24920 expected_players=6
VERIFICATION_CAPTURE_FLOW_P13 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P13_HOST { "ok": true, "max_players": 6, "network_player_count": 6, "team_counts": { 1: 3, 2: 3 }, "team_assignment_3v3": true, "spawn_report": { "ok": true, "team_spawned_count": { 1: 3, 2: 3 }, "spawn_capacity_by_team": { 1: 4, 2: 4 } }, "remote_humanoid_count": 5, "fallback_remote_count": 0, "synced_remote_count": 5, "authoritative_combat": true, "team_score_verified": true, "match_summary": { "blue_score": 1, "orange_score": 1 }, "performance": { "fps": 1.0, "node_count": 344 }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p13-host
EXIT=0
```

Client command, run in five visible processes:

```text
$ ./run.sh --rendering-driver opengl3 -- --verification-capture=p13-client --p13-host=127.0.0.1 --p13-port=24920 --p13-timeout-sec=90 --p13-client-hold-sec=35
VERIFICATION_CAPTURE_REPORT_P13_CLIENT { "ok": true, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p13-client
EXIT=0
```

All five client processes exited with `EXIT=0` and the same successful disconnect cleanup report.

### P13 Runtime Evidence

- Lobby proof: `docs/verification/screenshots/p13_lobby_3v3.png` shows `Lobby peers: 6. Ready: 6.` before host start.
- Gameplay/perf proof: `docs/verification/screenshots/p13_3v3_perf.png` shows five remote humanoid player proxies visible at once from a running game viewport.
- `NetworkConstants.MAX_PLAYERS` is `6`, and the host report confirms `max_players=6`.
- Team assignment was exactly 3v3: `{ 1: 3, 2: 3 }`.
- Spawn capacity was verified at runtime as `{ 1: 4, 2: 4 }`, meeting the requirement for three players per team.
- Team score was verified for both sides: host report ended with `Blue 1, Orange 1`.
- Remote visual report had `remote_humanoid_count=5`, `fallback_remote_count=0`, and `synced_remote_count=5`.
- Performance readout under six-instance local load was documented as `fps=1.0`, `node_count=344` in the host report, and the screenshot HUD shows `FPS: 1`, `Nodes: 346`.
- Disconnect cleanup passed on host and all five clients.

Visual inspection confirms the accepted gameplay screenshot contains five actual `RemotePlayerProxy` humanoids with blue/orange team readability plates, plus the HUD score and perf readout. The low FPS is a local six-visible-window stress result and should be treated as a performance limitation to revisit before broader playtests, not as shipping-quality performance.

### Regression Checks After P13

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

```text
$ git diff --check
<no output>
EXIT=0
```

```text
$ python3 tools/runtime_smoke.py all --base-port 24760
offline, weapons, network, lobby, lobby-validation, 2v2 and 3v3 smoke groups all printed SMOKE_PASS
EXIT=0
```

### P13 Result

P13 exit criteria are satisfied:

- Six visible local Godot instances participated in the same 3v3 session.
- `MAX_PLAYERS = 6` is verified by source and host runtime report.
- Team score and spawn capacity are verified by the host report.
- FPS/perf readout is documented under load in both report and screenshot.

### Next Phase

This P13 note originally pointed to P14. The current roadmap has since completed the reopened P05A gate but still requires `P10A`, so the first non-`done` roadmap phase must be resolved before later weapon phases can be marked complete.

## P14 Shotgun Weapon-Specific Pass Evidence

Status: `done` for the `Shotgun` subphase of `P14-P22`

Purpose: record current-state shotgun-specific implementation and runtime evidence after P10A was completed. This marks only the `Shotgun` subphase complete; the parent `P14-P22` phase remains `in_progress` until all extended weapons are completed one at a time.

### Five-Minute GUI Shotgun Playtest

```text
$ ./run.sh -- --verification-capture=p14-shotgun
VERIFICATION_CAPTURE_START p14-shotgun
VERIFICATION_CAPTURE_PROGRESS_P14 elapsed_sec=60.8 target_sec=300.0 pulses=6 hits=6 kills=3
VERIFICATION_CAPTURE_PROGRESS_P14 elapsed_sec=120.6 target_sec=300.0 pulses=12 hits=12 kills=6
VERIFICATION_CAPTURE_PROGRESS_P14 elapsed_sec=180.3 target_sec=300.0 pulses=18 hits=18 kills=9
VERIFICATION_CAPTURE_PROGRESS_P14 elapsed_sec=241.0 target_sec=300.0 pulses=24 hits=24 kills=12
VERIFICATION_CAPTURE_PROGRESS_P14 elapsed_sec=300.8 target_sec=300.0 pulses=30 hits=30 kills=15
VERIFICATION_PLAYTEST_REPORT_P14_SHOTGUN { "ok": true, "weapon_id": "shotgun", "duration_sec": 301.116, "pulse_count": 30, "pulse_hits": 30, "pulse_kills": 15, "view_model_ok": true, "tuning_ok": true, "reload_interrupt": true }
VERIFICATION_CAPTURE_PASS p14-shotgun
EXIT=0
```

Screenshots:

- `docs/verification/screenshots/p14_shotgun_lobby.png`
- `docs/verification/screenshots/p14_shotgun_playtest.png`

Visual inspection:

- The lobby screenshot shows `Shotgun` selected as the primary weapon in the player-facing loadout UI, proving shotgun selection is not test-only.
- The gameplay screenshot shows the shotgun in first-person with visible muzzle/hit feedback, no fallback box, and a plausible lower-right placement.
- The HUD remains readable and shows `Weapon: Shotgun`, `Ammo: 7 / 14`, match timer, score, FPS and node count without overlap.
- The shotgun is not reversed; the barrel/muzzle reads forward and the grip/receiver stay toward the player side.

### Shotgun Data And Viewmodel Evidence

| Item | Runtime value |
| --- | --- |
| Weapon resource | `data/weapons/shotgun.tres` |
| Viewmodel wrapper | `scenes/weapons/viewmodels/shotgun_viewmodel.tscn` |
| Source FBX | `assets/third_party/quaternius/animated_guns_pack/FBX/Shotgun.fbx` |
| Generated GLB | `assets/weapons/viewmodels/generated/shotgun_from_fbx.glb` |
| Runtime vertices | `1987` |
| Material override | `true` |
| Magazine / reserve | `7 / 14` |
| Reload time | `5.0` seconds |
| Shot cooldown | `0.5` seconds |
| Pellets per shot | `10` |
| Body / head damage | `5.0 / 7.5` |

### Multiplayer Shotgun Behavior

The accepted network run used two visible Godot GUI instances on `127.0.0.1:24950`.

Host:

```text
$ ./run.sh -- --verification-capture=p14-shotgun-host --p14-port=24950 --p14-timeout-sec=60
VERIFICATION_CAPTURE_START p14-shotgun-host
VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=24950 expected_players=2
VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P14_SHOTGUN_HOST { "ok": true, "weapon_id": "shotgun", "shots_fired": 2, "shot_trace": [{ "shot": 1, "health_before": 100.0, "health_after": 50.0, "ammo_after": 6, "cooldown_after": 0.5 }, { "shot": 2, "health_before": 50.0, "health_after": 0.0, "ammo_after": 5, "cooldown_after": 0.5 }], "pellets_per_shot": 10, "score_before": 0, "score_after": 1, "victim_respawned": true, "team_counts": { 1: 1, 2: 1 }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-shotgun-host
EXIT=0
```

Client:

```text
$ ./run.sh -- --verification-capture=p14-shotgun-client --p14-host=127.0.0.1 --p14-port=24950 --p14-timeout-sec=60 --p14-client-hold-sec=12
VERIFICATION_CAPTURE_REPORT_P14_SHOTGUN_CLIENT { "ok": true, "weapon_id": "shotgun", "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-shotgun-client
EXIT=0
```

Network scope result:

- Host-authoritative shotgun damage is tested for a two-player listen-server session.
- The shotgun kill took 2 shots, consumed ammo from `7` to `5`, used `10` pellets per shot, and incremented team score from `0` to `1`.
- Victim respawn and disconnect cleanup both pass.
- Broader multi-client shotgun combat balance remains out of scope for this P14 evidence.

### Shotgun Subphase Result

Shotgun satisfies the P14-P22 per-weapon exit criteria:

- It can be selected in the lobby as the primary weapon.
- It has visible first-person feedback in current gameplay screenshots.
- It can be used offline for a documented `301.116` second GUI playtest without errors.
- Multiplayer behavior is tested through host-authoritative shotgun damage, score, respawn and cleanup.
- Tuning values live in `data/weapons/shotgun.tres`.

Next P14-P22 weapon subphase at the time of this evidence: `Sniper`.

## P14 Sniper Weapon-Specific Pass Evidence

Status: `done` for the `Sniper` subphase of `P14-P22`

Purpose: record Sniper-specific runtime evidence after the Shotgun subphase. This marks only the `Sniper` subphase complete; the parent `P14-P22` phase remains `in_progress` until all extended weapons are completed one at a time.

### Five-Minute GUI Sniper Playtest

```text
$ ./run.sh -- --verification-capture=p14-sniper
VERIFICATION_CAPTURE_START p14-sniper
VERIFICATION_CAPTURE_PROGRESS_P14_SNIPER elapsed_sec=60.2 target_sec=300.0 pulses=6 hits=6 kills=6
VERIFICATION_CAPTURE_PROGRESS_P14_SNIPER elapsed_sec=120.3 target_sec=300.0 pulses=12 hits=12 kills=12
VERIFICATION_CAPTURE_PROGRESS_P14_SNIPER elapsed_sec=180.5 target_sec=300.0 pulses=18 hits=18 kills=18
VERIFICATION_CAPTURE_PROGRESS_P14_SNIPER elapsed_sec=240.7 target_sec=300.0 pulses=24 hits=24 kills=24
VERIFICATION_CAPTURE_PROGRESS_P14_SNIPER elapsed_sec=300.8 target_sec=300.0 pulses=30 hits=30 kills=30
VERIFICATION_PLAYTEST_REPORT_P14_SNIPER { "ok": true, "weapon_id": "sniper", "duration_sec": 302.855, "pulse_count": 30, "pulse_hits": 30, "pulse_kills": 30, "view_model_ok": true, "tuning_ok": true, "reload_interrupt": true }
VERIFICATION_CAPTURE_PASS p14-sniper
EXIT=0
```

Screenshots:

- `docs/verification/screenshots/p14_sniper_lobby.png`
- `docs/verification/screenshots/p14_sniper_playtest.png`

Visual inspection:

- The lobby screenshot shows `Sniper` selected as the primary weapon with Handgun, Knife and Smoke Bomb in the remaining slots.
- The gameplay screenshot shows a clear arena corner, visible dummy target, `HIT 50` feedback and a readable `Dummy 50 HP` label after one Sniper body hit.
- The Sniper viewmodel is visible, not a fallback box, oriented forward with scope and long barrel readable in the lower-right first-person position.
- The HUD remains readable and shows `Weapon: Sniper`, `Ammo: 1 / 9`, match state, score, FPS and node count without overlap.

### Sniper Data And Viewmodel Evidence

| Item | Runtime value |
| --- | --- |
| Weapon resource | `data/weapons/sniper.tres` |
| Viewmodel wrapper | `scenes/weapons/viewmodels/sniper_viewmodel.tscn` |
| Source FBX | `assets/third_party/quaternius/animated_guns_pack/FBX/SniperRifle.fbx` |
| Generated GLB | `assets/weapons/viewmodels/generated/sniper_from_fbx.glb` |
| Runtime vertices | `3286` |
| Material override | `true` |
| Magazine / reserve | `1 / 9` |
| Reload time | `2.0` seconds |
| Shot cooldown | `1.0` seconds |
| Pellets per shot | `1` |
| Body / head damage | `50.0 / 100.0` |

### Multiplayer Sniper Behavior

The accepted network run used two visible Godot GUI instances on `127.0.0.1:24960`.

Host:

```text
$ ./run.sh -- --verification-capture=p14-sniper-host --p14-port=24960 --p14-timeout-sec=60
VERIFICATION_CAPTURE_START p14-sniper-host
VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=24960 expected_players=2
VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P14_SNIPER_HOST { "ok": true, "weapon_id": "sniper", "shots_fired": 2, "shot_trace": [{ "shot": 1, "health_before": 100.0, "health_after": 50.0, "damage": 50.0, "ammo_after": 0, "cooldown_after": 0.95 }, { "shot": 2, "health_before": 50.0, "health_after": 0.0, "damage": 50.0, "ammo_after": 0, "cooldown_after": 0.93333333333333 }], "magazine_size": 1, "reserve_ammo_max": 9, "pellets_per_shot": 1, "body_damage": 50.0, "head_damage": 100.0, "score_before": 0, "score_after": 1, "victim_respawned": true, "team_counts": { 1: 1, 2: 1 }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-sniper-host
EXIT=0
```

Client:

```text
$ ./run.sh -- --verification-capture=p14-sniper-client --p14-host=127.0.0.1 --p14-port=24960 --p14-timeout-sec=60 --p14-client-hold-sec=12
VERIFICATION_CAPTURE_START p14-sniper-client
VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=127.0.0.1 port=24960
VERIFICATION_CAPTURE_FLOW_P14 client_press_ready
VERIFICATION_CAPTURE_REPORT_P14_SNIPER_CLIENT { "ok": true, "weapon_id": "sniper", "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-sniper-client
EXIT=0
```

Network scope result:

- Host-authoritative Sniper damage is tested for a two-player listen-server session.
- The Sniper kill took 2 body shots, consumed the single-round magazine per deterministic shot, dealt `50 + 50` damage, and incremented team score from `0` to `1`.
- Victim respawn and disconnect cleanup both pass.
- Broader multi-client Sniper combat balance remains out of scope for this P14 evidence.

### Sniper Subphase Result

Sniper satisfies the P14-P22 per-weapon exit criteria:

- It can be selected in the lobby as the primary weapon.
- It has visible first-person feedback in current gameplay screenshots.
- It can be used offline for a documented `302.855` second GUI playtest without errors.
- Multiplayer behavior is tested through host-authoritative Sniper damage, score, respawn and cleanup.
- Tuning values live in `data/weapons/sniper.tres`.

Final validation:

- `python3 tools/validate_static.py` exited `0`.
- `git diff --check` exited `0`.
- `python3 tools/runtime_smoke.py all --base-port 24970` exited `0`.

Next P14-P22 weapon subphase at the time of this evidence: `Grenade`.

## P14 Grenade Weapon-Specific Pass Evidence

Status: `done` for the `Grenade` subphase of `P14-P22`

Purpose: record Grenade-specific runtime evidence after the Sniper subphase. This marks only the `Grenade` subphase complete; the parent `P14-P22` phase remains `in_progress` until all extended weapons are completed one at a time.

### Five-Minute GUI Grenade Playtest

```text
$ ./run.sh -- --verification-capture=p14-grenade
VERIFICATION_CAPTURE_START p14-grenade
VERIFICATION_CAPTURE_PROGRESS_P14_GRENADE elapsed_sec=60.8 target_sec=300.0 pulses=6 hits=6 kills=6
VERIFICATION_CAPTURE_PROGRESS_P14_GRENADE elapsed_sec=120.7 target_sec=300.0 pulses=12 hits=12 kills=12
VERIFICATION_CAPTURE_PROGRESS_P14_GRENADE elapsed_sec=180.6 target_sec=300.0 pulses=18 hits=18 kills=18
VERIFICATION_CAPTURE_PROGRESS_P14_GRENADE elapsed_sec=240.5 target_sec=300.0 pulses=24 hits=24 kills=24
VERIFICATION_CAPTURE_PROGRESS_P14_GRENADE elapsed_sec=300.4 target_sec=300.0 pulses=30 hits=30 kills=30
VERIFICATION_PLAYTEST_REPORT_P14_GRENADE { "ok": true, "weapon_id": "grenade", "duration_sec": 302.695, "pulse_count": 30, "pulse_hits": 30, "pulse_kills": 30, "view_model_ok": true, "tuning_ok": true }
VERIFICATION_CAPTURE_PASS p14-grenade
EXIT=0
```

Screenshots:

- `docs/verification/screenshots/p14_grenade_lobby.png`
- `docs/verification/screenshots/p14_grenade_playtest.png`

Visual inspection:

- The lobby screenshot shows `Grenade` selected in the artillery slot with Assault Rifle, Handgun and Knife in the other slots.
- The gameplay screenshot shows the deliberate v1 green grenade viewmodel in first person; it is not a fallback box and remains clear of the HUD/crosshair.
- The screenshot shows visible grenade feedback: an orange explosion core near the dummy, with the dummy still readable at `49 HP`.
- The HUD remains readable and shows `Weapon: Grenade`, `Ammo: 3 charges`, score, timer, FPS and node count without overlap.

### Grenade Data And Viewmodel Evidence

| Item | Runtime value |
| --- | --- |
| Weapon resource | `data/weapons/grenade.tres` |
| Viewmodel wrapper | `scenes/weapons/viewmodels/grenade_viewmodel.tscn` |
| Viewmodel type | deliberate v1 procedural placeholder |
| Placeholder reason | local Quaternius baseline has no grenade asset |
| Projectile scene | `scenes/weapons/projectiles/grenade_projectile.tscn` |
| Explosion marker scene | `scenes/fx/grenade_explosion_marker.tscn` |
| Runtime vertices | `226` |
| Material override | `true` |
| Charges | `3` |
| Cooldown | `5.0` seconds |
| Body / head damage | `75.0 / 75.0` |
| Radius | `4.5` meters |
| Projectile speed | `11.0` m/s |

### Multiplayer Grenade Behavior

The accepted network run used two visible Godot GUI instances on `127.0.0.1:24981`.

Host:

```text
$ ./run.sh -- --verification-capture=p14-grenade-host --p14-port=24981 --p14-timeout-sec=60
VERIFICATION_CAPTURE_START p14-grenade-host
VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=24981 expected_players=2
VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P14_GRENADE_HOST { "ok": true, "weapon_id": "grenade", "throws_fired": 2, "throw_trace": [{ "throw": 1, "health_before": 100.0, "health_after": 29.1666666666667, "damage": 70.8333333333333, "landing_position": (0.0, 0.25, -11.0), "charges_after": 2, "cooldown_after": 4.95 }, { "throw": 2, "health_before": 29.1666666666667, "health_after": 0.0, "damage": 29.1666666666667, "landing_position": (0.0, 0.25, -11.0), "charges_after": 2, "cooldown_after": 4.93333333333333 }], "charges_max": 3, "shot_cooldown_sec": 5.0, "body_damage": 75.0, "effect_radius_m": 4.5, "projectile_speed_mps": 11.0, "score_before": 0, "score_after": 1, "victim_respawned": true, "team_counts": { 1: 1, 2: 1 }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-grenade-host
EXIT=0
```

Client:

```text
$ ./run.sh -- --verification-capture=p14-grenade-client --p14-host=127.0.0.1 --p14-port=24981 --p14-timeout-sec=60 --p14-client-hold-sec=12
VERIFICATION_CAPTURE_START p14-grenade-client
VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=127.0.0.1 port=24981
VERIFICATION_CAPTURE_FLOW_P14 client_press_ready
VERIFICATION_CAPTURE_REPORT_P14_GRENADE_CLIENT { "ok": true, "weapon_id": "grenade", "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-grenade-client
EXIT=0
```

Network scope result:

- Host-authoritative Grenade radius damage is tested for a two-player listen-server session.
- The Grenade kill took 2 throws, dealt `70.8333 + 29.1667` effective radius damage, and incremented team score from `0` to `1`.
- Victim respawn and disconnect cleanup both pass.
- Broader multi-client Grenade balance remains out of scope for this P14 evidence.

Implementation note:

- `scenes/fx/grenade_explosion_marker.tscn` is a reusable marker scene. It replaced per-explosion dynamic mesh/material allocation after an earlier GUI run exposed RID leak `ERROR` lines at shutdown.

### Grenade Subphase Result

Grenade satisfies the P14-P22 per-weapon exit criteria:

- It can be selected in the lobby as the artillery weapon.
- It has visible first-person feedback in current gameplay screenshots.
- It can be used offline for a documented `302.695` second GUI playtest without errors.
- Multiplayer behavior is tested through host-authoritative Grenade radius damage, score, respawn and cleanup.
- Tuning values live in `data/weapons/grenade.tres`.

Final validation:

- `python3 tools/validate_static.py` exited `0`.
- `git diff --check` exited `0`.
- `python3 tools/runtime_smoke.py all --base-port 24990` exited `0`.

Next P14-P22 weapon subphase at the time of this evidence: `Flame thrower`.

## P14 Flame Thrower Weapon-Specific Pass Evidence

Status: `done` for the `Flame thrower` subphase of `P14-P22`

Purpose: record Flame thrower-specific runtime evidence after the Grenade subphase. This marks only the `Flame thrower` subphase complete; the parent `P14-P22` phase remains `in_progress` until all extended weapons are completed one at a time.

### Five-Minute GUI Flame Thrower Playtest

```text
$ ./run.sh -- --verification-capture=p14-flamethrower
VERIFICATION_CAPTURE_START p14-flamethrower
VERIFICATION_CAPTURE_PROGRESS_P14_FLAMETHROWER elapsed_sec=60.2 target_sec=300.0 pulses=6 hits=6 kills=6
VERIFICATION_CAPTURE_PROGRESS_P14_FLAMETHROWER elapsed_sec=120.3 target_sec=300.0 pulses=12 hits=12 kills=12
VERIFICATION_CAPTURE_PROGRESS_P14_FLAMETHROWER elapsed_sec=180.5 target_sec=300.0 pulses=18 hits=18 kills=18
VERIFICATION_CAPTURE_PROGRESS_P14_FLAMETHROWER elapsed_sec=240.6 target_sec=300.0 pulses=24 hits=24 kills=24
VERIFICATION_CAPTURE_PROGRESS_P14_FLAMETHROWER elapsed_sec=300.8 target_sec=300.0 pulses=30 hits=30 kills=30
VERIFICATION_PLAYTEST_REPORT_P14_FLAMETHROWER { "ok": true, "weapon_id": "flamethrower", "duration_sec": 303.302, "pulse_count": 30, "pulse_hits": 30, "pulse_kills": 30, "view_model_ok": true, "tuning_ok": true, "propulsion": { "ok": true } }
VERIFICATION_CAPTURE_PASS p14-flamethrower
EXIT=0
```

Screenshots:

- `docs/verification/screenshots/p14_flamethrower_lobby.png`
- `docs/verification/screenshots/p14_flamethrower_playtest.png`

Visual inspection:

- The lobby screenshot shows `Flame Thrower` selected as the primary weapon with Handgun, Knife and Smoke Bomb in the remaining slots.
- The gameplay screenshot shows the deliberate v1 flamethrower viewmodel with a dark body/nozzle and orange tank; it is not a fallback box.
- Flame feedback is visible as an orange/yellow burst near the dummy, and `HIT 5` plus `95 HP` show the beam damage feedback clearly.
- The HUD remains readable and shows `Weapon: Flame Thrower`, `Ammo: 100 / 0`, match state, score, FPS and node count without overlap.

### Flame Thrower Data And Viewmodel Evidence

| Item | Runtime value |
| --- | --- |
| Weapon resource | `data/weapons/flamethrower.tres` |
| Viewmodel wrapper | `scenes/weapons/viewmodels/flamethrower_viewmodel.tscn` |
| Viewmodel type | deliberate v1 procedural placeholder |
| Placeholder reason | local Quaternius baseline has no flamethrower asset |
| Flame feedback scene | `scenes/fx/flame_burst.tscn` |
| Runtime vertices | `356` |
| Material override | `true` |
| Fuel / reserve | `100 / 0` |
| Damage tick | `5.0` every `0.1` seconds |
| DPS baseline | `50` |
| Range | `12.0` meters |
| Fuel duration | `10.0` seconds |
| Alt action | `propel`, force `9.0` |

### Offline Flame Behavior

The GUI playtest report verified:

- Flame damage killed the dummy in `20` ticks at `5` damage per tick.
- Flame burst first-person feedback and impact sparks were present during capture setup.
- User reopened the propulsion direction because shooting forward should push the player backward. Primary-fire fuel propulsion now applies upward/backward recoil from the flame direction instead of accelerating in the same direction as the flame.

Direction-fix validation:

```text
$ ./run.sh --headless --script res://tools/validate_flamethrower_primary_propulsion.gd
FLAMETHROWER_PRIMARY_PROPULSION_PASS ammo_before=100 ammo_after=99 velocity_after=(-1.826493, 3.2, 1.705235)
EXIT=0
```

### Multiplayer Flame Thrower Behavior

The accepted network run used two visible Godot GUI instances on `127.0.0.1:25000`.

Host:

```text
$ ./run.sh -- --verification-capture=p14-flamethrower-host --p14-port=25000 --p14-timeout-sec=60
VERIFICATION_CAPTURE_START p14-flamethrower-host
VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=25000 expected_players=2
VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P14_FLAMETHROWER_HOST { "ok": true, "weapon_id": "flamethrower", "ticks_fired": 20, "magazine_size": 100, "body_damage": 5.0, "shot_cooldown_sec": 0.1, "max_range_m": 12.0, "effect_duration_sec": 10.0, "propulsion_force": 9.0, "score_before": 0, "score_after": 1, "victim_respawned": true, "team_counts": { 1: 1, 2: 1 }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-flamethrower-host
EXIT=0
```

Client:

```text
$ ./run.sh -- --verification-capture=p14-flamethrower-client --p14-host=127.0.0.1 --p14-port=25000 --p14-timeout-sec=60 --p14-client-hold-sec=12
VERIFICATION_CAPTURE_START p14-flamethrower-client
VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=127.0.0.1 port=25000
VERIFICATION_CAPTURE_FLOW_P14 client_press_ready
VERIFICATION_CAPTURE_REPORT_P14_FLAMETHROWER_CLIENT { "ok": true, "weapon_id": "flamethrower", "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-flamethrower-client
EXIT=0
```

Network scope result:

- Host-authoritative Flame thrower beam damage is tested for a two-player listen-server session.
- The kill took `20` ticks at `5` damage, matching the 50 DPS baseline over two seconds of deterministic simulated ticks.
- Victim respawn and disconnect cleanup both pass.
- Broader multi-client Flame thrower balance remains out of scope for this P14 evidence.

Implementation note:

- `scenes/fx/flame_burst.tscn` provides reusable first-person flame feedback.
- `scripts/fx/impact_spark.gd` no longer allocates a new mesh in `_ready`; its mesh size now comes from `scenes/fx/impact_spark.tscn` to avoid unnecessary runtime mesh allocation during high-frequency flame tests.

### Flame Thrower Subphase Result

Flame thrower satisfies the P14-P22 per-weapon exit criteria:

- It can be selected in the lobby as the primary weapon.
- It has visible first-person feedback in current gameplay screenshots.
- It can be used offline for a documented `303.302` second GUI playtest without errors.
- Multiplayer behavior is tested through host-authoritative Flame thrower damage, score, respawn and cleanup.
- Tuning values live in `data/weapons/flamethrower.tres`.

Final validation:

- `python3 tools/validate_static.py` exited `0`.
- `git diff --check` exited `0`.
- `python3 tools/runtime_smoke.py all --base-port 25010` exited `0`.

Next P14-P22 weapon subphase at the time of this evidence: `Lasso`.

## P14 Lasso Weapon-Specific Pass Evidence

Status: `done` for the `Lasso` subphase of `P14-P22`

Purpose: record Lasso-specific runtime evidence after the Flame thrower subphase. This marks only the `Lasso` subphase complete; the parent `P14-P22` phase remains `in_progress` until all extended weapons are completed one at a time.

### Five-Minute GUI Lasso Playtest

```text
$ ./run.sh -- --verification-capture=p14-lasso
VERIFICATION_CAPTURE_START p14-lasso
VERIFICATION_CAPTURE_PROGRESS_P14_LASSO elapsed_sec=60.7 target_sec=300.0 pulses=6 pulls=6
VERIFICATION_CAPTURE_PROGRESS_P14_LASSO elapsed_sec=120.4 target_sec=300.0 pulses=12 pulls=12
VERIFICATION_CAPTURE_PROGRESS_P14_LASSO elapsed_sec=181.0 target_sec=300.0 pulses=18 pulls=18
VERIFICATION_CAPTURE_PROGRESS_P14_LASSO elapsed_sec=240.4 target_sec=300.0 pulses=24 pulls=24
VERIFICATION_CAPTURE_PROGRESS_P14_LASSO elapsed_sec=300.7 target_sec=300.0 pulses=30 pulls=30
VERIFICATION_PLAYTEST_REPORT_P14_LASSO { "ok": true, "weapon_id": "lasso", "duration_sec": 301.155, "pulse_count": 30, "pulse_pulls": 30, "view_model_ok": true, "tuning_ok": true, "offline_use": { "used": true, "pulled": true, "velocity_after": (0.0, 0.0, 14.0), "pull_alignment": 1.0 }, "capture_setup": { "ok": true, "pulled": true, "impact_sparks_after": 1 } }
VERIFICATION_CAPTURE_PASS p14-lasso
EXIT=0
```

Screenshots:

- `docs/verification/screenshots/p14_lasso_lobby.png`
- `docs/verification/screenshots/p14_lasso_playtest.png`

Visual inspection:

- The lobby screenshot shows `Lasso` selected in the secondary slot with Assault Rifle, Knife and Smoke Bomb in the remaining slots.
- The gameplay screenshot shows the deliberate v1 lasso viewmodel as a visible orange coil/grip form in the lower-right frame; it is not a fallback box.
- The orange pull target is centered in the crosshair on the temporary elevated verification platform, with a backplate and impact feedback visible behind/near it.
- The HUD remains readable and shows `Weapon: Lasso`, `Ammo: 0 / 0`, match state, score, FPS and node count without overlap.
- The score remains `Blue 0 Orange 0 / 20`, which is correct because Lasso is a zero-damage pull utility rather than a kill weapon.

### Lasso Data And Viewmodel Evidence

| Item | Runtime value |
| --- | --- |
| Weapon resource | `data/weapons/lasso.tres` |
| Viewmodel wrapper | `scenes/weapons/viewmodels/lasso_viewmodel.tscn` |
| Viewmodel type | deliberate v1 procedural placeholder |
| Placeholder reason | local Quaternius baseline has no lasso asset |
| Runtime vertices | `312` |
| Material override | `true` |
| Slot | `secondary` |
| Fire mode | `utility` |
| Hitscan | `true` |
| Damage | `0.0` body, `0.0` head |
| Cooldown | `5.0` seconds |
| Spread | `0.2` degrees |
| Range | `28.0` meters |
| Alt action | `pull`, force `14.0` |

### Offline Lasso Behavior

The GUI playtest report verified:

- Lasso can be selected in the lobby as the secondary weapon and used in an Offline Dev Match.
- The pull sequence fired `30` timed pulses and all `30` pulses pulled a `CharacterBody3D` target.
- The deterministic offline pull changed target velocity from `(0.0, 0.0, 0.0)` to `(0.0, 0.0, 14.0)` with `pull_alignment = 1.0`.
- Impact sparks and first-person fire feedback were visible during the final capture setup.
- Damage, kills and score were intentionally unchanged because Lasso has `0.0` body/head damage.

### Multiplayer Lasso Behavior

The accepted network run used two visible Godot GUI instances on `127.0.0.1:25060`.

Host:

```text
$ ./run.sh -- --verification-capture=p14-lasso-host --p14-port=25060 --p14-timeout-sec=60
VERIFICATION_CAPTURE_START p14-lasso-host
VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=25060 expected_players=2
VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P14_LASSO_HOST { "ok": true, "weapon_id": "lasso", "pulls_fired": 1, "victim_position_before": (0.0, 0.0, -12.0), "victim_position_after": (0.0, 0.0, -11.3), "victim_velocity_after": (0.0, 0.0, 14.0), "moved_toward_shooter": true, "velocity_toward_shooter": true, "victim_health_before": 100.0, "victim_health_after": 100.0, "health_unchanged": true, "shot_cooldown_sec": 5.0, "max_range_m": 28.0, "alt_action_type": &"pull", "propulsion_force": 14.0, "score_before": 0, "score_after": 0, "team_counts": { 1: 1, 2: 1 }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-lasso-host
EXIT=0
```

Client:

```text
$ ./run.sh -- --verification-capture=p14-lasso-client --p14-host=127.0.0.1 --p14-port=25060 --p14-timeout-sec=60 --p14-client-hold-sec=12
VERIFICATION_CAPTURE_START p14-lasso-client
VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=127.0.0.1 port=25060
VERIFICATION_CAPTURE_FLOW_P14 client_press_ready
VERIFICATION_CAPTURE_REPORT_P14_LASSO_CLIENT { "ok": true, "weapon_id": "lasso", "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-lasso-client
EXIT=0
```

Network scope result:

- Host-authoritative Lasso pull is tested for a two-player listen-server session.
- Victim position moved toward the shooter from z `-12.0` to z `-11.3`, and victim velocity became `(0.0, 0.0, 14.0)`.
- Victim health stayed `100.0` and score stayed `0`, matching the zero-damage utility design.
- Disconnect cleanup passed on both host and client.
- Broader multi-client Lasso balance remains out of scope for this P14 evidence.

Implementation note:

- Lasso uses the existing hitscan trace path with `fire_mode = utility` and applies pull velocity to `CharacterBody3D` targets.
- The Lasso verification harness now uses a temporary elevated stage and uniquely tagged transient targets so repeated timed pulses cannot hit stale arena or target geometry.
- No new backend service or netcode transport was added.

### Lasso Subphase Result

Lasso satisfies the P14-P22 per-weapon exit criteria:

- It can be selected in the lobby as the secondary weapon.
- It has visible first-person feedback in current gameplay screenshots.
- It can be used offline for a documented `301.155` second GUI playtest without errors.
- Multiplayer behavior is tested through host-authoritative pull movement, zero-damage invariants, score invariants and cleanup.
- Tuning values live in `data/weapons/lasso.tres`.

Final validation:

- `python3 tools/validate_static.py` exited `0`.
- `git diff --check` exited `0`.
- `python3 tools/runtime_smoke.py all --base-port 25070` exited `0`.

Next P14-P22 weapon subphase at the time of this evidence: `Redbull`.

## P14 Redbull Weapon-Specific Pass Evidence

Status: `done` for the `Redbull` subphase of `P14-P22`

Purpose: record Redbull-specific runtime evidence after the Lasso subphase. This marks only the `Redbull` subphase complete; the parent `P14-P22` phase remains `in_progress` until all extended weapons are completed one at a time.

### Five-Minute GUI Redbull Playtest

```text
$ ./run.sh -- --verification-capture=p14-redbull
VERIFICATION_CAPTURE_START p14-redbull
VERIFICATION_CAPTURE_PROGRESS_P14_REDBULL elapsed_sec=60.4 target_sec=300.0 pulses=6 buffs=6
VERIFICATION_CAPTURE_PROGRESS_P14_REDBULL elapsed_sec=120.6 target_sec=300.0 pulses=12 buffs=12
VERIFICATION_CAPTURE_PROGRESS_P14_REDBULL elapsed_sec=180.4 target_sec=300.0 pulses=18 buffs=18
VERIFICATION_CAPTURE_PROGRESS_P14_REDBULL elapsed_sec=240.1 target_sec=300.0 pulses=24 buffs=24
VERIFICATION_CAPTURE_PROGRESS_P14_REDBULL elapsed_sec=300.8 target_sec=300.0 pulses=30 buffs=30
VERIFICATION_PLAYTEST_REPORT_P14_REDBULL { "ok": true, "weapon_id": "redbull", "duration_sec": 301.133, "pulse_count": 30, "pulse_buffs": 30, "view_model_ok": true, "tuning_ok": true, "offline_use": { "used": true, "buff_active": true, "speed_multiplier_before": 1.0, "speed_multiplier_after": 1.5, "charges_before": 2, "charges_after": 1, "cooldown_after": 0.5 }, "capture_setup": { "ok": true, "buff_active": true, "charges_after": 1 } }
VERIFICATION_CAPTURE_PASS p14-redbull
EXIT=0
```

Screenshots:

- `docs/verification/screenshots/p14_redbull_lobby.png`
- `docs/verification/screenshots/p14_redbull_playtest.png`

Visual inspection:

- The lobby screenshot shows `Redbull` selected in the artillery slot with Assault Rifle, Handgun and Knife in the remaining slots.
- The gameplay screenshot shows the deliberate v1 Redbull viewmodel as a visible blue energy-can form in the lower-right frame; it is not a fallback box.
- The HUD shows `Weapon: Redbull`, `Ammo: 1 charges`, active cooldown and `Speed Buff: x1.50`, proving the buff has visible first-person/HUD feedback.
- The buff screenshot still shows readable arena landmarks and route geometry; the view is not inside geometry and the HUD panels do not overlap.
- The score remains `Blue 0 Orange 0 / 20`, which is correct because Redbull is a zero-damage self-buff item rather than a damage weapon.

### Redbull Data And Viewmodel Evidence

| Item | Runtime value |
| --- | --- |
| Weapon resource | `data/weapons/redbull.tres` |
| Viewmodel wrapper | `scenes/weapons/viewmodels/redbull_viewmodel.tscn` |
| Viewmodel type | deliberate v1 procedural placeholder |
| Placeholder reason | local Quaternius baseline has no Redbull asset |
| Runtime vertices | `332` |
| Material override | `true` |
| Slot | `artillery` |
| Fire mode | `self_buff` |
| Hitscan | `false` |
| Projectile | `false` |
| Damage | `0.0` body, `0.0` head |
| Charges | `2` |
| Cooldown | `0.5` seconds |
| Buff duration | `30.0` seconds |
| Alt action | `speed_buff` |
| Speed multiplier | `1.5` |

### Offline Redbull Behavior

The GUI playtest report verified:

- Redbull can be selected in the lobby as the artillery weapon and used in an Offline Dev Match.
- The buff sequence fired `30` timed pulses and all `30` pulses activated the speed buff.
- The deterministic offline use changed movement speed multiplier from `1.0` to `1.5`.
- Redbull consumed one charge per use, changing charges from `2` to `1`.
- Cooldown was applied at `0.5` seconds and the buff duration was initialized to `30.0` seconds.
- Damage, kills and score were intentionally unchanged because Redbull has `0.0` body/head damage.

### Multiplayer Redbull Behavior

The accepted network run used two visible Godot GUI instances on `127.0.0.1:25080`.

Host:

```text
$ ./run.sh -- --verification-capture=p14-redbull-host --p14-port=25080 --p14-timeout-sec=60
VERIFICATION_CAPTURE_START p14-redbull-host
VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=25080 expected_players=2
VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P14_REDBULL_HOST { "ok": true, "weapon_id": "redbull", "uses_fired": 1, "local_buff": { "buff_active": true, "speed_multiplier_before": 1.0, "speed_multiplier_after": 1.5, "charges_before": 2, "charges_after": 1, "cooldown_after": 0.5 }, "charges_before": 2, "charges_after": 1, "charges_consumed": true, "cooldown_after": 0.5, "current_slot_after": &"artillery", "victim_health_before": 100.0, "victim_health_after": 100.0, "health_unchanged": true, "body_damage": 0.0, "head_damage": 0.0, "charges_max": 2, "shot_cooldown_sec": 0.5, "effect_duration_sec": 30.0, "alt_action_type": &"speed_buff", "move_speed_multiplier": 1.5, "score_before": 0, "score_after": 0, "team_counts": { 1: 1, 2: 1 }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-redbull-host
EXIT=0
```

Client:

```text
$ ./run.sh -- --verification-capture=p14-redbull-client --p14-host=127.0.0.1 --p14-port=25080 --p14-timeout-sec=60 --p14-client-hold-sec=12
VERIFICATION_CAPTURE_START p14-redbull-client
VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=127.0.0.1 port=25080
VERIFICATION_CAPTURE_FLOW_P14 client_press_ready
VERIFICATION_CAPTURE_REPORT_P14_REDBULL_CLIENT { "ok": true, "weapon_id": "redbull", "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-redbull-client
EXIT=0
```

Network scope result:

- Host-authoritative Redbull use is tested for a two-player listen-server session.
- The local host buff changed speed multiplier from `1.0` to `1.5`.
- Authoritative Redbull weapon state consumed one charge, changing charges from `2` to `1`, and applied cooldown.
- Victim health stayed `100.0` and score stayed `0`, matching the zero-damage self-buff design.
- Disconnect cleanup passed on both host and client.
- Broader multi-client Redbull movement-balance tuning remains out of scope for this P14 evidence.

Implementation note:

- `WeaponController.fire_active_weapon_for_verification()` now has an opt-in consuming verification path so self-buff weapons can prove charge and cooldown behavior without changing existing non-consuming weapon checks.
- The HUD now displays active speed-buff multiplier and remaining duration while a Redbull buff is active.
- Redbull uses the existing `self_buff` path in `WeaponController`; no new backend service or netcode transport was added.

### Redbull Subphase Result

Redbull satisfies the P14-P22 per-weapon exit criteria:

- It can be selected in the lobby as the artillery weapon.
- It has visible first-person and HUD feedback in current gameplay screenshots.
- It can be used offline for a documented `301.133` second GUI playtest without errors.
- Multiplayer behavior is tested through local speed-buff activation, host-authoritative charge/cooldown consumption, zero-damage invariants, score invariants and cleanup.
- Tuning values live in `data/weapons/redbull.tres`.

Final validation:

- `python3 tools/validate_static.py` exited `0`.
- `git diff --check` exited `0`.
- `python3 tools/runtime_smoke.py all --base-port 25090` exited `0`.

Next P14-P22 weapon subphase: `Portal gun`.

## P14 Portal Gun Weapon-Specific Pass Evidence

Status: `done` for the `Portal gun` subphase of `P14-P22`

Purpose: record Portal gun-specific runtime evidence after the Redbull subphase. This marks the final extended weapon subphase complete; the parent `P14-P22` phase is complete after this evidence.

### Five-Minute GUI Portal Gun Playtest

```text
$ ./run.sh -- --verification-capture=p14-portal-gun
VERIFICATION_CAPTURE_START p14-portal-gun
VERIFICATION_CAPTURE_PROGRESS_P14_PORTAL_GUN elapsed_sec=60.1 target_sec=300.0 pulses=6 portals=6 transports=6
VERIFICATION_CAPTURE_PROGRESS_P14_PORTAL_GUN elapsed_sec=120.9 target_sec=300.0 pulses=12 portals=12 transports=12
VERIFICATION_CAPTURE_PROGRESS_P14_PORTAL_GUN elapsed_sec=180.9 target_sec=300.0 pulses=18 portals=18 transports=18
VERIFICATION_CAPTURE_PROGRESS_P14_PORTAL_GUN elapsed_sec=240.9 target_sec=300.0 pulses=24 portals=24 transports=24
VERIFICATION_CAPTURE_PROGRESS_P14_PORTAL_GUN elapsed_sec=300.9 target_sec=300.0 pulses=30 portals=30 transports=30
VERIFICATION_PLAYTEST_REPORT_P14_PORTAL_GUN { "ok": true, "weapon_id": "portal_gun", "duration_sec": 302.126, "pulse_count": 30, "pulse_portals": 30, "pulse_transports": 30, "view_model_ok": true, "tuning_ok": true, "offline_use": { "used": true, "placed_two_portals": true, "teleported": true, "momentum_preserved": true, "ammo_before": 2, "ammo_after": 0, "ammo_consumed": true }, "capture_setup": { "ok": true, "placed_two_portals": true, "marker_count": 2 } }
VERIFICATION_CAPTURE_PASS p14-portal-gun
EXIT=0
```

Screenshots:

- `docs/verification/screenshots/p14_portal_gun_lobby.png`
- `docs/verification/screenshots/p14_portal_gun_playtest.png`

Visual inspection:

- The lobby screenshot shows `Portal Gun` selected in the secondary slot with Assault Rifle, Knife and Smoke Bomb in the remaining slots.
- The gameplay screenshot shows the deliberate v1 Portal Gun viewmodel in the lower-right frame; it is a recognizable blocky emitter and not a fallback box.
- Blue and orange portal markers are visible on the test wall, and the crosshair/HUD remain readable.
- The HUD shows `Weapon: Portal Gun`, `Ammo: 0 / 0` and an active cooldown after both portal shots.
- Score remains `Blue 0 Orange 0 / 20`, matching the zero-damage Portal gun design.

### Portal Gun Data And Viewmodel Evidence

| Item | Runtime value |
| --- | --- |
| Weapon resource | `data/weapons/portal_gun.tres` |
| Viewmodel wrapper | `scenes/weapons/viewmodels/portal_gun_viewmodel.tscn` |
| Viewmodel type | deliberate v1 procedural placeholder |
| Placeholder reason | local Quaternius baseline has no portal-gun asset |
| Runtime vertices | `356` |
| Material override | `true` |
| Slot | `secondary` |
| Fire mode | `portal` |
| Hitscan | `true` |
| Projectile | `false` |
| Damage | `0.0` body, `0.0` head |
| Magazine | `2` |
| Reserve ammo | `0` |
| Cooldown | `0.35` seconds |
| Max range | `80.0` meters |
| Portal duration | `60.0` seconds |
| Portal radius | `1.1` meters |
| Alt action | `portal` |

### Offline Portal Gun Behavior

The GUI playtest report verified:

- Portal Gun can be selected in the lobby as the secondary weapon and used in an Offline Dev Match.
- The timed playtest fired `30` pulses, placed portal pairs for all `30`, and transported the player for all `30`.
- Deterministic offline use placed two portals, consumed both magazine shots, and left ammo at `0 / 0`.
- Teleport transport preserved velocity through the portal pair.
- Portal placement creates visible blue/orange world markers and first-person firing feedback.
- Damage, kills and score were intentionally unchanged because Portal Gun has `0.0` body/head damage.

### Multiplayer Portal Gun Behavior

The accepted network run used two visible Godot GUI instances on `127.0.0.1:25120`.

Host:

```text
$ ./run.sh -- --verification-capture=p14-portal-gun-host --p14-port=25120 --p14-timeout-sec=60
VERIFICATION_CAPTURE_START p14-portal-gun-host
VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=25120 expected_players=2
VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match
VERIFICATION_CAPTURE_REPORT_P14_PORTAL_GUN_HOST { "ok": true, "weapon_id": "portal_gun", "shots_fired": 2, "local_portal": { "placed_two_portals": true, "teleported": true, "momentum_preserved": true, "ammo_before": 2, "ammo_after": 0, "ammo_consumed": true }, "ammo_before": 2, "ammo_after": 0, "ammo_consumed": true, "cooldown_after": 0.33333333333333, "victim_health_before": 100.0, "victim_health_after": 100.0, "health_unchanged": true, "body_damage": 0.0, "head_damage": 0.0, "magazine_size": 2, "reserve_ammo_max": 0, "shot_cooldown_sec": 0.35, "max_range_m": 80.0, "effect_duration_sec": 60.0, "effect_radius_m": 1.1, "alt_action_type": &"portal", "score_before": 0, "score_after": 0, "team_counts": { 1: 1, 2: 1 }, "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-portal-gun-host
EXIT=0
```

Client:

```text
$ ./run.sh -- --verification-capture=p14-portal-gun-client --p14-host=127.0.0.1 --p14-port=25120 --p14-timeout-sec=60 --p14-client-hold-sec=12
VERIFICATION_CAPTURE_START p14-portal-gun-client
VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=127.0.0.1 port=25120
VERIFICATION_CAPTURE_FLOW_P14 client_press_ready
VERIFICATION_CAPTURE_REPORT_P14_PORTAL_GUN_CLIENT { "ok": true, "weapon_id": "portal_gun", "disconnect_cleanup": { "ok": true, "network_active": false, "remote_proxies_after_close": 0 } }
VERIFICATION_CAPTURE_PASS p14-portal-gun-client
EXIT=0
```

Network scope result:

- Host-authoritative Portal Gun use is tested for a two-player listen-server session.
- Authoritative Portal Gun weapon state consumed both shots, changing ammo from `2` to `0`, and applied cooldown.
- The local host portal sequence placed two portals, transported the player and preserved momentum.
- Victim health stayed `100.0` and score stayed `0`, matching the zero-damage portal utility design.
- Disconnect cleanup passed on both host and client.
- Broader cross-client portal traversal replication remains out of scope for this P14 evidence; v1 network scope verifies safe authoritative ammo/cooldown and zero damage/score behavior.

Implementation note:

- Portal markers now use metadata-backed identity and unique names so repeated portal replacement cannot be confused with stale queued marker nodes.
- Portal transport has a short cooldown and preserves the incoming velocity vector while moving the body to the paired portal exit.
- Authoritative `portal` and `self_buff` fires now send a snapshot after ammo/cooldown consumption so network weapon state is synchronized for utility weapons.
- No new backend service or netcode transport was added.

### Portal Gun Subphase Result

Portal Gun satisfies the P14-P22 per-weapon exit criteria:

- It can be selected in the lobby as the secondary weapon.
- It has visible first-person and world portal feedback in current gameplay screenshots.
- It can be used offline for a documented `302.126` second GUI playtest without errors.
- Multiplayer behavior is tested through host-authoritative ammo/cooldown consumption, zero-damage invariants, score invariants and cleanup.
- Tuning values live in `data/weapons/portal_gun.tres`.

Final validation:

- `python3 tools/validate_static.py` exited `0`.
- `git diff --check` exited `0`.
- `python3 tools/runtime_smoke.py all --base-port 25130` exited `0`.

P14-P22 result: all extended weapon subphases are `done`.

## P23 City Asset Level Designer Tool

Status: `done`

Purpose: record the City Asset Level Designer tooling pass for `arena_downtown_01` without changing gameplay blockout, spawns, kill volumes, player, match, HUD or weapon nodes.

### Tooling Summary

- Editor tool: `addons/city_level_designer/` enabled in `project.godot` as the `City Asset Level Designer` dock.
- Catalog: `data/maps/downtown_city_asset_catalog.json` with `29` curated Downtown City MegaKit entries.
- Required categories covered: `building`, `facade`, `street`, `trim`, `prop`, `landmark`, `backdrop`.
- Placement script: `scripts/maps/downtown_city_asset_instance.gd` stores provenance and loads via `ResourceLoader.exists(path, "PackedScene")`, with explicit raw GLTF helper fallback.
- Proof dressing: `scenes/maps/art/p23_city_asset_dressing.tscn` with `17` persisted P23 placements.
- Runtime integration: `scripts/maps/art/arena_downtown_01_art.gd` instances the proof dressing as a child of `ArenaDowntown01ArtRoot`.

### Designer Testlog

- Opened the P23 tool UI and verified the category filter, selected asset label, catalog list, map layer dropdown, snap presets `0.5m`/`1m`/`5m`, and rotation presets `15 deg`/`90 deg` are present.
- Verified tool actions are exposed through the dock: `Preview Ghost`, `Place`, `Apply Transform`, `Duplicate`, `Delete`, and `Validate`.
- Verified undo/redo integration is implemented through `EditorUndoRedoManager` for place, transform, duplicate and delete.
- Verified persisted placements retain stable node names like `P23_decal_crosswalk_wide_001` and remain parented under spec layers.
- Reopened through Godot editor load; the tool initialized without `SCRIPT ERROR` or `ERROR`. Remaining editor output is non-fatal vendor texture case-sensitivity warnings from Downtown City MegaKit.

### Representative Proof Placements

| asset_id | source_path | map_layer | purpose |
| --- | --- | --- | --- |
| `decal_crosswalk_wide` | `res://assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Decal_Crosswalk_Wide.gltf` | `GameplayCore` | Spawn-side street readability and scale reference |
| `trim_wall_guard` | `res://assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Trim_Wall_Guard.gltf` | `TraversalRoutes` | Visual trim along high traversal routes |
| `prop_ac_unit` | `res://assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Prop_ACUnit.gltf` | `CombatCover` | Rooftop/high-route visual cover dressing |
| `prop_bollard` | `res://assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Prop_Bollard.gltf` | `CombatCover` | Spawn-side small prop scale proof |
| `building_large_2` | `res://assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Building_Large_2.gltf` | `SkylineBackdrop` | Skyline massing around the arena perimeter |

### Validation Commands

```text
$ ./run.sh --headless --editor --quit
EXIT=0
No SCRIPT ERROR or ERROR; only vendor texture case-sensitivity warnings.

$ ./run.sh --script res://tools/capture_p23_editor_palette.gd
P23_EDITOR_PALETTE_CAPTURED res://docs/verification/screenshots/p23_level_designer_editor_palette.png
EXIT=0

$ python3 tools/validate_p23_city_designer.py
P23 validation passed: catalog_entries=29 proof_scene=scenes/maps/art/p23_city_asset_dressing.tscn
EXIT=0

$ ./run.sh --rendering-driver opengl3 -- --verification-capture=p23
VERIFICATION_CAPTURE_PASS p23
summary: ok=true, proof_placement_count=17, stable_name_count=17, missing_sources=[], source_pack_paths=[], invalid_transforms=[], routes blue_wallrun_to_high/orange_wallrun_to_high completed
EXIT=0

$ python3 tools/validate_static.py
static validation passed
EXIT=0
```

### Screenshots

- `docs/verification/screenshots/p23_level_designer_editor_palette.png`
- `docs/verification/screenshots/p23_level_designer_game_view.png`
- `docs/verification/screenshots/p23_level_designer_traversal_check.png`

### Visual QA Observations

`p23_level_designer_editor_palette.png`:

- The City Asset Level Designer dock shows a selected asset, `building_large_2`, with its Downtown City MegaKit GLTF source path.
- The palette list is populated and categorized, including visible `building` and `facade` rows.
- The layer dropdown, move/rotate/scale controls, snap preset, rotation preset and all required action buttons are visible.

`p23_level_designer_game_view.png`:

- The running game viewport shows new city buildings/facades around the arena perimeter and mid-map.
- Street/crosswalk dressing and small props are visible at gameplay scale without covering the HUD or weapon viewmodel.
- The player spawn view remains readable; no placed asset visibly blocks immediate spawn view or the central sightline.

`p23_level_designer_traversal_check.png`:

- High-route visual trim and nearby building/facade dressing are visible around the traversal path.
- Blue/orange route markers and platforms remain visible, so the proof dressing does not hide the tested traversal route.
- The check view shows street decals and cover props near the route, but no placed asset visibly blocks the wallrun/high-route corridor.

### P23 Result

P23 satisfies its exit criteria: the tool is a Godot editor dock, the catalog has more than `25` valid third-party Downtown City MegaKit entries, proof placements are persisted under project-owned scenes and allowed map layers, no `source_packs` paths are used, and the real game viewport shows the proof dressing without blocking the verified blue/orange traversal routes.

## Rooftop Fog Hazard Iteration

Date: 2026-05-28

- Added `data/maps/arena_downtown_01_rooftop_config.tres` for rooftop fog height, low-ground kill height, visual mist settings and spawn clearance.
- `ArenaDowntown01Art` now exposes runtime rooftop spawns above solid city-building collision proxies, with a high fallback set if the editable scene has no suitable buildings.
- `GameRoot` enables height fog and kills players immediately once they reach low ground at the bottom of the map, so the map reads as a rooftop-only arena without making the fog layer itself lethal.
- User reopened the visual gate because the engine-only height fog still read as no fog in gameplay. `GameRoot` now also creates a low-ground fog sea from config-driven runtime mesh layers under roof height, while engine fog is tuned lower with a steeper height falloff so rooftop sightlines stay readable.

Validation:

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0

$ ./run.sh --headless --script res://tools/validate_runtime_scene_contract.gd
RUNTIME_SCENE_CONTRACT_PASS no_generated_visual_artifacts=true
EXIT=0

$ ./run.sh --headless --script res://tools/validate_rooftop_map_contract.gd
ROOFTOP_MAP_CONTRACT_PASS spawns=8 team_counts={ 1: 4, 2: 4 } ground_kill_height=0.25 low_ground_test_y=-6.76 fog_density=0.0050 fog_height=0.70 fog_height_density=10.00 fog_visual_layers=8 fog_enabled=true
EXIT=0

$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0

$ ./run.sh --script res://tools/capture_normal_runtime_game_view.gd
NORMAL_RUNTIME_CAPTURED res://docs/verification/screenshots/normal_runtime_no_generated_artifacts.png
EXIT=0

$ ./run.sh --script res://tools/capture_rooftop_fog_view.gd
ROOFTOP_FOG_CAPTURED res://docs/verification/screenshots/rooftop_low_ground_fog.png
EXIT=0
```

Visual QA for `docs/verification/screenshots/normal_runtime_no_generated_artifacts.png`:

- The player starts grounded on a rooftop surface, not at street level.
- Roof-height sightlines are readable: the roof surface, nearby facades, HUD and assault-rifle viewmodel are visible without the whole frame turning white.
- Distant lower buildings retain a blue-gray atmospheric fade, but the view is no longer relying on per-building white paint or masks.
- The HUD and assault-rifle viewmodel remain readable, with no UI overlap introduced by the fog pass.

Visual QA for `docs/verification/screenshots/rooftop_low_ground_fog.png`:

- The camera looks down between tall buildings and the actual street/bottom plane is hidden by a continuous blue-gray fog sea.
- Building sides remain their normal materials above the fog surface; the fog is a shared low-ground layer, not white paint applied to individual buildings.
- The fog is strongest below roof height and does not cover the top ledges or erase the readable rooftop route geometry.

## Taser Gun Secondary

Date: 2026-05-28

- Added `Taser Gun` as a selectable secondary weapon.
- Tuning lives in `data/weapons/taser_gun.tres`: `effect_duration_sec = 2.0`, `shot_cooldown_sec = 5.0`, `fire_mode = utility`, `alt_action_type = stun`.
- Runtime stun is applied through `apply_stun(duration)` on player/dummy targets; stunned players cannot move, look or fire until the timer expires.
- Network state carries `stun_remaining_sec` so host-authoritative taser hits can freeze a victim and reject movement snapshots while stunned.

Validation:

```text
$ python3 tools/validate_static.py
static validation passed
EXIT=0

$ ./run.sh --headless --script res://tools/validate_taser_gun.gd
TASER_GUN_PASS stun=1.95 cooldown=4.95 health_before=100.0 health_after=100.0
EXIT=0

$ python3 tools/runtime_smoke.py weapons
SMOKE_PASS weapons: lobby options and all weapon resources fired without runtime errors
EXIT=0

$ python3 tools/runtime_smoke.py offline
SMOKE_PASS offline: offline game scene, movement/combat/HUD/match/art smoke passed
EXIT=0
```

Visual QA for `docs/verification/screenshots/taser_gun_viewmodel.png`:

- The HUD shows `Slot: secondary` and `Weapon: Taser Gun`, so the new weapon is selectable in the expected slot.
- The taser placeholder is visible in the lower-right viewmodel area with a dark body and bright cyan top/probe accent.
- The viewmodel does not overlap the crosshair, score HUD or health/ammo panel.
