#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/maps/downtown_city_asset_catalog.json"
ARENA_ART_SCENE = ROOT / "scenes/maps/art/arena_downtown_01_art.tscn"
ARENA_ART_SCRIPT = ROOT / "scripts/maps/art/arena_downtown_01_art.gd"
PLUGIN_CFG = ROOT / "addons/city_level_designer/plugin.cfg"
PLUGIN_SCRIPT = ROOT / "addons/city_level_designer/city_level_designer_plugin.gd"
DOCK_SCRIPT = ROOT / "addons/city_level_designer/city_level_designer_dock.gd"
PLACEMENT_SCRIPT = ROOT / "scripts/maps/downtown_city_asset_instance.gd"
CAPTURE_SCRIPT = ROOT / "tools/capture_p23_editor_palette.gd"
SCREENSHOTS = [
    ROOT / "docs/verification/screenshots/p23_level_designer_editor_palette.png",
]

REQUIRED_CATEGORIES = {"building", "facade", "street", "trim", "prop", "landmark", "backdrop"}
MAP_LAYERS = {
    "GameplayCore",
    "TraversalRoutes",
    "CombatCover",
    "SkylineBackdrop",
    "SpawnSpaces",
    "HazardsAndKillVolumes",
    "LightingAndAtmosphere",
}


def fail(message: str) -> None:
    print(f"P23 validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def res_to_path(path: str) -> pathlib.Path:
    if not path.startswith("res://"):
        fail(f"expected res:// path, got {path}")
    return ROOT / path.removeprefix("res://")


def assert_catalog() -> list[dict]:
    if not CATALOG.exists():
        fail(f"missing {CATALOG.relative_to(ROOT)}")
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    entries = data.get("entries", [])
    if len(entries) < 25:
        fail(f"catalog has {len(entries)} entries, expected at least 25")
    categories = {entry.get("category") for entry in entries}
    missing_categories = REQUIRED_CATEGORIES - categories
    if missing_categories:
        fail(f"catalog missing categories {sorted(missing_categories)}")
    seen_ids: set[str] = set()
    for entry in entries:
        asset_id = str(entry.get("asset_id", ""))
        if not re.fullmatch(r"[a-z0-9_]+", asset_id):
            fail(f"invalid asset_id {asset_id}")
        if asset_id in seen_ids:
            fail(f"duplicate asset_id {asset_id}")
        seen_ids.add(asset_id)
        for key in ["display_name", "category", "source_path", "default_scale", "default_rotation_degrees"]:
            if key not in entry:
                fail(f"{asset_id} missing {key}")
        source_path = str(entry["source_path"])
        if "assets/source_packs/quaternius" in source_path:
            fail(f"{asset_id} uses source_packs")
        if "assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)" not in source_path:
            fail(f"{asset_id} does not use Downtown City MegaKit third_party path")
        if not res_to_path(source_path).exists():
            fail(f"{asset_id} source path missing: {source_path}")
        if len(entry["default_scale"]) != 3 or len(entry["default_rotation_degrees"]) != 3:
            fail(f"{asset_id} has invalid transform defaults")
    return entries


def assert_tool_files() -> None:
    for path in [PLUGIN_CFG, PLUGIN_SCRIPT, DOCK_SCRIPT, PLACEMENT_SCRIPT, CAPTURE_SCRIPT]:
        if not path.exists():
            fail(f"missing {path.relative_to(ROOT)}")
    project_text = (ROOT / "project.godot").read_text(encoding="utf-8")
    if "res://addons/city_level_designer/plugin.cfg" not in project_text:
        fail("City Asset Level Designer plugin is not enabled in project.godot")
    plugin_text = PLUGIN_CFG.read_text(encoding="utf-8")
    if 'script="city_level_designer_plugin.gd"' not in plugin_text:
        fail("plugin.cfg must use a plugin-relative script path")
    dock_text = DOCK_SCRIPT.read_text(encoding="utf-8")
    for token in [
        "EditorUndoRedoManager",
        "Preview Ghost",
        "Clear Preview",
        "Place",
        "Apply Transform",
        "Duplicate",
        "Delete",
        "Validate",
        "_snap_value",
        "_rotation_step_value",
        "add_do_method",
        "add_do_property",
    ]:
        if token not in dock_text:
            fail(f"dock script missing designer capability token {token}")
    placement_text = PLACEMENT_SCRIPT.read_text(encoding="utf-8")
    for token in ["ResourceLoader.exists", "GLTFDocument", "visual_only", "source_path"]:
        if token not in placement_text:
            fail(f"placement script missing required loading/provenance token {token}")
    capture_text = CAPTURE_SCRIPT.read_text(encoding="utf-8")
    if "city_level_designer_dock.gd" not in capture_text:
        fail("editor palette capture must render the actual dock control")


def assert_direct_arena_scene() -> None:
    if not ARENA_ART_SCENE.exists():
        fail(f"missing {ARENA_ART_SCENE.relative_to(ROOT)}")
    text = ARENA_ART_SCENE.read_text(encoding="utf-8")
    script_text = ARENA_ART_SCRIPT.read_text(encoding="utf-8")
    if "arena_downtown_01_city_dressing.tscn" in text or "p23_city_asset_dressing.tscn" in text:
        fail("arena art scene still instances a separate dressing scene")
    if "P23CityAssetDressing" in text:
        fail("arena art scene still contains nested P23 dressing root")
    for token in [
        "P04_DRESSING_ASSETS",
        "P10A_",
        "_add_city_surface_replacement_assets",
        "arena_downtown_01_city_dressing.tscn",
    ]:
        if token in script_text:
            fail(f"arena art script still contains generated placement token {token}")
    placements = re.findall(
        r'\[node name="(?P<name>(?:P04|P10A|P23)_[^"]+)" type="Node3D" parent="(?P<parent>[^"]+)"\](?P<body>.*?)(?=\n\[node|\Z)',
        text,
        flags=re.S,
    )
    names: set[str] = set()
    for name, parent, body in placements:
        if name in names:
            fail(f"duplicate placement node name {name}")
        names.add(name)
        layer = parent.split("/")[-1]
        if layer not in MAP_LAYERS:
            fail(f"{name} parented under invalid layer {parent}")
        asset_match = re.search(r'asset_id = "([^"]+)"', body)
        source_match = re.search(r'source_path = "([^"]+)"', body)
        map_layer_match = re.search(r'map_layer = &"([^"]+)"', body)
        scale_match = re.search(r"scale = Vector3\(([^)]+)\)", body)
        if not asset_match or not source_match or not map_layer_match:
            fail(f"{name} missing asset_id/source_path/map_layer")
        source_path = source_match.group(1)
        if "assets/source_packs/quaternius" in source_path:
            fail(f"{name} uses source_packs")
        if not res_to_path(source_path).exists():
            fail(f"{name} source path missing: {source_path}")
        if map_layer_match.group(1) != layer:
            fail(f"{name} map_layer {map_layer_match.group(1)} does not match parent {layer}")
        if not scale_match:
            fail(f"{name} missing scale")
        scale_values = [float(value.strip()) for value in scale_match.group(1).split(",")]
        if any(value <= 0.0 for value in scale_values):
            fail(f"{name} has non-positive scale {scale_values}")


def assert_screenshots() -> None:
    for path in SCREENSHOTS:
        if not path.exists():
            fail(f"missing screenshot {path.relative_to(ROOT)}")
        if path.stat().st_size < 10_000:
            fail(f"screenshot too small to be useful: {path.relative_to(ROOT)}")


def main() -> None:
    catalog = assert_catalog()
    assert_tool_files()
    assert_direct_arena_scene()
    assert_screenshots()
    print(
        "P23 validation passed: "
        f"catalog_entries={len(catalog)} editable_scene={ARENA_ART_SCENE.relative_to(ROOT)}"
    )


if __name__ == "__main__":
    main()
