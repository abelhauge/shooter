# FPS Technical Spec

Status: v1 locked  
Date: 2026-05-24  
Depends on: `docs/fps-design-brief.md`

## Formål

Dette dokument er den tekniske source of truth for v1. Det beskriver den konkrete Godot-struktur, data-modeller, netcode-ansvar, movement-defaults og asset-shortlist, så en agent kan implementere spillet uden at opfinde centrale systemvalg selv.

## Dokumenthierarki

Læs og følg dokumenterne i denne rækkefølge:

1. `docs/fps-design-brief.md`
2. `docs/fps-technical-spec.md`
3. `docs/fps-development-plan.md`

Regel ved konflikt:

- `fps-design-brief.md` vinder på produktregler og gameplay-beslutninger
- `fps-technical-spec.md` vinder på arkitektur, datastrukturer og netcode-model
- `fps-development-plan.md` vinder på fase-rækkefølge, scope-gates og konkret task-opdeling

## Projektkonventioner

- Engine: `Godot 4`
- Sprog: `GDScript`
- Runtime-perspektiv: `first-person`
- Fysik-tick: `60 Hz`
- Enhedsskala: `1 Godot unit = 1 meter`
- Standard sceneformat: `.tscn`
- Standard dataformat: `Resource`-baserede `.tres`
- Standard launch-interface: `./run.sh` fra repo-root
- Ingen eksterne backend-services i v1
- Ingen alternative engine-spor i repoet

## Root launch-kontrakt

V1 skal altid kunne startes fra repo-root med:

```bash
./run.sh
```

På Windows skal samme kontrakt findes som:

```bat
run.cmd
```

Regler:

- `run.sh` skal ligge i repo-root
- `run.cmd` skal ligge i repo-root og være Windows-native pendant til `run.sh`
- fremtidige agenter må ikke erstatte denne kontrakt med editor-only kørsel
- scriptet må gerne udvides over tid, men kommandoerne skal forblive `./run.sh` og `run.cmd`
- scriptet skal starte Godot-projektet fra repo-root uden at brugeren først skal vælge en scene manuelt
- launch-scriptet må ikke committe, pull'e eller pushe; almindelig game/editor-start skal være uden git-sideeffekter
- publicering til GitHub skal ske eksplicit med `./udgiv.sh`, som auto-stager, committer, puller og pusher den aktive branch
- `install.sh` og `install.cmd` skal kunne verificere lokale dependencies og bootstrappe Godot-import/cache på henholdsvis Unix/macOS/Linux og Windows
- desktop runtime skal bruge Godots `Forward+` renderer; paa macOS betyder det Metal-rendering i normale GUI-runs
- macOS-export skal beholde GPU-komprimerede texture formats slået til: `texture_format/etc2_astc=true` for Apple Silicon/universal exports og `texture_format/s3tc_bptc=true` som desktop fallback; `project.godot` skal importere begge VRAM compression families
- GitHub macOS releases skal bygges paa en macOS runner og mindst ad-hoc signes foer upload til itch; fuld friktionsfri Mac-download kraever Apple Developer ID signing og notarization

## Anbefalet Godot-projektstruktur

```text
/project.godot
/run.sh
/run.cmd
/install.sh
/install.cmd
/AGENTS.md
/docs/
  fps-design-brief.md
  fps-technical-spec.md
  fps-development-plan.md
/scenes/
  app/
    app_root.tscn
    scene_router.tscn
  frontend/
    main_menu.tscn
    lobby_menu.tscn
    results_menu.tscn
  game/
    game_root.tscn
    match_director.tscn
  player/
    player_controller.tscn
    remote_player_proxy.tscn
    player_avatar.tscn
  weapons/
    weapon_controller.tscn
    projectiles/
      smoke_bomb_projectile.tscn
  maps/
    blockout/
      movement_test_course.tscn
      arena_downtown_01_blockout.tscn
    art/
      arena_downtown_01_art.tscn
    props/
      container_a.tscn
      crane_platform_a.tscn
      catwalk_a.tscn
      spawn_room_a.tscn
  ui/
    hud.tscn
    crosshair.tscn
    debug_hud.tscn
    scoreboard.tscn
  fx/
    impact_spark.tscn
    smoke_volume.tscn
  debug/
    movement_marker.tscn
    spawn_debug_marker.tscn
/scripts/
  app/
    app_root.gd
    scene_router.gd
  game/
    match_director.gd
    match_rules.gd
    game_events.gd
  network/
    network_session.gd
    network_constants.gd
    state_snapshot.gd
  player/
    player_controller.gd
    player_input_state.gd
    player_runtime_state.gd
    health_component.gd
    movement_config.gd
  weapons/
    weapon_definition.gd
    weapon_runtime_state.gd
    weapon_controller.gd
    loadout_definition.gd
    damage_event.gd
  maps/
    spawn_point.gd
    map_metadata.gd
  ui/
    hud_controller.gd
    debug_hud_controller.gd
  data/
    resource_ids.gd
/data/
  movement/
    movement_default.tres
  match/
    team_skirmish_v1.tres
  loadouts/
    default_v1_loadout.tres
  weapons/
    assault_rifle.tres
    handgun.tres
    knife.tres
    smoke_bomb.tres
    shotgun.tres
    sniper.tres
    grenade.tres
    flamethrower.tres
    lasso.tres
    taser_gun.tres
    redbull.tres
    portal_gun.tres
/assets/
  README.md
  source_packs/
    quaternius/
      animated_guns_pack/
      downtown_city_megakit/
      modular_streets_pack/
      ultimate_guns_pack/
      ultimate_modular_men_pack/
  third_party/
    quaternius/
      animated_guns_pack/
      downtown_city_megakit/
      ultimate_modular_men_pack/
  environment/
  characters/
  weapons/
  materials/
  hdri/
  audio/
```

## Lokal asset staging i repoet

Status pr. `2026-05-24`:

- Den aktuelle v1-baseline er reduceret til de import-klare/runtime-noedvendige asset-dele
- Raa vendor-downloads, source archives, Blender-kilder, preview-filer og screenshots skal ikke committes
- `assets/third_party/quaternius/` er den import-klare mirror, som Godot-arbejde skal tage udgangspunkt i
- Gameplay og data-modeller skal forblive asset-agnostiske, saa bedre assets senere kan erstatte art-laget uden at aendre mekanikkerne

Aktiv lokal baseline:

- Miljoe: `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)`
- Karakterer: `assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF`
- Vaaben: `assets/third_party/quaternius/animated_guns_pack/FBX`

Valgfrie supplement-reserver:

- `modular_streets_pack` er reserveret til senere miljoesupplement, men er ikke en kickoff-afhaengighed for v1
- `ultimate_guns_pack` er reservebibliotek til senere vaabenudvidelser og er ikke en kickoff-afhaengighed for v1

Agentregler:

- Importer vendor-assets fra `assets/third_party/quaternius/`, ikke fra source archives
- Rediger ikke originale vendor-filer direkte
- Lav Godot-specifikke scenes, material-overrides og kuraterede prefabs uden for vendor-mapperne
- Start ikke ny asset-jagt, mens den lokale baseline er tilstraekkelig til den aktuelle fase
- Runtime scripts maa ikke antage, at raw `.gltf`/`.fbx` vendor-filer kan loades som `PackedScene`; brug `ResourceLoader.exists(path, "PackedScene")` og fallback placeholders indtil assets er kurateret/importeret som Godot scenes.
- For P03 asset proof maa art-laget bruge `GLTFDocument` som eksplicit fallback til at importere godkendte `assets/third_party/quaternius/.../glTF (Godot)` filer i runtime. Senere dressing/viewmodel-faser boer stadig flytte gentagne produktionsassets mod kuraterede Godot-scenes/wrappers.

## Sceneansvar

### `app_root.tscn`

Ansvar:

- starte spillet
- vælge menu eller kamp-scene
- holde referencer til globale UI-lag
- holde `NetworkSession`

Må ikke:

- indeholde gameplay-logik
- simulere movement eller våben

### `game_root.tscn`

Ansvar:

- eje den aktive kamp
- samle map, players, projectiles, FX, HUD og `MatchDirector`

Anbefalet node-hierarki:

```text
GameRoot
  WorldEnvironment
  MapRoot
  SpawnPoints
  PlayersRoot
  ProjectilesRoot
  EffectsRoot
  MatchDirector
  HudCanvasLayer
  DebugCanvasLayer
```

### `player_controller.tscn`

Ansvar:

- lokal eller host-simuleret spillerkrop
- movement state machine
- health component
- weapon controller
- camera rig og first-person viewmodel-root

Anbefalet node-hierarki:

```text
PlayerController (CharacterBody3D)
  CollisionShape3D
  HeadPivot
    Camera3D
    ViewModelRoot
    MuzzleMarker
  GroundCheck
  WallCheckLeft
  WallCheckRight
  CeilingCheck
  HealthComponent
  WeaponController
  AudioRoot
```

### `remote_player_proxy.tscn`

Ansvar:

- vise andre spillere over netværket
- bruge simplere visualisering end den lokale first-person spiller

Må ikke:

- eje authoritative movement
- selv afgøre damage

### `arena_downtown_01_blockout.tscn`

Ansvar:

- gameplay-layout
- traversal-linjer
- spawn points
- kill volumes
- wallrun-egnede flader

Må ikke:

- være afhængig af final art

### `arena_downtown_01_art.tscn`

Ansvar:

- visuel replacement oven på blockout-strukturen
- må gerne instansiere blockout-scenen og erstatte udvalgte child roots gradvist
- skal have editor-preview, så `./run.sh --editor` viser arenaens blockout, city dressing, P23 placements og lys uden først at starte spillet
- editor-preview må ikke gemme genererede runtime-child nodes ind i scenefilen

## Mapstruktur for v1

## Arenaformat

- Navn: `arena_downtown_01`
- Type: kompakt urban-industrial arena
- Target footprint: ca. `85m x 65m`
- Maks gameplay-højde: ca. `28m`
- Primært kampareal: `55m x 40m`
- Matchformat designet omkring: `1v1`, men skalerbart til `2v2` og `3v3`; runtime må ikke have en hardcoded 6-player cap

## Maplag

Mapscenen skal opdeles i disse logiske lag:

1. `GameplayCore`
2. `TraversalRoutes`
3. `CombatCover`
4. `SkylineBackdrop`
5. `SpawnSpaces`
6. `HazardsAndKillVolumes`
7. `LightingAndAtmosphere`

## Konkrete mapregler

- Spawns skal ligge i halvbeskyttede lommer, ikke i fuld line-of-sight
- Midten af mappet skal have mindst to vertikale muligheder
- Der skal være mindst to wallrun-flader, som faktisk giver en traversal-fordel
- Ingen enkelt sniper-linje må dominere mere end ca. `30m` uden flank-route
- Mindst én høj traversal-rute skal belønne slide-jump eller wallrun
- Containers og kranplatforme må bygges som simple custom props, hvis asset-pakkerne ikke dækker dem godt nok
- `Downtown City MegaKit` bruges primært til bystruktur og skyline, ikke som tvang til at hele arenaen er en almindelig bygade

## Spawn-struktur

Hver spawn skal være en instans af `spawn_point.gd` med:

- `team_id`
- `spawn_group`
- `yaw_degrees`
- `is_enabled`

V1-regel:

- `Blue` og `Orange` har hver mindst `4` mulige spawn points i arenaen
- Host vælger spawn blandt aktive points med simpelt sikkerhedstjek mod nærmeste fjende

## Data-model

V1 skal bruge `Resource`-baserede definitioner til statiske data og runtime-state-klasser eller dictionaries til live-state.

## `WeaponDefinition`

Fil:

- `scripts/weapons/weapon_definition.gd`

Instanser:

- `data/weapons/*.tres`

Felter:

- `weapon_id: StringName`
- `slot_type: StringName`
- `display_name: String`
- `fire_mode: StringName`
- `is_hitscan: bool`
- `uses_projectile: bool`
- `supports_hold_fire: bool`
- `magazine_size: int`
- `reserve_ammo_max: int`
- `reload_time_sec: float`
- `shot_cooldown_sec: float`
- `pellets_per_shot: int`
- `body_damage: float`
- `head_damage: float`
- `spread_degrees: float`
- `max_range_m: float`
- `projectile_scene_path: String`
- `projectile_speed_mps: float`
- `projectile_gravity_scale: float`
- `charges_max: int`
- `effect_duration_sec: float`
- `effect_radius_m: float`
- `alt_action_type: StringName`
- `move_speed_multiplier: float`
- `propulsion_force: float`
- `scope_enabled: bool`
- `scope_fov: float`
- `scope_transition_sec: float`
- `scope_sensitivity_multiplier: float`
- `scope_viewmodel_position: Vector3`
- `scope_viewmodel_rotation_degrees: Vector3`

V1-regel:

- Alle våbental må ligge i `WeaponDefinition` resources
- Ingen våbenstats må hardcodes i `weapon_controller.gd`
- Sniper ADS-tuning ligger på `sniper.tres`: højreklik holdes for scope/zoom, venstreklik affyrer skuddet, normalt crosshair skjules under scope-overlayet, og mouse sensitivity sænkes mens scoped.

## `WeaponRuntimeState`

Felter:

- `weapon_id`
- `ammo_in_mag`
- `reserve_ammo`
- `charges_current`
- `is_reloading`
- `reload_elapsed_sec`
- `cooldown_remaining_sec`
- `is_trigger_held`

Bemærk:

- Runtime-state resettes ved kampstart
- Ammo og charges resettes ved respawn i v1

## `LoadoutDefinition`

Fil:

- `scripts/weapons/loadout_definition.gd`

Felter:

- `primary_weapon_id`
- `secondary_weapon_id`
- `melee_weapon_id`
- `artillery_weapon_id`

V1-regel:

- Loadout vælges i lobby eller pre-match
- Loadout er låst under kampen

## `HealthComponent`

Felter:

- `max_health: float`
- `current_health: float`
- `is_alive: bool`
- `spawn_protection_remaining_sec: float`
- `last_damage_source_peer_id: int`
- `last_damage_weapon_id: StringName`

V1-regel:

- `max_health = 100`
- Død indtræffer ved `current_health <= 0`

## `MatchRulesDefinition`

Fil:

- `scripts/game/match_rules.gd`

Instans:

- `data/match/team_skirmish_v1.tres`

Felter:

- `mode_id`
- `team_count`
- `players_per_team`
- `respawn_delay_sec`
- `spawn_protection_sec`
- `time_limit_sec`
- `score_limit`
- `friendly_fire`
- `allow_join_mid_match`
- `allow_spectators`
- `allow_loadout_changes_mid_match`

V1-værdier:

- `mode_id = team_skirmish`
- `team_count = 2`
- `players_per_team = 0`, hvor `0` betyder ingen hardcoded holdcap; hold balanceres løbende mellem Blue og Orange
- `respawn_delay_sec = 3.0`
- `spawn_protection_sec = 1.0`
- `time_limit_sec = 480.0`
- `score_limit = 20`
- `friendly_fire = false`
- `allow_join_mid_match = true`
- `allow_spectators = false`
- `allow_loadout_changes_mid_match = false`

## `PlayerRuntimeState`

Felter:

- `peer_id`
- `player_name`
- `team_id`
- `selected_loadout_id`
- `is_ready`
- `is_alive`
- `kills`
- `deaths`
- `score`
- `current_slot`
- `position`
- `velocity`
- `yaw`
- `pitch`

## V1 våbendefinitioner

Disse fire skal være klar først:

### `assault_rifle.tres`

- `weapon_id = assault_rifle`
- `slot_type = primary`
- `fire_mode = auto`
- `is_hitscan = true`
- `magazine_size = 30`
- `reserve_ammo_max = 90`
- `reload_time_sec = 3.2`
- `shot_cooldown_sec = 0.10`
- `pellets_per_shot = 1`
- `body_damage = 10`
- `head_damage = 14`
- `spread_degrees = 1.0`
- `max_range_m = 120`

### `handgun.tres`

- `weapon_id = handgun`
- `slot_type = secondary`
- `fire_mode = semi`
- `is_hitscan = true`
- `magazine_size = 13`
- `reserve_ammo_max = 39`
- `reload_time_sec = 2.6`
- `shot_cooldown_sec = 0.22`
- `body_damage = 16`
- `head_damage = 24`
- `spread_degrees = 0.7`
- `max_range_m = 90`

### `taser_gun.tres`

- `weapon_id = taser_gun`
- `slot_type = secondary`
- `fire_mode = utility`
- `is_hitscan = true`
- `magazine_size = 0`
- `reserve_ammo_max = 0`
- `shot_cooldown_sec = 5.0`
- `body_damage = 0`
- `head_damage = 0`
- `spread_degrees = 0.15`
- `max_range_m = 24`
- `effect_duration_sec = 2.0`
- `alt_action_type = stun`

### `knife.tres`

- `weapon_id = knife`
- `slot_type = melee`
- `fire_mode = melee`
- `magazine_size = 0`
- `reserve_ammo_max = 0`
- `reload_time_sec = 0.0`
- `shot_cooldown_sec = 3.0`
- `body_damage = 100`
- `head_damage = 100`
- `max_range_m = 2.2`

### `smoke_bomb.tres`

- `weapon_id = smoke_bomb`
- `slot_type = artillery`
- `fire_mode = throwable`
- `uses_projectile = true`
- `charges_max = 3`
- `shot_cooldown_sec = 0.75`
- `projectile_speed_mps = 11.0`
- `projectile_gravity_scale = 1.0`
- `effect_duration_sec = 14.0`
- `effect_radius_m = 4.0`

## Netcode-model v1

V1 skal bruge en enkel listen-server-model uden backend.

## Topologi

- Host er `peer 1`
- Host spiller også som normal spiller
- Klienter forbinder via IP eller LAN
- Host er authoritative for kampregler og skade

## LAN discovery

V1 må bruge en lille lokal discovery-kanal til at finde private LAN-hosts uden backend:

- Hostens ENet listen-server forbliver den autoritative matchforbindelse.
- Mens hosten står i lobby, annonceres matchen via UDP multicast på en separat discovery-port.
- Discovery-payload må kun indeholde lobby metadata som protocol version, host name, ENet-port, advertised capacity og lobby state.
- Discovery må fortsætte, når matchen starter, fordi v1 tillader join mid-match i private kampe.
- Manual `Join By IP` skal bevares som fallback, hvis multicast eller lokal firewall blokerer discovery.
- Discovery må ikke bruge ekstern backend, relay, NAT traversal eller central matchmaking.

## Multiplayer capacity

- Spillet må ikke begrænse private pre-match lobbies til 6 spillere.
- Host-knappen starter en hostet kamp med det samme; der er ikke længere et obligatorisk ready/start-lobbytrin.
- Nye peers der forbinder efter kampstart får en targeted `start_network_match` RPC, loader `GameRoot`, sender scene-ready tilbage til hosten og får derefter respawn/snapshot.
- Nye peers må ikke sendes ind i kampen, før hostens egen `GameRoot` er scene-ready; peers der forbinder under host-load holdes pending, og LAN discovery viser først hosten som `in_game`, når hosten er klar.
- `NetworkConstants.MAX_ENET_CLIENTS` følger Godots ENet-loft på `4095` samtidige klienter; `MAX_PLAYERS` inkluderer hosten og er derfor `4096`.
- Den reelle praktiske grænse er hostens maskine, netværk, map/spawn-readability og performance, ikke en 3v3-regel i gameplay-data.
- P13 3v3 er fortsat en regressionstest for seks instanser, men den må ikke bruges som runtime-cap.

## Simulation

- Physics tick: `60 Hz`
- Client input snapshot sendes til host ved `20 Hz`
- Host state snapshot sendes til klienter ved `15 Hz`
- Interpolationsbuffer for remote spillere: `100 ms`

## Host-authoritative systemer

Host afgør altid:

- kampfase
- ready-state
- team assignment
- spawn-valg
- respawn-timer
- health
- damage
- death
- score
- ammo
- charges
- reload completion
- aktive cooldowns
- hitscan-resultater
- projectile spawn og impact
- smoke-volume lifetime
- kampslutning

## Client-lokal visning

Klienten må vise eller forudsige lokalt:

- mouse look
- local camera shake
- local head bob
- viewmodel animation
- muzzle flash
- crosshair feedback
- footstep audio
- predikeret lokal movement
- predikeret våbenskift UI

V1-regel:

- Klienten må aldrig selv afgøre damage eller kill

## Remote spiller-visning

Andre spillere vises som interpolerede proxies.

Proxyen viser:

- position
- yaw
- active slot
- alive/dead
- simpel movement-state hvis nødvendigt

Proxyen må ikke:

- køre fuld autoritativ movement-simulation
- lokalt opfinde hits

## Input-model over netværk

Klienten sender en `PlayerInputState` med:

- `input_sequence`
- `move_x`
- `move_z`
- `jump_pressed`
- `jump_held`
- `slide_pressed`
- `fire_pressed`
- `fire_held`
- `alt_fire_pressed`
- `reload_pressed`
- `slot_select`
- `yaw`
- `pitch`

Regel:

- Knapper som kun er "pressed this frame" nulstilles efter afsendelse
- Hold-input som `fire_held` og `jump_held` bevares så længe knappen holdes nede

## Snapshot-model

Host sender en `StateSnapshot` med:

- `server_tick`
- `match_phase`
- `remaining_time_sec`
- `blue_score`
- `orange_score`
- `player_states[]`
- `projectile_states[]`
- `active_smoke_volumes[]`

## Korrektion for lokal spiller

- Lokal klient må simulere movement med samme movement-config som host
- Når host sender authoritative position, sammenlignes fejl
- Hvis afvigelse er mindre end `0.35m`, glattes korrektionen over `0.1s`
- Hvis afvigelse er større end `0.35m`, snaps spilleren til host-position

## Reliability-regler

Brug reliable RPC til:

- host/create/join
- ready-state
- loadout confirm
- match start
- match end
- respawn events

Brug unreliable RPC til:

- input snapshots
- state snapshots
- remote transform-opdateringer

## Bevidst fravalg i v1

V1 skal ikke forsøge at bygge:

- rollback netcode
- lag compensation rewind
- server rewind hit validation
- NAT traversal
- relay service
- central matchmaking
- join-in-progress

## Movement default-tal

Alle movement-tal skal ligge i `data/movement/movement_default.tres`.

## Krops- og kameramål

- capsule radius: `0.35`
- capsule height: `1.8`
- eye height: `1.62`
- step offset target: `0.35`

## Grundbevægelse

- ground move speed: `9.5 m/s`
- ground acceleration: `28.0`
- ground deceleration: `22.0`
- ground friction: `8.0`
- air acceleration: `9.0`
- air control max speed contribution: `2.5 m/s`
- gravity: `24.0 m/s²`
- terminal fall speed: `40.0 m/s`

## Jump

- jump velocity: `8.75 m/s`
- coyote time: `0.12 s`
- jump buffer: `0.12 s`
- landing grace before re-slide: `0.08 s`

## Slide

- slide min entry speed: `7.0 m/s`
- slide start boost: `2.25 m/s`
- slide max duration: `1.15 s`
- slide friction: `3.25`
- slide steering factor: `0.35`
- slide jump horizontal bonus multiplier: `1.10`
- target max flat slide distance: `11.0 m`

## Wallrun

- wallrun min speed: `7.5 m/s`
- wallrun max duration: `1.2 s`
- wallrun gravity multiplier: `0.35`
- wall stick force: `6.0`
- wall jump vertical velocity: `8.25 m/s`
- wall jump lateral push: `5.5 m/s`
- wall reattach lockout after jump: `0.25 s`

## Smoke relation

- standing smoke throw range target: `11.0 m`
- relation lock: max flat slide distance og standing smoke throw range skal føles omtrent ens
- momentum må øge smoke-rækkevidde, men ikke slide max duration

## Movement state machine

V1-state-machine:

- `grounded`
- `airborne`
- `sliding`
- `wallrunning`
- `dead`

Regler:

- `dead` afbryder alle andre movement-states
- `sliding` kræver ground contact ved start
- `wallrunning` kræver airborne + gyldig væg + min speed
- jump fra `sliding` går til `airborne`
- jump fra `wallrunning` går til `airborne` med wall-jump bonus

## Gratis asset-shortlist for første art pass

## Låst v1-familie

Miljø, karakterer og våben skal føles som samme spil. V1 bruger derfor én primær gratis familie og få bevidste supplementer.

### Miljøbase

- `Downtown City MegaKit`
  - brug: skyline, bygninger, facader, gadeelementer, urban struktur
  - rolle: definere den overordnede grounded city-stil
  - link: `https://quaternius.com/packs/downtowncitymegakit.html`
  - lokal importkilde: `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)`

- `Modular Streets Pack`
  - brug: vejsegmenter, ramper, simple byflader hvis downtown-pakken mangler en simpel modulær brik
  - rolle: sekundært supplement, ikke hovedstil
  - link: `https://quaternius.com/packs/modularstreets.html`
  - lokal status: valgfri reserve, ikke del af mandatory kickoff-import

### Karakterbase

- `Ultimate Modular Men Pack`
  - brug: netværksavatarer og tredjepersons fjende/allieret-visuals
  - rolle: grounded character silhouettes
  - link: `https://quaternius.com/packs/ultimatemodularcharacters.html`
  - lokal importkilde: `assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF`
  - runtime-kuratering: P06 loader godkendte `.gltf` humanoids via `GLTFDocument` i `RemotePlayerProxy`; blue/orange readability tilfoejes med ikke-tekstlige team-color plates

Kurateringsregel:

- Brug kun moderne/urbane/taktiske looks
- Undgå joke-figurer
- Materialer må recolores til `Blue` og `Orange` holdsignaturer

### Våbenbase

- `Animated Guns Pack`
  - brug: assault rifle og handgun i v1
  - rolle: grounded low-poly viewmodels
  - link: `https://quaternius.com/packs/animatedguns.html`
  - lokal importkilde: `assets/third_party/quaternius/animated_guns_pack/FBX`
  - runtime-kuratering: P05 konverterer `Rifle.fbx` og `Pistol.fbx` til generated GLB assets under `assets/weapons/viewmodels/generated/`; wrapper-scenes skal bevare `source_fbx_path` som provenance og loade `generated_glb_path` i runtime

- `Ultimate Guns Pack`
  - brug: reservekilde til senere shotgun, sniper og andre udvidelser
  - rolle: sekundær våbenkilde når Animated Guns ikke dækker behovet
  - link: `https://quaternius.com/packs/ultimategun.html`
  - lokal status: reserve, ikke del af mandatory kickoff-import

### Materialer og lys

- `ambientCG`
  - brug: metal, painted metal, concrete, rust, asphalt, grunge decals
  - rolle: løfte low-poly geometri mod mere troværdig overfladekvalitet

- `Poly Haven`
  - brug: HDRI, lysreference og eventuelle få simple props hvis de visuelt matcher
  - rolle: lys og atmosfære, ikke stilskift

## Asset-brugsregler

- Gameplay-geometri må starte som custom greybox-meshes
- Hvis downtown-pakken ikke giver gode containere eller kraner, bygges de som simple custom meshes i samme skala
- Mekanik må aldrig afhænge af et specifikt asset
- Hvis bedre assets findes senere, må kun art-laget skiftes, ikke gameplay-laget

## V1 asset mapping

- Arena backdrop: `Downtown City MegaKit` fra `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)`
- Core traversal props: custom blockout meshes + samme materialsprog
- Player avatars: `Ultimate Modular Men Pack` fra `assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF`
- First-person rifle/pistol: `Animated Guns Pack` fra `assets/third_party/quaternius/animated_guns_pack/FBX`
- Knife: custom low-poly prop
- Smoke bomb: custom low-poly prop

## Implementeringsregler for agenter

- Start ikke med art-pass før `Fase C03`
- Erstat ikke blockout gameplay-meshes med mere komplekse meshes, hvis collision eller traversal bliver dårligere
- Introducér ikke nye asset-familier uden at opdatere `fps-design-brief.md` og denne spec
- Brug de allerede staged lokale packs, foer du leder efter nye assets
