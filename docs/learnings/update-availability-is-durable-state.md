# Update availability is durable state, not a once-only event

| Field | Value |
|---|---|
| Date | 2026-07-28 |
| Area | sidecar / relay / mod |
| Tags | update-availability, http, file-ipc, map-load, deduplication |
| Status | confirmed |

## Symptom

The first update-notification design was about to suppress repeat
`update_available` IPC messages in the sidecar after announcing one release.
That looked like harmless noise reduction, but OSPlus deliberately truncates
`inbox.jsonl` on every map load. If the sidecar wrote the one allowed event
during a transition, Lua could lose it before caching or presenting it and
would never learn about that release again during the session.

## Root cause

Update availability is a recoverable fact — “stable version X is newer than
the installed version” — but the proposed sidecar behavior treated it as an
edge-triggered event. File IPC has no acknowledgement, and map-load truncation
is part of the current lifecycle contract, so the producer cannot know that
Lua consumed a particular line.

The UI has a different requirement: its sound and entrance animation must not
repeat. Conflating transport suppression with presentation suppression put
reliability and user experience in the same owner.

## Fix

- `GET /updates/latest` is the durable source of truth. The relay validates and
  caches the latest stable GitHub Release; WebSocket is not required.
- `sidecar/update.js` caches successful release state for five minutes and may
  re-emit the known `update_available` fact for every accepted startup,
  confirmed-queue, or match-completion check.
- `mod/OSPlus/scripts/update_notification.lua` owns session presentation
  de-duplication. It records versions only after the Blueprint notice is
  actually shown, so losing an unread inbox line cannot consume the UI budget.
- A warm sidecar cache may still re-emit a previously validated newer release
  when a refresh fails. A cold failure emits nothing and remains fail-open.

The relay and sidecar tests cover cached repeat emission, in-flight
coalescing, warm failure, cold failure, ETag revalidation, and stale relay
backoff.

## Lesson

Deduplicate at the layer that owns the effect. Durable facts may be repeated
across an unacknowledged IPC boundary; the consumer that plays the sound and
animation must suppress duplicate presentation only after presentation
succeeds.

## Related

- Files: `server/updates/index.js`, `sidecar/update.js`,
  `mod/OSPlus/scripts/update_notification.lua`,
  `mod/OSPlus/scripts/main.lua`
- Canonical architecture: `docs/architecture/relay.md`,
  `docs/architecture/state-contract.md`
- Prior learning: `docs/learnings/github-release-distribution-contract.md`
