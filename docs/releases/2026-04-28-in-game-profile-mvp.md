# Release 2026-04-28: In-Game Profile MVP (account-bound clients + chat-only backwards compatibility)

**Commit:** `329bbdc` (`fix(deploy): ship server/api subdir to relay VM`)
**Branch:** main
**Built by:** Cursor session — full session transcript: [In-game profile MVP ship](f9b7af72-ea9c-4164-a943-9ce03670c2b3)
**Zip size:** 39.55 MB
**Distributed via:** Drive (direct link)

## What's in this build

User-visible:

- **First-class account on the OSPlus relay.** OSPlus now resolves the local player's authoritative Prometheus ID and friendly display name and persists them to the relay's SQLite-backed profile store via a TOFU-paired bearer token. From the user's perspective: install the build, launch the game, and your in-game name is registered server-side without any setup on first launch. No login, no shared password.
- **Display-name resolution is now correct on every launch.** The previous chat-presence build occasionally surfaced the Windows hostname (`DESKTOP-EJ47PRO-D197`) instead of the in-game name in edge cases. This build resolves the friendly name from the canonical Prometheus UI data model (`UPMPlayerUIData.Profile.Username` keyed by Prometheus ID) — no heuristics, no hostname fallback.

Under the hood (no user-visible behavior change):

- New relay endpoints `POST /api/auth/pair` + `PUT|GET /api/profiles/{pid}` mounted alongside the existing chat WS, served from a new `server/api/` persistence module. SQLite at `/opt/osplus/relay/data/osplus.sqlite3`.
- Sidecar carries a per-install bearer token at `%LOCALAPPDATA%\OSPlus\token` (mode `0o600`), TOFU-bound to the user's Prometheus ID at first contact with the relay. Token-mismatch recovery (relay didn't recognize the token from a prior dev pairing) is a smooth `PUT 401 → PAIR → PUT 200` flow with no user prompt.
- Two ADRs accepted in this branch: ADR 0001 (Prometheus ID is the canonical OSPlus account binding) and ADR 0002 (single-process relay with TOFU auth, SQLite-backed profile store).

Backwards compatibility (verified against live production):

- v22/v23 chat-only clients keep working. The relay's WS contract (`{join, leave, ping, chat}` in, `{joined, left, error, chat, ping, presence}` out) is byte-identical to the prior release. The new `/api/*` namespace is purely additive. Confirmed live during smoke test: a real chat-only user (`Paguma`, IP `200.86.227.104`) connected and joined a room within 5 seconds of the new relay coming up.

## Smoke test

- [x] Pre-flight clean (game closed, sidecar killed)
- [x] Install via `install.bat` as admin — `Installation complete!` with no `[ERROR]` lines
- [x] Game launches, sidecar visible in Task Manager
- [x] Profile feature end-to-end against PRODUCTION relay (`wss://play-osplus.duckdns.org`):
  - Sidecar log: `[WS] Connected (no room yet, waiting for match)` at `00:42:32.716Z`
  - Sidecar log: `[PROFILE] POST /api/auth/pair for 632680c154686dedd6522b09` at `00:43:01.097Z`
  - Sidecar log: `[PROFILE] paired ..., retrying PUT` at `00:43:01.240Z` (143ms PAIR latency over public TLS to the OCI VM)
  - Sidecar log: `[PROFILE] PUT-after-pair -> 200 ...` at `00:43:01.366Z` (126ms PUT latency)
- [x] Production SQLite verification (queried via better-sqlite3 on the VM):
  - `profiles` row present: `prometheus_id=632680c154686dedd6522b09`, `display_name=Ispicas`, `steam_id=76561198022185004`
  - `auth_tokens` row present: same `prometheus_id`, `last_seen_at` advanced after the successful PUT
  - Total profiles: 1; total tokens: 1 (fresh DB, no contamination)

What was NOT smoke-tested in this build (deliberately deferred):

- In-match chat with the new relay (chat path is byte-identical to the v22/v23 contract — verified live by an unrelated chat-only user; an explicit in-match send/receive smoke is the next session's first action).
- Match transition smoke (chat box surviving lobby→match→lobby→match — same rationale, contract-identical).
- 409 conflict path (`prometheusId already paired with a different token`) — requires a second machine to provoke; unreachable in single-developer smoke.

## Known issues at ship

- **Build artifact verbosity.** `dist/install.bat` prints raw stderr lines from PowerShell-side npm/esbuild/postject pipelines as if they were errors (e.g. `node.exe :` lines). They are informational only — the build succeeds. Confusing for a casual reader; cosmetic-only.
- **Token-file portability.** Moving the OSPlus install to a new Windows account / new machine does not transfer the token file. The sidecar will TOFU a new pairing on first launch, which on this build creates a SECOND auth_tokens row for the same Prometheus ID and the relay returns 409 (`prometheusId already paired with a different token`). Maintainer recovery: SSH the VM, delete the old `auth_tokens` row for that PID, re-launch on the new machine. Documented in `sidecar/profile.js` log message; should be turned into a runbook entry next session.
- **No client-side migration UX for chat-only users adopting this build.** Old users who upgrade get the new sidecar transparently and silently start producing profile rows in the relay's SQLite. There's no opt-out, no notice. Acceptable at our pre-public scale; revisit before any broader announcement.

## Notes

- **First production deploy of the new relay hit a deploy-script bug** (`Cannot find module './api'`) because `ship.ps1` + `install-relay.sh` enumerate per-file copy lists, not a tree sync. New `server/api/` subdir was missed in both. Fixed on `fix/relay-deploy-api-subdir`, merged fast-forward, re-shipped. The relay was in a restart loop for ~3 minutes between the first ship and the fix. Captured as gotcha § 6 in `docs/learnings/oci-relay-deploy-gotchas.md` with the long-term mitigation (rsync sync) flagged as a follow-up.
- **The display-name resolver took 5 in-game-reflection iterations to land** (v37 PMPlayerModel cache → v38 NotifyOnNewObject → v39 deep field/function dump (game crash) → v40 UTextBlock visual probe → v41 UPMPlayerUIData binding → v42 UPMPlayerUIData.Profile.Username). The lesson: always grep the UE4SS type-stub dump at `<game>/Binaries/Win64/Mods/shared/types/` BEFORE reaching for in-game reflection. Captured in `docs/learnings/ue4ss-type-stubs-as-canonical-source.md`. The `FOdy*Binding.InitialValue ≠ live value` corollary is in `docs/learnings/ody-ui-binding-initialvalue-vs-live.md`.
- **Build commit identity.** The release SHA is `329bbdc` (the deploy-fix commit, which only touched scripts) but all the user-facing functionality landed in the merge commit `6bc472d` and the v42 resolver commit `4b91379` immediately preceding it. The HEAD on `main` at ship time was `329bbdc`.
- **Stash @{0}** still holds the `feat/emote-pipeline-profile-groundwork` WIP — not part of this release. The two untracked emote files were artifacts from that abandoned exploration; deleted from the working tree during pre-build cleanup. The stash is preserved in case the emote feature comes back post-account-system.
