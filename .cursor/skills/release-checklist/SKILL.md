---
name: release-checklist
description: Build, validate, and ship an OSPlus release end-to-end. Use when the user asks to ship a build, cut a release, package the mod for users, or update the public download.
---

# Release Checklist

You are a specialized sub-skill for shipping an OSPlus release. You produce a structured **Release Run Document** that records exactly what was built, what was tested, and where the artifact landed. The skill exists so "ship a build" is a one-prompt operation and so every release is documented in a way that lets us roll back or diagnose user reports later.

The public package version lives in `dist/version.json`. Release tags use
`v<version>` and GitHub Releases must include `OSPlus.zip` plus `version.json`.

## When to use

Use this skill when the user asks to:

- "ship a build" / "cut a release" / "make a new build"
- "update the download link"
- "package the mod for users"
- prepare an artifact to share with someone outside the dev loop

Skip this skill (don't use it) when:

- The user is iterating locally (`deploy.ps1` for fast Lua-only sync, no full rebuild needed).
- The change is server-only (relay deploy uses `server/deploy/ship.ps1`, not this skill).
- The change is documentation-only (no artifact rebuild needed).

## Required preconditions

This skill assumes:

- You are on Windows with the OSPlus repo checked out and the toolchain installed (UE 5.1.0 source build at `F:\UE510\...`, Steam install of Omega Strikers at `F:\SteamLibrary\...`, the project at `F:\Omegamod\OmegaStonkers 5.1\`).
- The `OmegaStrikers` game is **closed** (`build_dist.ps1` step 3 builds the sidecar `OSPlus.exe`; `package_logicmod.ps1` writes to `Content/Paks/LogicMods/OSPlus.pak` which the running game holds locked).
- You have the `OmegaStonkers 5.1.uproject` openable in the UE editor for the cook step.

If any precondition is missing, stop and surface it to the user — don't try to work around.

---

## Phase 1: Pre-flight state check

Before touching the build chain, verify the source state is shippable.

```
PRE-FLIGHT
  Branch: <git rev-parse --abbrev-ref HEAD>
  Expected: main (releases ship from main, not feature branches)

  Working tree: <git status --short — should be empty>
  Expected: clean (no uncommitted changes leak into the build)

  Last commit: <git log -1 --oneline>
  Expected: matches what the user thinks they're shipping

  UE project folder: F:\Omegamod\OmegaStonkers 5.1\Content\Mods\OSPlus\
  Expected: exists (NOT the legacy "OmegaStrikersMod" name — see UE_PROJECT_MIGRATION)

  dist/ folder:
  Decision: [ ] keep prior dist for diff comparison
            [ ] clean dist/ before build (recommended for clean room)
```

If working tree is dirty or branch ≠ main, stop and ask. Don't ship from a dirty tree.

If the legacy `OmegaStrikersMod` folder exists in the UE project but `OSPlus` doesn't, the cook will produce the wrong path and `package_logicmod.ps1` will fail with a clear error — fix the UE-side migration first (see `docs/UE_PROJECT_MIGRATION.md`), don't try to patch around it in the build script.

---

## Phase 2: Build chain in order

The chain is **non-parallel** — each step consumes the previous step's output:

```
BUILD CHAIN

Step 1 — UE Editor: Cook Content for Windows
  This is a manual UE Editor step (no headless cook configured).
  Open: F:\Omegamod\OmegaStonkers 5.1\OmegaStonkers.uproject
  Menu: File > Cook Content for Windows
  Wait: until the editor reports "Cook Complete"
  Verify: F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OSPlus\
          contains the cooked .uasset / .uexp files (not OmegaStrikersMod)

  STATUS: [ ] cook complete  [ ] verified output path

Step 2 — Package the LogicMod pak
  Run: .\ue-assets\package_logicmod.ps1
  Expected output: "[ok] Pak: F:\SteamLibrary\...\LogicMods\OSPlus.pak (<N> bytes)"
  Failure mode to watch: "Cooked content not found" with hint about migration
                         => Step 1 produced wrong path; fix UE side, re-cook

  STATUS: [ ] pak built  [ ] size sane (>0, <few MB)

Step 3 — Build the dist zip
  Run: .\build_dist.ps1
  Expected output: "Created <path>\OSPlus.zip (<N> MB)"
  Steps internally: clean dist → copy Lua → build sidecar SEA exe → copy pak
                    → copy UE4SS bundle → copy installer/updater/version docs
                    → zip
  Failure modes to watch:
    - "OSPlus.pak not found" => Step 2 didn't run / failed silently
    - sidecar SEA build failure (npm/esbuild/postject errors) => check sidecar/
    - "ue4ss-bundle/ not found" => run setup first

  STATUS: [ ] zip built  [ ] step counter went 1/7 through 7/7
```

After all three steps:

```
ARTIFACT
  Zip path: dist/OSPlus.zip
  Zip size: <MB>
  Zip mtime: <timestamp> (sanity check it's from this run, not a stale prior)
```

---

## Phase 3: Spot-check zip contents

Before installing, verify the zip has everything the installer expects. Listing only — no extraction needed.

```powershell
$zip = "dist\OSPlus.zip"
[System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $zip)) |
    ForEach-Object { $_.Entries | Select-Object FullName, Length }
```

Expected entries (the installer fails confusingly if any are missing):

```
EXPECTED CONTENTS
  Top-level:
    install.bat
    install.sh
    update.bat
    update.ps1
    update.sh
    uninstall.bat
    uninstall.sh
    README.txt
    version.json
    mod\OSPlus.pak
    mod\scripts\*.lua    (~10 files: main, chat, ipc, log, config, utils, json, assets, pings, wheel)
    mod\sidecar\OSPlus.exe
    mod\sidecar\launch_hidden.vbs
    mod\sidecar\config.json
    ue4ss-files\UE4SS.dll
    ue4ss-files\dwmapi.dll
    ue4ss-files\UE4SS-settings.ini
    ue4ss-files\Mods\mods.txt
    ue4ss-files\Mods\BPModLoaderMod\...
```

If something is missing, do NOT ship — go back to Phase 2 and find out what failed silently.

```
SPOT CHECK
  All expected files present: [ ] yes  [ ] no — missing: <list>
  config.json relay_url: <should be wss://play-osplus.duckdns.org for public release>
```

---

## Phase 4: Smoke test on a real install

You **must** install the zip on a real Steam install and verify it works in-game. Building successfully ≠ shipping correctly. The minimum bar:

```
SMOKE TEST

Pre-test cleanup:
  [ ] Game closed
  [ ] Sidecar (OSPlus.exe) not in Task Manager
  [ ] Optional: nuke prior install (delete <game>\Binaries\Win64\Mods\OSPlus\
                and <game>\Content\Paks\LogicMods\OSPlus.pak) for clean-room test.
                Recommended for first build of a new feature; skipping is fine
                for incremental builds.

Install:
  [ ] Extract OSPlus.zip to a temp folder
  [ ] Right-click install.bat > Run as administrator (or just double-click; it self-elevates)
  [ ] Installer reaches "Installation complete!" with no [ERROR] lines
  [ ] [OK] All files unblocked appears (MOTW strip ran)

Launch:
  [ ] Launch Omega Strikers from Steam normally
  [ ] Sidecar window appears (or runs hidden via launch_hidden.vbs — check Task Manager for OSPlus.exe)
  [ ] UE4SS log shows mod loaded (look for [HOOK] / [TICK] / [CHAT] entries in
      <game>\Binaries\Win64\ue4ss\Mods\OSPlus\Scripts\osplus.log)

In-match smoke:
  [ ] Join a match (custom or matchmade)
  [ ] Press ENTER — chat box opens
  [ ] Type a message, press ENTER — message sends and appears in chat panel
  [ ] Receive a message from another OSPlus user (or send one to yourself
      via two installs)

Match transition smoke (the Phase 1d learning — chat-match-detection-via-seed):
  [ ] Finish a match, return to lobby
  [ ] Start a SECOND match
  [ ] Chat box still works in the second match
  [ ] No stale messages from the first match leak into the second

If ANY box is unchecked, the build is not shippable.

Result: [ ] PASS — proceed to distribution
        [ ] FAIL — stop here, file a bug-investigate, do not ship
```

---

## Phase 5: Distribution

```
DISTRIBUTION (GitHub Releases)
  [ ] Confirm `dist/version.json` has the version being shipped
  [ ] Confirm `CHANGELOG.md` has an entry for that version
  [ ] Run `tools/release/publish_github_release.ps1`
      (requires GH_TOKEN or GITHUB_TOKEN with repo release permissions)
  [ ] Confirm GitHub release `v<version>` exists at:
      https://github.com/LuizinhoF/osplus/releases
  [ ] Confirm release assets include:
      - OSPlus.zip
      - version.json
  [ ] Confirm the stable latest URL resolves:
      https://github.com/LuizinhoF/osplus/releases/latest/download/OSPlus.zip
  [ ] Notify whoever needs to know that a new build is up
```

Do not publish a release that failed smoke testing. If the publish script
fails after creating the GitHub release, delete the draft/broken release or
upload the missing asset before notifying users.

---

## Phase 6: Record the run

End every release with a small written record. This isn't bureaucracy — it's what lets us answer "which build does that user have?" three weeks from now when they report a bug.

Write to `docs/releases/<YYYY-MM-DD-shortdesc>.md` (create `docs/releases/` if it doesn't exist):

```markdown
# Release <YYYY-MM-DD>: <short description>

**Commit:** <full sha> (`git rev-parse HEAD`)
**Branch:** main
**Built by:** <user / AI session id if relevant>
**Version:** <dist/version.json version>
**Zip size:** <MB>
**Distributed via:** GitHub Releases

## What's in this build
- <1-3 bullets — the user-visible things this build does that the prior didn't>

## Smoke test
- [x] Install on clean game folder
- [x] Chat works in first match
- [x] Chat works after match transition
- <other checks if any>

## Known issues at ship
- <anything you knew was broken but shipped anyway, with rationale>
- (or "none")

## Notes
- <anything noteworthy about THIS build — toolchain quirks, last-minute fixes, etc.>
```

---

## Output Format

Your final output MUST follow this structure:

```
═══════════════════════════════════════════════
RELEASE RUN: <YYYY-MM-DD>
═══════════════════════════════════════════════

── PHASE 1: PRE-FLIGHT ──
<from §1>

── PHASE 2: BUILD CHAIN ──
<from §2>

── PHASE 3: ARTIFACT SPOT-CHECK ──
<from §3>

── PHASE 4: SMOKE TEST ──
<from §4>

── PHASE 5: DISTRIBUTION ──
<from §5>

── PHASE 6: RECORDED AT ──
<path to docs/releases/<file>.md>

═══════════════════════════════════════════════
```

---

## Rules

1. **Sequential, not parallel.** UE cook → pak → dist zip → spot-check → smoke test → ship. No skipping, no reordering.
2. **Smoke test is non-negotiable.** A built zip is not a shipped build. The minimum bar (Phase 4) is the bare minimum, not the ceiling — if the release adds new features, smoke-test those features too.
3. **Versioning is part of the release.** Update `dist/version.json` and
   `CHANGELOG.md` before publishing.
4. **The GitHub release asset contract is stable.** Keep the asset name
   `OSPlus.zip`; the updater depends on GitHub's latest-release download URL.
5. **Record every release.** `docs/releases/<date>-<desc>.md` is the artifact-trail that lets us answer user reports. No release is done without it.
6. **Failed smoke = no ship.** "We can patch it after" is how shipped builds get reputational damage. If the smoke fails, file `bug-investigate`, fix, rebuild, re-smoke. Don't ship through it.
7. **Stop at the first precondition failure.** Wrong branch, dirty tree, missing UE folder, game running — surface and pause. Working around any of these in-flight is how shipped builds end up containing experimental code.
