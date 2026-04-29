# identity-display-name-substrate-replaces-heuristics

| Field | Value |
|---|---|
| Date | 2026-04-28 |
| Area | mod |
| Tags | identity, display-name, playernameprivate, machine-name, blocklist-failure, ue4ss |
| Status | partially-superseded-by-ue4ss-type-stubs-as-canonical-source |

> **2026-04-28 update:** The "delete the heuristics" half of this learning is correct and stands. The prescribed substrate (`PMPlayerPublicProfile.Username` keyed by Prometheus ID) was empirically falsified later the same day — that cache stays empty at the main menu for 2+ minutes while the on-screen widget renders the name. The actual canonical source is `UPMPlayerUIData.Username` (a `FOdyUITextBinding` struct on the UI data model), found by grepping the UE4SS type-stub dump rather than by in-game reflection. See `docs/learnings/ue4ss-type-stubs-as-canonical-source.md` for the discovery method and `mod/OSPlus/scripts/identity.lua` v41 for the production resolver. The heuristic-removal lesson below is the durable half; the resolver mechanism in the *Fix* section was an intermediate dead-end.


## Symptom

`profile_upsert` IPC emitted `displayName=DESKTOP-EJ47PRO-D197` instead of the in-game name `Ispicas`. The relay PUT a profile row keyed by the maintainer's actual Prometheus ID (`632680c154686dedd6522b09`) but with the Windows hostname-with-suffix as the display name. The mod log line was `[IDENTITY] Resolved display name: DESKTOP-EJ47PRO-D197` — the **fast path** in `identity.lua:resolveDisplayName()`, with no preceding `[IDENTITY] Ignoring local machine name from PlayerNamePrivate` line that should have fired if the rejection had matched.

## Root cause

Two layers, one structural.

**Mechanical layer (the immediate "why").** `identity.lua` had a heuristic `looksLikeMachineName(s)` that did strict equality: `s:upper() == localMachineName`, where `localMachineName` came from `os.getenv("COMPUTERNAME")`. On the maintainer's machine `COMPUTERNAME=DESKTOP-EJ47PRO`, but `PlayerState.PlayerNamePrivate` returned `DESKTOP-EJ47PRO-D197` in the out-of-match context — the OS adds a workgroup/DNS-like suffix in some contexts, and the strict comparison missed. Equality check looked correct, input shape just didn't match.

**Structural layer (the actual "why").** The whole rejection-by-shape design existed because — pre-Pass-6 — `PlayerState.PlayerNamePrivate` was the only display-name source we had for the local player, and it has at least three observed modes (friendly name in-match / 20+-char lowercase-hex Prometheus account ID during the early replication window / Windows hostname out of match) with no flag exposing which mode is active. The code defended against the bad modes via shape-based rejections (`looksLikeAccountId`, `looksLikeMachineName`, `isUsableDisplayName`).

That's a **blocklist** — and blocklists fail in two directions:

- **Open** on shapes the regex didn't anticipate. The `-D197` suffix is one example; any future hostname-decoration scheme (corporate domain joins, OneDrive AAD-bound names, alternate Windows enterprise SKUs) could produce different shapes. Each one is a new bug.
- **Closed** on legitimate input. A player whose in-game name happens to equal their hostname, or any 20+-char lowercase-hex handle, or the literal string `Player-1234`, would be silently dropped with no recourse — a worse failure than the bug above because the user has no way to know why their profile row never appears.

The Pass 4–6 substrate work made the heuristics obsolete without anyone noticing. We now resolve an authoritative local Prometheus ID via `PMIdentitySubsystem:GetAuthenticatedPlayerId` (R-B substrate, ADR 0001). The canonical display name lives at `PMPlayerPublicProfile.Username` on the row whose `PlayerId` matches that Prometheus ID — Pass 6 v2 confirmed the cache is reliably populated for the local player by the time `GetIdentityState` fires. The lookup function (`findFriendlyNameByAccountId`) already existed; it was just being called with the wrong key, because `resolveDisplayName` reached for `PlayerNamePrivate` first instead of waiting for the Prometheus ID.

## Fix

`mod/OSPlus/scripts/identity.lua` — replaced the `PlayerNamePrivate` fast path with a substrate path:

- `resolveDisplayName()` now waits for `getLocalPrometheusId()` to be non-nil, then calls `findFriendlyNameByPrometheusId(pid)` and uses the returned `Username`. No shape filtering. `profile.tick` polls every frame, so a transient nil (cache not yet populated) just retries on the next tick.
- Deleted: `localMachineName`, `looksLikeAccountId`, `looksLikeMachineName`, `isUsableDisplayName`, `didRejectMachineName`, `getLocalAccountId`, the `utils` import (its only consumer was `getLocalAccountId`).
- Renamed `findFriendlyNameByAccountId` → `findFriendlyNameByPrometheusId` (the parameter is a Prometheus ID, not a `PlayerNamePrivate` value; the old name now misleads).
- `dumpProfileDiagnostics` updated to log `local Prometheus ID:` instead of `localId (PlayerState.PlayerNamePrivate):`.
- `M.reset()` no longer touches `didRejectMachineName` (deleted).

Net diff: ~30 fewer lines, no new bug surface, the failure mode that produced this learning is now structurally impossible. Display name `Ispicas` resolved cleanly on the next launch.

What's NOT changed: `chat.lua` has its own copies of `looksLikeAccountId` and `findFriendlyNameByAccountId`, used for **remote** player disambiguation (sender names from inbound chat replication). That's a different problem — remote players don't have a "local Prometheus ID" we can substrate-resolve from. Left in place.

Also unchanged: the prior learnings `playernameprivate-machine-name-out-of-match.md` and `playernameprivate-transient-account-id.md` remain accurate descriptions of `PlayerNamePrivate`'s behavior. They're not wrong; they're just no longer the right input for a *local* display-name resolution because we have a better source. Both should be updated with a "superseded by substrate path for local-player display name" header — done in the same commit.

## Lesson

**When a substrate lands that gives you authoritative data, the heuristics that defended against the un-authoritative source are not "extra safety" — they're scar tissue, and they carry their own failure modes.** Specifically:

1. A blocklist (reject known-bad shapes) is always wrong when an allowlist (accept only known-good source) is available. The blocklist trades silent false-positives for silent false-negatives, and you can't tell which kind a given user is hitting without instrumentation that wasn't there.
2. When migrating from heuristic-derived to substrate-derived data, **delete the heuristic** in the same change — don't leave it as "belt and suspenders." The two paths can race or interleave, and the heuristic path's failure modes (which were tolerable when it was the only source) become latent bugs when the substrate path becomes available.
3. The Pass 4–6 work pinned identity resolution to substrate (`GetAuthenticatedPlayerId` + `PMPlayerPublicProfile`), but only the *Prometheus ID* read was migrated end-to-end. The display-name read kept the old heuristic structure because nobody was asked to revisit it. Treat any substrate landing as a checkpoint to grep for *every* consumer of the data the substrate replaces, not just the one motivating the substrate work.

The user-facing version of this lesson: a player should never lose data because their in-game name happens to match a defensive heuristic. If the rejection is the only thing standing between a valid input and a stored row, the design is wrong.

## Related

- Files: `mod/OSPlus/scripts/identity.lua` (this fix), `mod/OSPlus/scripts/profile.lua` (downstream consumer), `mod/OSPlus/scripts/chat.lua` (still uses heuristics for remote players — separate concern).
- Prior learnings now superseded for the local-player display-name path:
  - `docs/learnings/playernameprivate-machine-name-out-of-match.md` — the `PlayerNamePrivate` failure mode it describes is real, but the three-layer rejection it prescribed is no longer the recommended fix for *local* display names. Substrate path replaces it.
  - `docs/learnings/playernameprivate-transient-account-id.md` — same status: the observation about the account-ID window is correct, but for the local player we now bypass `PlayerNamePrivate` entirely.
- Substrate references that made this fix possible:
  - `docs/decisions/0001-identity-model.md` (R-B substrate)
  - `docs/learnings/os-runtime-data-model.md` (Pass 6 v2 — `PMPlayerPublicProfile` cache populated for local player at `GetIdentityState` fire time)
  - `docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md` (the `({}, {})` shape used by `readAuthenticatedPlayerId`)
- Issue trail: `docs/features/in-game-profile-mvp.md` Slice 1 local smoke testing, 2026-04-28 session.
