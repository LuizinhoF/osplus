# UE MCP Widget Blueprint Gotchas

| Field | Value |
|---|---|
| Date | 2026-05-23 |
| Area | ue-editor |
| Tags | `ue-mcp, widget-blueprint, umg, node-graph, python, mcp-server` |
| Status | `confirmed` |

## Symptom

UE widget work through the lightweight MCP server repeatedly stalled on
tool/API mismatches rather than on the actual UI problem:

- `manage_blueprint.set_pin_default_value` silently did the wrong thing when
  called with the intuitive key `defaultValue`.
- Python `WidgetBlueprint.WidgetTree` was protected, and the loaded
  `WidgetTree` object did not expose `construct_widget`.
- Unreal Python enum names were not the C++-looking names first guessed by
  the agent (`HALIGN_FILL`), so layout scripts failed partway through
  reparenting.
- `manage_blueprint.create_node` created invalid dynamic-cast nodes when called
  with `nodeType: "K2Node_DynamicCast"`.
- The Node REPL kernel persists bindings between calls, so ordinary names like
  `results` can collide with earlier snippets.

These failures made simple BP edits look more mysterious than they were.

## Root cause

The MCP server exposes a thin, partly-stubbed UE 5.1.0 bridge. It is usable,
but its argument names and Python surface are not always the same as the
natural Unreal/Python names or the schema names an agent would infer.

The editor asset surface also has two different access patterns:

1. MCP graph tools for nodes and pins.
2. Unreal Python object-path access for widget-tree subobjects.

Mixing those without probing the exact callable shape wastes iterations.

## Fix

Use this checklist before and during UE MCP widget work:

1. Keep reusable MCP helpers in the Node REPL, but wrap scratch code in `{ ... }`
   blocks or use unique names. The REPL is persistent.
2. For graph pin defaults, call:

   ```js
   await ueTool4("manage_blueprint", {
     action: "set_pin_default_value",
     blueprintPath,
     graphName,
     nodeId,
     pinName,
     value: "0"
   })
   ```

   The working key is `value`, not `defaultValue`.

3. Verify important graph edits with `get_node_details` before compiling. Do
   not trust a successful setter call alone when a pin value is load-bearing.
4. Load widget-tree subobjects by full object path when normal properties are
   protected:

   ```py
   unreal.load_object(
       None,
       "/Game/Mods/OSPlus/UI/WBP.WBP:WidgetTree.WidgetName"
   )
   ```

5. The loaded `:WidgetTree` object is generic enough that
   `tree.construct_widget(...)` may not exist in this MCP/Python environment.
   To create a new widget under the tree, use:

   ```py
   overlay = unreal.new_object(unreal.Overlay, outer=tree, name="MyOverlay")
   ```

6. Unreal Python alignment enum names in this environment are:

   - `unreal.HorizontalAlignment.H_ALIGN_FILL`
   - `unreal.HorizontalAlignment.H_ALIGN_RIGHT`
   - `unreal.VerticalAlignment.V_ALIGN_FILL`
   - `unreal.VerticalAlignment.V_ALIGN_BOTTOM`

   Probe with `dir(unreal.HorizontalAlignment)` / `dir(unreal.VerticalAlignment)`
   before guessing.

7. Reparent UMG widgets defensively:

   ```py
   child.remove_from_parent()
   parent.clear_children()
   slot = parent.add_child_to_overlay(child)
   slot.set_padding(unreal.Margin(0, 0, 18, 60))
   ```

   Then inspect the resulting parent/slot/children state by loading the same
   object paths and printing `get_children_count()`, `get_child_at(i)`,
   `get_content()`, and `widget.slot.get_class().get_name()`.

   When an existing designer widget was not marked `Is Variable`, the graph
   tools could not create a variable-get node for it. For narrow runtime edits,
   prefer either marking the widget as a variable in UE, or contain a short
   parent-walk inside one helper function starting from a nearby bound child
   that is already exposed. Example from `WBP_OSPlusEmoteLoadout`: the footer
   panel is reached from `OSPlusSelectedInfoIcon -> GetParent()` five times in
   `OSPlus_SetFooterVisible(...)`, rather than scattering that fragile lookup
   across multiple graphs.

8. Compile through MCP and save explicitly:

   ```js
   await ueTool4("manage_blueprint", {
     action: "compile",
     blueprintPath,
     saveAfterCompile: true,
     timeoutMs: 60000
   })
   await ueTool4("control_editor", { action: "save_all" })
   ```

   `save_all` may report `0` saved if the compile already saved the package.

9. Do not try to replace a dispatcher broadcast with a direct call to the
   generated `__DelegateSignature` function. Unreal compiles that as:
   `delegates cannot be called directly`. The generic MCP `create_node` path
   can create a `K2Node_CallDelegate`, but it does not populate the protected
   delegate reference, so the node comes out as `Call None`. Use an existing
   real dispatcher node, create the bound/dispatcher node in the editor, or
   solve the interaction at the widget event/property level instead.

   Confirmed again on the emote slot-picker popover: `manage_blueprint` can add
   ordinary custom events with parameters, but it cannot create a new
   parameterized Blueprint event dispatcher such as `OnSlotChosen(SlotIndex)`.
   Its `add_variable` path does not expose `PC_MCDelegate`, and `add_event`
   only supports custom events or parent-class override events. The compiled
   bridge also does not expose a real `Button.OnClicked` graph binding path;
   the widget-authoring `bind_on_clicked` source path only returns instructions
   to bind manually in the Designer. For a reusable popover that owns mini-card
   clicks, either create the dispatcher/bindings manually in UE or extend the
   MCP bridge first. Do not fake this by layering hit-testable hover buttons
   over a parent-owned geometry hit test: the buttons consume the click before
   the loadout can map the selected slot.

10. For dynamic casts, use the MCP's special node type:

   ```js
   await ueTool4("manage_blueprint", {
     action: "create_node",
     blueprintPath,
     graphName,
     nodeType: "Cast",
     targetClass: "Image"
   })
   ```

   Calling the fallback with `nodeType: "K2Node_DynamicCast"` creates a node,
   but its target class is unset and it appears in the graph as an invalid cast.
   Verify the cast with `get_node_details`; a valid node should read like
   `Cast To Image` / `Projetar para Image` and expose an `As...` output pin.

11. A widget blueprint can retain an invalid empty graph after failed MCP graph
    creation. Symptom: compile fails even though the visible graph looks fine,
    and `manage_blueprint.get` lists a bogus function/graph such as `None`.
    Remove the graph inside UE Python rather than hand-editing the asset:

   ```py
   import unreal

   bp = unreal.load_object(
       None,
       "/Game/Mods/OSPlus/UI/WBP_OSPlusEmoteTile.WBP_OSPlusEmoteTile"
   )
   for graph in list(bp.function_graphs):
       if graph.get_name() == "None":
           unreal.BlueprintEditorLibrary.remove_graph(bp, graph)
   unreal.BlueprintEditorLibrary.compile_blueprint(bp)
   unreal.EditorAssetLibrary.save_loaded_asset(bp)
   ```

12. The underlying UE bridge may register `manage_widget_authoring` even when
    the MCP server's `tools/list` does not expose it as a callable MCP tool.
    If the editor is running the bridge on `ws://127.0.0.1:8090`, call it
    directly with the bridge handshake:

   ```json
   {"type":"bridge_hello"}
   ```

   Then send:

   ```json
   {
     "type": "automation_request",
     "requestId": "codex-1",
     "action": "manage_widget_authoring",
     "payload": {
       "subAction": "add_overlay",
       "widgetPath": "/Game/Mods/OSPlus/UI/WBP_OSPlusSlotPickerPopover",
       "slotName": "OSPlusSlotPickerRoot"
     }
   }
   ```

   This path successfully created and compiled the
   `WBP_OSPlusSlotPickerPopover` scaffold after `system_control.add_widget_child`
   returned `NOT_AVAILABLE`.

13. A UMG widget subobject must be marked **Is Variable** before MCP graph
    tools can create a `VariableGet` node for it. UE Python can load protected
    subobjects by path, but it cannot read or write the protected
    `bIsVariable` flag through `get_editor_property` / `set_editor_property`.
    Prefer setting the flag in the editor UI when practical. If automation is
    required on UE 5.1, prove the `UWidget` flag byte first by toggling the
    public enabled state on a throwaway loaded widget, compare the changed byte
    to an already-variable widget of the same class, set only the variable bit,
    then compile/save the Blueprint. In this project, the UE 5.1 `UWidget`
    bitfield byte was found by toggling `set_is_enabled(false)` and seeing byte
    offset `257` change from `36` to `32`; an already-variable `HorizontalBox`
    at the same offset had value `37`, so setting bit `0x01` marked
    `OSPlusSlotPickerRow` as variable and allowed a clean
    `VariableGet(OSPlusSlotPickerRow)` node. Treat this as an editor-automation
    escape hatch, not shipped runtime logic.

14. Do not rebuild the MCP bridge by targeting `UnrealEditor` directly from
    the source-built UE tree unless you have first proved the exact build
    scope. On this machine, both:

   ```powershell
   Build.bat UnrealEditor Win64 Development -Project="F:\Omegamod\OmegaStonkers 5.1\OmegaStonkers.uproject"
   Build.bat UnrealEditor Win64 Development -Project="F:\Omegamod\OmegaStonkers 5.1\OmegaStonkers.uproject" -DisableUnity -MaxParallelActions=1
   ```

   were unsafe for an autonomous UI pass. The first spawned several multi-GB
   `cl.exe` workers, and the second planned `27189` engine compile actions.

15. Do not use the generic `manage_blueprint get` action on dispatcher-bearing
    Widget Blueprints. Confirmed crash class:

   ```text
   'Default__WBP_OSPlusSlotPickerPopover_C' is of class
   'WBP_OSPlusSlotPickerPopover_C' however property 'OnSlotChosen' belongs to
   class 'SKEL_WBP_OSPlusSlotPickerPopover_C'
   ```

   The unsafe part is generated-class/CDO/default-property export. It is a
   bridge inspection bug around skeleton-owned dispatcher properties, not proof
   that the widget asset is corrupt.

   Use the safe reader instead:

   ```powershell
   node tools\ue\run_safe_bp_inspect.mjs --asset /Game/Mods/OSPlus/UI/WBP_OSPlusSlotPickerPopover.WBP_OSPlusSlotPickerPopover
   ```

   This runs `tools/ue/safe_bp_inspect.py` through
   `system_control.execute_python`, reads source Blueprint/widget-tree
   subobjects by object path, and avoids CDO export. It reports widget tree
   shape, graph names, generated functions, delegate signatures, and
   event-like graphs.

16. For pin-level Blueprint graph reading on those same widgets, use graph
    scoped calls instead of the full Blueprint dump:

   ```powershell
   node tools\ue\read_bp_graph.mjs /Game/Mods/OSPlus/UI/WBP_OSPlusSlotPickerPopover EventGraph --all-nodes
   ```

   The bridge implementation for `get_graph_details` / `get_node_details`
   stays on `UBlueprint -> UEdGraph -> UEdGraphNode -> UEdGraphPin` and was
   live-tested against `WBP_OSPlusSlotPickerPopover`, which has the
   `OnSlotChosen` dispatcher. It returned node IDs, titles, pins, defaults, and
   pin links without crashing UE.

17. `system_control.execute_python`'s `file` parameter is path-sanitized to the
    UE project directory in this MCP build. It will reject repo files under
    `C:\Users\T-Gamer\Documents\omega-strikers-overlay`. To run repo-local
    Python, send inline code that opens and executes the file, or use
    `tools/ue/run_safe_bp_inspect.mjs`, which does that wrapping.

18. UE 5.1 Python protects several useful Blueprint editor arrays
    (`UBlueprint.NewVariables`, `FunctionGraphs`, `DelegateSignatureGraphs`,
    and `UEdGraph.Nodes`) from direct `get_editor_property` access. The safe
    inspector works around that by loading the asset, then enumerating
    `unreal.ObjectIterator()` and filtering object paths under:

   ```text
   /Game/Path/WBP.WBP:
   /Game/Path/WBP.WBP_C:
   /Game/Path/SKEL_WBP_C:
   ```

   That is safe for broad orientation. Use `read_bp_graph.mjs` when exact
   node GUIDs and pin wiring are needed.

19. For dispatcher-bearing UMG widgets, prefer a tiny project-local editor
    helper plugin over raw MCP graph surgery once the edit requires protected
    Blueprint internals. `OSPlusEditorBridge` builds safely with:

   ```powershell
   & 'F:\UE510\UnrealEngine-5.1.0-release\Engine\Build\BatchFiles\RunUAT.bat' BuildPlugin `
     -Plugin='F:\Omegamod\OmegaStonkers 5.1\Plugins\OSPlusEditorBridge\OSPlusEditorBridge.uplugin' `
     -Package='C:\Users\T-Gamer\Documents\omega-strikers-overlay\.codex-work\BuiltOSPlusEditorBridge' `
     -TargetPlatforms=Win64
   ```

   Then copy `Binaries\Win64` from the package output back into the project
   plugin and restart UE. This compiles only a handful of plugin actions, not
   the engine. The helper is currently used to add slot-picker hit cards,
   forward their `OnSlotCardChosen(SlotIndex)` dispatchers to the reusable
   popover's `OnSlotChosen(SlotIndex)`, and bind that popover dispatcher back
   to the loadout's existing `HandleSlotTileClicked` path. It is also the
   right place for narrow cleanup edits that need protected graph access, such
   as disconnecting the old loadout-parent geometry branch that inferred a
   picker slot from mouse position.

   Sharp edge found during the bridge build: do not create a
   `UK2Node_CallFunction` for an existing Blueprint custom event by calling
   `SetFromFunction()` on its generated `UFunction` and then
   `AllocateDefaultPins()`. In UE 5.1 that crashed inside
   `EnsureLoadoutSlotPickerBinding`. Create the node through
   `FGraphNodeCreator<UK2Node_CallFunction>` and set
   `FunctionReference.SetSelfMember(CustomEventName)` instead.

15. Do not call `manage_blueprint get` on widget Blueprints that contain fresh
    event dispatchers while using the currently loaded bridge build. On
    `WBP_OSPlusSlotPickerPopover`, after adding `OnSlotChosen`, the bridge
    crashed UE with:

   ```text
   'Default__WBP_OSPlusSlotPickerPopover_C' is of class
   'WBP_OSPlusSlotPickerPopover_C' however property 'OnSlotChosen' belongs to
   class 'SKEL_WBP_OSPlusSlotPickerPopover_C'
   ```

   This is a bridge inspection bug around skeleton-class dispatcher
   properties, not a RAM problem and not evidence that the widget asset is
   corrupt. Use Designer/manual graph inspection for dispatcher-bearing widgets
   until the bridge is rebuilt with safer class/property handling.

## Lesson

For UE MCP work, spend the first minute proving the exact tool shape, then
write the edit. Treat the bridge like an API with local quirks, not like full
Unreal Editor Python. Use MCP graph tools for node/pin changes, object-path
Python for UMG tree surgery, and verify the resulting asset structure before
asking the user to cook.

## Related

- Files: UE asset `/Game/Mods/OSPlus/UI/WBP_OSPlusEmoteLoadout`
- Prior learnings: `docs/learnings/umg-scrollbox-chip-buttons.md`,
  `docs/learnings/osplus-widget-integration-pattern.md`,
  `docs/learnings/ue-cook-additional-asset-dirs.md`
