# AGENTS.md

## Formål

Denne repo bruges til at bygge et native `Godot 4` movement-FPS i små, kontrollerede faser. En agent skal arbejde konservativt, følge dokumenterne i korrekt rækkefølge og undgå at opfinde nye retninger, når projektet allerede har låste beslutninger.

## Læserækkefølge

Læs altid disse dokumenter før implementering:

1. `docs/fps-design-brief.md`
2. `docs/fps-technical-spec.md`
3. `docs/fps-development-plan.md`

Hvis du arbejder med art eller asset-import, laes ogsaa `assets/README.md`.

## Hvad de enkelte dokumenter betyder

- `fps-design-brief.md`: produkt- og gameplay-source-of-truth
- `fps-technical-spec.md`: teknisk source-of-truth for Godot-struktur, data, netcode og defaults
- `fps-development-plan.md`: eneste plan-source-of-truth for fase-rækkefølge, operative agent-opgaver og exit-kriterier

## Hvilken plan skal agenten følge?

Følg kun `docs/fps-development-plan.md` som plan.

Standard goal-prompt for denne repo er:

```text
Implementer fps-development-plan.md fase for fase og sørg for at exit kriterier for hver fase er opfyldt, før du går videre til næste fase.
```

Praktisk regel:

- `fps-development-plan.md` bestemmer både `hvad der kommer før hvad` og `hvad du gør lige nu`
- Der må ikke oprettes eller bruges et separat agentfase-dokument

Hvis de konflikter:

1. `fps-design-brief.md` vinder
2. `fps-technical-spec.md` vinder derefter
3. `fps-development-plan.md` vinder derefter

## Agent-adfærd

- Implementér kun den næste uafsluttede fase eller subfase
- Spring ikke direkte til senere features
- Hold placeholders så længe planens fase siger det er korrekt
- Brug `Godot 4` og `GDScript`
- Læg konfigurerbare gameplay-tal i data/resources, ikke som magic numbers i scripts
- Hold movement, combat, UI og netcode som separate systemer
- Tilføj ikke backend-services udenfor spilprojektet
- Hold v1 på `host/client ENet listen-server`
- Default primary/loadout og P10A visual-polish flow skal bruge `assault_rifle`, ikke `shotgun`. Shotgun må kun bruges som historisk/extended weapon-bevis, hvis den eksplicit testes som selectable weapon, og aldrig som default primary-bevis.
- Skift ikke asset-familie uden at opdatere dokumentationen
- Bevar altid repoets launch-kontrakt: spillet skal kunne startes med `./run.sh` fra root
- Bevar også editor-kontrakten: `./run.sh --editor` skal importere Godot-assets først og åbne `res://scenes/maps/art/arena_downtown_01_art.tscn`, så editoren viser den eksisterende arena med city assets i stedet for en tom scene
- Efter hver implementeringsfase skal spillet startes i en rigtig Godot GUI build via `./run.sh`, og agenten skal bruge computer-use/GUI-observation til at vurdere om spillet også giver visuel mening. Headless tests alene er aldrig nok til at markere en fase `done`.
- Hvis en fase ændrer assets, kamera, HUD, våben, player visuals, map layout, lys, FX eller multiplayer-repræsentation, skal agenten tage screenshots fra den kørende game viewport og kontrollere åbenlyse visuelle fejl som forkert rotation, forkert skala, clipping, usynlige assets, UI-overlap, kamera inde i geometri, eller våben der vender forkert.
- Screenshots tæller kun som bevis, hvis agenten bagefter åbner og vurderer dem visuelt. Det er ikke nok at screenshot-filen findes. Agenten skal skrive konkrete observationer om billedet og markere fasen `in_progress` eller `blocked`, hvis billedet ser forkert ud.
- Hvis brugeren afviser et screenshot eller påpeger en konkret visuel fejl, vinder brugerens observation over agentens tidligere `pass`-markering. Fasen skal genåbnes, indtil fejlen er rettet og verificeret med nye screenshots.

## Asset-workflow

- Commit kun import-klare/runtime-noedvendige asset-dele; store source archives, screenshots, Blender-kilder og preview-filer skal holdes ude af git
- Importer til Godot fra `assets/third_party/quaternius/`
- Den nuvaerende mandatory lokale baseline er:
  - `assets/third_party/quaternius/downtown_city_megakit/`
  - `assets/third_party/quaternius/ultimate_modular_men_pack/`
  - `assets/third_party/quaternius/animated_guns_pack/`
- `modular_streets_pack` og `ultimate_guns_pack` er valgfrie supplement-/reservepakker og er ikke kickoff-blokkere, men deres raapakker skal ikke committes
- Brug de lokale packs foer du leder efter andre gratis assets
- Hold gameplay og data uafhaengige af den aktuelle asset-familie, saa art kan udskiftes senere

## Når du implementerer

- Start med den første fase i `fps-development-plan.md`, der ikke er markeret `done`
- Opfyld exit-kriterierne for den fase før du går videre
- Udfør den globale computer-use visuelle QA fra `fps-development-plan.md` før fasen markeres `done`
- Hvis du undervejs opdager at dokumentationen mangler noget vigtigt, opdatér docs i samme ændring
- Hvis et valg allerede er låst i dokumenterne, genåbn det ikke uden tydelig grund

## Når du er færdig med en fase

- verificér at exit-kriterierne faktisk er opfyldt
- verificér med computer-use/GUI-observation at den kørende build visuelt ser korrekt ud for fasens ændringer
- åbn de screenshots fasen bruger som bevis og skriv konkret, hvad de viser; screenshots uden efterfølgende visuel vurdering er ugyldige
- opdatér relevant dokumentation hvis implementeringen præciserer noget
- foreslå næste konkrete fase ud fra `fps-development-plan.md`
