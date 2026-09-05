# Match-room membership does not permit revealing opponents

| Field | Value |
|---|---|
| Date | 2026-09-05 |
| Area | mod / sidecar / relay |
| Tags | chat, presence, privacy, character-select, bans, match-phase, stale-snapshots |
| Status | working-theory |

Implementation and offline behavior are verified; current in-game phase
readability and transition timing remain unverified. The user explicitly asked
for a solution now and reserved the in-game test for themselves.

## Symptom

The user reported that the chat connected-player list exposes opposing player
names during bans/character selection, when the native game hides those names.
Showing opponents during gameplay is allowed. Prior art inspected first:
`chat-presence`, `chat-match-detection-via-seed`, and
`chat-match-wide-room-audience-routing`.

## Root cause

Chat's nonzero `CurrentMatchSeed` gate joins a match-wide relay room before
gameplay. The relay previously sent the identical list of all usernames to
every member; neither sidecar nor Lua checked a presence audience. Lua receives
only names, so it cannot safely classify enemies by itself. The user's symptom
matches this source-level path; it was not reproduced live in this session.

An offline reproduction using the actual relay entrypoint and real local
WebSocket clients confirmed the old behavior: an unknown-team pregame client
received all five users' names. The original sidecar also forwarded delayed and
legacy snapshots into its inbox/logs in the isolated dispatcher tests.

Hypotheses checked: moving back to a Pawn gate would conceal pregame presence,
but prior live evidence shows it also drops chat during KOs. Keeping separate
team rooms would break existing match-wide/spectator chat. Both were rejected.

The engine reference was also stale: it said **"No phase enum is exposed
(yet)."** and called a `PlayerState` + valid `Pawn` predicate canonical.
The current code and seed-gate learning contradict the latter. The stored
2026-04-24 object dump and generated type stubs expose
`PMGameState.CurrentMatchPhase` and all `EMatchPhase` values, including
`InGame=5`, `BanSelect=19`, and `CharacterPreSelect=20`. These values are not
chronological. Exact source pointers and the full enum now live in
[game-state.md](../engine/game-state.md#phase-model).

## Fix

- Lua keeps room membership seed-based. At the existing room-check cadence,
  it reads phase independently; failed/unknown reads cannot grant permission
  and do not break the seed detector. Only explicit numeric `InGame=5` unlocks
  opposing names for the same seed. Goals, KOs, and between-set drafts retain
  that permission; seed/map/room exit resets it. No new unverified hook or
  timer-based assumption about when selection ends is introduced.
- `room_change` / `join` carry `revealOpponents` and `presenceRevision`.
  The relay makes a list per recipient: self plus confirmed same-team players
  before gameplay, all connected members afterward. Unknown-team players and
  spectators get self-only before gameplay, regardless of spectator viewing
  team. Chat message routing remains unchanged.
- The revision advances before requesting a changed room/team/identity/audience,
  including before identity retries. Lua clears old names immediately. Relay
  echoes revision and permission; sidecar and Lua reject mismatched or missing
  metadata. Reconnects preserve desired state. Map resets preserve the revision
  counter and drop the widget reference before clearing presence, avoiding any
  call into the previous map's widget.
- Legacy relay snapshots fail closed (empty list on new clients). Old clients
  on the new relay remain restricted. The relay must be updated before shipping
  the matching client. Client-reported team/phase state is not anti-cheat proof.

## Verification and remaining check

Offline tests exercise the actual Lua chat/IPC modules with mocked game objects,
every stored phase value, malformed/unreadable phases, gameplay latching, team
and spectator changes, delayed/wrong/legacy snapshots, seed loss and map reset.
Node tests cover relay WebSocket behavior and sidecar joins/reconnects/inbox
filtering. No match, queue, or game launch was performed for this investigation.

Final results: 19 relay tests and 20 sidecar tests passed; 70 inline Lua/IPC
assertions passed using WSL Lua and in-memory game/IO mocks. Independent review
found one retry-recovery defect (a temporary team/name change could advance the
revision, then revert to the previously joined identity without a fresh join).
Invalidating the cached join seed before retry fixed it; three focused recovery
cases passed afterward. Lua parse checks and `git diff --check` also passed.
The existing sidecar Windows build completed successfully.

Initial pre-release preparation: `deploy.ps1` synchronized Lua/data and the rebuilt sidecar
was copied into the existing game mod directory; changed-file hashes matched.
The prior three changed scripts and executable are backed up under
`%LOCALAPPDATA%/OSPlus/dev-backups/pregame-presence-56b6438b-cfc1-4cd3-8cbc-715efc0c86d0/`.
The cooked widget/pak did not need to change for this fix. At that checkpoint,
no version bump, release, or public-relay deployment had been performed and the
fix was uncommitted for testing. The release follow-up below supersedes that state.

**Initial local test setup needed a relay restart.** The installation was on
`ws://127.0.0.1:3100`. Restarting its existing process was blocked by execution
policy, before the command ran. That instance served the old protocol, so the
new client intentionally rejected its untagged presence snapshots. This local
setup was superseded by the public deployment below; no local restart is now
required to use the maintainer's installed mod. Players must use the same relay
to share a chat room.

### Release follow-up (2026-09-05)

Committed as `dc578e1`, merged to `main`, and published in v0.4.1 with the update
notification. The public relay was deployed before client publication. An
isolated live test using synthetic players on that relay passed pregame
filtering, gameplay disclosure, legacy fallback, revision tagging, chat routing,
and disconnect cleanup. All test sockets closed; no real player room was used.

The maintainer installed the actual release ZIP successfully. Installed files
match the package, and the mod now points to the public relay rather than port
3100. The installed sidecar confirmed v0.4.1 as current. The in-game phase test
is still explicitly deferred to the maintainer; the live relay test does not
establish engine field readability or transition timing. See the
[release record](../releases/2026-09-05-osplus-0.4.1.md).

User's in-game checklist:

1. During bans and character selection, open chat with teammates and opponents
   connected to OSPlus: only self/teammates should appear.
2. Enter gameplay: opponents should appear after the existing room check
   (normally within roughly two seconds), without anyone joining/leaving.
3. Check a KO, goal, and between-set awakening selection: opponents remain.
4. Return to the Home Hub, then enter another match: the next pregame list is
   restricted again. If possible, also check a reconnect and spectator role.

If opponents never appear in gameplay, collect the `[CHAT] Joining room` log
line, which includes observed phase and requested presence scope. Do not loosen
the default without checking the runtime field/marshaling. Starting the mod
mid-intermission can remain restricted until the next observed `InGame` phase;
the initial awakening/loading sequence is deliberately still restricted.

## Lesson

Sharing a transport room does not mean every member's identity may be revealed
at every stage. Separate membership from disclosure permission, and reject old
snapshots when the permission context changes. A reflected schema proves a
field exists in that dump, not its present-day timing or readability in-game.

## Related

- Runtime: `mod/OSPlus/scripts/chat.lua`, `ipc.lua`, `main.lua`,
  `sidecar/index.js`, `server/index.js`.
- Current contract: [relay.md](../architecture/relay.md),
  [state-contract.md](../architecture/state-contract.md).
- Extends: [chat-presence](chat-presence.md),
  [seed gate](chat-match-detection-via-seed.md),
  [match-wide audiences](chat-match-wide-room-audience-routing.md).
