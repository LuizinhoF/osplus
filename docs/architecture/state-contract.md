# Lua / BP State Contract

The OSPlus mod runs across two execution contexts that can't share memory directly: **Lua** (UE4SS scripts, evaluated each tick) and **Blueprint** (cooked into `OSPlus.pak`, executed by the UE runtime). Every piece of state in the mod must have **one canonical home** in one of those contexts, decided by who consumes it.

This is the long-form companion to `.cursor/rules/mod-architecture.mdc`. The rule is the quick reference; this doc is the rationale, the worked examples, and the audit of current code.

---

## The principle, in one sentence

> **State lives where it's consumed. Logic lives where it's expressive. Each piece of state has exactly one owner.**

---

## Three buckets, one owner each

### Bucket 1: UI-reactive state — owned by BP

State that drives UMG bindings, BP animations, or BP event reactions. UMG cannot bind to Lua variables, and BP cannot react to Lua-side flag changes without polling. So if any BP-side rendering or event handling depends on a piece of state, that state lives in BP.

**Examples:**

- `IsTyping` — drives chat focus, submit/cancel behavior, and input-mode restoration
- `IsExpanded` — drives chat panel collapsed/expanded animation
- `IsAuthenticated`, `Username` (Profile feature) — drives menu vs login button

**Lua reads these via getters or reflected properties:** `widget.IsTyping`. Lua never writes them directly — it triggers BP functions like `:OpenInput()` that update them as a side effect.

### Bucket 2: Domain / operational state — owned by Lua

State that requires data structures, IPC, filesystem access, process management, or algorithmic work that BP can't express well.

**Examples:**

- `M.messages` — array of `{sender, text, audience, targetTeam, time}` records (BP arrays-of-structs are clunky; Lua tables are cheap)
- `M.selectedChannel` — current match-scoped audience choice; Lua applies it to the single compact recipient control
- IPC outbound queue — FIFO of pending writes to `outbox.jsonl`
- Sidecar PID, socket state, file handles
- Match seed → room code derivation (string parsing)
- Periodic tasks (heartbeat, IPC poll, room derivation) — `LoopAsync` lives in Lua
- Cached references like `M.widget`, plus session identity values owned by `identity.lua`

BP doesn't see this state and doesn't need to. When BP needs to *display* a value derived from this state, Lua pushes it via bucket 3.

### Bucket 3: Derived display values — BP holds, Lua pushes

The TextBlock that shows chat history isn't "state" in the sense bucket 2 means — it's a rendering of state. Lua decides what string to render (joining `M.messages` with newlines, formatting senders, etc.) and pushes that string to BP via a setter. BP holds the string only to render it. No logic happens on it BP-side.

**Examples:**

- `ChatHistory.Text` (set by `:SetHistory(text)`) — Lua decides the format, BP shows it
- Currency display (Profile feature) — Lua tracks the actual value, pushes formatted string
- Unread message badge — Lua tracks the count, pushes the rendered "12" or hides the badge

**Rule:** if BP needs to do anything other than display the value, the underlying state is bucket 1 or bucket 2 — not bucket 3.

---

## The contract API surface

For each cross-context interaction, exactly one of three verbs applies:

### 1. Lua → BP push (display)

```lua
widget:SetHistory(formattedString)
widget:SetTypingIndicator(name)         -- "" to hide
widget:SetUnreadCount(n)
```

BP stores and renders. No BP-side logic operates on the value. Lua decides everything about the format.

### 2. Lua reads BP UI state

```lua
if widget.IsTyping then ... end
```

BP is source of truth. Lua reads it whenever it needs to make a decision. Lua never caches the value across ticks (it might change between calls).

### 3. BP fires events back to Lua

Two viable patterns. Pick one per event, document which:

**Pattern A — `Pending<X>` polling** (current chat uses this for submission):

```lua
-- BP: on Submit clicked, set widget.PendingMessage = inputText
-- Lua: poll each tick
local raw = widget.PendingMessage
if raw and raw ~= "" then
    widget.PendingMessage = ""    -- consume
    handle(raw)
end
```

Pros: simple, no UE4SS hook setup, decoupled timing. Cons: polling latency (one tick).

**Pattern B — UE4SS function hook** (use when BP must call a specific Lua function synchronously):

```lua
RegisterHook("/Game/Mods/OSPlus/Chat/WBP_ModChat.WBP_ModChat_C:OnSendClicked",
             function(self) chat.handleSubmit() end)
```

Pros: synchronous, no polling. Cons: harder to debug, asset-path-coupled.

**Default to Pattern A** unless synchronous handling is required.

---

## Anti-patterns

### Mirrored state

```lua
-- BAD: same fact in two places
M.isTyping = false                          -- Lua side
widget:SetIsTyping(false)                   -- BP side
-- Now if Lua and BP both write, they drift.
```

```lua
-- GOOD: one owner
-- BP owns IsTyping. Lua reads via M.isTyping(). Lua never writes it directly.
```

### Pulling logic into BP because state lives there

`IsTyping` lives in BP. The logic that *decides when to enter typing mode* (keybind handling, match-state gating) lives in Lua. Don't pull keybind handling into BP just because the resulting state is BP-owned. Lua triggers `widget:OpenInput()`; BP-side logic updates `IsTyping` as part of that function.

### Pulling state into Lua because logic lives there

Message formatting logic lives in Lua. Don't pull `IsTyping` into Lua just because the surrounding code is Lua. Read it from BP every time you need it (`M.isTyping()`).

### Two writers with implicit ordering

If both BP and Lua can write the same value, with each side assuming the other won't write at certain times, you have a race condition waiting to happen. Either single-writer, or use the explicit `Pending<X>` protocol where one writes-once and the other consumes-once.

---

## Designing a new feature: contract template

Before writing any code for a new feature, fill this in and put it at the top of the feature's Lua module:

```lua
-- ============================================================
-- Feature: <name>
--
-- BP-owned (UI-reactive state):
--   <Var1>: <type>  -- consumed by: <BP binding/event>
--   <Var2>: <type>
--
-- Lua-owned (domain / operational state):
--   <Var1>: <type>  -- managed by: <module function>
--   <Var2>: <type>
--
-- Lua → BP (display push setters):
--   :Set<Thing>(value)
--
-- BP → Lua (events, Pending<X> polling unless noted):
--   Pending<Action>: <type>  -- BP writes, Lua polls + clears
--
-- State explicitly NOT synchronized:
--   <BP-side animation state, Lua-side IPC plumbing, etc.>
-- ============================================================
```

Done well, this is 15-30 lines and tells the next reader (or agent) the entire surface in one glance.

---

## Audit: current `chat.lua` against this contract

Audited 2026-07-24 against `mod/OSPlus/scripts/chat.lua` and the rebuilt `WBP_ModChat`.

### State inventory

**Lua-owned (correct per contract):**

| Variable | Bucket | Notes |
|---|---|---|
| `M.widget` | operational | Cached UE object reference. Single owner. |
| `M.inMatch` | operational | Cached polling result. |
| `M.currentRoom` | domain | Match-wide WebSocket room code. |
| `M.currentTeam` | domain | Local relay routing team (`0` for game `TeamOne`, `1` for game `TeamTwo`; `nil` for spectator or unknown). Spectator status is tracked separately; `nil` team alone is not a caster permission signal. |
| `M.currentSpectator` | domain | Explicit local spectator flag derived from PlayerState spectator signals. Used for relay policy, because spectators may still carry an `AssignedTeam` viewing-side value. |
| `M.currentUsername` | domain | Last username sent to the relay for room membership; sourced from `identity.lua`, and changed names trigger a same-room rejoin. |
| `M.roomDelayTicks`, `roomRetries`, `matchProbeTimer`, `matchExitTimer` | operational | Timer state. |
| `M.messages` | domain | Array of `{sender, text, audience, targetTeam, time}`. Painful in BP. |
| `M.presence` | domain | Array of usernames in the current room (relay-pushed). Cached so widget reattach can re-render without waiting for the next server broadcast. |
| `M.feedTicks`, `M.feedVisible` | operational / derived display | Own the 10-second passive-feed lifetime and mirror the resulting background visibility into UMG. |
| `M.selectedChannel`, `M.channelRole`, `M.channelTouched` | domain / UI choice | Own the match-scoped audience selection, role-specific valid choices, and sticky-selection behavior. |
| `M.overlayFlags` | operational | Tracks the native `WBP_SettingsHub_C` navigation lifecycle so chat is suppressed while the Escape/settings screen is open. |
| `M.onChatSent`, `M.onRoomChange`, `M.onRoomLeave` | operational | IPC callbacks. `onRoomChange(room, username, team, isSpectator)` since v51. |

`chat.lua` deliberately owns no player-name cache. Local display-name ownership
stays in `identity.lua`, whose session identity source does not depend on a
match pawn or `PlayerState`.

**BP-owned (correct per contract):**

| Property | Bucket | Notes |
|---|---|---|
| `IsTyping` | UI-reactive | Drives Send button, click-out-close, animations. Also gates `SetHistory`'s follow-tail ScrollToEnd in v16. |
| `PendingMessage` | event channel | BP writes on submit, Lua polls and clears (Pattern A). |
| `ChatInput` | UMG | TextBox sub-widget. Pure UMG. |
| `ChannelTeam`, `ChannelAll`, `ChannelTeam1`, `ChannelTeam2` | input surface / derived display | Lua exposes only the selected choice as one compact control, mirrors `M.selectedChannel` into checked state, and treats a click as a request to cycle. The checkboxes are not a second owner of the selected audience. |
| `ClickCatcher` | UI-reactive input surface | BP shows this transparent full-screen button only while typing and binds it directly to `CloseInput()`, so an outside click closes chat without treating recipient-control clicks as focus loss. |
| `IsResizing`, `ResizeHandle` | UI-reactive input surface | BP owns press/release state and Slate pointer capture for the focused-only top drag edge. Lua reads `IsResizing` during the bounded drag, gets the live Slate cursor through `UWidgetLayoutLibrary:GetMousePositionOnViewport`, applies the mouse delta, and BP restores keyboard focus to `ChatInput` on release. |
| `FocusedHeight` | UI-reactive presentation | BP stores the current focused height so it survives close/reopen within the widget lifetime. Lua initializes it to 280 px, clamps it to 220-420 px, and applies it to the root size box. |
| `ChatHistory.Text` (implied) | derived display | Lua pushes via `:SetHistory()`. Tags must match rows in `DT_ChatRichTextStyles` (`Default`, `MessageTeam`, `MessageTeam1`, `MessageTeam2`, and `MessageAll`). Lua also restores `ChatScroll` to the end after open, close, or resize layout passes so viewport changes do not dislodge the newest rows. |
| `PresenceList.Text` (implied) | derived display | Lua pushes via `:SetPresence()`. RichTextBlock sharing the same Text Style Set as `ChatHistory`. |
| `ChatBackground` visibility and root size-box height | derived display | Lua pushes passive/focused/settings presentation and active resize height; BP does not make audience or match-state decisions from these values. A visible reserve spacer keeps the 40 px composer slot allocated while the composer panel itself is hidden, so existing rows do not jump when focus opens. |

### Findings

#### Finding 1 (substantive): `M.visible` semantics drift

`M.visible` claims to mean "is the widget visible," but actual BP visibility has at least three states (`HitTestInvisible`, `SelfHitTestInvisible`, `Collapsed`) and is written from both sides:

- **Lua writes:**
  - `M.showWidget()` → `SetVisibility(HitTestInvisible)`, sets `M.visible = true`
  - `M.hideWidget()` → `SetVisibility(Collapsed)`, sets `M.visible = false`
  - `M.open()` → `SetVisibility(SelfHitTestInvisible)`, **does not update `M.visible`**
- **BP writes:**
  - `CloseInput()` resets visibility to `HitTestInvisible` per the comment at `chat.lua#L385`

The boolean encodes "did Lua's match-detection decide to show the widget" — it has nothing to do with the widget's actual UMG visibility mode.

**Risk:** future code that reads `M.visible` expecting "is the widget on screen right now" will be subtly wrong.

**Recommendation:** rename to `M.shownForMatch`. Single line change. Captures the actual semantics.

**Future-proofing (defer until needed):** when adding any new visibility mode (e.g., expanded panel, focused chat), move all visibility orchestration into BP. Lua signals match-state and typing-state via setters; BP computes the right visibility mode itself. Eliminates the two-writer split.

#### Finding 2: visibility orchestration is split BP/Lua (related to Finding 1)

Lua sets visibility to `HitTestInvisible` / `SelfHitTestInvisible` / `Collapsed` directly. BP's `CloseInput` also writes visibility. This is two-writer state with implicit ordering rules: it works because the rules don't conflict today.

**Risk:** any future visibility state added to either side could conflict. The next feature requiring visibility coordination (e.g., a "minimize chat" toggle) will surface this.

**Current resolution:** the chat overhaul makes the division explicit instead of adding mirrored state. BP owns `IsTyping`, keyboard focus, and input mode. Lua owns match/feed/settings presentation and pushes root/background visibility plus height. `CloseInput()` returns the root to its non-interactive mode; Lua then applies the passive or hidden presentation. This remains an ordered cross-context contract and should not gain another writer.

#### Finding 3 (resolved 2026-07-24): local identity had two owners

The original chat implementation duplicated an old
`PlayerState.PlayerNamePrivate` resolver and maintained its own
`cachedPlayerName`. That contradicted the canonical local identity path in
`identity.lua` and failed for a custom-game spectator whose match-side player
state did not yield a friendly name.

`chat.lua` now calls `identity.resolveDisplayName()` for both room presence and
local sender labels. It waits for the authoritative
`UPMPlayerUIData.Profile.Username` value before joining when possible, uses
`identity.getBestLocalName()` as a neutral fallback, and re-joins automatically
when the friendly name becomes available. See
`docs/learnings/identity-display-name-substrate-replaces-heuristics.md`.

**Risk removed:** chat no longer depends on match actor/player-state lifecycle
for local identity, so players and spectators use the same session-stable name.

#### Finding 4 (positive): `PendingMessage` is the canonical Pattern A example

BP writes once on submit; Lua polls in `M.pollPending()`, reads, resets to `""` before processing. There's a polling latency (one tick ≈ 30ms) but no race because BP only writes a non-empty value once per submit.

This is the cleanest possible cross-context shared variable in the codebase. **Use this pattern as the reference for all future `BP → Lua` events.**

### Action items

| # | Action | Effort |
|---|---|---|
| 1 | Rename `M.visible` → `M.shownForMatch` in `chat.lua`. Update 8 references. | ~5 min |
| 2 | Add the contract header comment to `chat.lua` (template above) | ~10 min |
| 3 | Keep the documented BP-focus/Lua-presentation split; do not add another visibility writer | Ongoing guardrail |
| 4 | Keep local player identity in `identity.lua`; do not add a chat-level name cache | Resolved 2026-07-24 |

Items 1 and 2 remain cleanup tasks; they do not change the runtime ownership contract above.

---

## Future features will use this contract from day one

When Profile, Friends, Cosmetics, etc. land, each starts with the contract block at the top of its Lua module (see template above). The reviewer's first job (whether human or agent) is to verify the contract is honored: every state variable in one bucket, one owner, no mirroring, no two-writer races.

If a feature can't be expressed cleanly in the three-bucket model, that's a design signal — usually the feature is trying to put state in the wrong context.
