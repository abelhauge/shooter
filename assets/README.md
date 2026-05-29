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

## Agentregler

- Rediger ikke vendor-filer direkte
- Commit ikke source archives, screenshots, Blender-kilder, preview-videoer eller andre store filer, som ikke er noedvendige for at bygge og koere spillet
- Lav kuraterede Godot-scenes, prefabs og material-overrides uden for vendor-mapperne
- Bevar gameplay-logik, collision og data uafhaengigt af den nuvaerende art-familie
- Hvis bedre assets findes senere, skiftes art-laget uden at aendre designregler eller balance-data
