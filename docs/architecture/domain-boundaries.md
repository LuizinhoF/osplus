# OSPlus domain boundaries

This is the missing layer between product docs and script-level architecture:
*what concept owns this data or behavior?*

Read this before adding Lua modules, JSON files, BP functions, or sidecar
messages for features that might be reused by more than one screen.

---

## Rule

Domain concepts outlive any one screen.

A screen is an adapter: it arranges controls, renders a subset of data, and
routes user actions back to the owning domain. It should not become the home
for data that another screen, in-match UI, the sidecar, or a future feature
will need.

Before adding a file/function/module, ask:

1. What real game/product concept does this represent?
2. Could the same concept appear somewhere else?
3. Is this screen-specific copy/layout state, or reusable domain data?
4. Who should be able to consume it without importing this screen module?

If the answer to question 2 is "yes", do not put it under a screen-owned module
or JSON file.

## Contributor-legible authoring

This is a decision heuristic, not a hard placement rule.

The goal is that a UE/Lua modder can predict where to edit something and
understand why it lives there. Prefer the authoring surface that matches the
artifact and the people likely to maintain it.

For asset-like game-facing content, the UE project is usually the least
surprising home: `Content/Mods/OSPlus/...`, cooked into `OSPlus.pak`.
This commonly includes:

- Widgets and widget subcomponents.
- Materials, textures, animated textures, sounds, VFX, and style assets.
- Blueprint helper classes and drag/drop operation classes.
- Data tables, data assets, or Blueprint-authored catalogs when the data is
  primarily consumed by Blueprint or authored by UE contributors.

Repo JSON/Lua can be the clearer home when the artifact is:

- Runtime data Lua must read directly, such as screen localization JSON.
- Curated metadata overlays that need reviewable text diffs or can be generated
  from game/UE assets.
- Operational code and integration logic that cannot live in Blueprint, such as
  file IPC, sidecar launch, native catalog reads, and equip calls.

For trust and contributor legibility, avoid surprising pipelines. This matters
more because OSPlus also ships a sidecar/relay path; contributors and players
should not have to reverse-engineer where content lives or what code is
network-facing. When placement is ambiguous, choose the least surprising home
and record the reason in the feature doc.

---

## Current boundaries

### Emotes

**Domain.** Emotes are account/game cosmetic content. They appear in:

- Customize -> Cosmetics -> Emote loadout.
- In-match reaction wheel / reaction modal.
- Future OSPlus profile, unlock, event, or reward surfaces.
- Future catalog/admin/editor tools.

**Reusable files/modules.**

| Path | Owner | Purpose |
|---|---|---|
| `mod/OSPlus/scripts/catalog.lua` | Native game catalog adapter | Reads live Omega Strikers catalog, ownership, equipped slots, and native equip APIs. No screen layout assumptions. |
| `mod/OSPlus/scripts/emote_metadata.lua` | OSPlus emote metadata overlay | Merges repo-owned metadata into native emote records: tags, descriptions, source, visual paths, search text. Reusable anywhere emotes render. |
| `data/emotes/catalog.json` | Emote domain data | Emote IDs, localized names/descriptions, tags, source, visual metadata. Not tied to one widget. |

Emote visual assets themselves belong in the UE project. If OSPlus adds custom
emotes, their textures, animated textures, materials, sounds, and preview
widgets should live under `/Game/Mods/OSPlus/Emotes/` or a shared UE asset
folder. The JSON catalog may reference those assets, but it should not carry the
asset content or become the only place a UE-focused contributor can understand
the emote.

**Screen-owned files/modules.**

| Path | Owner | Purpose |
|---|---|---|
| `mod/OSPlus/scripts/emote_loadout.lua` | Customize emote loadout screen | Mounts `WBP_OSPlusEmoteLoadout`, pushes view data to that widget, handles that widget's equip events. |
| `data/localization/screens/emote_loadout.json` | Emote loadout screen copy | Search hint, section labels, button labels, footer text for this one screen. |

**Anti-patterns.**

- Putting screen labels into `data/emotes/catalog.json`.
- Letting `emote_loadout.lua` become the generic emote service.
- Adding hardcoded category chips in BP when the tags belong to emote metadata.
- Creating separate static/animated emote UI branches when one emote visual path can represent both.

If another screen needs "the emote list", extract a reusable view-model module
such as `emote_view_model.lua`; do not import `emote_loadout.lua`.

### Localization

**Domain.** Locale detection and localized string lookup are global OSPlus
infrastructure.

**Reusable file.**

| Path | Purpose |
|---|---|
| `mod/OSPlus/scripts/localization.lua` | Reads the current game/engine text language, loads localization JSON, resolves locale fallback, keeps a short startup probe alive so saved culture can settle, hooks game/engine language setters, and notifies subscribers when language changes. |

**Data file convention.**

| File kind | Location | Purpose |
|---|---|---|
| Domain metadata localization | Domain JSON, e.g. `data/emotes/catalog.json` | Names/descriptions/tags for reusable entities. |
| Screen copy | `data/localization/screens/<screen>.json` | Labels and text specific to one screen. |
| Shared OSPlus UI copy | Future `data/localization/common.json` | Generic commands reused across screens, e.g. Save/Cancel/Equip, if they truly become shared. |

Do not move text into `common.json` merely because two screens currently use the
same English word. Share only when the product concept is genuinely the same.

### Screens

Screens own:

- Widget mounting/routing.
- Screen-specific BP bridge functions.
- Layout state, selected/hover state, local filters, scroll position.
- Screen copy.

Screens do not own:

- Native catalog reads/writes.
- Account identity.
- Cross-feature metadata.
- Relay protocol.
- Persistent domain state.

---

## Module placement checklist

Use this before adding or expanding a Lua module.

| If the new code... | Put it in... |
|---|---|
| Is authored game-facing content or a reusable visual asset | The UE project under `Content/Mods/OSPlus/...`. |
| Reads native Omega Strikers catalog/state | A domain adapter such as `catalog.lua`. |
| Enriches a reusable OSPlus entity | A domain metadata module such as `emote_metadata.lua`. |
| Mounts or talks to one cooked widget | That screen's module, e.g. `emote_loadout.lua`. |
| Resolves current locale or generic translated text | `localization.lua`. |
| Formats one screen's labels | A screen localization JSON file. |
| Owns sidecar/relay IPC | `ipc.lua`, sidecar, or server docs depending on direction. |

When a function seems to fit two rows, stop and name the boundary explicitly in
the feature doc before coding.

---

## Relationship to existing architecture docs

- `state-contract.md` answers: "Lua or BP owns this state?"
- `mod-scripts.md` answers: "Which Lua module owns this engine integration?"
- This doc answers: "Which product/domain concept owns this data or behavior?"

All three questions are required. Passing only the Lua/BP boundary is not enough
if the data is still filed under the wrong product concept.
