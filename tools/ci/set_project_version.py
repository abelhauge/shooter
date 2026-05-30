#!/usr/bin/env python3
"""Set the Godot application version before CI export."""

from __future__ import annotations

import argparse
from pathlib import Path


def set_application_version(project_file: Path, version: str) -> None:
    text = project_file.read_text(encoding="utf-8")
    lines = text.splitlines()
    output: list[str] = []
    in_application = False
    saw_application = False
    wrote_version = False

    for line in lines:
        if line.strip() == "[application]":
            in_application = True
            saw_application = True
            output.append(line)
            continue

        if in_application and line.startswith("[") and line.endswith("]"):
            if not wrote_version:
                output.append(f'config/version="{version}"')
                wrote_version = True
            in_application = False

        if in_application and line.startswith("config/version="):
            output.append(f'config/version="{version}"')
            wrote_version = True
        else:
            output.append(line)

    if in_application and not wrote_version:
        output.append(f'config/version="{version}"')
        wrote_version = True

    if not saw_application:
        output.extend(["", "[application]", f'config/version="{version}"'])

    project_file.write_text("\n".join(output) + "\n", encoding="utf-8")


def set_export_preset_versions(export_presets_file: Path, version: str) -> None:
    if not export_presets_file.exists():
        return

    version_keys = {
        "application/file_version",
        "application/product_version",
        "application/short_version",
        "application/version",
    }
    output: list[str] = []
    for line in export_presets_file.read_text(encoding="utf-8").splitlines():
        key = line.split("=", 1)[0] if "=" in line else ""
        if key in version_keys:
            output.append(f'{key}="{version}"')
        else:
            output.append(line)

    export_presets_file.write_text("\n".join(output) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument(
        "--project-file",
        default="project.godot",
        type=Path,
        help="Path to project.godot",
    )
    parser.add_argument(
        "--export-presets-file",
        default="export_presets.cfg",
        type=Path,
        help="Path to export_presets.cfg",
    )
    args = parser.parse_args()

    if not args.project_file.exists():
        parser.error(f"Project file not found: {args.project_file}")

    set_application_version(args.project_file, args.version)
    set_export_preset_versions(args.export_presets_file, args.version)
    print(f"Set Godot application version to {args.version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
