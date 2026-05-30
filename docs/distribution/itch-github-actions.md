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

## Manual Release

The workflow can also be started manually from:

```text
GitHub -> Actions -> Build and publish to itch.io -> Run workflow
```

## Local Release

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
- macOS builds are currently unsigned. Friends may need to approve the first launch in macOS security settings until code signing/notarization is added.
