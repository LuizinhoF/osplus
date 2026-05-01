# UE4SS 3.0.1 — version pin, Lua API, and gotchas

The *"how do I write Lua against UE4SS 3.0.1 specifically, and
what bites you"* doc — third read for any agent touching mod
code. Distilled from [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md)
§"UE4SS Lua API — Key Functions" + §"Common Pitfalls" + cross-
linked to the version-sensitive learnings under
[`docs/learnings/`](../learnings/).

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md).
>
> **Stability:** UE4SS 3.0.1 is the pinned dev-environment
> version as of 2026-04-25. The Lua marshaling layer is the most
> patch-volatile surface OSPlus depends on; any UE4SS upgrade
> *requires* re-validating every fact below. Bump the version pin
> at [`overview.md` → "The engine pin"](./overview.md#the-engine-pin)
> in the same change as any UE4SS upgrade.

## TL;DR

- **UE4SS 3.0.1 is pinned.** Anchor every UE4SS docs/issues
  lookup to this version. Fixes landed in 3.1+ may not apply;
  2.x-era behavior may differ. See
  [§"The version pin and why it bites"](#the-version-pin-and-why-it-bites).
- **The Lua API surface that matters:** lifecycle hooks
  (`RegisterLoadMapPostHook`, `RegisterBeginPlayPostHook`,
  `NotifyOnNewObject`, `RegisterHook`, `RegisterKeyBind`),
  execution helpers (`ExecuteInGameThread`,
  `LoopInGameThreadWithDelay`), object lookup
  (`StaticFindObject`, `FindFirstOf`, `FindAllOf`, `LoadAsset`),
  class introspection (`GetClass`, `ForEachFunction`),
  `RegisterHook`, `FVector`/`FRotator` via UEHelpers.
- **Twelve common pitfalls** carried forward from the original KB
  (`pcall` everything, game thread, hook param wrapping,
  Blueprint events vs native, Lua 5.4 quirks, etc.) — see
  [§"Common pitfalls"](#common-pitfalls).
- **Five UE4SS-3.0.1-specific known bugs** with documented
  workarounds in `docs/learnings/`:
  out-param marshaling shape, multicast delegate `Add` no-op,
  cold-start hook install pattern, `ExecuteInGameThread` +
  `UnregisterHook` corruption, and BP-function-name resolution
  by display-name-without-spaces. See
  [§"UE4SS 3.0.1 known bugs"](#ue4ss-301-known-bugs).

## The version pin and why it bites

**UE4SS 3.0.1** is the dev-environment version as of 2026-04-25.

The Lua marshaling layer (UFunction call shapes, out-param
handling, multicast-delegate binding, hook callback registry
internals) is the part of UE4SS most likely to change between
releases — and that's exactly the surface OSPlus depends on most.

**Sources of truth, in decreasing trust:**

1. **Empirical:** a working call in `mod/OSPlus/scripts/`
   confirms the shape on this build. Always preferred. Production-
   shipping code is the most reliable reference.
2. **UE4SS GitHub issues** with explicit "repros on 3.0.1" or
   with no fix-version newer than 3.0.1 in the resolution. Also
   check the [3.0.1 release notes](https://github.com/UE4SS-RE/RE-UE4SS/releases)
   and any 3.1.x changelog entries describing fixes that *don't*
   apply to us.
3. **The official [UE4SS docs site](https://docs.ue4ss.com/)** —
   note the docs lag releases; cross-check with issues, and
   confirm the documented behavior isn't gated on a newer
   version.

**When upgrading UE4SS:**

- Bump the version pin line at
  [`overview.md` → "The engine pin"](./overview.md#the-engine-pin).
- Re-run any version-sensitive probes.
- Revisit `docs/learnings/ue4ss-*.md` — each carries a "tested
  under" note; verify still applies.
- Specifically re-test the five known bugs in
  [§"UE4SS 3.0.1 known bugs"](#ue4ss-301-known-bugs) — some may
  be fixed upstream; others may be replaced by new ones.

## The Lua API surface

### Lifecycle hooks

| Function | When it fires | Notes |
|---|---|---|
| `RegisterLoadMapPostHook(cb)` | After any map loads | Fires for every map transition (lobby ↔ arena, arena ↔ post-match). |
| `RegisterBeginPlayPostHook(cb)` | After any actor's `BeginPlay` | Fires per-actor; used carefully, can be high-cadence. |
| `NotifyOnNewObject(className, cb)` | When any instance of `className` is constructed | Class name short form, no `_C` suffix typically. Use for catching constructor moments (e.g., first `PMPlayerPublicProfile` = local player — see [`docs/learnings/os-runtime-data-model.md`](../learnings/os-runtime-data-model.md)). |
| `RegisterHook(funcPath, cb)` | Before/after a UFunction executes | The workhorse. See [§"RegisterHook"](#registerhook) below. |
| `RegisterKeyBind(keyCode, cb)` | On key press (game must be focused) | Fires on the input thread, not the game thread — wrap engine calls in `ExecuteInGameThread`. |

### Execution helpers

| Function | Behavior | Notes |
|---|---|---|
| `ExecuteInGameThread(cb)` | Run code on game thread | Required for UObject operations from off-thread contexts (e.g., from keybind callbacks). **DO NOT** wrap UE4SS-internal callback registry mutations in this — see [§"UE4SS 3.0.1 known bugs"](#5-executeingamethread--callback-registry-corruption). |
| `ExecuteWithDelay(ms, cb)` | Run code after delay (on game thread) | One-shot delayed execution. |
| `LoopInGameThreadWithDelay(ms, cb)` | Repeating loop on game thread | **Preferred** repeating-loop primitive. |
| `LoopAsync(ms, cb)` | Repeating loop | **DEPRECATED** — use `LoopInGameThreadWithDelay`. |

### Object lookup

| Function | Returns | Notes |
|---|---|---|
| `StaticFindObject(path)` | Single UObject by full path | Most precise; requires the canonical engine path. |
| `FindFirstOf(className)` | First instance of `className` | Short-name only (no path, no `_C` suffix is typical). Cold-start race: returns nil before the instance is constructed. |
| `FindAllOf(className)` | Table of all instances | Same short-name rule. May return many — see [`docs/learnings/os-runtime-data-model.md`](../learnings/os-runtime-data-model.md) for why "first non-empty" is wrong for identity-bootstrap. |
| `LoadAsset(path)` | Load an asset | **Must run on the game thread.** Use inside `ExecuteInGameThread` if calling from elsewhere. |

### Class introspection

```lua
local cls = obj:GetClass()
cls:ForEachFunction(function(func)
    local name = func:GetFullName()
    local flags = func:GetFunctionFlags()
end)
local super = cls:GetSuperStruct()  -- parent class
```

Used during reverse-engineering probes. For *production* code,
prefer the static type stubs at
`Binaries\Win64\Mods\shared\types\` — see
[`docs/learnings/ue4ss-type-stubs-as-canonical-source.md`](../learnings/ue4ss-type-stubs-as-canonical-source.md).
**Probing in-game is for confirming runtime values; static dumps
are for discovering schemas.**

### `RegisterHook`

```lua
RegisterHook("/Script/Engine.HUD:ReceiveDrawHUD", function(Context, SizeX, SizeY)
    local hud = Context:get()
end)

RegisterHook("/Game/MyBP.MyBP_C:MyFunc", function(Context)
    local self = Context:get()
end)
```

**Path prefix changes the hook timing:**

- `/Script/...` prefix → **pre-hook** (fires BEFORE the function
  body runs).
- Non-`/Script/` prefix (typically `/Game/...`) → **post-hook**
  (fires AFTER the function body returns).

Hook callback parameters are wrapped in `RemoteUnrealParam` — call
`:get()` to unwrap.

**Cold-start gotcha:** hooks for known UFunction paths can be
registered at module load (UFunctions live in the class table
from package load — no instance, no defer needed). Hooks for
discovery-time-known UFunctions need a two-phase install via
`NotifyOnNewObject`. Full pattern in
[`docs/learnings/ue4ss-cold-start-hook-install-pattern.md`](../learnings/ue4ss-cold-start-hook-install-pattern.md).

### `FVector` / `FRotator` creation

```lua
local UEHelpers = require("UEHelpers")
local kml = UEHelpers.GetKismetMathLibrary()
local vec = kml:MakeVector(x, y, z)
local rot = kml:MakeRotator(roll, pitch, yaw)
```

`UEHelpers` is the shipped helper module from UE4SS itself.
`KismetMathLibrary` is the standard UE math library, available
because the engine includes it.

## Common pitfalls

Twelve carried forward from the original KB's "Common Pitfalls"
section. These bite often enough to be worth a single-file
reference:

1. **Mod not updating after Lua edit.** Always copy ALL `.lua`
   files to the game's `Mods\OSPlus\scripts\` folder after
   editing. The source copy in the project repo is NOT what the
   game reads. Use [`deploy.ps1`](../../deploy.ps1).

2. **"Reload All Mods" doesn't reload paks.** Reloading mods
   re-runs Lua scripts but does NOT reload `.pak` files. After
   cooking + paking, a full game restart is required. See
   [`setup.md` → "Pak packaging"](./setup.md#pak-packaging).

3. **Keybind conflicts.** Check that your keybind doesn't
   conflict with the game's controls. The game uses **G** for
   its own emote wheel.

4. **`pcall` everything UObject-touching.** UE4SS Lua calls to
   engine functions can crash if objects are invalid. Always
   wrap in `pcall()` and check `IsValid()`.

5. **Game thread requirement.** Most UObject operations must run
   on the game thread. Keybind callbacks run on the input
   thread — wrap engine calls in `ExecuteInGameThread()`. **But
   see the inverse rule** in
   [§"UE4SS 3.0.1 known bugs"](#5-executeingamethread--callback-registry-corruption):
   never wrap UE4SS-internal callback-registry mutations in
   `ExecuteInGameThread`.

6. **Hook parameters are wrapped.** Parameters in `RegisterHook`
   callbacks are `RemoteUnrealParam` — call `:get()` to unwrap.

7. **Blueprint events vs native functions.** `RegisterHook` on a
   `BlueprintImplementableEvent` (like `ReceiveDrawHUD`,
   `ReceiveTick`) only fires if the Blueprint actually
   implements the event. Just because the UFunction *exists*
   doesn't mean it's *called*. The OS HUD's
   `ReceiveDrawHUD` is the canonical example —
   see [`overview.md` → "UMG-only HUD"](./overview.md#umg-only-hud).

8. **Lua 5.4+ semantics.** UE4SS uses modern Lua. `math.atan2`
   does NOT exist — use `math.atan(y, x)` (two-argument form).
   Integer division uses `//`, not `math.floor(a/b)`.

9. **Widget creation pattern.**
   `WidgetBlueprintLibrary::Create` expects 4 params
   (`WorldContext`, `WidgetClass`, `OwningPlayer`, `WidgetName`).
   Use `StaticConstructObject(widgetClass, playerController, FName("name"))`
   instead — simpler and proven working. Detail in
   [`widgets.md` → "Widget instantiation"](./widgets.md#widget-instantiation).

10. **Lua local-function ordering.** If function A calls
    function B, and both are `local function`, B must be defined
    before A — or forward-declare B with `local B` at the top
    and assign later with `B = function(...)`. Otherwise A
    captures a nil upvalue. Less obvious cousin: see
    [`docs/learnings/lua-vararg-in-pcall-closure.md`](../learnings/lua-vararg-in-pcall-closure.md)
    for vararg + pcall + closure crashes.

11. **UE4SS has no networking.** No HTTP, WebSocket, or socket
    support in Lua. Use file-based IPC (`io.open`) with an
    external sidecar process for networking. Architecture in
    [`docs/architecture/`](../architecture/).

12. **`PlaySound2D` requires all 8 params.**
    `UGameplayStatics:PlaySound2D(world, sound, vol, pitch, startTime, nil, nil, true)` —
    UE4SS does not support default parameter values, all must be
    passed explicitly.

## UE4SS 3.0.1 known bugs

Five UE4SS-3.0.1-specific behaviors that have bitten OSPlus
hard enough to earn dedicated learnings. Each links to its
canonical source.

### 1. Out-param marshaling shape

**Symptom:** `(Bool out, X out)` UFunction calls fail with
diagnostic-but-misleading error messages (`"no table on the
stack"` and similar) on naive call shapes. Earlier conclusion:
*"these UFunctions are not callable from Lua at all on this
build."*

**Reality:** the canonical UE4SS 3.0.1 multi-out-param call
shape is `inst:Fn({}, {})` — pass one empty Lua table per
declared out-param. UE4SS writes results into
`bucket.<ParamName>` for base-type params, and on 3.0.1
specifically (per [Issue #971](https://github.com/UE4SS-RE/RE-UE4SS/issues/971))
collapses multiple base-type out-params into the *first* bucket.
You still must pass a bucket per declared param to satisfy the
marshaler's argument count.

**Canonical reference:**
[`docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md`](../learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md)
(supersedes the older
[`ue4ss-outparam-marshaling-failure.md`](../learnings/ue4ss-outparam-marshaling-failure.md)
at the call-shape layer; that older entry's per-shape error
catalog and discipline-lessons remain valid).

### 2. Multicast delegate `Add` is a silent no-op

**Symptom:** `MulticastInlineDelegateProperty:Add(uobject, fname)`
returns `true`, but `GetBindings()` stays empty across all 6
callable methods + every bind-shape variation tried.
`Broadcast()` fires nothing. Likely root cause: vtable-offset
mismatch in UE4SS's binary parser for this game's binary.

**Workaround:** `RegisterHook` on the *originating* engine
UFunction (the one that triggers the delegate fire). Maintainer-
recommended per [UE4SS Issue #455](https://github.com/UE4SS-RE/RE-UE4SS/issues/455).

**Canonical reference:**
[`docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md`](../learnings/ue4ss-multicast-delegate-add-silent-noop.md);
related crash details in
[`ue4ss-lua-multicast-delegate-binding.md`](../learnings/ue4ss-lua-multicast-delegate-binding.md).

### 3. Cold-start hook install patterns

**Two patterns, picked by use case:**

- **Pattern A (known UFunction path):** direct `RegisterHook` at
  module load. UFunctions live in the class table from package
  load — no instance, no defer, no race. **Use this when
  shipping production code** for a known-class hook (e.g., the
  identity hook on `PMIdentitySubsystem:GetIdentityState`).
- **Pattern B (discovery probe needing class enumeration):**
  two-phase install — `FindFirstOf` + `NotifyOnNewObject`,
  then `RegisterHook` from inside the new-object callback.
  Required because instance is needed for `cls:ForEachFunction`
  enumeration. **Use this for RE probes,** not production code.

**Failure modes documented:**

- Keypress-driven install for events that fire pre-interactive
  ("0 fires across 79 hooks").
- Copy-pasting Pattern-B install machinery into Pattern-A
  production code; the `ExecuteInGameThread` defer adds ~14ms
  post-construction and loses the race against engine-internal
  post-construction probes.

**Canonical reference:**
[`docs/learnings/ue4ss-cold-start-hook-install-pattern.md`](../learnings/ue4ss-cold-start-hook-install-pattern.md).

### 4. BP function name resolution: display name without spaces

**Symptom:** `widget:OpenInput()` returns `nullptr`, when the BP
function is clearly defined and named "Open Input" in the editor.

**Cause:** UE4SS Lua resolves Blueprint functions by their
*internal name*, which matches the editor display name **with
spaces removed**. A BP function displayed as "Open Input" must
be called as `widget:OpenInput()` from Lua. A mismatch wraps a
null UFunction and `:Call()`-style usage crashes.

(This isn't documented as a learning entry yet — it's a small
fact carried forward from the KB Editor-Text section. Worth
folding into a learning if it bites again.)

### 5. `ExecuteInGameThread` + callback-registry corruption

**Symptom:** game crashes deterministically ~88-93 minutes after
introducing a Lua pattern that wraps `UnregisterHook` (or
similar UE4SS-internal-registry-mutating call) inside an
`ExecuteInGameThread(...)` block. The crash signature is
`WRITE @ NULL` inside `UE4SS.dll` at the same RVA across
multiple sessions.

**Cause:** UE4SS processes deferred actions every engine tick
by iterating `m_engine_tick_actions` via `std::erase_if`. If a
callback inside that iteration mutates a UE4SS-internal callback
registry that participates in the iteration, mid-iteration
reallocation corrupts the in-progress `memcpy`'s pointers. The
corruption surfaces *later* when something traverses the
broken state and dereferences NULL — minutes or hours afterward.
Documented upstream as
[UE4SS Issue #1180](https://github.com/UE4SS-RE/RE-UE4SS/issues/1180).

**Rule:** don't wrap any of these in `ExecuteInGameThread`:

- `UnregisterHook` / `RegisterHook`
- `RegisterCustomEvent` / `UnregisterCustomEvent`
- `NotifyOnNewObject` listener install / teardown

**Stronger transferable rule:** prefer **"register once, never
unregister"** for hooks whose body is cheap. The cost of leaving
a hook registered is one Lua early-return per fire; the cost of
unregistering is a probabilistic latent crash 60-90 minutes
later. The trade is asymmetric — keep the hook.

**Canonical reference:**
[`docs/learnings/ue4ss-execute-in-game-thread-unregister-hook-corruption.md`](../learnings/ue4ss-execute-in-game-thread-unregister-hook-corruption.md).

## Cross-references

- **Engine + UE4SS version pin:** [`overview.md` → "The engine pin"](./overview.md#the-engine-pin)
- **Where to put your Lua so the game reads it:** [`setup.md` → "Game install layout"](./setup.md#game-install-layout-players-machine)
- **What the cooked content does at runtime:** [`widgets.md`](./widgets.md)
- **OSPlus Lua module split (which file does what):** [`docs/architecture/mod-scripts.md`](../architecture/mod-scripts.md)
- **Lua-side conventions enforced by `.cursor/rules/lua-conventions.mdc`:** [`.cursor/rules/lua-conventions.mdc`](../../.cursor/rules/lua-conventions.mdc) (glob-attached on Lua files)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)
- **All UE4SS-related learnings:** [`docs/learnings/`](../learnings/) — search prefix `ue4ss-`

## Open questions

- **Do `PMPlayerModel:GetCached*V1` UFunctions work with the
  `({}, {})` shape?** They were never re-tested with the
  canonical UE4SS 3.0.1 multi-out-param call shape after the
  v33→v36 identity work. May now be reachable, may still fail
  for an orthogonal `PMPlayerModel`-specific reason. Probe
  before relying. Tracking note in
  [`docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md`](../learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md).
- **Whether UE4SS 3.1+ fixes any of the known bugs above.** The
  team has not done a UE4SS upgrade pass; before any future
  upgrade, re-check each of the five known bugs against the
  fixed-version metadata in upstream issues.
- **Full enumeration of UE4SS Lua API methods on this build.**
  The auto-dumped type stubs at
  `Binaries\Win64\Mods\shared\types\` contain the runtime
  schema; whether they cover the UE4SS Lua API surface itself is
  not documented. Worth checking before assuming a method
  doesn't exist.
