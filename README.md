# OSPlus

OSPlus is a community-maintained mod layer for Omega Strikers. The current
public package ships UE4SS, the OSPlus Lua mod, the cooked Blueprint pak, the
Node sidecar, and platform-specific install/update/uninstall scripts.

## Install

Download the latest `OSPlus.zip` from:

https://github.com/LuizinhoF/osplus/releases/latest

Extract it, then run:

- Windows: `install.bat`
- Linux / Steam Deck: `bash install.sh`

Linux / Steam Deck users must also set this Omega Strikers Steam Launch Option:

```text
WINEDLLOVERRIDES="dwmapi=n,b" %command%
```

## Update

From an extracted OSPlus package, run:

- Windows: `update.bat`
- Linux / Steam Deck: `bash update.sh`

The updater downloads the latest `OSPlus.zip` from GitHub Releases and reruns
the installer.

## Versioning

The release version source is `dist/version.json`. Public release tags use the
same version with a `v` prefix, for example `v0.2.1`.

GitHub Releases must include:

- `OSPlus.zip`
- `version.json`

## Development

The product and architecture docs start at `AGENTS.md` and `docs/product.md`.
The release flow is documented in `docs/ops/github-release-distribution.md`.
