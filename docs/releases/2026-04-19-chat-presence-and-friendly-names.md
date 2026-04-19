# Release 2026-04-19: chat presence + friendly names

**Commit:** 7c278ea94f8fca8a54eb958f3a26f4ee9406980f
**Branch:** main
**Built by:** local dev box (Cursor agent session 792820de)
**Zip size:** 39.5 MB (`dist/OSPlus.zip`, built 2026-04-19 17:07)
**Distributed via:** Drive (direct link — see Phase 5 below)

## What's in this build

User-visible:
- **Persistent presence list** above the chat history showing every teammate currently in the room, rendered horizontally with a mid-dot separator and a muted accent color. Empty rooms now look distinguishably different from broken rooms.
- **Sender labels rendered in an accent color** (`<Sender>[Name]</>` via UMG RichTextBlock + DT_ChatRichTextStyles) so the eye finds the sender quickly.
- **Friendly player name resolution** that survives the brief window where `PlayerState.PlayerNamePrivate` transiently returns the raw account ID.
- **Follow-tail scrolling**: chat auto-scrolls to the latest message when the box is closed OR when the user is open-and-already-at-the-end; preserves scroll position when the user has scrolled up while typing.

Under the hood (latent bugs surfaced and fixed during this work):
- Relay regex was rejecting every mod-derived `<seed>T<team>` room code; loosened to allow alphanumeric 4–16 char codes.
- Sidecar's WebSocket connection could be held open as a zombie by Caddy after relay restarts; added client-side ping/pong keepalive.
- Sidecar now mirrors its console output to `%LOCALAPPDATA%\OSPlus\sidecar.log` so the hidden process is debuggable without a visible window.

## Smoke test

Human-validated in this session:

- [x] Installer path works (`install.bat` completed and mod launched in-game)
- [x] Join a match; chat opens with Enter
- [x] Sender name renders as the friendly username (e.g. `Ispicas`), not the account ID hex string
- [x] Presence list shows the friendly username (no internal account ID leak)

Still recommended before broad rollout:

- [ ] Receive a message from another OSPlus user (or send one to yourself via two installs)
- [ ] Finish the match, return to lobby, start a SECOND match — chat still works, presence list repopulates, no stale messages from the first match

## Known issues at ship

- The `PMPlayerPublicProfile` fallback path in the friendly-name resolver almost never finds the local player's profile (it's mostly populated by recently-seen opponents, not the local user). The fast path via `PlayerNamePrivate` covers the realistic case. If the resolver ever returns the account ID despite this build, flip `M.DEBUG = true` in `mod/OSPlus/scripts/config.lua` and re-test — the diagnostic dump will print every cached profile so we can pinpoint where the local name actually lives. See `docs/learnings/playernameprivate-transient-account-id.md`.
- Wire format for presence broadcasts uses a `\n`-joined string instead of a JSON array because the mod's `json.lua` is intentionally flat-objects-only. If we ever add per-member metadata (e.g. per-player colors, badges), the right move is to extend `json.lua` to support arrays — not to keep piling delimiters into strings. See `docs/learnings/chat-presence.md`.
- The relay's `error` frames are not surfaced in chat history yet (they only land in the sidecar log). If a future regression makes the relay reject joins again, the user-visible symptom will be "presence list never populates" rather than a chat-side error. Followup: route relay error frames into chat history with a distinct style. Tracked informally in `docs/learnings/relay-room-code-regex-vs-derived-codes.md`.

## Notes

- v22 fixed local sender-name caching but still allowed a JOIN-time race where the relay cached the transient account ID into `ws._username`, making presence disagree with chat history.
- v23 (`v23-defer-room-join-on-name`) adds the missing gate: defer room join until the local friendly name is resolved/cached, then join. This keeps presence and chat history consistent.
- Sidecar SEA build emits cosmetic warnings on stderr (`The signature seems corrupted!` from postject; PowerShell formatting noise from npx). Ignored — these are documented in `build_dist.ps1` as expected output.
- No new toolchain steps were introduced in this release; the build chain (UE cook → `package_logicmod.ps1` → `build_dist.ps1`) ran end-to-end as documented in the release-checklist skill.
- Bundled UE4SS DLL set is unchanged from the prior build (15.6 MB total).
