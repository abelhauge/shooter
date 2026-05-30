#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]

REQUIRED_INPUTS = [
    "move_forward",
    "move_back",
    "move_left",
    "move_right",
    "jump",
    "slide",
    "reload",
    "fire_primary",
    "fire_secondary",
    "slot_primary",
    "slot_secondary",
    "slot_melee",
    "slot_artillery",
    "pause",
]

REQUIRED_WEAPONS = [
    "assault_rifle",
    "handgun",
    "knife",
    "smoke_bomb",
    "shotgun",
    "sniper",
    "grenade",
    "flamethrower",
    "lasso",
    "taser_gun",
    "redbull",
    "portal_gun",
]


def fail(message: str) -> None:
    print(f"static validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(path: str) -> str:
    file_path = ROOT / path
    if not file_path.exists():
        fail(f"missing {path}")
    return file_path.read_text(encoding="utf-8")


def parse_resource(path: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in read(path).splitlines():
        if "=" not in line or line.startswith("["):
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def assert_resource_paths_exist() -> None:
    paths = list((ROOT / "scripts").glob("**/*.gd"))
    paths += list((ROOT / "scenes").glob("**/*.tscn"))
    paths += list((ROOT / "data").glob("**/*.tres"))
    paths.append(ROOT / "project.godot")
    missing: list[tuple[str, str]] = []
    for path in paths:
        text = path.read_text(encoding="utf-8")
        for match in re.findall(r'"(res://[^"]+)"', text):
            if match.startswith("res://docs/verification/screenshots/"):
                continue
            if not (ROOT / match.removeprefix("res://")).exists():
                missing.append((str(path.relative_to(ROOT)), match))
    if missing:
        fail(f"missing res:// targets: {missing}")


def assert_inputs() -> None:
    project = read("project.godot")
    for action in REQUIRED_INPUTS:
        if f"{action}={{" not in project:
            fail(f"missing input action {action}")


def assert_weapons() -> None:
    controller = read("scripts/weapons/weapon_controller.gd")
    for weapon_id in REQUIRED_WEAPONS:
        weapon_path = f"data/weapons/{weapon_id}.tres"
        values = parse_resource(weapon_path)
        encoded_id = f'&"{weapon_id}"'
        if values.get("weapon_id") != encoded_id:
            fail(f"{weapon_path} has wrong weapon_id: {values.get('weapon_id')}")
        if f'&"{weapon_id}": "res://{weapon_path}"' not in controller:
            fail(f"WeaponController.WEAPON_PATHS missing {weapon_id}")
        if "slot_type" not in values or "fire_mode" not in values:
            fail(f"{weapon_path} missing slot_type or fire_mode")

    expected_tuning = {
        "assault_rifle": {
            "magazine_size": "30",
            "reserve_ammo_max": "90",
            "reload_time_sec": "3.2",
            "body_damage": "10.0",
            "head_damage": "14.0",
        },
        "handgun": {
            "magazine_size": "13",
            "reserve_ammo_max": "39",
            "reload_time_sec": "2.6",
            "body_damage": "16.0",
            "head_damage": "24.0",
        },
    }
    for weapon_id, expected in expected_tuning.items():
        values = parse_resource(f"data/weapons/{weapon_id}.tres")
        for key, expected_value in expected.items():
            if values.get(key) != expected_value:
                fail(f"{weapon_id} {key} expected {expected_value}, got {values.get(key)}")
    knife = parse_resource("data/weapons/knife.tres")
    if knife.get("body_damage") != "100.0":
        fail("knife damage does not match v1 spec")
    smoke = parse_resource("data/weapons/smoke_bomb.tres")
    if (
        smoke.get("charges_max") != "3"
        or smoke.get("effect_duration_sec") != "14.0"
        or smoke.get("effect_radius_m") != "4.0"
    ):
        fail("smoke bomb values do not match v1 spec")


def assert_match_rules() -> None:
    values = parse_resource("data/match/team_skirmish_v1.tres")
    expected = {
        "mode_id": '&"team_skirmish"',
        "team_count": "2",
        "players_per_team": "0",
        "respawn_delay_sec": "3.0",
        "spawn_protection_sec": "1.0",
        "time_limit_sec": "480.0",
        "score_limit": "20",
        "friendly_fire": "false",
        "allow_join_mid_match": "true",
        "allow_spectators": "false",
        "allow_loadout_changes_mid_match": "false",
    }
    for key, expected_value in expected.items():
        if values.get(key) != expected_value:
            fail(f"match rule {key} expected {expected_value}, got {values.get(key)}")


def assert_gpu_texture_compression() -> None:
    project = read("project.godot")
    for setting in (
        'renderer/rendering_method="forward_plus"',
        "textures/vram_compression/import_s3tc_bptc=true",
        "textures/vram_compression/import_etc2_astc=true",
    ):
        if setting not in project:
            fail(f"missing project GPU texture import setting {setting}")

    export_presets = read("export_presets.cfg")
    preset_match = re.search(r'\[preset\.(\d+)\]\s+name="macOS"', export_presets)
    if preset_match is None:
        fail("missing macOS export preset")
    options_header = f"[preset.{preset_match.group(1)}.options]"
    if options_header not in export_presets:
        fail("missing macOS export preset options")
    macos_preset = export_presets.split(options_header, 1)[1]
    next_preset = re.search(r"\n\[preset\.\d+", macos_preset)
    if next_preset is not None:
        macos_preset = macos_preset[: next_preset.start()]
    for setting in (
        "texture_format/s3tc_bptc=true",
        "texture_format/etc2_astc=true",
    ):
        if setting not in macos_preset:
            fail(f"macOS export preset missing GPU texture format {setting}")


def assert_macos_distribution_signing() -> None:
    workflow = read(".github/workflows/itch-build.yml")
    for expected in (
        "runs-on: macos-latest",
        'tools/ci/sign_macos_zip.sh "build/macos/MovementFPS.zip"',
        'butler push "build/macos/MovementFPS.zip" "${ITCH_TARGET}:mac"',
    ):
        if expected not in workflow:
            fail(f"macOS GitHub release workflow missing {expected}")

    signing_script = read("tools/ci/sign_macos_zip.sh")
    for expected in (
        "codesign --force --deep --sign -",
        "codesign --force --deep --options runtime --timestamp --sign",
        "codesign --verify --deep --strict",
        "xcrun notarytool submit",
        "xcrun stapler staple",
        "ditto -c -k --keepParent",
    ):
        if expected not in signing_script:
            fail(f"macOS signing helper missing {expected}")


def assert_run_script_git_pull() -> None:
    run_script = read("run.sh")
    for expected in (
        "SHOOTER_SKIP_GIT_SYNC",
        'git -C "$ROOT_DIR" pull --ff-only --autostash',
        "sync_github_before_run",
    ):
        if expected not in run_script:
            fail(f"run.sh missing git sync behavior {expected}")

    windows_run_script = read("run.cmd")
    for expected in (
        'for %%I in ("%~dp0.") do set "ROOT_DIR=%%~fI"',
        'set "ROOT_DIR=%ROOT_DIR:"=%"',
        'pushd "%ROOT_DIR%"',
        "--path .",
        "SHOOTER_SKIP_GIT_SYNC",
        'git -C "%ROOT_DIR%" pull --ff-only --autostash',
        ":sync_github_before_run",
        "%LOCALAPPDATA%\\Microsoft\\WinGet\\Links",
        "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages",
        ":find_godot_under",
    ):
        if expected not in windows_run_script:
            fail(f"run.cmd missing git sync behavior {expected}")
    for forbidden in (
        'git -C "%ROOT_DIR%" add -A',
        'git -C "%ROOT_DIR%" commit',
        'git -C "%ROOT_DIR%" push',
    ):
        if forbidden in windows_run_script:
            fail(f"run.cmd should not auto-write to git during launch: {forbidden}")
    for forbidden in (
        "%ROOT_DIR%project.godot",
        '--path "%ROOT_DIR%"',
        "%ROOT_DIR%.godot",
        "%ROOT_DIR%.bin",
    ):
        if forbidden in windows_run_script:
            fail(f"run.cmd should use normalized ROOT_DIR with explicit separators: {forbidden}")

    windows_install_script = read("install.cmd")
    for expected in (
        'for %%I in ("%~dp0.") do set "ROOT_DIR=%%~fI"',
        'set "ROOT_DIR=%ROOT_DIR:"=%"',
        'pushd "%ROOT_DIR%"',
        "--path .",
        "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages",
        "%LOCALAPPDATA%\\Microsoft\\WinGet\\Links",
        ":find_godot_under",
        'dir /b /s "%~1\\Godot*.exe"',
    ):
        if expected not in windows_install_script:
            fail(f"install.cmd missing Windows Godot resolver behavior {expected}")
    for forbidden in (
        "%ROOT_DIR%project.godot",
        '--path "%ROOT_DIR%"',
        "%ROOT_DIR%tools\\validate_static.py",
        "%ROOT_DIR%assets\\",
        "%ROOT_DIR%.bin",
    ):
        if forbidden in windows_install_script:
            fail(f"install.cmd should use normalized ROOT_DIR with explicit separators: {forbidden}")


def main() -> None:
    assert_resource_paths_exist()
    assert_inputs()
    assert_weapons()
    assert_match_rules()
    assert_gpu_texture_compression()
    assert_macos_distribution_signing()
    assert_run_script_git_pull()
    print("static validation passed")


if __name__ == "__main__":
    main()
