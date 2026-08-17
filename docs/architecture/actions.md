# Subsystem: Actions & Interaction

The E-key interaction flow: the player points the crosshair at an interactable, presses E, and a pop-up menu lists the actions available on that target. Each action is a data-driven `Resource` chain — a `GameAction` (what happens) wrapped in an `ActionOption` (which button, gated by `Condition`s) — so designers add interactions by authoring `.tres` files, not by touching the player or the UI. Maps to GDD §4 (interaction interrupt rule + the E keybind) and §7.2 (interactable furniture). Authoring walkthrough: `docs/HOWTO-author-interactions.md`.

> **Design notes:**
> - **The whole chain is composable Resources.** `GameAction`, `Condition`, and `ActionOption` all extend `Resource`; each is authored as its own `.tres`. An `ActionOption` references one `GameAction` plus zero-or-more `Condition`s; a `FurnitureDef` references one-or-more `ActionOption`s.
> - **The UI never references `FurnitureDef`.** The menu label is resolved via the target's `label` property (`Furniture.label` getter returns `def.display_name`), falling back to `InteractionComponent.display_name`, then the node name. This keeps `ui/interaction/` decoupled from the data layer.
> - **Interaction is disabled in Blueprint mode.** `Player._update_interaction_target` early-returns when `mode != NORMAL`, so the crosshair never picks a target while building.
> - **Conditions gate at menu-open time, not execute time.** `ActionOption.is_available` only sets each button's `disabled` state when the menu is built. Pressing an enabled button calls `GameAction.execute` directly — conditions are not re-checked. A condition that should block execution must keep the option disabled (or the action must re-validate internally).
> - **`BlockDef` has no interactions.** Voxel blocks resolve through the voxel grid, not as `Node3D` instances. Only `FurnitureDef` carries `action_options`.

## Files

| File | Type | Responsibility |
|---|---|---|
| `subsystems/actions/interaction_component.gd` | Script (Node) | The runtime attachment. Parented under a Furniture node (named exactly `"InteractionComponent"`); `interact(actor)` spawns the UI, mounting it on a CanvasLayer. Owns the actor/target cache; the cursor/mouse round-trip is owned by [UiGate](ui.md) (the UI registers as a modal). |
| `subsystems/actions/game_action.gd` | Script (Resource) | Base class for "what happens". One `label: String` export (the button text) + a virtual `execute(actor, target)`. |
| `subsystems/actions/condition.gd` | Script (Resource) | Base class for gating. A virtual `is_met(actor, target) -> bool` (default `true`). |
| `subsystems/actions/action_option.gd` | Script (Resource) | One menu button. References a `GameAction` plus an `Array[Condition]`; `is_available` ANDs all conditions. |
| `subsystems/actions/any_of.gd` | Script (Resource) | Condition composite — true if any child `is_met`. |
| `subsystems/actions/all_of.gd` | Script (Resource) | Condition composite — true only if all children `is_met` (redundant inside an option, which already ANDs its conditions). |
| `subsystems/actions/not.gd` | Script (Resource) | Condition composite (`class_name NotCondition`) — inverts a single child `condition`. |
| `../data/conditions/` | Script (Resource) | Leaf conditions — `CanCarryDispensedItems` (dispenser pickup capacity check), `MinSkillCondition` + `HasItemCondition` (actor gates, shared with `JobDef.conditions`). |
| `../ui/interaction/interaction_ui.tscn` / `.gd` | Scene/Script | Pop-up `Control` (Label + button list). Built by `InteractionComponent`; one `Button` per `ActionOption`. See [UI](ui.md). |
| `../data/actions/` | Data | `GameAction` subclasses + their `.tres`. Thirteen interaction actions ship as `.tres` chains (print/build/instant_build/add_materials/give_item/open_storage/open_crafting/craft/harvest/toggle_harvest/farm_manual/inspect_crop/select_crop). `dig_action.gd` (`DigAction`, Phase-5 mining) is the one action NOT authored as an `.tres` chain: terrain isn't an interactable — its trigger is the build menu's Dig tool (an equipped-tool LMB later), so its entry point is `begin(actor, grid, center, tool)` instead of the `(actor, target)` node shape. See [Build](build.md). |
| `../data/action_options/` | Data | `ActionOption` `.tres` resources — ten ship (one per shipped action family, e.g. `build_action_option`, `toggle_harvest_action_option`, `select_crop_action_option`). |

## Signals

*(No EventBus signals — the chain is direct calls: `Player → InteractionComponent.interact → InteractionUI → ActionOption.action.execute`. Furniture placement/removal is still broadcast via the existing `furniture_placed` / `furniture_removed` signals on EventBus, owned by the [Build](build.md) subsystem.)*

## Flow Trace: Player interacts with furniture

**Trigger:** Player points the crosshair at a furniture node carrying an `InteractionComponent` and presses E (`"interact"` input action) in Normal mode.

1. Every `_physics_process` tick, `Player._update_interaction_target` raycasts from the screen center (`interact_distance` 8.0, bodies only, player RID excluded). Skipped entirely when `mode != NORMAL`.
2. On a hit, `Player._find_interaction_component(hit.collider)` walks **up** the parent chain looking for a direct child named exactly `"InteractionComponent"` (handles any nesting depth). The result is cached in `_current_interactable`.
3. E press → `Player._try_interact`: if `_current_interactable` is non-null **and** its `action_options` is non-empty, calls `_current_interactable.interact(self)`.
4. `InteractionComponent.interact(actor)` calls `_open_interaction_ui(actor, get_parent(), action_options, self)` — note the target is the component's **parent** (the Furniture node).
5. `_open_interaction_ui` instantiates `interaction_ui.tscn`, connects its `action_selected` signal, and mounts it on a CanvasLayer (group `"hud_layer"` first — the shipped `main.tscn`'s HUDLayer carries it — falling back to `"ui_layer"`). The mount happens **before** `setup()` so `@onready` refs resolve. The UI registers with `UiGate` in its `_ready` (cursor + gameplay-input gating — see [UI](ui.md)).
6. `InteractionUI.setup(actor, target, options, component)` clears the list, sets the label (`target.get("label")` → falls back to `component.display_name` → then `target.name`), and builds one `Button` per option — text from `option.action.label`, `disabled = not option.is_available(actor, target)`. If the list ends up empty, the UI frees itself immediately.
7. Player clicks a button → `_on_option_pressed` emits `action_selected(option)` → `_on_action_selected` calls `option.action.execute(actor, target)` and the UI closes (`close()` → freed; Esc also calls `close()`; the empty-list case in step 6 frees directly). The cursor round-trip on free is UiGate's.

**End state:** The selected `GameAction.execute` has run (with the player as `actor` and the Furniture node as `target`); the menu is freed and the mouse re-captured.

## Flow Trace: Furniture spawns with an InteractionComponent

**Trigger:** A furniture def with non-empty `action_options` is placed via the [Build](build.md) subsystem.

1. `FurnitureLayer._create_furniture_node(def, dims, yaw)` instantiates `new_furniture_template.tscn` (a `Furniture` root) and assigns `root.def_id = def.id`, `root.def = def`.
2. After mesh/collision/yaw wiring, the attach condition is capability-driven: a `FurnitureDef` with non-empty `action_options` gets an `InteractionComponent` — and `harvest_params` / `farm_plot_params` auto-append their options to the list before the check (`ToggleHarvest` for harvestable or farm-plot defs; `InspectCrop` + `SelectCrop` + `ToggleHarvest` for farm plots). It creates the component, sets `interaction.name = "InteractionComponent"`, adds it as a child of the Furniture root, and copies the combined options onto it.

**End state:** The spawned Furniture node carries a discoverable `InteractionComponent` child (the exact name `Player._find_interaction_component` looks for) pre-populated with the def's options.

## Class Reference

### Class: InteractionComponent

**Extends:** Node
**Script:** `subsystems/actions/interaction_component.gd`
**Description:** The runtime handle the player's raycast resolves to. Parented under a Furniture node (or any interactable); `interact(actor)` builds and mounts the interaction menu. Owns actor/target caching; the cursor/mouse round-trip while the menu is open is owned by UiGate (the UI registers as a modal), not this component.
**Used by:** `Player._try_interact` (calls `interact`), `FurnitureLayer._create_furniture_node` (creates + populates it), `InteractionUI` (the component wires the UI's `action_selected` signal to its own callback).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `action_options` | `Array[ActionOption]` | The options offered by this target. Plain `var` (not `@export`) — runtime-populated by `FurnitureLayer`, copied from `FurnitureDef.action_options` (+ the auto-appended harvest/crop options). |
| `display_name` | `String` | `[export default ""]` UI label fallback for targets without a `label` property (test cubes, ad-hoc bodies). |
| `info_text` | `String` | Optional live status line the parent furniture sets at runtime (e.g. a blueprint's "Plank 3/15"); the HUD InteractLabel shows it under the action hint. |

**Functions:**

| Function | Description |
|---|---|
| `interact(actor: Node) -> void` | Entry point. Opens the UI on `get_parent()` (the target) with `action_options`. |

### Class: GameAction

**Extends:** Resource
**Script:** `subsystems/actions/game_action.gd`
**Description:** Base class for "what happens when the player picks this option". Subclasses override `execute`. Thirteen concrete impls ship (see [Data Schemas](data-schemas.md) for the list — from `PrintAction`'s smoke test through build, storage, crafting, harvest, and crop actions).
**Used by:** `ActionOption.action`, invoked by `InteractionComponent._on_action_selected`.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `label` | `String` | `[export]` The button text shown in the menu. |

**Functions:**

| Function | Description |
|---|---|
| `execute(actor: Node, target: Node) -> void` | Virtual — override in a subclass to perform the action. `actor` is the player; `target` is the interactable node. |

### Class: Condition

**Extends:** Resource
**Script:** `subsystems/actions/condition.gd`
**Description:** Base class for option gating. Subclasses (the composites below, or the leaves in `data/conditions/`) override `is_met`.
**Used by:** `ActionOption.conditions`, and — re-evaluated hot every poll — `JobDef.conditions` (see [Jobs](jobs.md)).

**Functions:**

| Function | Description |
|---|---|
| `is_met(actor: Node, target: Node) -> bool` | Virtual — default `true`. ANDed by `ActionOption.is_available` / `JobDef.meets_requirements`. |

### Class: ActionOption

**Extends:** Resource
**Script:** `subsystems/actions/action_option.gd`
**Description:** One row in the interaction menu. Binds a `GameAction` to its gating `Condition`s. Authored as a `.tres` and referenced from `FurnitureDef.action_options`.
**Used by:** `FurnitureDef.action_options`, copied onto `InteractionComponent.action_options` at spawn; read by `InteractionUI.setup`.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `conditions` | `Array[Condition]` | `[export default []]` Gates the option. All must be met for the button to be enabled. |
| `action` | `GameAction` | `[export]` The action to execute when the button is pressed. |

**Functions:**

| Function | Description |
|---|---|
| `is_available(actor: Node, target: Node) -> bool` | Returns `false` on the first failing condition; `true` if empty. Drives each button's `disabled` state. |

### Class: AnyOf

**Extends:** Condition
**Script:** `subsystems/actions/any_of.gd`
**Description:** Condition composite — true if **any** child `is_met`, false if none.
**Properties:** `conditions: Array[Condition]` `[export]`.

### Class: AllOf

**Extends:** Condition
**Script:** `subsystems/actions/all_of.gd`
**Description:** Condition composite — true only if **all** children `is_met`. Redundant inside an `ActionOption` (which already ANDs its `conditions`), but useful where a single condition slot must combine several checks.
**Properties:** `conditions: Array[Condition]` `[export]`.

### Class: NotCondition

**Extends:** Condition
**Script:** `subsystems/actions/not.gd` (note: filename `not.gd`, class `NotCondition`)
**Description:** Condition composite — inverts a single child.
**Properties:** `condition: Condition` `[export]`.

### Class: MinSkillCondition

**Extends:** Condition
**Script:** `data/conditions/min_skill_condition.gd`
**Description:** Leaf — actor's `skill_set` is at least `min_level` in `skill_id` (see [Skills](skills.md)). Fails closed when the actor has no SkillSet component.
**Properties:** `skill_id: String`, `min_level: int` (`[export default 1]` — the regular-job L1 gate).

### Class: HasItemCondition

**Extends:** Condition
**Script:** `data/conditions/has_item_condition.gd`
**Description:** Leaf — actor carries `count` of an item, by exact `item_id` or by `item_tag` (any item whose `ItemDef.tags` match; id wins when both are set; both empty fails closed). Fails closed when the actor has no inventory.
**Properties:** `item_id: String`, `item_tag: String`, `count: int` (`[export default 1]`).

## Authoring

See `docs/HOWTO-author-interactions.md` for the step-by-step recipe: write a `GameAction` subclass + `.tres` → (optionally) author `Condition` `.tres` resources → create an `ActionOption.tres` binding them → drag it into a `FurnitureDef.action_options`. Schemas for each resource are in [Data Schemas](data-schemas.md).
