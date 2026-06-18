# GitHub release distribution contract

| Field | Value |
|---|---|
| Date | 2026-06-18 |
| Area | build |
| Tags | github-releases, update-script, versioning, distribution |
| Status | confirmed |

## Symptom

The project was moving from ad-hoc Google Drive zip sharing to a public GitHub
repository, but the repo had no stable version source, no release asset
contract, and no updater entry point.

## Root cause

The old release flow treated `dist/OSPlus.zip` as a hand-uploaded artifact.
That works for a small closed group, but it gives users no stable "latest"
download target and gives maintainers no machine-readable version to publish
or check.

## Fix

The release contract is now:

- `dist/version.json` is the source of truth for the public version.
- GitHub tags are `v<version>`.
- GitHub Releases upload `OSPlus.zip` and `version.json`.
- `update.bat` and `update.sh` download
  `https://github.com/LuizinhoF/osplus/releases/latest/download/OSPlus.zip`
  and rerun the platform installer.

## Lesson

Keep the asset name stable and put the changing version in the tag/manifest.
That gives users and scripts a permanent latest-release URL without guessing
which versioned zip filename to download.

## Related

- Files: `dist/version.json`, `dist/update.ps1`, `dist/update.sh`,
  `tools/release/publish_github_release.ps1`
- Docs: `docs/ops/github-release-distribution.md`
