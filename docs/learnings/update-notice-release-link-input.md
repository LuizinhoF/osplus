# Clickable update notices need a bounded input target and the displayed release URL

| Field | Value |
|---|---|
| Date | 2026-09-05 |
| Area | ue-editor |
| Tags | `update-notification, github-release, hit-testing, localization, ue-5-1` |
| Status | `confirmed` |

## Symptom

The update notice displayed a new release but offered no way to open its
GitHub page. Adding a button alone would not make it clickable: the existing
full-screen outer widget used `HitTestInvisible`, which disables hit testing
for every descendant.

The prior Home Hub learning said it "keeps the full-screen wrapper
hit-test-invisible." That was correct for the original passive notice. The
clickable version needs `SelfHitTestInvisible` on the outer widget and inner
root, with only its bounded card button receiving input. Its native Home Hub
parent, layer order, loading coverage, and cue timing remain the same.

The first clickable build opened the correct page in English and Portuguese,
but its native Slate tooltip remained above other windows after the game was
minimized while the notice was hovered. The player confirmed it disappeared
only after hovering the notice again.

## Root cause

UE distinguishes ignoring a widget from ignoring its entire subtree. A
`Visible` button under any `HitTestInvisible` ancestor still cannot receive a
click. Making the full-screen wrapper itself `Visible` would create an
unnecessarily broad input target.

The release URL also needs presentation ownership. The newest pending release
can differ from the card currently displayed, especially during an asynchronous
check, language change, or widget recovery. Looking up the newest release at
click time could open a page for a version the player is not seeing.

A standard Slate tooltip is a separate floating window, outside the card's
Home Hub hierarchy. The live minimize sequence left that popup visible after
the game lost focus. Parent layering cannot contain a popup painted in a
different window, so the hint must render inside the card itself.

A separate registration defect invalidated the first Settings gate:
`RegisterCustomEvent` retains only the first callback for an event name on
UE4SS 3.0.1. `chat.init()` registers navigation names first, so the update
module's later callbacks do not run. The mock had accepted multiple callbacks
and did not reproduce this limitation. The corrected rule and pinned source
links live in [the UE4SS reference](../engine/ue4ss-version-and-gotchas.md#6-registercustomevent-retains-only-the-first-registration).

## Fix

- `mod/OSPlus/scripts/update_notification.lua` accepts only the exact
  `https://github.com/LuizinhoF/osplus/releases/tag/v<version>` address for the
  displayed strict stable version. Missing, mismatched, alternate-host,
  non-HTTPS, asset-download, query, and fragment variants become an empty link.
- `visibleVersion` and `visibleReleaseUrl` hold the visible card's snapshot,
  separately from pending facts. Restore and language refresh reapply that
  same pair.
- `WBP_OSPlusUpdateNotice` owns one `ReleaseLinkButton` filling the existing
  300x64 card. Its `OnClicked` event calls `OSPlus_OpenReleasePage`, which checks
  the stored `ReleasePageUrl` before calling Unreal's `LaunchURL`.
- `OSPlus_SetReleaseLink` stores the validated URL, converts the localized
  inline hover hint from `FString` to `FText` inside BP, and enables the button
  only when the URL is nonempty. The `tooltipString` parameter name remains for
  compatibility, and the localization key remains
  `update_notification.view_release`; neither creates a native tooltip popup.
- `OnHovered`/`OnUnhovered` call BP-owned `OSPlus_SetReleaseHover`. The hint
  replaces the card's secondary version line while hovered. `VersionText` and
  `ReleaseHintText` share the bounded `VersionDisplay` overlay; the version is
  `Hidden` rather than `Collapsed` while the hint shows, preserving its layout
  contribution. The normal line returns on unhover or any link refresh. The
  standard tooltip text is empty. Restyling resolves the vertical-box slot on
  `VersionDisplay` after this reparenting, rather than assuming `VersionText`
  is still a direct vertical-box child.
- The outer widget and inner root use `SelfHitTestInvisible`. If the cooked
  link setter fails, Lua puts the outer widget in `HitTestInvisible` so a stale
  destination cannot remain interactive; the informational notice can still
  render.
- The existing native `OdyUIRouter:OnMenuDisplayStateChanged` hook owns the
  Settings input gate, filtering `WBP_SettingsHub_C`. Numeric nonzero states
  keep the cover active; `NotShowing` (`0`) clears it; unreadable state leaves
  the prior gate unchanged. It shares this native hook with Home Hub handling,
  not chat's short-name custom navigation registrations.
- Settings router state and native loading events temporarily clear the applied
  link and hint and disable descendant hit testing while those overlays cover
  the Home Hub. On return, Lua restores the saved visible release without
  ending its Home Hub visit or replaying its consumed cue. BP owns hover
  presentation; Lua does not poll the cursor or invent a minimize timer.
- UE 5.1's C++ `UButton` exposes the public `IsFocusable` field, not a
  `SetIsFocusable` method. The editor authoring helper sets that field to
  `false` to avoid taking keyboard focus.

Verification as of this revision: the initial clickable widget compiled and
saved twice; graph inspection found one bound click event; and tree inspection
confirmed the 300x64 fill button. Live English and Portuguese clicks opened
`https://github.com/LuizinhoF/osplus/releases/tag/v0.4.0` while the game stayed
running. The browser's 404 was expected because 0.4.0 was a simulated release.
That same build exposed the stranded native tooltip described above.

The inline-hint replacement is now live-verified in English and Portuguese:
normal and hovered text fit inside the card, clicking opens the exact 0.4.0
tag, the game remains running through browser focus loss and return, and the
Settings screen has no floating hint. These observations do not prove the
exact minimize-while-hovered sequence.

The earlier 31 mocked scenarios passed before the custom-event registration
limitation was modeled. The corrected first-registration-wins mock now passes
27 scenarios for the Settings router, including wrapped arguments, transition
states, overlapping covers, language/pending facts, and Home Hub exit.

The final native Settings gate passed in a Steam-launched session: the
`02:33:29` local event log recorded
`Settings input cover=true (router display state)`, and clicking the covered card's location in an empty
Settings gap produced no `LaunchURL`. Closing Settings recorded the cover
clearing at `02:35:48`; unhover restored the version line, and clicking the
visible card then logged the exact `v0.4.0` release URL at
`2026.09.05-05.36.43:005` UTC. The game remained responsive. Exact
minimize-while-hovered behavior remains unverified.

## Lesson

Give a passive overlay a bounded interactive child without disabling that
child at an ancestor. Bind external actions to the content actually shown,
and clear or disable the action when its validated destination cannot be
applied. Keep short hints in the same widget hierarchy when they must share
the game's visibility and lifetime; a native floating tooltip is a separate
surface that needs its own focus/lifecycle verification.
Model callback registration semantics in tests: successful registration calls
do not establish that multiple modules will receive the same named event.

## Related

- Canonical engine reference:
  [`widgets.md`](../engine/widgets.md#bounded-release-links-in-persistent-widgets).
- Feature: [`update-availability-notification`](../features/update-availability-notification.md).
- Prior learning: [`home-hub-visibility-requires-router-and-loading-state`](./home-hub-visibility-requires-router-and-loading-state.md).
- Source: `mod/OSPlus/scripts/update_notification.lua`,
  `data/localization/screens/update_notification.json`, and the external
  `OSPlusEditorBridgeLibrary.cpp` authoring helper.
- Pinned UE 5.1 source: `Components/SlateWrapperTypes.h`,
  `Components/Button.h`, and `Kismet/KismetSystemLibrary.h`
  (`LaunchURL(const FString&)` is Blueprint callable and returns `void`).
