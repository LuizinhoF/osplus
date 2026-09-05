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

Every GitHub Release must upload this asset:

- `OSPlus.zip`

The archive must contain `version.json` at its root. Both installers copy that
same manifest to `Mods/OSPlus/version.json` only after all required mod files
have been installed successfully. The sidecar reads this marker when comparing
the installed build with the relay's latest stable release.

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

The script reads `dist/version.json`, builds `dist/OSPlus.zip`, verifies that
the archive's root manifest matches the release/tag version, creates tag
`v<version>`, and uploads the zip.

Add `-NotesPath .\path\to\release-notes.md` to supply nonempty UTF-8 Markdown
notes, including English and Portuguese sections. The script validates the file
before publishing and preserves its text when creating the release. Without
this option it uses the default description; reusing an existing release does
not overwrite that release's notes.

If the zip has already been built and verified:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\release\publish_github_release.ps1 -SkipBuild
```

Do not publish a release until the normal release checklist smoke test passes.
