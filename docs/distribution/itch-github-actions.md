# itch.io GitHub Actions Distribution

This repo builds Windows and macOS exports on every push to `main` and publishes them to:

```text
abelhauge/shooter
```

The itch channels are:

- `windows`
- `mac`

The version format is:

```text
0.1.<github_run_number>
```

If a workflow run is re-run, the retry gets:

```text
0.1.<github_run_number>.<github_run_attempt>
```

## Required GitHub Secret

Create an itch.io API key and add it in GitHub:

```text
Settings -> Secrets and variables -> Actions -> New repository secret
Name: ITCH_KEY
Value: <your itch.io API key>
```

The workflow uses `butler push` with `--userversion`, so the itch app can update installed copies from the pushed channel versions.

## In-game Update Check

The lobby checks itch's public latest-version endpoint on startup:

```text
https://itch.io/api/1/x/wharf/latest?target=abelhauge/shooter&channel_name=<channel>
```

Channels:

- macOS: `mac`
- Windows: `windows`

If the returned `latest` value is newer than Godot's `application/config/version`, the lobby shows an update banner and opens the itch page when the player clicks `Update`.

This is deliberately an update prompt, not a self-updater. Replacing a running `.app` or `.exe` safely needs a separate launcher/updater or itch app integration, especially on macOS where Gatekeeper quarantine and signing/notarization are involved.

## Manual Release

The workflow can also be started manually from:

```text
GitHub -> Actions -> Build and publish to itch.io -> Run workflow
```

## Local Release

Run the installer first; it verifies or installs Godot, Python and butler:

```bash
./install.sh
```

Local publishing reads `.env` and pushes the same itch channels:

```bash
tools/ci/publish_itch_local.sh
```

You can also pass an explicit version:

```bash
tools/ci/publish_itch_local.sh 0.1.123
```

## Notes

- Godot and export templates are downloaded during CI; they are not committed to the repo.
- Build outputs stay in `build/` and are ignored by git.
- macOS builds run on a macOS GitHub runner and are ad-hoc signed before publishing, so they are no longer completely unsigned bundles.
- Ad-hoc signing is not the same as Apple Developer ID notarization. Friends may still need to right-click the app and choose `Open` the first time, or use macOS Security settings to approve it.
- One-click macOS launch from a direct download requires Developer ID signing and Apple notarization secrets in CI.
- Desktop builds use Godot `Forward+`; normal macOS GUI runs should report the Metal renderer.
- macOS exports use GPU-compressed texture formats. Keep both `texture_format/etc2_astc=true` and `texture_format/s3tc_bptc=true` in the macOS preset, and keep both matching VRAM import settings enabled in `project.godot`.
