# FPS Design Brief

Status: v1 locked  
Date: 2026-05-24  
Owner: Abel + Codex

## Formål

Dette dokument samler de låste designbeslutninger, tekniske anbefalinger og scope-rammer for et native desktop 1st person 3D movement-FPS.

Dokumentet er bevidst opdelt i:

- `Låst`: ting vi med rimelighed kan beslutte nu
- `Foreslået`: ting jeg anbefaler som standardretning

## Spilvision

Et online 1st person FPS hvor movement er den centrale skill. Spilleren bevæger sig gennem et stort industrielt map med containere og kraner, bygger fart op gennem hop, slides, wallruns og special-abilities, og bruger et loadout-system med fire våbenslots før hver kamp.

Den stærkeste kernefantasi lige nu er:

- høj fart og momentum
- kreative movement-combos
- våbenvalg med stærk identitet
- små hold og private kampe mellem venner

## Retning Jeg Anbefaler

### Produktretning

Status: `Låst`

- Platform: native desktop-spil til `Mac` og `PC`
- Kamera: first-person
- Primær oplevelse: online arena shooter med movement-fokus
- Holdstørrelser som produktmål: `1v1`, `2v2` og `3v3`
- Første shipping-scope: få modes, én stærk map, høj movement-kvalitet
- Første implementeringsmål: start småt og udvid holdstørrelse gradvist

Begrundelse:

- Native desktop passer til dit mål og reducerer de kompromiser, et browser-FPS ellers ville tvinge os ind i.
- Lille spillerantal reducerer kompleksitet og gør game feel og netcode mere realistisk at få rigtigt.
- Movement, netcode og game feel er vigtigere end stort content-volumen tidligt.

### Teknisk stack

Status: `Låst`

- Engine: `Godot 4`
- Sprog: `GDScript`
- Character controller: `CharacterBody3D`
- Fysik og collision: `Godot 3D physics`, med mulighed for `Jolt` senere hvis nødvendigt
- HUD og menuer: `Godot Control UI`
- Multiplayer: `Godot high-level multiplayer` over `ENet`
- Første netværksmodel: simple private lobbies, sandsynligvis host/client eller letvægts listen-server
- Asset-format: `GLB`

Begrundelse:

- Godot er en mere realistisk vej til et native `Mac + PC` FPS end en web-stack.
- Godot har officiel støtte for 3D character bodies, fysik, native eksport og high-level multiplayer via ENet.
- En samlet engine med editor, scene-system, input, UI og eksport reducerer mængden af specialinfrastruktur, som Codex ellers skulle bygge.

### Visuel strategi

Status: `Låst`

Målet bør ikke være fotorealistisk AAA, men et troværdigt "rigtigt spil"-look, som Codex realistisk kan levere med en gratis asset-strategi.

- stil: stylized til semi-realistisk industrial arena
- miljø: containergård, kraner, stilladser, metalbroer, cargo-zoner
- geometri: enkel, læsbar, tydelig og gameplay-drevet
- materialer: robuste metal-, beton-, maling-, rust- og asfaltmaterialer
- lys: dramatisk havne-look med stærk readability
- farveprofil: klare team/readability-farver oven på neutrale industrifarver
- reference-retning: høj fart og visuel læsbarhed ala `NutShot`, men uden at vi endnu låser hvor komisk eller karikeret tonen skal være
- anbefalet tone: brug `NutShot` mest som reference for movement, pacing og readability, men hold miljøet mere grounded end rent joke-spil

Dette er vigtigt:

- Vi bør greyboxe hele mappet først.
- Vi bør ikke satse på at Codex genererer alle hero-assets fra bunden.
- Vi bør planlægge efter gratis assets først og bruge custom-assets selektivt senere.

## Designlog

| ID | Emne | Status | Beslutning |
| --- | --- | --- | --- |
| D-001 | Genre | Låst | 1st person 3D FPS |
| D-002 | Fokus | Låst | Movement er spillets hovedidentitet |
| D-003 | Multiplayer | Låst | Online spil med invite-flow |
| D-004 | Holdstørrelse | Låst | Produktmålet er 1v1, 2v2 og 3v3 |
| D-005 | Lobby | Låst | Man kan invitere andre til at spille med sig |
| D-006 | Friendly battle | Låst | Man kan invitere folk til at spille imod sig |
| D-007 | Loadout | Låst | Spilleren vælger våben før kampstart |
| D-008 | Våbenslots | Låst | 4 slots: primary, secondary, melee, artillery |
| D-009 | Første platform | Låst | Native desktop til Mac og PC |
| D-010 | Teknisk retning | Låst | Godot 4 + GDScript + ENet multiplayer |
| D-011 | Asset-strategi | Låst | Alle gratis assets er acceptable |
| D-012 | Første map | Låst | Ét stærkt industrial container/crane-map først, planlagt så flere maps kan tilføjes senere |
| D-013 | V1 våbensæt | Låst | Assault rifle, handgun, knife og smoke bomb |
| D-014 | Portal gun prioritet | Låst | Portal gun kommer sent i roadmapet |
| D-015 | Placeholder-politik | Låst | Placeholder-figurer og placeholder-våben er acceptable kortvarigt |
| D-016 | Base health | Låst | 100 HP som første balance baseline |
| D-017 | Invite-kompleksitet | Låst | Første version skal være så simpel som muligt |
| D-019 | Første mode | Låst | Én simpel respawn-baseret skirmish/team deathmatch, der kan skaleres mellem 1v1, 2v2 og 3v3 |
| D-020 | Match structure | Låst | Time limit + score limit, ikke elimination-runder i v1 |
| D-021 | Multiplayer rollout | Låst | Start med 1v1, udvid til 2v2, derefter 3v3 |
| D-022 | Netværksmodel v1 | Låst | Host/client listen-server over ENet, host kan spille med, join via IP/LAN, ingen backend-room-service i v1 |
| D-023 | V1 input | Låst | Keyboard + mus, ingen controller-support i v1 |
| D-024 | V1 loadout flow | Låst | Loadout vælges før kampstart og er låst under kampen |
| D-025 | V1 kampregler | Låst | Respawn delay, score limit, time limit, ingen spectators og ingen join mid-match |
| D-026 | Team model | Låst | To hold bruges i alle formater, også 1v1 |
| D-027 | V1 simplificeringer | Låst | Ingen accounts, ingen progression, ingen pickups, ingen weapon drops, ingen crouch-system udenfor slide |
| D-028 | Taser gun rolle | Låst | Secondary utility der stunner i 2 sek ved impact og har 5 sek cooldown |

## Loadout-system

### Slot 1: Primary

| Våben | Status | Regler |
| --- | --- | --- |
| Assault rifle | Låst | 30 skud pr. magasin, 10 body damage, 14 head damage, fuld auto, 4 magasiner i alt, 3.2 sek reload |
| Shotgun | Låst | 10 pellets, 5 body damage pr. pellet, 7.5 head damage pr. pellet, 21 skud i alt, 7 skud før reload, 0.5 sek cooldown mellem skud, 5 sek reload |
| Sniper | Låst | 100 head damage, 50 body damage, 10 skud i alt, 2 sek reload |
| Flame thrower | Låst | Kort rækkevidde, 50 DPS, 10 sek brændstof, kan give opdrift og fremdrift |

### Slot 2: Secondary

| Våben | Status | Regler |
| --- | --- | --- |
| Handgun | Låst | 13 skud pr. magasin, 16 body damage, 24 head damage, 4 magasiner i alt, 2.6 sek reload |
| Portal gun | Låst | 2 skud, ingen damage, 2 portaler, momentum bevares gennem portalen |
| Lasso | Låst | Uendelige uses, semi-lang rækkevidde, trækker ramt spiller mod brugeren, 0 damage, 5 sek cooldown |
| Taser gun | Låst | Hitscan utility, 0 damage, stunner ramt spiller i 2 sek, 5 sek cooldown |

### Slot 3: Melee

| Våben | Status | Regler |
| --- | --- | --- |
| Knife | Låst | Kort rækkevidde, 100 damage, uendelig ammo, 3 sek cooldown |

### Slot 4: Artillery

| Våben | Status | Regler |
| --- | --- | --- |
| Smoke bomb | Låst | 0 damage, uigennemsigtig røgsky, 3 charges, kasteafstand afhænger af momentum |
| Grenade | Låst | 75 damage, samme radius/range/air-time som smoke bomb, 3 charges, 5 sek cooldown |
| Redbull | Låst | 30 sek buff, +50% speed boost, 2 charges |

### Reload-regel

Status: `Låst`

- Reload er på `R`.
- Spilleren skal holde våbnet fremme under reload.
- Hvis man skifter væk fra våbnet midt i reload, er reload ikke færdig og skal startes forfra senere.

## Movement-system

| Mekanik | Status | Regler |
| --- | --- | --- |
| Jump | Låst | `Space`, momentum-baseret hoplængde |
| Slide | Låst med åbne detaljer | `Shift`, lille speed boost i starten, derefter gradvis slowdown, kan afbrydes med hop |
| Slide længde | Låst som relation | Maks slide-længde svarer til smoke bomb max range |
| Wallrun | Låst | Hvis spilleren er i luften og rammer en væg i vinkel, fortsætter wallrun indtil hop eller jordkontakt |
| Wallrun gravity | Låst | Spilleren falder langsomt nedad under wallrun |
| Climbability | Låst | Containere og kraner skal kunne traverseres |
| Flame mobility | Låst | Flame thrower kan bruges til opdrift og boost |

## Map-retning

Status: `Låst`

Første map bør designes som en kompakt, vertikal industrial playground med fokus på movement-linjer frem for realismens skyld alene.

Map-principper:

- flere højdelag
- tydelige wallrun-flader
- lange synslinjer til sniper, men ikke for mange
- tætte close-range zoner til shotgun/flamethrower
- traversal-ruter mellem containere, broer og kranplatforme
- få stærke landmarks, så spillere ikke mister orientering

## Anbefalet Kampstruktur

Status: `Låst`

Den simpleste og mest realistiske første mode er:

- én fælles `skirmish/team deathmatch`-regelpakke
- respawns i stedet for elimination-runder
- fast time limit
- fast score limit
- samme kerneflow for `1v1`, `2v2` og `3v3`

Begrundelse:

- Det er langt enklere at implementere og teste end runde-baserede modes.
- Det giver flere gentagelser af movement og combat pr. kamp.
- Det passer bedre til et movement-spil, hvor flow er vigtigt.

### Låste v1-regler

- Kampformat: `Team Skirmish`
- Teamstruktur: `Blue` vs `Orange`
- `1v1` spilles som ét hold mod ét hold
- Respawn delay: `3 sek`
- Spawn protection: `1 sek`
- Time limit: `8 minutter`
- Score limit: `20 kills`
- Friendly fire: `off`
- Join mid-match: `off`
- Spectators: `off`
- Ammo og charges resettes ved respawn
- Loadout kan ikke ændres midt i kampen
- Headshots er aktive på våben hvor der er særskilt head damage

### Kampflow v1

1. Host opretter kamp.
2. Spillere joiner lobby via IP/LAN.
3. Spillere vælger loadout.
4. Host starter kampen.
5. Kampen kører til score limit eller time limit.
6. Resultatskærm viser vinder og mulighed for rematch eller retur til lobby.

## Netværksmodel v1

Status: `Låst`

For at gøre v1 realistisk for Codex låses netværket til den enklest mulige model:

- `Godot ENet` listen-server
- host fungerer også som spiller
- klienter joiner via lokal IP eller manuel IP-adresse
- LAN er first-class target
- internetspil er kun realistisk i v1 hvis host kan eksponere den nødvendige port
- ingen konto-systemer
- ingen central matchmaking
- ingen room-code service
- ingen Steam networking i v1

Begrundelse:

- Det er den mest sandsynlige vej til en faktisk fungerende multiplayer-v1 uden backend-projekt ved siden af spillet.
- Det reducerer risikoen markant i forhold til NAT traversal, relay-services og social infrastruktur.

## V1 Produktgrænser

Status: `Låst`

- Input: keyboard + mus
- Platforme: macOS og Windows desktop
- Viewmodel: simple first-person placeholder-våben er acceptable i tidlige faser
- Karakterrepræsentation: simple mannequins eller kapsler er acceptable i tidlige netværksfaser
- Build-distribution: lokal debug-build eller simpel intern testbuild
- Ingen controller-support
- Ingen progression, cosmetics eller unlocks
- Ingen bots i første online-v1
- Ingen avanceret audio-pipeline som blocker for gameplay

## V1 Gameplay-defaults

Status: `Låst`

- Primær skydning er på venstre museknap
- Alternativ funktion er på højre museknap når et våben bruger den
- Våbenskift er på `1`, `2`, `3`, `4`
- Reload er på `R`
- Jump er på `Space`
- Slide er på `Shift`
- Der er ingen separat sprint-knap i v1
- Der er ingen aim-down-sights i v1
- Slide bruger ikke et separat crouch-system i v1
- Der er ingen fall damage i v1
- Der er ingen ammo pickups i v1

## Asset-strategi

Status: `Låst`

### Praktisk pipeline

1. Greybox map og gameplay med primitive meshes.
2. Lås movement og combat-feel før art pass.
3. Indfør modulære miljø-assets i GLB-format.
4. Tilføj realistiske PBR-materialer, decals, lys og atmosfære.
5. Tilføj karaktermodeller og våbenmodeller, når gameplayet holder.

### Låst asset-arbejdsgang for v1

- Greybox bygges med primitive former og modulære blokke
- Første art-pass må gerne bruge gratis placeholder-assets
- PBR-materialer og lys bruges til at løfte looket før vi jagter unikke hero-assets
- Karakterer kan være simple mannequins i tidlige builds
- Våben kan være simple viewmodels eller low-detail proxies i tidlige builds
- Miljøets readability prioriteres højere end høj asset-kompleksitet
- Gameplay og combat-balance maa ikke kobles til en bestemt asset-pack, saa vi senere kan skifte art uden at aendre mekanikkerne
- Raa vendor-downloads og store kildeformater committes ikke; agenten skal importere fra de reducerede runtime-mapper under `assets/third_party/quaternius/`
- Den nuvaerende lokale kickoff-baseline er `Downtown City MegaKit`, `Ultimate Modular Men Pack` og `Animated Guns Pack`

### Asset shortlist v1

Status: `Låst`

Anbefalet visuel familie til v1 er en `grounded urban low-poly` retning primært fra `Quaternius`, så miljø, karakterer og våben holder sig inden for samme formsprog.

#### Miljø

- Primær miljøpakke: `Downtown City MegaKit`
- Lokal path: `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)`
- Sekundær miljøpakke: `Modular Streets Pack` kun som supplement til vejstykker, ramper og simple byelementer
- Status: valgfri reserve, ikke noedvendig for kickoff
- Regel: downtown-pakken definerer hovedstilen, og ældre pakker må ikke overtage looket

#### Karakterer

- Primær karakterpakke: `Ultimate Modular Men Pack`
- Lokal path: `assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF`
- Brug kun den grounded del af pakken i v1
- Tilladte silhouettes til v1: suit, worker, construction, hoodie/punk-lignende civilian, tactical/sci-fi suit hvis den tones ned i farver
- Ikke tilladte silhouettes til v1: horse mask, konge-look og andre tydeligt joke-prægede figurer
- Team readability skabes via farvezoner, arm/vest-markeringer og simple UI-markører, ikke via helt forskellige karakteruniverser

#### Våben

- Primær våbenpakke: `Animated Guns Pack`
- Lokal path: `assets/third_party/quaternius/animated_guns_pack/FBX`
- Bruges til de første realistiske core-våben: assault rifle, handgun, shotgun og sniper
- Sekundær våbenreference: `Ultimate Guns Pack` som reservebibliotek til senere våbenudvidelser
- Status: reserve, ikke noedvendig for kickoff
- Knife og smoke bomb kan laves som simple custom low-poly props i samme materiale- og farvesprog

#### Stilregel

- Vi jagter ikke fotorealisme i geometri
- Vi jagter et troværdigt, lidt mere realistisk by-look gennem lys, materialer, decals og konsekvent assetvalg
- Hvis et asset ser fedt ud alene men ikke matcher `Downtown City MegaKit`, bruges det ikke i v1

### Kilder der ser realistiske ud at bruge

- `Poly Haven`: gratis modeller, HDRI og materialer
- `ambientCG`: gratis PBR-materialer
- `Quaternius`: gratis model packs, ofte styliserede men gode til hurtig modularitet
- `Kenney`: gratis kits, gode til prototype og simple environment blocks

### Anbefalet art-kompromis

Den mest realistiske retning for dette projekt er sandsynligvis:

- styliseret eller semi-realistisk geometri
- troværdige materialer og lys
- tydelig readability over ren detaljegrad

Det giver et bedre resultat end:

- fuldt AI-genererede 3D hero-assets
- fotorealistiske karakterer og våben fra scratch
- for tidlig satsning på komplekse custom animation pipelines

## Ting Vi Ikke Bør Låse For Tidligt

Status: `Foreslået`

- endelige damage-tal
- præcis time-to-kill
- alle specialvåben i første vertical slice
- fuldt invite-system med accounts/social graph
- mange maps
- avanceret cosmetic/progression

## MVP-forslag

Status: `Låst`

Hvis målet er at få en agent til faktisk at bygge dette, bør første rigtige playable version være:

- 1 map
- native desktop only
- host/join multiplayer via IP eller LAN
- `1v1` først eller anden meget lille spillerkonfiguration, hvis det reducerer risiko tidligt
- movement sandbox + combat
- loadout-system med et begrænset antal første våben
- simple hit-reacts og tydelig HUD
- host/join via IP eller LAN i stedet for fuldt venne-/konto-system

## Preproduction Gate

Status: `Cleared`

De vigtigste preproduction-beslutninger er nu låst:

- engine og teknisk retning
- første mode og kampstruktur
- rollout fra `1v1` til `3v3`
- første våbensæt til vertical slice
- placeholder-politik
- simpel invite-model
