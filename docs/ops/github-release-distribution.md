# GitHub release distribution

OSPlus public builds are distributed through GitHub Releases on
`LuizinhoF/osplus`. Google Drive is no longer the release channel.

## Version source

The source of truth for the public package version is:

```text
dist/version.json
```

Release tags use the same version with a `v` prefix:

```text
0.2.1 -> v0.2.1
```

Every GitHub Release must upload these assets:

- `OSPlus.zip`
- `version.json`

The update scripts use GitHub's stable latest-release URL:

```text
https://github.com/LuizinhoF/osplus/releases/latest/download/OSPlus.zip
```

That means the asset name must stay `OSPlus.zip` even when the release tag
changes.

## User install and update

Install:

- Windows: extract `OSPlus.zip`, run `install.bat`.
- Linux / Steam Deck: extract `OSPlus.zip`, run `bash install.sh`.

Update:

- Windows: run `update.bat` from an extracted OSPlus package.
- Linux / Steam Deck: run `bash update.sh` from an extracted OSPlus package.

The updater downloads the latest `OSPlus.zip`, extracts it to a temporary
folder, and reruns the installer. The install scripts remain idempotent and are
the only code path that writes into the game folder.

## Maintainer release flow

Prerequisites:

- The game is closed.
- The UE content has been cooked.
- `ue-assets/package_logicmod.ps1` has produced `OSPlus.pak`.
- The working tree is clean on `main`.
- `GH_TOKEN` or `GITHUB_TOKEN` is set to a token that can create releases in
  `LuizinhoF/osplus`.

Release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\release\publish_github_release.ps1
```

The script reads `dist/version.json`, builds `dist/OSPlus.zip`, creates release
tag `v<version>`, and uploads both required assets.

If the zip has already been built and verified:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\release\publish_github_release.ps1 -SkipBuild
```

Do not publish a release until the normal release checklist smoke test passes.
