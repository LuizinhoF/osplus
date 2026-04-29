# profile.tick userdata allocation leak crashes UE4SS after long sessions

| Field | Value |
|---|---|
| Date | 2026-04-28 |
| Area | mod |
| Tags | crash, ue4ss, per-tick, profile, identity, userdata-leak, minidump, regression |
| Status | confirmed |

## Symptom

Game crashes randomly after extended play (~15–60 min observed) since the
account-creation feature shipped (commit `4b91379`, `feat(identity): resolve display name via UPMPlayerUIData (v42)`). N=3 reports across days, none with a same-second
proximate trigger in the Lua log; the user could be idle in lobby or in the
middle of a match. Pre-account-creation chat-only builds did not crash.

UE4SS writes a minidump to `Binaries\Win64\crash_<timestamp>.dmp` (UE4SS's
own vectored exception handler catches the fault before Windows Error
Reporting engages — that's why the dump lands there and not in
`%LOCALAPPDATA%\OmegaStrikers\Saved\Crashes` or the Application event
log).

Parsed minidump (representative N=1 dump, all three were the same shape):

```
EXCEPTION_ACCESS_VIOLATION (0xC0000005)
Operation:        READ
Faulting address: 0xFFFFFFFFFFFFFFFF  (= -1, classic "iterator-at-end" /
                                          "invalid handle slot" sentinel)
Faulting RIP:     UE4SS.dll + 0x9211B2
Crashing thread:  TID inside UE4SS's hook/userdata machinery (post-fault
                  RIP captured in ntdll's KiUserExceptionDispatch).
```

Sidecar log line proves the host process actually died (not just the Lua VM):

```
[HEARTBEAT] Stale (22s old), game gone — exiting
```

## Root cause

`profile.tick` ran every frame at 30 Hz from `main.lua`'s `LoopAsync`, and
even after the first profile_upsert successfully landed it kept re-running
the snapshot-build path:

1. `identity.getLocalPrometheusId()` — cheap, cached.
2. `identity.resolveDisplayName()` — cheap, early-exits on `cachedPlayerName`.
3. `identity.getFriendlyDisplayName()` — cheap, cached.
4. **`identity.resolveSteamId()` — NOT cached.** Each call did:
   - `FindFirstOf("PMIdentitySubsystem")` → fresh UObject userdata wrapper
   - `subsystem:GetSteamId()` → fresh FString userdata (UFunction return)
   - `steamId:ToString()` → another userdata-to-string conversion
5. `buildSnapshot` (fresh table) + `snapshotsEqual` compare, return.

That's **3 UE4SS-tracked userdata allocations per frame, ~5,400/min, ~92,000
per 17 min lobby idle**. The pre-feature chat-only build did similar
`FindFirstOf` calls but `chat.tickMatchProbe` self-throttles to 1 Hz
(`MATCH_PROBE_TICKS = 30`) — i.e. ~30× less load.

UE4SS's userdata-tracking table eventually hits a stale slot
(`0xFFFFFFFFFFFFFFFF` is the sentinel it returns from a missed
hash-lookup-or-end-iterator path), dereferences it on a subsequent
allocation/lookup, and faults inside its own machinery. The exact line in
UE4SS at RVA 0x9211B2 is unsymbolized (no public PDBs for the v3.0.1 tag),
but the shape is unambiguous: this is a UE4SS-internal use-after-free or
stale-slot deref triggered by allocation churn.

Snapshot fields are session-immutable in OS:
- Prometheus ID — assigned once on account creation, never changes.
- Display name — OS client doesn't expose a rename mid-session path.
- Steam ID — established at Steam login, can't change without relaunch.
- Platform — hardcoded `"Steam"`.

So polling for them past the first emit was guaranteed-no-op work that
also happened to be allocation-churn fuel.

## Fix

`fix(profile): stop polling identity every tick after first emit` (commit
`31d57c4`, branch `fix/profile-tick-resource-leak`):

```lua
function M.tick()
    if lastSnapshot then return end
    -- ...rest of the body unchanged...
end
```

Plus removal of the now-dead `snapshotsEqual` function and its caller
(neither can ever fire — `lastSnapshot` is nil until the first emit
succeeds, and after that the new guard returns first).

Also bumped `cfg.VERSION` from the long-stale `v36-identity-stable` (the
banner was never updated through v37–v42 of the resolver work) to
`v43-profile-tick-stop` so future log triage matches code identity.

The fix is *not* "cache the SteamID more aggressively." That would be
treating the symptom (per-call cost) instead of the cause (the call
shouldn't exist). The right answer is to stop polling for a value that
cannot change.

Validation pending — needs an extended local play session. Crash
signature to watch for (and refute the fix if it reappears): exception
0xC0000005 with `ExceptionAddress` in the UE4SS.dll address range and
faulting address ≈ -1.

## Lesson

Three transferable rules from this:

1. **Per-tick UE-reflected calls are allocations, not just CPU cost.**
   `FindFirstOf` / `FindAllOf` / UFunction calls / userdata property reads
   each allocate UE4SS-tracked wrappers. UE4SS GCs them later, but the
   churn isn't free and it isn't infinitely robust. Treat any per-tick
   UE call the same way you'd treat a per-tick `malloc` in C++ — justify
   it or eliminate it.

2. **Cache push-down is the callee's job.** When a function looks like
   `local x = resolveX()` from a 30 Hz callsite, the *callee* must short-
   circuit on a cached value. Don't expect every caller to remember to
   only call the resolver "when needed" — the call site can't tell from
   reading it that the resolver is expensive.

3. **For a value that can't change in this session, the right caching
   policy is "never refresh."** Not "refresh rarely." Not "refresh on
   change detection." The polling itself is the bug, not its frequency.
   Codified in `.cursor/rules/mod-architecture.mdc` § "Per-tick discipline."

### Methodology that worked: parsing UE4SS .dmp files without Windows SDK

UE4SS writes standard MDMP-format minidumps. With no `cdb` / `windbg` /
`dotnet-dump` installed, Python's `pip install minidump` is the cheapest
path to attribution. The script at `.crash-parse.py` (one-shot for this
investigation; not yet promoted to `tools/re/`) extracts:

- `ExceptionCode` + `ExceptionAddress` (faulting instruction)
- `NumberParameters` + `ExceptionInformation` (op + faulting address for
  AVs)
- Module that owns the faulting address (so you know if it's the game's
  C++, UE4SS, a driver, or unmapped JIT code)
- Per-thread CONTEXT64 register state (manual seek to the
  `MINIDUMP_LOCATION_DESCRIPTOR.Rva` since the library's `ContextObject`
  exposes it as a raw blob)

Without this, the investigation would have been "guess and pray." With
it, the attribution to UE4SS.dll was unambiguous in 30 minutes from a
cold start. Worth promoting to `tools/re/parse_minidump.py` next time we
hit a crash dump (per harnesses rule: propose before authoring).

The other key methodology bit: **always check the heartbeat file's last
write time** (`%LOCALAPPDATA%/OSPlus/heartbeat.txt`) and the sidecar log's
last line. Together they bracket "when did the host process die" to a
~5 s window independent of any crash dump tooling.

## Related

- Files:
  - `mod/OSPlus/scripts/profile.lua` — the fix site
  - `mod/OSPlus/scripts/identity.lua` — the unthrottled resolver that was
    being called
  - `mod/OSPlus/scripts/main.lua` — `LoopAsync` callsite
  - `.cursor/rules/mod-architecture.mdc` — § "Per-tick discipline" codifies
    the rule
  - `docs/architecture/mod-scripts.md` — readable architecture map
- Prior learnings:
  - Doesn't supersede anything directly. Adjacent:
    `ue4ss-multicast-delegate-add-silent-noop.md` (also UE4SS-internal
    state machine misbehavior that pcall can't catch)
- Tooling:
  - Python `minidump 0.0.24` (pip install minidump)
  - One-shot parser: `.crash-parse.py` at repo root (consider promoting
    to `tools/re/parse_minidump.py`)
- Commits:
  - `31d57c4` — the fix
  - `9363cf9` — the chat-owns-engine-hooks refactor (separate; landed
    immediately after the fix)
