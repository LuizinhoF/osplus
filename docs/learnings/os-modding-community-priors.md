# OS modding community priors — what's been done, where to look

| Field | Value |
|---|---|
| Date | 2026-05-02 |
| Area | re |
| Tags | community, modding, prior-art, gamebanana, discord, ui-mods |
| Status | `confirmed` for the inventory + Demon Drive analysis; `working-theory` for the broader claim about technique-availability (see *Lesson — what this is NOT yet*). |

## Symptom

OSPlus Stage-3 work was being done from the assumption that *"OS internal code is entirely unexplored except for what we're doing."* That framing led to brute-force RE on questions that may already have community-known answers (e.g. *"can we replace a sub-tab widget at runtime"* → we hit the subobject-embedding wall in `WBP_Panel_StrikerCosmetics`, but a community mod that *adds* a removed menu element back must have solved a related problem). The wasted-effort failure mode is silent: bad architectural choices (R1 vs R2 vs R3) get made with incomplete priors, and the agent confidently recommends the wrong one.

## Root cause

OSPlus docs (`AGENTS.md`, `docs/engine/`, `docs/learnings/`) catalogued the *engine* perspective extensively but had **no inventory** of the OS modding community itself — what's been built, who's built it, where the conversation happens. So every session started from "alone with the engine binary" rather than "alone with the engine binary *and* an existing modding scene's accumulated knowledge."

The community is real and active enough to warrant a prior-art lookup before any RE spike. Concrete evidence: at least one structural-UI mod ([Demon Drive Menu Restoration](https://gamebanana.com/mods/615651), 53 MB pak) restores a UI element Odyssey *removed*, which means a modder solved widget-injection-into-cooked-asset for a non-trivial UI surface.

## Fix — recorded inventory of OS modding-community resources

These are the resources OSPlus agents should consult **before** treating a UI / asset / widget question as unexplored territory.

### Discord

- **"Opening the Prometheus"** — modding-focused Omega Strikers Discord. Separate from the official OS Discord. Named after the engine internal codename (`/Game/Prometheus/`), confirming the membership knows OS internals at the cooked-content level. *Treat this as the canonical place to ask "has anyone done X?" before sinking RE time.* Invite link not recorded here — ask the user when needed.

### GameBanana

- **[OS UI mod category](https://gamebanana.com/mods/cats/24439)** — small (single-digit count of UI mods), but two of them are structural (not retexture):
  - **[Demon Drive Menu Restoration](https://gamebanana.com/mods/615651)** — *initially looked like the highest-value prior art, but pak inspection contradicts that read.* The 53 MB pak (`OmegaStrikers-Windows_OldMenu.pak`, no `_P` suffix) mounts under `../../../OmegaStrikers/Content/Prometheus/Maps/` and contains **211 files, zero of them widgets**. It's `EnvironmentArt/Lobby/{Default,LobbyMain,LobbyMain_Updated,LobbyMusic}/` (textures, meshes, materials, BP visual containers) plus `MainMenuMap/MainMenuMap.{umap,uexp}` — i.e. the *visual style* of the home hub / main menu, not the *widget tree* of any screen. The "Menu Restoration" naming is about restoring the older lobby look from the Demon Drive era of the game; the mod is mis-categorized under "UI" on GameBanana. Inspection output kept at `docs/research/other-mods/demon-drive-list.txt`.
    - **Negative-result corollary, valuable**: the most popular UI-category OS mod does *not* solve widget-tree replacement. If a widely-known community technique for that existed, it would have been used here. The absence is a real signal — it doesn't prove the technique doesn't exist, but it does mean the bar for finding it is higher than "browse the obvious mod and copy its approach."
    - **Positive-result corollary**: map-level replacement (full `.umap` swap) and static-asset replacement (textures, meshes, materials, visual BPs) at native paths *do* work without `_P` suffix on OS — likely via alphabetical-pak-order priority on the OS install (`OmegaStrikers-Windows_OldMenu.pak` sorts after `OmegaStrikers-WindowsNoEditor.pak`). This contradicts our [recent assumption](customization-screen-widgetswitcher-architecture.md) that `_P` is mandatory; `_P` is *one* priority mechanism, alphabetical-after is another. The OSPlus mod ships as `OSPlus.pak` which doesn't naturally sort after the base `OmegaStrikers-WindowsNoEditor.pak` (`O` < `O` then `S` < `W`), which is why our earlier `_P` attempt was needed for path collision.
    - **Path taxonomy**: `/Game/Prometheus/Maps/EnvironmentArt/Lobby/{...}` and `/Game/Prometheus/Maps/MainMenuMap/MainMenuMap.umap` are real OS asset paths. The `Maps/` parent is non-obvious — most game packages put `EnvironmentArt/` directly under `/Game/`. Cascade update queued for `docs/engine/` (asset path tree).
  - **[Under Night in Birth Character Select + Pre Match](https://gamebanana.com/mods/453337)** — *also not what the title suggests.* Ships two paks, both mounting at `../../../OmegaStrikers/Content/WwiseAudio/Media/`, each containing a single `.wem` file: `375575394.wem` (22 MB, character-select music) and `128186285.wem` (1.7 MB, pre-match music). It's a **pure Wwise audio swap** — "Character Select" / "Pre Match" refer to the in-game *phases when the music plays*, not to UI screens being replaced. Zero widgets, zero textures, zero meshes. Useful corollary: Wwise audio replacement on OS works by matching the existing numeric `.wem` ID under `/Game/WwiseAudio/Media/` — drop a same-name `.wem` in a pak, the engine resolves to ours. Inspection output kept at `docs/research/other-mods/OmegaStrikers-Windows_gathersundernightCharacterSelect-list.txt` and `OmegaStrikers-Windows_touchngoPreMatch-list.txt`.
- **[Change Goal to "SKILL ISSUE"](https://gamebanana.com/mods/466685)** and **[UwUified Text](https://gamebanana.com/mods/460933)** — text-replacement mods. Likely localization-table or font-style level. Useful as a reference for *text-data* replacement; less directly relevant to widget-structure work.

### Code repos (network-side, not UI-mod source)

- `lukimana/strikr` — Strikr (defunct stat tracker). Network-side reverse engineering of the OS API.
- `ckhawks/omega-strikers-tracker` — match-history tracker. Network-side.
- `Chrisr0/RE-UE4SS` — Stellar Blade fork of UE4SS. Not OS-specific, but a reference for non-English UE5 modding workflows that share the UE4SS toolchain with us.

No public repo containing OS-specific UE4SS Lua mod source has been found via web search. The Discord is likely where mod source / techniques are shared, not GitHub.

### Asset-extraction tooling

- **umodel** (gildor.org) — confirmed working on OS 5.1 cooked content for meshes/textures/animations (not materials). [Forum thread](https://www.gildor.org/smf/index.php?topic=8342.0). Already in our toolchain via UAssetGUI for `.uasset` parsing; umodel is the alternative for batch mesh/texture export when needed.

## Lesson

**Before committing to an architectural direction that depends on an unanswered RE question, run the modding-community-priors check.** Concretely, for any *"is X possible / how is X done in OS?"* question that's about cooked assets, widgets, or runtime hooks (not network protocol):

1. **Search GameBanana** for OS mods in the category closest to the question (UI / Skins / Audio / Other). Read the descriptions; if a mod's *behavior* implies it solved your question, prioritize downloading and statically inspecting its pak (UnrealPak `-List`, then `parse_uasset.ps1` on the most relevant uasset). The pak's *which assets it replaces and which it ships fresh* is a strong signal for technique. **And** — sharply learned this round — *don't trust the GameBanana category as a proxy for technique class.* "UI" on GameBanana includes map-level visual mods that don't touch widgets at all. A 30-second `UnrealPak -List` cuts through that.
2. **Ask in "Opening the Prometheus"** if the static analysis is inconclusive and the question is well-formed enough for a one-line ask.
3. **Only then** spike a custom RE experiment — and frame it as "the community didn't seem to have solved this" rather than "this is unexplored."

Implementation note for OSPlus features: this lookup is now an explicit step in the `discover` skill (Stage-3 Pass-1 / Pass-2). Before designing a Pass-2 probe in feasibility space the community-priors check should run. *(This learning entry is additive; the cascade update to `discover/SKILL.md` is queued under the next session's "apply correct-knowledge skill" step.)*

The architectural lesson, restated: **a complete absence of community prior art is itself information** — and in this round, the *most popular* UI-category mod turning out to be a map-replacement (not a widget-tree replacement) is a strong negative-prior signal. It doesn't prove widget-tree replacement is impossible; it just means the cheapest "go copy what worked" path isn't there.

### Strengthened picture after UNIB inspection

All four GameBanana "UI" mods now have a known or inferred shape, and the negative-prior signal got stronger:

| Mod | Shape | Source |
|---|---|---|
| Demon Drive Menu Restoration | Map + static-visual-asset replacement under `/Game/Prometheus/Maps/`. 211 files, zero widgets. | Static inspection. |
| Under Night in Birth Character Select + Pre Match | Pure Wwise audio swap under `/Game/WwiseAudio/Media/` (one `.wem` per pak). Zero widgets. | Static inspection. |
| Change Goal to "SKILL ISSUE" | Text replacement (likely localization-table or font level). | Behavioral inference; not statically inspected. |
| UwUified Text | Text replacement (same inference). | Behavioral inference; not statically inspected. |

**Not a single confirmed widget-tree replacement in the entire OS UI mod category on GameBanana.** Two of four are confirmed widget-free via static inspection; the other two are scoped narrowly enough that widget-tree replacement is unlikely to be how they work.

### What this is NOT yet

The static-evidence picture is now strong but not closed. One open move:

- **The "Opening the Prometheus" Discord** has not been queried. A single post asking "has anyone done widget-level replacement (replacing a `WBP_*` that's embedded in a parent's `WidgetTree`) — or is the working pattern Lua injection + side-loaded widgets?" would close the question with a definitive yes/no faster than any further static analysis. Even a "no" with no explanation would lock in R2 as the safer bet; a "yes, here's how" would re-open the R1 path with a known-working technique to copy.

The two text-replacement mods (Skill Issue, UwUified Text) are *not* worth inspecting before the Discord query — text replacement is a different technique class that doesn't transfer to widget-tree replacement either way.

## Related

- Files:
  - `docs/research/other-mods/omegastrikers-windows_oldmenu.zip` — Demon Drive Menu Restoration pak, queued for inspection.
  - `docs/learnings/customization-screen-widgetswitcher-architecture.md` — the immediate-prior probe that *should* have started with this priors check.
  - `docs/decisions/0004-emote-loadout-as-osplus-layer.md` — ADR currently committed to a path the priors check might re-frame.
- Upstream sources:
  - <https://gamebanana.com/mods/cats/24439> — OS UI mods category.
  - <https://gamebanana.com/mods/615651> — Demon Drive Menu Restoration.
  - <https://www.gildor.org/smf/index.php?topic=8342.0> — umodel/OS 5.1 thread.
- Cross-links into existing docs (queued cascade per `correct-knowledge` skill):
  - `.cursor/skills/discover/SKILL.md` — add a Pass-1 step "community-priors check" before custom RE.
  - `AGENTS.md` "Pre-work reading" — add this entry as a recommended skim alongside `docs/learnings/`.
