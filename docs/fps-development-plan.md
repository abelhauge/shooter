# FPS Development Plan

Status: single source of truth for implementation phases
Date: 2026-05-24  
Depends on: `docs/fps-design-brief.md`, `docs/fps-technical-spec.md`

## Formaal

Dette er projektets eneste plan-dokument. Det erstatter baade den tidligere roadmap-plan og den tidligere agentfase-plan.

Standard goal-prompt for denne repo er:

```text
Implementer fps-development-plan.md fase for fase og sørg for at exit kriterier for hver fase er opfyldt, før du går videre til næste fase.
```

En agent skal bruge dette dokument til at afgøre:

- hvilken fase der er naeste
- hvad der maa implementeres i den fase
- hvilke konkrete exit-kriterier der skal opfyldes
- hvilket bevis der skal ligge i repoet, foer fasen maa markeres faerdig

## Dokumenthierarki

Laes og foelg dokumenterne i denne raekkefoelge:

1. `docs/fps-design-brief.md`
2. `docs/fps-technical-spec.md`
3. `docs/fps-development-plan.md`

Ved konflikt:

1. `fps-design-brief.md` vinder paa produkt og gameplay
2. `fps-technical-spec.md` vinder paa teknisk arkitektur og data
3. `fps-development-plan.md` vinder paa faseorden og konkret implementation

Der maa ikke findes et separat agentfase-dokument. Faseorden og exit-kriterier skal holdes her.

## Anti-Spoof Regler

En fase maa ikke markeres faerdig gennem tekst alene.

Gyldigt bevis er:

- kommando med exit-kode `0`
- screenshot fra en koerende Godot build
- computer-use/GUI-observation af den koerende game viewport
- konkret visuel vurdering af de screenshots, fasen bruger som bevis
- runtime-genereret rapport fra spillet eller et testvaerktoej
- manuel playtest-log med varighed, handlinger og observerede fejl
- konkret filsti til asset wrapper, scene, dataresource eller screenshot

Ugyldigt bevis er:

- "docs siger at det virker"
- "filen findes"
- "pathen er refereret i kode"
- smoke-output der printer pass men processen ender med timeout eller nonzero exit
- headless smoke som erstatning for et visuelt krav
- screenshot af editoren i stedet for den koerende game viewport, medmindre fasens exit-kriterie specifikt beder om editor-proof
- screenshot-filer der aldrig er aabnet og visuelt vurderet
- verification-tabeller der siger `pass`, mens screenshotet viser en aabenlys visuel fejl
- at markere en fase `done` uden at have kigget paa spillet i en rigtig GUI/game viewport med computer-use eller tilsvarende visuel observation

Hvis en fase har visuelle krav, skal beviset inkludere screenshots under:

```text
docs/verification/screenshots/
```

Hvis en fase har runtime-krav, skal beviset skrives i:

```text
docs/verification/playable-vertical-slice.md
```

Fasen er ikke faerdig, hvis bevisfilen mangler.

## Global Computer-Use Visual QA

Fra og med `P01` gaelder dette som et ekstra exit-kriterie for hver fase, ogsaa hvis fasens lokale exit-kriterier ikke gentager det:

- Start spillet med `./run.sh` i en rigtig Godot GUI/game viewport.
- Brug computer-use/GUI-observation til faktisk at se spillet, ikke kun terminaloutput.
- Test den aendrede fase i den kørende build efter implementationen.
- Tag eller opdater mindst et relevant screenshot under `docs/verification/screenshots/`, medmindre fasen udelukkende er et command-line testharness fix uden visuel game-state. Hvis fasen er command-line only, skal naeste visuelle fase stadig koeres i GUI foer den kan blive `done`.
- Aabn hvert screenshot, der bruges som fasebevis, med et image-view/computer-use vaerktoej efter capture. Billedet skal vurderes som et menneske ville vurdere det, ikke bare registreres som en fil.
- Skriv mindst 3 konkrete visuelle observationer for hvert visuelt gate-screenshot, eller mindst 1 konkret observation pr. weapon screenshot i en weapon QA fase.
- Skriv en kort visuel QA-note i `docs/verification/playable-vertical-slice.md`.

Visuel QA skal mindst kontrollere:

- kamera og spawn view: kameraet maa ikke starte inde i geometri, pege den forkerte vej eller vise en tom/uforstaalig scene
- vaaben/viewmodels: modeller maa ikke vaere usynlige, alt for store/smaa, forkert roteret, for langt fra kameraet, clippe voldsomt eller vende baglaens
- remote players: humanoids skal staa/opfoere sig visuelt plausibelt, have laesbar teambehandling og ikke vaere erstattet af kun capsule/box/label
- map/art: assets skal vaere synlige fra gameplay routes, have rimelig skala/rotation, og ikke blokere traversal, spawns eller sightlines utilsigtet
- HUD/UI: tekst maa ikke overlappe, forsvinde, ligge udenfor viewporten eller skjule central combat-information
- FX: muzzle flash, impact, smoke og explosions maa ikke vaere usynlige, permanent blokerende, placeret forkert eller ekstremt skaleret

Hvis noget ser visuelt forkert ud, er fasen ikke `done`, selv hvis scripts kompilerer og smoke-tests passerer. Eksempler paa fail:

- pistolen vender forkert eller sidder forkert i kameraet
- rifle-viewmodel er en fallback box, selv om fasen kraever asset
- remote player er kun en kapsel eller vender forkert
- spawn view viser mest greybox, selv om fasen kraever art dressing
- UI overlapper ammo/health/timer
- smoke eller prop-assets blokerer hele synsfeltet uden gameplay-intention

Hvis brugeren afviser et screenshot eller peger paa en konkret visuel fejl, skal den relevante fase genabnes uanset tidligere `done`-status. Brugerobservationer om billeder vinder over agentens tidligere visuelle pass/fail-vurdering.

## Fase Statusregler

Hver fase har en status:

- `todo`: ikke startet
- `in_progress`: aktiv
- `blocked`: kan ikke gennemfoeres uden ekstern handling
- `done`: alle exit-kriterier og beviser er opfyldt

En agent maa kun arbejde paa den foerste fase, der ikke er `done`, medmindre brugeren eksplicit beder om andet.

Hvis en fase fejler, inklusive visuel computer-use QA, skal agenten stoppe ved fasen og rapportere `blocked` eller `in_progress`. Den maa ikke springe videre for at lave nemmere opgaver.

## Aktuel Sandhed

Projektet har meget filbaseret implementation, men er ikke en faerdig v1.

Kendt status pr. `2026-05-24`:

- Godot-projekt, scripts, scener og dataresources findes.
- `./run.sh` kan finde Godot 4 paa mindst en lokal maskine.
- `tools/validate_static.py` findes.
- `tools/runtime_smoke.py` findes, men smoke-tests alene er ikke nok.
- Tidligere docs paastod runtime-verifikation for meget. Disse paastande maa ikke bruges som completion-bevis.
- Det vigtigste naeste maal er en visuelt spilbar vertical slice med de lokale Quaternius-assets faktisk synlige i spillet.

## V1 Faseplan

### P00: Plan Consolidation

Status: `done`

Maal:

- fjerne den dobbelte planstruktur
- goere dette dokument til eneste implementation plan

Arbejde:

- opdatere `AGENTS.md` til kun at pege paa dette plan-dokument
- opdatere `docs/fps-technical-spec.md` til samme dokumenthierarki
- fjerne `docs/fps-agent-implementation-phases.md`
- sikre at der ikke findes ekstra goal-/plan-dokumenter, som kan konkurrere med denne plan

Exit-kriterier:

- `rg "fps-agent-implementation-phases|Følg begge|foelg begge|begge, men" AGENTS.md docs --glob '!fps-development-plan.md'` returnerer ingen aktive instruktioner til at bruge to plan-dokumenter
- `rg "codex-goal|codex-slash-goal" docs --glob '!fps-development-plan.md'` returnerer ingen ekstra goal-dokumenter
- `docs/fps-development-plan.md` findes og indeholder faseplanen
- `docs/fps-agent-implementation-phases.md` findes ikke
- `git status --short` viser kun plan-refactoren og eksisterende brugerarbejde, ikke uventede sletninger udenfor docs

Bevis:

- slutrapporten for denne fase viser de relevante `rg`- og `git status`-resultater

Ikke accepteret:

- at lade det gamle phasedokument ligge som en "reference"
- at have to forskellige steder med naeste agentopgave

### P01: Baseline Runtime Audit

Status: `done`

Maal:

- fastslaa den faktiske spiltilstand fra en koerende Godot build

Arbejde:

- koer `git status --short`
- koer `python3 tools/validate_static.py`
- koer `./run.sh --version`
- start `./run.sh`
- tag baseline screenshot fra lobby og foerste spawn
- skriv en konkret gap-liste

Exit-kriterier:

- Godot version er registreret
- static validation exit-kode er registreret
- `./run.sh` startup-resultat er registreret
- mindst 2 baseline screenshots findes
- mindst 8 konkrete gaps er skrevet, hvoraf mindst 3 handler om visuals/assets og mindst 2 handler om gameplay/playability

Bevis:

- `docs/verification/playable-vertical-slice.md`
- `docs/verification/screenshots/p01_lobby_baseline.png`
- `docs/verification/screenshots/p01_spawn_baseline.png`

Ikke accepteret:

- at bruge gamle docs som status
- at nojes med headless smoke
- at skrive "looks unfinished" uden konkrete observerbare gaps

### P02: Verification Harness Must Exit Cleanly

Status: `done`

Maal:

- sikre at automatiske tests ikke kan snyde med `SMOKE_PASS` efterfulgt af timeout

Arbejde:

- gennemgaa `tools/runtime_smoke.py` og smoke-exit flowet
- ret test-runner eller Godot quit-flow, hvis pass-processer ikke lukker rent
- koer de korte smoke-suiter

Exit-kriterier:

- `python3 tools/runtime_smoke.py offline` exit-kode `0`
- `python3 tools/runtime_smoke.py weapons` exit-kode `0`
- ingen af kommandoerne ender i timeout
- hvis en test printer `SMOKE_PASS`, skal processen ogsaa ende med exit-kode `0`

Bevis:

- kommandoer og exit-koder skrives i verification note

Ikke accepteret:

- at fjerne timeout-detektion
- at ignorere nonzero exit
- at markere smoke som pass paa tekstmatch alene

### P03: Environment Asset Import Proof

Status: `done`

Maal:

- bevise at Downtown City MegaKit assets faktisk kan vises i spillet

Arbejde:

- brug kun `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)`
- lav wrapper-scenes under `scenes/maps/props/` hvis noedvendigt
- placer et lille proof area i eller ved arenaen

Exit-kriterier:

- mindst 10 forskellige Downtown City MegaKit asset-filer er synlige i en koerende game viewport
- hver af de 10 assets er listet med kildefil og scene/node der bruger den
- der findes mindst 1 screenshot hvor mindst 5 af assetsene er synlige samtidigt
- der er ingen dependency paa `assets/source_packs/quaternius/`

Bevis:

- verification note med asset-liste
- `docs/verification/screenshots/p03_environment_asset_proof.png`

Ikke accepteret:

- path constants uden synlig instans
- assets placeret udenfor spillerens synlige omraade
- editor-only proof

### P04: Arena Dressing Pass 1

Status: `done`

Maal:

- goere foerste map visuelt laesbart som urban-industrial arena, ikke ren greybox

Arbejde:

- dress `arena_downtown_01` med Downtown City MegaKit assets
- bevar simple gameplay collision hvis noedvendigt
- skab spawn landmarks, mid landmarks og traversal landmarks

Exit-kriterier:

- mindst 20 synlige Downtown City MegaKit instances findes i normal gameplay
- mindst 4 store bygning/facade/skyline-assets er synlige som landmarks
- mindst 8 street/sidewalk/stairs/railing/trim/prop-assets er placeret i eller direkte ved playable space
- foerste spawn view viser real environment art uden at spilleren skal vende sig 180 grader
- mindst 2 traversal routes er visuelt understoettet af art og stadig gennemfoerlige
- ingen ny art blocker en hovedrute, spawn eller wallrun-route

Bevis:

- runtime-genereret eller manuelt optalt asset count i verification note
- historiske screenshots fra P23 completion, ikke aktiv layout-regression:
  - `p04_blue_spawn.png`
  - `p04_orange_spawn.png`
  - `p04_mid_map.png`
  - `p04_traversal_route.png`

Ikke accepteret:

- at taelle skjulte nodes
- at taelle samme usynlige instans flere gange
- et map der stadig laeser som primitiv greybox i screenshots

### P05: Weapon Viewmodel Pass

Status: `done`

Maal:

- erstatte de mest synlige weapon placeholders

Arbejde:

- brug `assets/third_party/quaternius/animated_guns_pack/FBX/Rifle.fbx`
- brug `assets/third_party/quaternius/animated_guns_pack/FBX/Pistol.fbx`
- lav wrapper-scenes under `scenes/weapons/viewmodels/` hvis noedvendigt
- placer og skaler viewmodels til first-person

Exit-kriterier:

- assault rifle viser en synlig rifle-model i first-person
- handgun viser en synlig pistol-model i first-person
- vaabenskift mellem rifle og handgun aendrer synlig model
- modellerne er ikke fallback boxes
- modellerne er ikke usynlige, ekstremt store eller forkert vendt
- muzzle flash og impact feedback er synligt med rifle

Bevis:

- screenshots:
  - `p05_rifle_viewmodel.png`
  - `p05_handgun_viewmodel.png`
- verification note med kildeasset og wrapper path

Ikke accepteret:

- fallback box for rifle eller handgun
- kun world-model uden first-person viewmodel
- kun kodepath uden screenshot

### P05A: Weapon Visual QA Sweep

Status: `done`

Genvalideret pr. `2026-05-25`:

- De tidligere shotgun-screenshots blev afvist, fordi de ikke tydeligt beviste korrekt first-person orientation.
- Brugerens seneste observation om at musen ikke aimede og at shotgunens kolbe vendte fremad genåbnede gate-beviset; ældre `done`-noter må ikke bruges uden den nye input/shotgun-fix i `docs/verification/playable-vertical-slice.md`.
- P05A er rerun i en rigtig GUI build med clean no-fire screenshots for alle vaaben og separate feedback-screenshots for rifle, handgun og shotgun.
- `docs/verification/screenshots/weapon_visual_qa/shotgun.png` er nu et rent after-screenshot uden muzzle flash, hvor shotgunens muzzle direction kan vurderes.
- `docs/verification/screenshots/weapon_visual_qa/shotgun_before_after.png` viser den afviste flash-obscured state ved siden af den accepterede clean after-state.
- `docs/verification/playable-vertical-slice.md` indeholder opdateret visual-observation table for alle 13 vaaben.
- Default/primary visual flow er nu `assault_rifle`, ikke `shotgun`. Shotgun-krav i denne fase gælder kun, hvis shotgun stadig er selectable eller testes som historisk/extended weapon; shotgun maa ikke bruges som bevis for default primary.

Maal:

- sikre at alle vaaben, der kan vaelges eller bruges som default, ser visuelt korrekte ud i first-person
- fange fejl som shotgun der vender forkert, mangler material/texture, har forkert skala eller sidder forkert i kameraet

Arbejde:

- start spillet med `./run.sh` i en rigtig GUI/game viewport
- brug computer-use/GUI-observation til at teste vaaben visuelt i den koerende build
- gennemgaa alle vaaben, der kan vaelges i lobbyen, med ekstra fokus paa default-loadout og primary assault rifle
- ret viewmodel wrapper scenes, rotation, scale, position og material/texture setup
- hvis en imported FBX mangler brugbar texture/material i Godot, lav en bevidst material override i en project-owned scene/resource; utekstureret default grey er ikke acceptabelt for asset-vaaben

Vaaben der skal inspiceres:

- assault rifle
- handgun
- shotgun
- sniper
- knife
- smoke bomb
- grenade
- flamethrower
- lasso
- taser gun
- redbull
- portal gun

Exit-kriterier:

- hvert vaaben kan vaelges eller aktiveres i en koerende Offline Dev Match uden crash
- hvert vaaben har et synligt first-person viewmodel eller en bevidst, dokumenteret v1 placeholder, hvis der ikke findes et passende lokalt asset
- shotgun vender korrekt: loeb/muzzle peger fremad vaek fra kameraet, grip/stock ligger plausibelt mod spilleren, og modellen er ikke spejlvendt/baglaens
- shotgun har synligt material/texture eller en bevidst material override; utekstureret default grey/white import er ikke acceptabelt
- shotgun skal kunne vurderes tydeligt i screenshotet; et billede hvor shotgun er skaaret af, kun delvist synlig, skjult i skygge, eller hvor kameraet kigger skraet ind i vaeg/geometri, er ikke gyldigt bevis
- rifle, handgun, shotgun og sniper bruger ikke fallback boxes
- vaabenmodeller clipper ikke voldsomt ind i kameraet, HUD eller midten af crosshair
- vaabenmodeller har konsistent first-person skala og sidder i et plausibelt lower-right/lower-center viewmodel-omraade
- weapon switching viser tydelig visuel forskel mellem slots og efterlader ikke gamle viewmodels synlige
- muzzle flash/impact feedback er stadig visuelt plausibelt for mindst rifle, handgun og shotgun
- ingen Godot `SCRIPT ERROR` eller `ERROR` observeres under testen

Bevis:

- verification note indeholder en tabel med hvert vaaben, kildeasset/wrapper, orientation `pass/fail`, material/texture `pass/fail`, scale/position `pass/fail`, og kendte restfejl
- verification note indeholder en `visual observations` kolonne, hvor hvert weapon screenshot beskrives konkret med mindst én observation om muzzle direction, material/texture og placement
- screenshots under `docs/verification/screenshots/weapon_visual_qa/` for mindst:
  - `assault_rifle.png`
  - `handgun.png`
  - `shotgun.png`
  - `sniper.png`
  - `knife.png`
  - `smoke_bomb.png`
  - `grenade.png`
- `docs/verification/screenshots/weapon_visual_qa/shotgun_before_after.png` hvis shotgun blev rettet i fasen
- playtest-log beskriver hvordan hvert vaaben blev aktiveret, og at testen foregik i den koerende game viewport
- shotgun beviset skal inkludere et rent after-screenshot, hvor hele viewmodelens relevante form kan ses og hvor muzzle direction kan vurderes uden gæt

Ikke accepteret:

- headless smoke som eneste vaaben-test
- screenshots fra Godot editoren uden gameplay camera
- at sige "FBX'en loader" uden at kontrollere orientation, scale og material i first-person
- shotgun der stadig vender forkert eller mangler material/texture
- default-loadout der starter med et visuelt defekt vaaben
- at skjule et defekt vaaben ved kun at teste rifle og handgun
- at bruge et screenshot hvor shotgun er saa afskaaret eller mork, at orientation ikke kan vurderes
- at markere `pass` uden en konkret visuel observation af selve screenshotet

### P06: Remote Humanoid Player Pass

Status: `done`

Maal:

- goere remote players visuelt rigtige nok til multiplayer-test

Arbejde:

- brug mindst en humanoid fra `assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF`
- undgaa joke-silhouettes som `King.gltf`
- tilfoej blue/orange team readability

Exit-kriterier:

- remote player proxy viser humanoid mesh i en koerende multiplayer match
- capsule/box alene er ikke laengere remote representation
- blue og orange kan skelnes visuelt uden debugtekst
- remote position og yaw sync virker stadig
- screenshot viser remote humanoid fra gameplay camera

Bevis:

- `docs/verification/screenshots/p06_remote_humanoid.png`
- verification note med kildeasset og team-readability metode

Ikke accepteret:

- kun Label3D eller team text
- capsule/box som eneste visuelle remote player
- humanoid asset kun vist i editor

### P07: Offline Playability Pass

Status: `done`

Maal:

- bevise at den dressed arena kan spilles som FPS prototype

Arbejde:

- spil Offline Dev Match i GUI i mindst 10 minutter
- test movement, combat, HUD og respawn
- ret blockers fundet under testen

Exit-kriterier:

- manuel GUI-playtest varer mindst 10 minutter
- spilleren gennemfoerer mindst 2 fulde traversal routes
- jump, slide, slide-jump, wallrun og wall-jump er alle testet
- assault rifle, handgun, knife og smoke bomb er alle brugt
- reload interrupt ved weapon switch er testet
- mindst 3 dummies rammes, og mindst 1 dummy kill registreres
- player death og respawn er testet
- HUD viser health, ammo/charges, active slot, cooldown, timer, score og FPS/node count
- ingen Godot `SCRIPT ERROR` eller `ERROR` observeres under testen

Bevis:

- playtest start/end eller varighed i verification note
- `docs/verification/screenshots/p07_combat_hud.png`
- liste over testede mechanics og resultat

Ikke accepteret:

- headless smoke som erstatning
- playtest under 10 minutter
- test i movement-testbane i stedet for dressed arena

### P08: Two-Instance Multiplayer Pass

Status: `done`

Maal:

- bevise at en rigtig to-spiller session kan bruges

Arbejde:

- start to synlige instanser
- brug lobby-flowet: Host Private Match, Join By IP, Ready, Host Start Match
- test movement og combat mellem de to

Exit-kriterier:

- host og client er begge i samme arena
- begge kan se den anden spiller som humanoid remote player
- remote movement sync er synlig
- mindst 1 skud/hit eller authoritative combat event er verificeret
- mindst 1 death/respawn cycle gennemfoeres, eller fasen markeres `blocked` med konkret fejl
- disconnect cleanup giver ingen kritisk Godot error

Bevis:

- screenshots:
  - `p08_lobby_host_join.png`
  - `p08_multiplayer_remote_player.png`
- host/client testlog i verification note
- console error summary for begge instanser

Ikke accepteret:

- headless-only ENet check
- command-line join uden at teste lobby-flowet
- data sync uden synlig remote player

### P09: Automated Regression Pass

Status: `done`

Maal:

- sikre at baseline scripts og smoke checks stadig passer efter visuelle og runtime rettelser

Arbejde:

- koer static validation
- koer hele smoke-suiten

Exit-kriterier:

- `python3 tools/validate_static.py` exit-kode `0`
- `python3 tools/runtime_smoke.py all` exit-kode `0`
- ingen timeout i smoke output
- ingen `SCRIPT ERROR` eller `ERROR` i testoutput

Bevis:

- exact commands, exit-koder og kort outputsummary i verification note

Ikke accepteret:

- at slette failing tests
- at filtrere Godot errors vaek
- at godkende nonzero exit

### P10: Vertical Slice Verification Note

Status: `done`

Maal:

- samle det faktiske bevis for vertical slice status

Arbejde:

- opdater `docs/verification/playable-vertical-slice.md`
- link alle screenshots
- skriv kendte bugs og naeste fase

Exit-kriterier:

- verification note findes
- alle screenshots fra P01-P08 samt P05A findes paa de angivne paths
- note indeholder Godot version, testkommandoer, exit-koder, manual playtest-varighed, asset-liste, kendte bugs og final status
- final status er:
  - `done` kun hvis P00-P09 samt P05A er `done`
  - `partial` hvis spillet er forbedret men en gate mangler
  - `blocked` hvis en blocker forhindrer videre runtime/playtest

Bevis:

- `docs/verification/playable-vertical-slice.md`

Ikke accepteret:

- at skrive "v1 done" i stedet for vertical slice status
- at skjule kendte bugs som "polish"

### P10A: Computer-Use Visual Game Polish Pass

Status: `done`

Genvalideret pr. `2026-05-25`:

- Brugerens observation om at mappet ikke var lukket og havde moerke omraader genåbnede map-composition delen af P10A.
- Den aktuelle map closure-fix ligger i `docs/verification/playable-vertical-slice.md` under `User-Reopened Map Closure Fix`.
- Aeldre P10A `done`-noter maa ikke bruges som bevis for map-readability uden den nye perimeter-closure, edge-lighting og offline art-smoke regression.

Maal:

- spille spillet som en rigtig spiller med computer-use/GUI-kontrol og lave en samlet visuel tilpasning, saa spillet ikke bare virker teknisk, men faktisk ser godt ud og laeser som et rigtigt spil
- fange helhedsproblemer, som enkelte fase-screenshots ikke fanger: grim komposition, forkerte proportioner, daarlig lys/laesbarhed, kluntet HUD, skaeve viewmodels, tomme spawn views, uprofessionelle materialer og assets der ikke haenger sammen

Arbejde:

- start spillet med `./run.sh` i en rigtig GUI build
- brug computer-use skill/GUI-kontrol til at navigere menuen, starte Offline Dev Match, bevæge spilleren gennem arenaen, skyde, skifte vaaben, kaste smoke/grenade, kigge op/ned og inspicere map, HUD, FX, viewmodels og remote-player visuals
- spil mindst 15 minutter offline i den aktuelle dressed arena
- start derefter en to-instans multiplayer session og inspicer mindst 5 minutter fra host eller client
- tag screenshots fra gameplay, ikke editoren
- lav en visuel punchlist med konkrete problemer og ret de vigtigste problemer i samme fase
- gentag play/capture efter rettelserne, indtil screenshots og gameplay ikke har aabenlyse "prototype/ser forkert ud"-fejl

Visuelle omraader der skal vurderes:

- foerste spawn impression: spilleren skal straks se en forstaaelig, interessant arena med retning og landmarks
- map composition: bygninger, blockout og gameplay-art skal haenge sammen i skala, stil og placering
- lys og materialer: scenen maa ikke vaere flad, alt for mork, overeksponeret, default-grey eller visuelt rodet
- viewmodels: alle default og hyppigt brugte vaaben skal vende korrekt, have plausibel skala/materiale og sidde godt i camera frame
- HUD: health, ammo, score, timer, debug/perf og hit feedback maa ikke se tilfældigt placeret, overlappe eller dominere billedet
- combat readability: crosshair, muzzle flash, hit feedback, smoke, dummy/remote target og impacts skal kunne laeses i bevægelse
- multiplayer readability: remote player skal ligne en spiller, have team-readability og ikke se ud som debug-placeholder
- movement readability: wallrun/slide/high routes skal se tilsigtede ud, ikke som tilfaeldige bla kasser

Exit-kriterier:

- computer-use/GUI-playtest er gennemfoert i mindst 15 minutter offline og mindst 5 minutter multiplayer
- mindst 12 screenshots findes under `docs/verification/screenshots/p10a_visual_polish/`
- screenshots daekker: lobby, blue spawn, orange spawn, mid-map, high route, close combat, smoke/combat FX, assault rifle, primary assault rifle, handgun, remote player, HUD under kamp
- verification note indeholder en visuel punchlist med mindst 10 konkrete fund fra foerste gennemspilning
- mindst 6 af punchlist-punkterne er rettet i samme fase
- verification note indeholder before/after for mindst 4 rettede visuelle problemer
- ingen screenshot i den accepterede after-serie viser aabenlyse blockers som forkert vendt primary weapon, shotgun i default/primary-flowet, kamera inde i vaeg, usynligt vaaben, helt tomt spawn view, kun greybox som hovedindtryk, uleselig HUD, eller remote player som ren capsule/box
- agenten har aabnet og vurderet after-screenshots visuelt og skrevet konkrete observationer for hvert screenshot
- `python3 tools/validate_static.py` passerer efter rettelserne

Bevis:

- `docs/verification/playable-vertical-slice.md` har et `P10A Computer-Use Visual Game Polish Pass` afsnit
- `docs/verification/screenshots/p10a_visual_polish/` indeholder before/after og final accepted screenshots
- playtest-log med varighed, rute, handlinger og fund
- punchlist med status: `fixed`, `accepted`, `deferred`, eller `blocked`

Ikke accepteret:

- at koere headless smoke i stedet for at spille med computer-use/GUI
- at tage screenshots uden at aabne og vurdere dem
- at lade aabenlyst grimme eller defekte billeder passere, fordi tests er groenne
- at kalde en visuel fejl "polish" hvis den oedelægger foerstehaandsindtrykket eller laesbarheden
- at markere fasen `done`, hvis default/primary capture viser shotgun i stedet for assault rifle, eller hvis et primary weapon vender forkert, mangler materiale, eller er saa skaaret af/mork at orientation ikke kan vurderes
- at markere fasen `done`, hvis spillet stadig overvejende ligner debug blockout i de accepterede screenshots

## Senere Faser Efter Vertical Slice

Disse maa foerst startes, naar P00-P10, P10A samt P05A er `done`.

### P11: Core Combat Tuning

Status: `done`

Exit-kriterier:

- 20 minutters offline combat playtest
- damage/ammo/reload-tuning dokumenteret i dataresource diff
- ingen nye magic numbers i scripts
- verification note med foer/efter tuning

### P12: 2v2 Runtime Pass

Status: `done`

Exit-kriterier:

- 4 synlige instanser eller 4 maskiner/LAN clients
- team assignment 2v2 dokumenteret
- spawns og score fungerer for begge hold
- screenshot med mindst 3 remote/human players synlige eller dokumenteret maskinbegrænsning

### P13: 3v3 Runtime Pass

Status: `done`

Exit-kriterier:

- 6 spillere/instanser testet, eller klar performance/blocker rapport
- `MAX_PLAYERS = 6` verificeret
- team score og spawn capacity verificeret
- FPS/perf readout dokumenteret under load

### P14-P22: Extended Weapons One At A Time

Status: `done`

Raekkefoelge:

1. Shotgun - `done`
2. Sniper - `done`
3. Grenade - `done`
4. Flame thrower - `done`
5. Lasso - `done`
6. Taser gun - `done`
7. Redbull - `done`
8. Portal gun - `done`

Exit-kriterier for hvert vaaben:

- vaabenet kan vaelges i lobbyen
- vaabenet har synlig first-person feedback
- vaabenet kan bruges offline uden errors
- multiplayer behavior er enten testet eller eksplicit markeret som ikke shipping i den fase
- tuning-tal ligger i `.tres`
- 5 minutters weapon-specific playtest er dokumenteret

### P23: City Asset Level Designer Tool

Status: `done`

Maal:

- bygge et Godot 4 editor-vaerktoej, saa level designeren kan placere importerede city assets paa `arena_downtown_01`
- goere map-dressing hurtigt, repeterbart og gemt som project-owned Godot scenes/resources
- bevare gameplay blockout, spawns, traversal routes og collision som separate systemer fra art placement
- give en sikker workflow til at bruge Downtown City MegaKit uden at redigere vendor-filer

Scope:

- Dette er en editor/tooling-fase, ikke et nyt runtime game mode og ikke en ekstern level-editor udenfor Godot.
- Vaerktoejet skal implementeres i Godot med GDScript som enten `EditorPlugin` under `addons/` eller en Godot-editor tool-scene under `tools/`.
- Foerste asset-kilde er kun `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)`.
- Output skal gemmes som project-owned data eller scenes under `data/maps/`, `scenes/maps/art/` eller `scenes/maps/props/`.
- `assets/source_packs/quaternius/` og raw vendor-filer maa ikke aendres.
- Placement target er `arena_downtown_01_art.tscn` eller en child scene instansieret af den. `arena_downtown_01_blockout.tscn` maa ikke omskrives af toolen, medmindre der kun tilfoejes eksplicit non-gameplay metadata.

Designerfunktioner:

- et kurateret asset-katalog med mindst `25` Downtown City MegaKit entries
- hver katalog-entry har `asset_id`, visningsnavn, kategori, kildepath, default scale og default rotation
- kategorier skal mindst daekke `building`, `facade`, `street`, `trim`, `prop`, `landmark` og `backdrop`
- palette UI hvor designeren kan filtrere efter kategori og vaelge et asset
- placement preview eller ghost, saa assetets omtrentlige skala og rotation kan vurderes foer placement
- single-place mode der instansierer det valgte asset under korrekt maplag
- transform controls for move, rotate, uniform scale og delete
- snap presets for mindst `0.5m`, `1m` og `5m`
- rotation presets for mindst `15` grader og `90` grader
- duplicate workflow til hurtig gentagelse af samme prop/facade
- undo/redo via Godots editor undo stack, hvis vaerktoejet er et `EditorPlugin`; ellers en dokumenteret save/revert workflow
- stabile node-navne baseret paa `asset_id` og loebenummer, saa diffs kan reviewes
- gemt placement skal kunne lukke Godot, aabne projektet igen og stadig vise samme assets med samme transforms

Tekniske krav:

- kataloget maa ikke vaere hardcoded som spredte path constants i UI-kode; brug en samlet resource, scene, JSON eller GDScript-datafil under projektets egne mapper
- toolen skal bruge Godot-importerbare scenes/resources og skal teste `ResourceLoader.exists(path, "PackedScene")` eller tilsvarende, saa manglende imports bliver synlige fejl i vaerktoejet
- raw `.gltf` fallback maa kun bruges som tydeligt markeret importer/helper-step, ikke som permanent skjult runtime-afhaengighed
- placerede city assets maa som default vaere visual-only eller bruge simple project-owned collision proxies; importerede komplekse collisions maa ikke automatisk blive authoritative gameplay blockers
- hvis et placeret asset skal paavirke gameplay collision, skal det markeres eksplicit og playtestes mod movement routes
- toolen skal respektere maplagene fra teknisk spec: `GameplayCore`, `TraversalRoutes`, `CombatCover`, `SkylineBackdrop`, `SpawnSpaces`, `HazardsAndKillVolumes`, `LightingAndAtmosphere`
- toolen maa ikke flytte eller slette spawn points, kill volumes, player controller, match director, HUD eller weapon nodes
- generated/wrapper scenes skal bevare provenance til original kildeasset, saa asset-oprindelse kan spores

Arbejde:

- audit den nuvaerende `arena_downtown_01` art-scene og find det korrekte child-root for city dressing
- opret asset-kataloget for Downtown City MegaKit med mindst `25` brugbare entries
- opret editor-vaerktoejet med palette, category filter, placement og transform controls
- opret eller genbrug wrapper-scenes under `scenes/maps/props/` for city assets, hvis direkte vendor-import ikke er stabil nok
- implementer save/load af placements i en Godot scene/resource, som kan reviewes i git
- tilfoej en validering, der rapporterer missing asset paths, brug af `source_packs`, off-layer placement og ugyldige transforms
- lav en lille designer proof-dressing i `arena_downtown_01_art.tscn` med mindst `15` nye placements fra toolen
- start spillet med `./run.sh` og verificer at de placerede assets er synlige i en rigtig game viewport
- kontroller at proof-dressingen ikke blokerer blue/orange spawn, mindst to traversal routes, wallrun-flader eller de vigtigste sightlines

Exit-kriterier:

- Godot-editoren kan aabne level designer-vaerktoejet uden `SCRIPT ERROR` eller kritiske importer-fejl
- `./run.sh --editor` importerer assets og aabner `arena_downtown_01_art.tscn`, hvor arenaen ikke er tom og city assets er synlige i editor viewporten
- asset-kataloget indeholder mindst `25` Downtown City MegaKit entries fra `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)`
- designeren kan placere, flytte, rotere, skalere, duplikere og slette et city asset via vaerktoejet
- mindst `15` city asset instances er placeret i `arena_downtown_01_art.tscn` eller en child scene gennem vaerktoejet
- efter luk/genaabn af projektet findes de samme placements stadig med samme transforms
- placerede assets er parentet under de relevante maplag og har stabile, reviewbare node-navne
- valideringen viser ingen brug af `assets/source_packs/quaternius/`
- valideringen viser ingen missing PackedScene/resource paths for de katalog-assets, der bruges i proof-dressingen
- `python3 tools/validate_static.py` exit-kode `0`
- `./run.sh` starter en rigtig Godot GUI/game viewport, hvor proof-dressingen kan ses i normal gameplay
- visuel QA bekraefter at de nye placements har rimelig skala, rotation og materialer, og ikke blokerer spawn view, traversal routes eller wallrun-ruter utilsigtet
- verification note indeholder en kort designer-testlog med hvilke tool-actions der blev testet

Bevis:

- `docs/verification/playable-vertical-slice.md` har et `P23 City Asset Level Designer Tool` afsnit
- verification note lister katalogets entry count, proof-placement count og de valideringskommandoer der blev koert
- verification note beskriver mindst `5` konkrete city assets med `asset_id`, kildepath, maplag og formaal i arenaen
- screenshots:
  - `docs/verification/screenshots/p23_level_designer_editor_palette.png`
  - `docs/verification/screenshots/p23_level_designer_game_view.png`
  - `docs/verification/screenshots/p23_level_designer_traversal_check.png`
- editor-screenshotet skal vise vaerktoejet i Godot-editoren med palette eller valgt asset
- game-view screenshots skal vaere fra den koerende game viewport, ikke kun editor viewport
- agenten skal aabne og visuelt vurdere alle P23 screenshots og skrive mindst `3` konkrete observationer pr. screenshot

Ikke accepteret:

- en separat ekstern level-editor udenfor Godot
- runtime-only placement, som ikke kan gemmes som Godot scene/resource og reviewes i git
- et katalog bestaende af spredte hardcoded path constants
- at bruge `assets/source_packs/quaternius/` som import- eller placement-kilde
- at placere assets direkte i blockout-scenen paa en maade der blander art og gameplay collision
- at flytte spawns, kill volumes eller traversal blockout som bivirkning af art placement
- at markere fasen `done` med editor-screenshot alene uden en koerende game viewport
- at taelle skjulte, off-map eller disabled nodes som proof placements
- at acceptere assets der aabenlyst har forkert skala, forkert rotation, manglende materialer, eller blokerer movement uden gameplay-intention

Efterfoelgende editor-refactor:

- P23 proof-placements og game-view screenshots er historisk fasebevis, ikke en fremadrettet layout-kontrakt.
- Den aktive validering maa ikke kraeve bestemte city placements, layer-populationer, traversal route names eller screenshot-kompositioner, fordi `arena_downtown_01_art.tscn` nu er den direkte editable scene og maa kunne ryddes og ombygges i Godot-editoren.
- Validering skal fortsat kontrollere asset-katalog, editor-plugin, brug af `assets/third_party/quaternius/`, manglende asset paths, `source_packs`-forbud og ugyldige transforms paa de placements, der faktisk findes.

## Naeste Fase

Naeste fase er altid den foerste fase i dette dokument med status andet end `done`.

Aktuelt: Ingen - `P00-P23` er `done`.
