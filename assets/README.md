# Asset Layout

Dette projekt holder kun import-klare/runtime-noedvendige assets i git. Raa vendor-downloads og store kildeformater skal ligge lokalt udenfor git eller genskabes fra den oprindelige asset-download ved behov.

## Mapper

- `assets/third_party/quaternius/`
  - import-klar mirror af de pack-dele vi faktisk bruger runtime/editor
  - er den godkendte kilde til foerste art-pass og Godot-import

## Lokal baseline pr. 2026-05-24

- Miljoe:
  - `assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)`

- Karakterer:
  - `assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF`

- Vaaben:
  - `assets/third_party/quaternius/animated_guns_pack/FBX`
  - `assets/third_party/quaternius/scifi_modular_gun_pack/gltf`
  - `assets/third_party/kenney/food_kit/glb`

## Kuraterede ekstra packs pr. 2026-05-29

- `Quaternius Sci-Fi Modular Gun Pack`
  - kilde: `https://quaternius.com/packs/scifimodularguns.html`
  - license: `CC0`
  - brugt til de tidligere hjemmelavede sci-fi/throwable viewmodels

- `Kenney Food Kit`
  - kilde: `https://kenney.nl/assets/food-kit`
  - license: `Creative Commons CC0`
  - brugt til energy can og knife, hvor den lokale Quaternius-baseline ikke havde gode replacements

## Agentregler

- Rediger ikke vendor-filer direkte
- Commit ikke source archives, screenshots, Blender-kilder, preview-videoer eller andre store filer, som ikke er noedvendige for at bygge og koere spillet
- Lav kuraterede Godot-scenes, prefabs og material-overrides uden for vendor-mapperne
- Bevar gameplay-logik, collision og data uafhaengigt af den nuvaerende art-familie
- Hvis bedre assets findes senere, skiftes art-laget uden at aendre designregler eller balance-data
