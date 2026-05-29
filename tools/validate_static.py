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
        "players_per_team": "3",
        "respawn_delay_sec": "3.0",
        "spawn_protection_sec": "1.0",
        "time_limit_sec": "480.0",
        "score_limit": "20",
        "friendly_fire": "false",
        "allow_join_mid_match": "false",
        "allow_spectators": "false",
        "allow_loadout_changes_mid_match": "false",
    }
    for key, expected_value in expected.items():
        if values.get(key) != expected_value:
            fail(f"match rule {key} expected {expected_value}, got {values.get(key)}")


def main() -> None:
    assert_resource_paths_exist()
    assert_inputs()
    assert_weapons()
    assert_match_rules()
    print("static validation passed")


if __name__ == "__main__":
    main()
