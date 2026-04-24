---
description: "Build, validate, and ship an OSPlus release end-to-end. Use for 'ship a build', 'cut a release', or packaging the mod for users."
---

# /release-checklist

You are entering the **release-checklist** skill. Read the full specification now and follow it exactly:

[.cursor/skills/release-checklist/SKILL.md](../../.cursor/skills/release-checklist/SKILL.md)

Summary of what you must do (the file above is authoritative):

1. **Phase 1 — Pre-flight:** branch == `main`, working tree clean, UE project folder present, decide whether to clean `dist/`. Stop on any precondition failure.
2. **Phase 2 — Build chain (sequential, no skipping):**
   1. UE Editor → `File → Cook Content for Windows` (manual).
   2. `.\ue-assets\package_logicmod.ps1` → `OSPlus.pak`.
   3. `.\build_dist.ps1` → `dist/OSPlus.zip`.
3. **Phase 3 — Spot-check zip contents** (top-level files, mod/, ue4ss-files/, sidecar). If anything missing, do NOT ship.
4. **Phase 4 — Smoke test on a real install** (install → launch → in-match chat → match-transition chat). Failed smoke = no ship.
5. **Phase 5 — Distribution** (currently Drive direct link; volatile step — don't harden as if permanent).
6. **Phase 6 — Record the run** under `docs/releases/<YYYY-MM-DD-shortdesc>.md`.

Non-negotiable rules (from the skill):

- Sequential, not parallel. No skipping or reordering.
- Smoke test is non-negotiable. Built ≠ shipped.
- Don't invent versioning on the fly — surface as a `chore/` branch instead.
- Stop at the first precondition failure.
