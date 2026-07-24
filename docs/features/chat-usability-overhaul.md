# Chat usability overhaul

| Field | Value |
|---|---|
| Slug | `chat-usability-overhaul` |
| Status | `shipped` |
| Created | 2026-07-09 |
| Last updated | 2026-07-24 |
| Owner | Codex + maintainer |
| Branch | `fix/chat-audience-routing-test` |

---

## Brief

**Problem.** The current in-match chat is difficult to operate and visually heavy. Opening and closing it does not feel reliable, it can remain above the game's Escape/settings screen, it gives no persistent indication of the selected recipient, channel selection depends on slash commands, and presence, history, and input are packed into one narrow panel.

**Audience.** All OSPlus players, with explicit support for custom-game spectators and tournament casters who need to switch between All, Team 1, and Team 2 quickly and confidently.

**Wedge fit.** Chat remains side infrastructure rather than the core OSPlus product, but a usable spectator workflow directly supports community events and casters. The work also strengthens the additive in-game UI pipeline used by future OSPlus features.

**Anti-goal check.** This remains an additive OSPlus widget and does not replace the native HUD or settings screen. It does not expose hidden gameplay information, add persistent chat history, add monetization, or make the relay authoritative over game state.

**Loose success criteria.**

- Pressing Enter always opens a clearly focused composer; Escape always closes it and restores game control.
- Clicking anywhere outside the open chat closes it and restores game control.
- Before typing, the player can see exactly who will receive the message and can change that target without entering a slash command.
- Players get Team and All choices. Spectators get All, Team 1, and Team 2 choices. Invalid recipient choices are not shown.
- The passive chat feed is compact enough to leave gameplay readable, while the focused state exposes the controls needed to send and review messages.
- The OSPlus chat does not render above the game's Escape/settings screen.
- Incoming messages from another connected player play one short, quiet notification sound.
- Message rows remain easy to scan without repeating long audience prefixes on every line.

**Out of scope.** Persistent history, moderation tools, relay protocol changes, configurable keybindings, configurable notification sounds, controller-first navigation, voice chat, and changing who is permitted to receive team-only messages. Slash commands may remain as a compatibility fallback, but they are no longer the primary interface.

---

## Feasibility

**Verdict:** Medium

**Confidence rationale.** The current cooked widget, Lua/BP boundary, message-audience model, and input-mode workaround are all working substrates that can be extended without changing the relay protocol. The settings lifecycle and rebuilt widget have now also been verified in the running game.

**Assumptions tested:**

- Reflected checkboxes can provide the compact channel control without adding a new BP-side channel variable or changing the relay wire format.
- Mouse selection and Tab/Shift+Tab cycling can return focus to `ChatInput` reliably.
- A transparent full-screen click catcher behind the panel can close chat on outside clicks without making recipient-control clicks count as focus loss.
- The proven `UI Only` on open and `Game And UI` plus `Set Focus to Game Viewport` on close sequence still restores gameplay control.
- `WBP_SettingsHub_C` navigation events accurately identify the Escape/settings screen without per-frame reflected-state polling.
- Existing team/spectator state is available before the composer opens often enough to show only valid recipient choices; unknown state safely falls back to All.
- The already-cooked `SFX_OSPlus_UI_Click` SoundWave is a 74 ms `SOUNDGROUP_UI` cue and can be played for relay-received messages without adding another asset.

**Evidence trail:**

- Static extraction of the cooked `WBP_ModChat` with `UAssetGUI tojson` shows a 41-export widget built from one fixed stack: presence header/list, divider, scrollable history, and input. Its `SizeBox` is 250 px wide with a 350 px maximum height, anchored at the bottom-right with `(-260, -50)` offsets.
- The existing widget already exposes `OpenInput`, `CloseInput`, `SetHistory`, `SetPresence`, `IsTyping`, and `PendingMessage`; `chat.lua` uses all of them successfully in the shipped mod.
- `PendingMessage` remains the only BP-to-Lua submission event. Lua owns the selected audience and mirrors it into the visible checkbox state.
- `docs/engine/widgets.md` records the working focus sequence and the reason closing must return through `Game And UI` rather than `Game Only`.
- Live verification confirmed `WBP_SettingsHub_C:OnNavigatedTo` on Escape/settings open and `OnNavBack` on close. It also disproved `WBP_InGameMenu_PC_C` as a pause-menu signal: that class is the normal match HUD and navigates in during match startup.
- The audience-routing work already carries `audience`, `targetTeam`, and explicit spectator state from Lua through the sidecar and relay. The visual overhaul only needs to select those existing values.

**Promoted findings:** -

**Recommended Stage 5 path:** thin slice first

Build and test the passive/focused layout, focus restoration, and channel selector as one local cooked slice; then lock the settings-overlay integration after one live pass before packaging the complete build.

---

## Design

**Approach.** Keep BP responsible for typing/focus transitions while Lua owns audience selection and the derived passive/focused presentation. During play, the bottom-left widget is only a short fading message feed. Opening it expands upward in the same 360 px footprint and adds exactly two things: one clipped line naming the players currently connected to OSPlus chat, and one composer row containing a compact audience control beside the input. The composer keeps its 40 px layout space while hidden so opening the chat does not move the visible message rows. Focused chat opens at 280 px tall and can be resized between 220 and 420 px by dragging its subtle top edge. The control reads `Team`, `All`, `Team 1`, or `Team 2`; clicking it or pressing Tab/Shift+Tab cycles through only the choices valid for the local player. Enter opens/submits, Escape closes, and a transparent full-screen click catcher behind the panel closes chat when the player clicks elsewhere. The native Escape/settings screen always suppresses the whole widget, including newly arriving feed rows. Messages received from another client play the existing short UI click sound; locally sent messages do not. Passive messages disappear after 10 seconds, opening chat reveals the full current-match history, colored audience markers replace repeated text prefixes, and slash commands remain as a compatibility fallback.

**Axes considered:**

- Presentation: chose a message-only passive feed plus focused composer over an always-expanded panel or submit-only popup because it preserves incoming-message awareness without occupying the HUD continuously.
- Placement: chose bottom-left, lifted above the reaction row, because it follows familiar game-chat placement without covering the reaction shortcuts.
- Audience control: chose one compact cycling recipient control over a full segmented row, slash commands, or a dropdown because the current recipient stays explicit without spending another row of HUD space.
- Audience lifetime: chose sticky selection within the current match, reset to Team for players and All for spectators, over resetting after every send or persisting across sessions.
- Focus behavior: chose explicit Enter/Escape/submit transitions plus close-on-outside-click. BP remains authoritative for typing, keyboard focus, and input mode; Lua pushes the panel size and visibility derived from match, feed, and settings state.
- Layout stability: chose a permanently reserved, invisible composer slot so passive message rows keep the same bottom anchor when the composer opens.
- History size: chose a taller 280 px focused default plus a 220-420 px vertical drag range. A 12 px transparent hit target with a centered 2 px grip appears only while composing and does not add another visible control to the crowded HUD.
- Passive lifetime: chose a 10-second fade over permanently visible history or immediate disappearance.
- Message density: chose one narrow colored audience marker plus an unbracketed sender over repeated `T1` / `T2` / `ALL` prefixes or separate per-message widgets.
- Presence: chose one clipped, focused-only connected-player line. It reports who is connected to OSPlus chat, not who receives the currently selected audience, and disappears with the composer.
- Settings integration: chose native settings lifecycle suppression, verified live before packaging, over per-frame polling; viewport ordering remains a defensive fallback.
- Notification: chose the existing short UI click cue for relay-received messages only, with no new setting or sound asset.
- Compatibility: chose extending the current BP/Lua contract while keeping the existing relay frames and slash-command parser.

**Decisions deferred to ADR:** -

**Files that changed:** `WBP_ModChat`, `DT_ChatRichTextStyles`, `mod/OSPlus/scripts/chat.lua`, `mod/OSPlus/scripts/config.lua`, `mod/OSPlus/scripts/main.lua`, and the chat/state architecture docs.

**Files that will NOT change but matter:** `sidecar/index.js` and `server/index.js` keep the approved audience-routing contract; `ModActor` continues to instantiate the same widget class.

---

## Outcome

The first `0.3.0` widget test proved the focus and settings lifecycle but was rejected during visual review: its permanent dark block, full-width audience tabs, low placement, and removed connected-player list did not fit the crowded match HUD or Omega Strikers' visual language.

The replacement compact design was approved on 2026-07-23. Its acceptance pass confirmed:

- Enter opens, Escape closes, and clicking outside closes with gameplay control restored.
- A player gets Team and All; a spectator gets All, Team 1, and Team 2 through the single compact recipient control.
- The connected-player line appears only while composing.
- The passive feed contains only recent message rows, clears the reaction shortcuts, and disappears after 10 seconds.
- Opening the composer does not move existing message rows, and the focused history opens taller than the passive feed.
- Dragging the focused chat's top edge resizes it between 220 and 420 px without losing input focus.
- Opening settings hides the chat and newly arriving messages cannot make it appear above settings.
- A relay-received message plays the short notification sound once; a locally sent message does not.
- The cooked widget loads from the newly packaged `OSPlus.pak` without UE4SS errors.

Build verification completed on 2026-07-23 and production acceptance completed on 2026-07-24:

- The rebuilt widget helper compiled and saved the compact widget with the outside-click binding.
- Windows cooking completed with zero errors and zero warnings.
- The installed pak contains the rebuilt widget, message styles, and notification sound.
- The running game loaded the widget and accepted local All and Team 1 incoming-message fixtures without chat, sound, or script errors.
- Short and overflowing histories remain bottom-anchored when the composer opens; the newest row stays beside the composer rather than jumping or disappearing.
- The audience label is optically centered, and the connected-player line remains available only in the focused view.
- The 12 px resize hit target keeps pointer capture outside the visible grip, follows upward and downward movement continuously, and restores input focus on release.
- Player-controlled verification confirmed Enter, Escape, outside-click close, settings suppression, incoming sound, and live resize behavior in Practice.
- The first two-client spectator test exposed one remaining identity bug: the spectator joined chat without a friendly name because chat still read its own match-side `PlayerState` path. Chat now uses the shared session identity resolver for both presence and sender labels, independent of whether the local client has a gameplay pawn.
- A final two-client custom-game pass confirmed that the spectator now appears under the correct friendly name and that the completed `0.3.0` chat works in live play.

---

## Notes

### Current widget baseline

```text
bottom-right, 250 px wide, up to 350 px tall

Presence
player list
divider
scrolling message history
message input
```

The old passive and focused states shared this same visual stack. The approved replacement keeps the passive state message-only and restores presence as one focused-only line above the history.
