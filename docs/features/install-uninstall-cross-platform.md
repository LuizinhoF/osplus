# Install, uninstall, and Linux/Steam Deck support

## Brief

OSPlus needs a more trustworthy distribution surface:

- Linux / Steam Deck users could not run the Windows-only `install.bat`.
- There was no first-class uninstall path.
- The sidecar launcher assumed native Windows shell behavior (`wscript.exe`
  and VBS), which is fragile under Proton.

## Design

### Installers

The distribution zip ships platform-specific entry points:

- `install.bat` for Windows.
- `install.sh` for Linux / Steam Deck.
- `update.bat` / `update.ps1` for Windows.
- `update.sh` for Linux / Steam Deck.
- `uninstall.bat` for Windows.
- `uninstall.sh` for Linux / Steam Deck.

The Linux installer detects standard Steam and Flatpak Steam libraries by
reading `libraryfolders.vdf` and, when needed, `appmanifest_*.acf`. If it cannot
find Omega Strikers, it asks for the game path.

Linux users must set the Omega Strikers Steam Launch Option:

```text
WINEDLLOVERRIDES="dwmapi=n,b" %command%
```

This forces Proton/Wine to load the local `dwmapi.dll` proxy that boots UE4SS,
instead of preferring Wine's builtin `dwmapi` implementation. The installer
prints this instruction; it does not edit Steam config automatically.

### Sidecar on Linux

Omega Strikers currently runs as a Windows game under Proton, so the first
Linux path keeps the Windows sidecar and launches it from inside the game's
compatibility environment. That avoids translating IPC paths between host
Linux and Wine's `%LOCALAPPDATA%`.

`main.lua` detects Proton/Wine-ish environment variables and skips the VBS
hidden-launch shim there, launching `OSPlus.exe` directly instead.

A native Linux sidecar remains a possible future improvement, but it requires a
deliberate IPC directory contract between the Proton prefix and the host-side
process.

### Uninstall

Uninstallers remove:

- `Binaries/Win64/Mods/OSPlus/`
- `Content/Paks/LogicMods/OSPlus.pak`
- Legacy OSPlus prototype artifacts
- The `OSPlus : 1` line in `mods.txt`

They ask before removing shared UE4SS files or local OSPlus runtime data
(logs/config/token), because those choices affect other mods or future
reinstalls.

### Update

The update scripts download the latest `OSPlus.zip` from GitHub Releases and
rerun the normal installer. The installer stays the only code path that writes
into the game folder.

## Outcome

Implemented in:

- `dist/install.sh`
- `dist/uninstall.sh`
- `dist/uninstall.bat`
- `dist/install.bat`
- `dist/update.bat`
- `dist/update.ps1`
- `dist/update.sh`
- `mod/OSPlus/scripts/main.lua`
- `build_dist.ps1`
- `dist/README.txt`

## Validation

- Shell syntax: `bash -n dist/install.sh dist/uninstall.sh dist/update.sh`.
- Zip permissions: `install.sh`, `update.sh`, and `uninstall.sh` must appear
  as `0755` executable entries when inspecting `dist/OSPlus.zip` with a
  permission-aware archive tool.
- Lua syntax: `npx --yes luaparse mod/OSPlus/scripts/main.lua`.

Runtime smoke still needs a real Windows install and a real Linux/Steam Deck
install before public release.
