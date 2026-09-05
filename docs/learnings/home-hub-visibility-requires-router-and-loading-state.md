# Home Hub add-ons belong in the native screen hierarchy, not a global viewport layer

| Field | Value |
|---|---|
| Date | 2026-07-28 |
| Area | mod / re |
| Tags | `home-hub, loading-screen, widget-lifecycle, update-notification, ue4ss` |
| Status | `confirmed` |

> **2026-07-28 final correction:** The symptom and persistent-widget diagnosis
> below remain correct, but no delayed visibility gate is needed. The
> production correction parents the notice to the Home Hub's native
> `UIContainer`; the loading transition then covers and reveals it naturally.
> Loading hide-completion releases the sound/attention cue and, for the clickable
> notice, restores link input; it does not decide whether the card's pixels may
> render. See
> [`ue4ss-stale-uobject-getclass-crash`](./ue4ss-stale-uobject-getclass-crash.md)
> for the crash that ruled out reflected router polling.

## Symptom

The update-available card rendered above the startup-to-Home-Hub transition,
before the native menu reveal had finished.

## Root cause

`FindFirstOf("WBP_HomeHub_PC_C")` was treated as proof that the Home Hub was
active. The Home Hub is a persistent out-of-game widget and can already be
constructed behind the loading screen. The notice was also added directly to
the global viewport, so even a correct Home Hub state check could not make it
participate in the native screen's paint order or transition.

The runtime log made the ordering explicit: the notice was shown from the
`presence probe`, with no preceding Home Hub `OnNavigatedTo` event.

## Fix

`mod/OSPlus/scripts/update_notification.lua` now:

- reparents the collapsed notice into
  `WBP_HomeHub_PC_C.UIContainer`, the same native canvas that directly owns
  `PlayPanel`;
- gives it a full-stretch canvas slot at z-order `2`, alongside `PlayPanel`,
  while group invites and modal/loading layers remain above it;
- uses `OdyUIRouter:OnMenuDisplayStateChanged` as the visit state owner,
  attaches on `AnimatingIn`, and presents on `Showing`;
- performs one immediate read of the Home Hub's own `DisplayState` after a map
  load to cover a missed startup event, with no settle delay and no repeated
  router lookup;
- keeps the full-screen wrapper and inner root `SelfHitTestInvisible`, so only
  the bounded `ReleaseLinkButton` accepts clicks, and relies on ModActor's
  existing `TopLevelOnly=false` duplicate lookup after the widget becomes a
  nested child. This input refinement adds the release link without changing
  the native layer or lifecycle rules; see
  [`update-notice-release-link-input`](./update-notice-release-link-input.md);
- arms the entrance animation and sound separately, then releases that cue from
  the native `OdyWidget:AnimateOutComplete` post-hook filtered to
  `WBP_LoadingScreen_C`. A one-shot `DisplayState` read handles notices that
  arrive after the loading screen is already gone, while a construction event
  reads the newly created loading widget itself to recover late startup order.
- restores localized copy and visibility after a Home Hub/widget rebuild
  without replaying an already-consumed cue, and keeps the release pending if
  the cooked localization bridge cannot populate the card.

Because the notice now lives inside the Home Hub, the native loading transition
covers it by construction. No loading-manager property read, timer, or
loading-state hook decides when its pixels become visible. The completion hook
aligns the one-shot cue with the moment the native cover has finished and
restores link input after that cover; the card's pixels follow native layering.

## Lesson

Persistent widget existence proves construction, not player-visible screen
state. For screen-specific additive UI, first put the widget inside that
screen's hierarchy, then use the screen/router's own display state for
presentation. Layer ownership is stronger than guessing how long a transition
will take. Never use `UObject:GetClass()` to filter a possibly stale wrapper.

## Related

- Files: `mod/OSPlus/scripts/update_notification.lua`,
  `docs/engine/widgets.md`,
  `docs/features/update-availability-notification.md`
- Prior learnings:
  `docs/learnings/osplus-widget-integration-pattern.md`,
  `docs/learnings/chat-settings-lifecycle-suppression.md`
- Runtime evidence:
  `%LOCALAPPDATA%/OSPlus/test_events.log`;
  installed UE4SS type stubs for `CommonLoadingScreen`, `OdyUI`, and
  `OdyUI_enums`
