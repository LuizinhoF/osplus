# ADR 0004 — Emote loadout as an OSPlus-canonical parallel layer

| Field | Value |
|---|---|
| Status | `accepted` (U-α mechanism revised 2026-05-16) |
| Date | 2026-05-01 |
| Forcing feature | `feat/first-unlock-emote-lvl10` (Stage 4 — first concrete unlockable; needs a way to equip OSPlus-cosmetics alongside vanilla ones) |
| Supersedes | — |
| Superseded by | — |

## Revision 2026-05-16 — U-α mechanism corrected

The original U-α decision committed to "replace the Cosmetics → Emote sub-tab content with an OSPlus-cooked widget" but the *mechanism* of that replacement was misframed. The original framing (and subsequent R1/R2/R3 iterations in the linked feature brief) all attacked the widget tree — cooked-asset replacement hit the `Serial size mismatch` wall, side-loaded viewport sacrificed the "one place" UX, and runtime widget-tree manipulation on `CosmeticsPanelSwitcher` produced UMG mutations that Slate never reflected. A dragnet of twelve native UMG/UPanelWidget functions during sub-tab clicks captured zero fires. The mechanism is not in the widget tree.

Static extraction of `WBP_Panel_StrikerCosmetics`, `Interface_WBP_Panel`, `WBP_TabHeaderGroup_IconAndText`, `WBP_TabHeader_IconAndTextItem` revealed the actual routing layer: a custom BP UFunction `SetActivePanel(targetPanel)` is the chokepoint, called once per sub-tab click by a delegate chain (tab button → tab group fires `OnActiveHeaderChanged(TabId Name)` → bound `OnCosmeticTabChanged` handler does SwitchName → `SetActivePanel(<matching sub-panel ref>)`). The same pattern is reused at `WBP_Menu_Striker_C` for top-level Affinity / Overview / Cosmetics routing.

**Validated production mechanism (2026-05-16, real change in-game showing correct behavior):**

- `RegisterCustomEvent("SetActivePanel", callback)` at module init. `RegisterHook` does NOT work for pure BP UFunctions (`FUNC_Native: 0`); `RegisterCustomEvent` hooks at `ProcessInternal` dispatch level instead. See [`docs/learnings/ue4ss-registerhook-vs-registercustomevent.md`](../learnings/ue4ss-registerhook-vs-registercustomevent.md).
- Inside callback: `Context:get():GetClass():GetFName():ToString()` filters to `WBP_Panel_StrikerCosmetics_C`. Required because `RegisterCustomEvent` matches by short name globally (`WBP_Menu_Striker_C` also has a `SetActivePanel` for top-level routing).
- `arg[2]:get()` retrieves the target sub-panel reference. When it's the native Emoticons panel, recursively call `self_:SetActivePanel(osplus_widget_ref)` — guarded by a recursion-flag — to redirect display to the OSPlus widget. `Param:set` was tested but `RegisterCustomEvent` fires post-execution; the recursive-call pattern is the working redirect.

**Revised U-α:** the OSPlus emote loadout widget plugs in via `RegisterCustomEvent` + recursive `SetActivePanel` redirect — NOT cooked-asset replacement, side-loaded viewport widget, or widget-tree mutation. The cooked OSPlus widget must implement `Interface_WBP_Panel` (provides `OnPanelActivated`) and respond to `OnUIDataSet` for striker context. Native data model (`PMUIDataModel.Catalog`, `ReactionsByCharacterId`, `EquipEmoticonToSlot`, `SwapEmoticonSlots`) is consumed unchanged — only the UI surface is OSPlus. See [`docs/learnings/customize-page-tab-routing-architecture.md`](../learnings/customize-page-tab-routing-architecture.md) and [`docs/learnings/emoticon-panel-data-model.md`](../learnings/emoticon-panel-data-model.md).

**R-Hook commitment for in-match wheel unchanged.** The original `R-Hook` decision (RegisterHook on `UpdateReactionButtons`, post-call hook for in-match wheel render) remains valid as written. That target is a native UMG render path (`FUNC_Native: 1`), and `RegisterHook` works correctly there. The mechanism correction in this revision applies *only* to U-α (menu-side panel routing), not R-Hook (in-match render).

**S-Relay, V-Relay, B-Seed unchanged.** Relay-canonical loadout state authority, cross-OSPlus-peer visibility via the relay, and first-launch bootstrap from native loadout are all unaffected — they're about loadout state, not UI activation.

**The R1 / R2 / R3 framing in the linked feature brief is now superseded by this revision.** Feature brief will be revised in the same change as the v1 deliverable (native-only emote tab rework) gets framed.

## Decision

Replace the native **Cosmetics → Emote** sub-tab content with an OSPlus-cooked widget. Treat the **OSPlus relay as the canonical source of truth for the player's 7-slot emote loadout**; native Prometheus loadout state is left untouched. Rendering in the in-match wheel and reaction modal is overridden per-slot via additive Lua hooks.

- **U-α** — UI surface: replace the sub-tab content widget. The native customization page (Affinity / Overview / Cosmetics tabs, and the Skins / Emote / Goal Explosion sub-tabs) stays — only the *Emote* sub-tab's body is ours.
- **S-Relay** — State authority: OSPlus relay holds the canonical 7-slot loadout per player. Native `SetCustomizationInfoForWidgetType` is **not called** from this feature.
- **R-Hook** — Render override: post-call hook on `WBP_ReactionButtonPanel.UpdateReactionButtons` (in-match wheel) and on the `WBP_ReactionModal_C` reaction-dispatch path (per-slot use). Per-slot dispatch:
  - Native-emote slot → call native `ShowEmoticon(<native_asset>)`. Replicates normally via UE; everyone (vanilla + OSPlus) sees correctly.
  - OSPlus-emote slot → **drive the same native render path with our cooked `PMEmoticonData`** (icon-above-head, native bounce/settle animation, native display timing, Wwise event from the asset → "one of three sounds"). Sender renders locala: ly; relay broadcast (V-Relay) drives the same render path on other OSPlus peers' clients. **Do not invoke the native replication path** with our cooked asset (the *replication* path is what reaches vanilla peers and would mis-resolve; the *render* path is local-only widget code we own at runtime). Vanilla peers see nothing.
- **R-Native-Render-Fidelity** — The native modal/widget owns the visual+audio behavior of an emote display (head-anchor placement, bounce-then-settle animation, on-screen lifetime, Wwise audio firing). OSPlus emotes inherit all of it by being driven through the same `WBP_ReactionModal_C` entry point as native emotes — we never reimplement the animation or the audio dispatch. The asset carries the texture + Wwise event; everything else is widget-native.
- **V-Relay** — Cross-OSPlus-peer visibility goes through the existing OSPlus relay, not native UE replication. New WS message types extend `VALID_TYPES` (Brief picks names, expected shape: client→relay carries `(slot, emote_id)`; relay→clients carries `(senderPid, slot, emote_id)`). The match-room is the chat-room already in use — derived from `GameState_Game_C.CurrentMatchSeed` per [`docs/learnings/relay-room-code-regex-vs-derived-codes.md`](../learnings/relay-room-code-regex-vs-derived-codes.md), so OSPlus peers in the same match are *already* in the same WS room before any emote flows. Receive-side renders the OSPlus emote on the firing player's avatar (Stage-3 confirms the render UFunction; native `ShowEmoticon` flow with a remote `PlayerState` target is the prime hypothesis).
- **B-Seed** — Bootstrap: on first OSPlus launch with empty relay state for this PID, one-time read of `PMPlayerState.GetEquippedReactions()` seeds the relay loadout. From there OSPlus owns the state; native is never re-read.

This ADR is gated on a Stage-3 Pass-2 in-game probe confirming (a) the sub-tab swap mechanism is reliable and (b) `UpdateReactionButtons` hookability survives a re-render trigger. Sign-off here authorizes the Brief + probe; failure of either probe re-opens this ADR.

## Why these picks

- **U-α over U-β / U-γ / U-δ.** β (inject filter + section into the native sub-tab) keeps native layout that's the very thing we're trying to fix (no filter, dense flat grid, no preview); we'd be working *around* the constraints that motivated this feature. γ (add a 4th sub-tab) means OSPlus emotes never interleave with native ones in one searchable list, which the maintainer-stated UX requires. δ (separate home-hub entry point) buries it. α is the smallest surface that delivers the actual UX goal. **Wholesale main-menu replacement (U-Ω) was considered earlier in the chat and rejected** as a product-shape change disproportionate to "ship one unlockable emote."
- **S-Relay over S-CrossWrite.** Cross-writing native emote equips to Prometheus from this feature was explicitly considered and rejected: the backend will reject unknown FNames (our cooked OSPlus assets), so cross-writing only "works" for the native-emote subset, and split source-of-truth between OSPlus relay and Prometheus invites drift. Single owner is honest. Side effect (named in *What this commits us to*): if the player uninstalls OSPlus, their reaction wheel reverts to the last vanilla-equipped state — acceptable for a parallel-layer model.
- **R-Hook over R-Replace / R-Reimpl.** Two paths exist for getting an OSPlus emote on screen: (Path A) drive the native render pipeline with our cooked `PMEmoticonData` and never invoke native replication, or (Path B) reimplement the render pipeline ourselves in OSPlus widgets. Path B forces us to reproduce the bounce/settle animation, head-anchor placement, on-screen lifetime, and Wwise audio dispatch — all native polish — *and* leaves us holding the Odyssey-server-comms question for vanilla-peer visibility (we'd need to talk to the vanilla server the way the game does, which is unknown territory we don't want to enter for v1). Path A treats the visibility-to-vanilla problem as separable (the V-Relay decision handles OSPlus-peer visibility cleanly; vanilla-peer visibility is its own follow-on if ever wanted), and reuses the same hook pattern `chat.lua` uses for native UI integration today. **We commit to Path A.**
- **V-Relay over V-NativeRepl over V-LocalOnly.** Native UE replication (V-NativeRepl) for OSPlus emotes would emit a `ShowEmoticon` RPC pointing at an asset vanilla peers can't resolve — behavior is unverified (silent fail / placeholder / crash all plausible) and we shouldn't ship something we haven't tested. Local-only (V-LocalOnly) was a v1 fallback considered when I was thinking in native-replication terms; it's strictly worse than V-Relay because OSPlus emotes are universally shipped (every OSPlus peer has every OSPlus asset by construction), so relay-mediated broadcast lets OSPlus peers in the match see the emote with zero asset-resolution risk. The chat-room substrate (room codes derived from `CurrentMatchSeed`) already places OSPlus peers in the same room before an emote fires; the marginal cost is one new pair of WS message types. An earlier draft of this ADR proposed shipping our cooked OSPlus assets with `bHideFromEnemyTeam=true` for "graceful invisibility on vanilla peers" — that reading was wrong (the flag is a gameplay-mechanic switch for team-only in-match callouts, not a cross-client visibility gate; verified by maintainer in-conversation). V-Relay sidesteps the question entirely: we don't emit a native packet for OSPlus emotes, so there's nothing for vanilla peers to mis-handle.
- **B-Seed over fresh-blank.** A first-launch player whose vanilla loadout is non-empty and whose relay state is empty would otherwise see a blank wheel — gratuitous regression. One-time native read, written through OSPlus's normal write path, makes the install seamless.

## What this commits us to

- **New cooked widget** at `/Game/Mods/OSPlus/UI/WBP_OSPlusEmoteLoadout` (or sibling under `mod/Mods/OSPlus`), shipped in `OSPlus.pak`. Brief decides exact path. Hosts the search bar, filter chips, sectioned grouping (per-striker + general), preview-with-Equip footer, and the equipped 7-slot row.
- **Sub-tab swap mechanism** confirmed by Stage-3 Pass-2 probe (verified widget tree captured in [`docs/engine/widgets.md` → "Customization screen"](../engine/widgets.md#customization-screen-home-hub--customize); swap target is `WBP_Panel_StrikerEmoticons_C` inside the `CosmeticsPanelSwitcher` `UWidgetSwitcher`); production install pattern lives in a new `mod/OSPlus/scripts/loadouts.lua` (or extension of an existing module — Brief picks).
- **Schema (relay) — adds to `osplus.sqlite3`** (per ADR 0002, growing the existing DB):
  - `emote_loadouts(prometheus_id, slot_index, emote_kind, emote_id, updated_at, PRIMARY KEY (prometheus_id, slot_index))` — `emote_kind` is `'native'` or `'osplus'`; `emote_id` is the FName for native or the OSPlus-internal ID for OSPlus.
  - `emote_unlocks(prometheus_id, emote_id, granted_at, source, PRIMARY KEY (prometheus_id, emote_id))` — relay-authoritative per-PID ownership; rows derived server-side from current profile state (e.g. `mastery_level >= 10` grants the lvl-10 emote). The forcing feature defines initial grant logic.
- **HTTP routes (relay)** — auth-required, cross-PID = `403`:
  - `GET /api/loadouts/emotes/{prometheusId}` → 7 slot rows
  - `PUT /api/loadouts/emotes/{prometheusId}` → full-replace upsert
  - `GET /api/unlocks/emotes/{prometheusId}` → list of owned OSPlus emote IDs (computed on read against current `mastery_level`)
- **Sidecar IPC + REST client** — read on identity-resolve, write on equip clicks, cache locally for offline render. Pending-write retry buffer like captures.
- **In-match Lua hooks** — `RegisterHook` on `UpdateReactionButtons` (post) and on the modal's slot-dispatch UFunction (Brief identifies exact target). Hooks read OSPlus state via the same module that drives the customization page.
- **New WS message types** — extend `VALID_TYPES` in `server/index.js` for the emote broadcast pair (Brief names them; current convention favors single-word imperative + past-tense pair like `chat`/`chat`, e.g. `emote` from client and `emote` from relay with a `senderPid` field, OR an explicit `emote`/`emoted` pair — Brief decides). 4 KB payload + 5 msg/s rate limit per ADR 0002's hardening baseline applies unchanged.
- **Receive-side render for remote OSPlus emote events** — sidecar forwards relay broadcast to Lua via inbox; Lua resolves the firing player's `PlayerState` from the match roster and triggers the OSPlus emote render on their avatar through the **same `WBP_ReactionModal_C` entry point native uses**. The existing spike (`mod/OSPlus/scripts/native_emotes.lua`) already drives this path for the local sender; Stage-3 Pass-2's only new question is whether the same entry point accepts a remote `PlayerState` target without triggering native replication.
- **Cooked OSPlus `PMEmoticonData` asset(s)** — at least one (the lvl-10 unlockable). Carries texture + one Wwise audio event ("one of three sounds" is per-asset, picked from the same set native uses). Used on the **local sender's render path** and on **OSPlus peers' render paths via relay broadcast**; never passed to native UE replication. Bounce/settle animation and head-anchor positioning are inherited from the native widget — not asset properties.
- **Per-striker grouping metadata strategy** — Brief-level decision; default approach is asset-path heuristic (`EmoticonData_<Striker>_*`) with a manual override table for outliers.
- **Maintenance commitment named explicitly:** the Cosmetics → Emote sub-tab is now ours forever (as long as this feature ships). Odyssey patches affecting that sub-tab's host widget → potential breakage we resolve.

## What this rules out (until superseded)

- Cross-writing equip changes to Prometheus (deferred).
- **Vanilla-peer visibility for OSPlus emote uses** — vanilla clients see nothing when an OSPlus emote fires (no native packet emitted, and they have no OSPlus relay connection). Per Q3 in-conversation, this is the deliberate posture, not a bug. A future feature could ship a "stand-in" native emote alongside the relay broadcast so vanilla peers see *something*; that's its own design and isn't part of this ADR.
- Slot 8+ in the in-match wheel and the OSPlus-dedicated multi-level-emote UI to access them — deferred to a future feature with its own ADR if the access surface is non-trivial.
- Other native-customization sub-tabs (Skins, Goal Explosion, Logos, Nameplates, Titles) — out of scope. Replacing those would force a separate ADR.

## Revisit when

- Second OSPlus customization-tab feature lands (e.g. nameplates with OSPlus-internal flair). Likely forces a shared "OSPlus-canonical-cosmetic-layer" pattern; this ADR's S-Relay framing generalizes naturally, but the abstraction question is its own ADR.
- A future feature wants OSPlus emotes visible to **vanilla** peers (e.g. paint a relay broadcast onto a "stand-in" native emote so vanilla players see *something*). Different design space from the OSPlus-peer pub/sub V-Relay commits us to. Would amend the *What this rules out* section.
- Odyssey ships a UI update affecting the Cosmetics → Emote sub-tab (notice → adapt; if the host widget structure changes, the swap mechanism may need re-discovery).
- Slot 8+ feature gets framed.

## Considered and rejected

- **U-β** — Tab-injection (filter/section into native sub-tab). Doesn't blend OSPlus + native into one searchable list; native layout limitations leak through.
- **U-γ** — Add 4th sub-tab "OSPlus" alongside Skins/Emote/Goal Explosion. OSPlus emotes don't interleave with native; UX context-switch.
- **U-δ** — Separate entry point in the home hub. Worst discoverability for the loadout flow.
- **U-Ω** — Wholesale main-menu replacement (rejected mid-conversation as a product-shape change without ADR / product.md update).
- **S-CrossWrite** — Mirror native-emote equips to Prometheus from this feature. Backend rejects unknown FNames; cross-writes only work for native-emote subset; invites split-source drift.
- **R-Replace** — Replace `WBP_ReactionButtonPanel` + `WBP_ReactionModal` wholesale. Forces re-implementation of native polish; hook is strictly cheaper for the same outcome and forbidden by R-Native-Render-Fidelity.
- **R-Reimpl (Path B)** — Reimplement the entire emote render pipeline in OSPlus widgets. Would let us render any asset we control end-to-end, but forces us to (a) reproduce native bounce/settle/audio fidelity exactly, and (b) own the Odyssey-server-comms question for vanilla-peer visibility (how the game actually requests peer-emote rendering). Path A sidesteps both for v1.
- **B-Blank** — Start with all 7 slots empty on first OSPlus launch. Gratuitous regression vs. vanilla.
- **Slot-8-only OSPlus** — Cap OSPlus to slot 8, leave slots 1–7 vanilla-controlled. Constrains the player's flexibility for no architectural benefit; rejected by maintainer.

## Related

- **Forced by:** [`docs/features/first-unlock-emote-lvl10.md`](../features/first-unlock-emote-lvl10.md) (Brief drafted next, after this ADR is accepted)
- **Relies on:** [`0001-identity-model.md`](./0001-identity-model.md) (`prometheus_id` PK), [`0002-profile-storage.md`](./0002-profile-storage.md) (`osplus.sqlite3`, auth middleware, schema-grow-on-demand policy)
- **Supersedes:** —
- **Code locations** (post-acceptance, to be implemented):
  - `server/api/loadouts/` (new module — schema, REST handlers)
  - `server/api/unlocks/` (new module — derived ownership read)
  - `sidecar/loadouts.js` (new — IPC + REST client + retry buffer)
  - `mod/OSPlus/scripts/loadouts.lua` (new — IPC handler, in-match render hooks)
  - `mod/OSPlus/scripts/emotes.lua` (revived from prior on-disk-only state — used by hooks for `ShowEmoticon` dispatch)
  - `ue-assets/.../WBP_OSPlusEmoteLoadout` + cooked `PMEmoticonData_OSPlus_*` asset(s)

## Notes

- The pattern "OSPlus owns parallel state, native game state untouched, render-side hooks do the integration" is the same shape `chat.lua` follows (parallel chat layer, no native chat dependency). Reusing it here keeps the architecture story coherent: OSPlus features default to *additive parallel layers*, with native-write-paths added only when a feature specifically needs native cross-client effects.
- An earlier draft of this ADR proposed `bHideFromEnemyTeam=true` on cooked OSPlus assets as a graceful-invisibility trick for vanilla peers. **That reading was wrong**: the flag gates team-only in-match *callouts* (e.g. "Spread out!" / goalie defends-callout) at the gameplay layer — not cross-client visibility based on installed mods. Verified by maintainer in-conversation. Captured here so the next agent doesn't reach for the same mistake. The corrected `PMEmoticonData` flag semantics also live in [`docs/learnings/native-reaction-showemoticon-pmemoticondata.md`](../learnings/native-reaction-showemoticon-pmemoticondata.md) so the engine-side note compounds.
- Per-striker grouping metadata is **not** pinned in this ADR. The Brief picks between asset-path heuristic / maintained classification table / hybrid. Default recommendation: hybrid (heuristic primary, manual override for outliers). Promoted here only because the choice affects the customization widget's data layer, not the state-authority decision this ADR is making.
