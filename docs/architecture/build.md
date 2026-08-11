# Subsystem: Build

Blueprint mode UX: cursor raycast, rotation state, ghost preview, validity check, commit — plus the global `BuildLibrary` catalog that everything reads from, and a `FurnitureLayer` for free-standing furniture. The controller is voxel-agnostic: all voxel coupling is behind the `IBlockGrid` adapter, and `voxel_tool` is never imported here.

**Two-kind placement, strategy-driven commit:** a single `BuildController` does per-kind VALIDITY only (block = air; furniture = free footprint, neither overlapping a blueprint), then delegates COMMIT to an `IPlacementStrategy`. Which strategy is wired decides what commit does:
- **`BlueprintPlacementStrategy`** (default) → spawns a non-physical `Blueprint` (an interactable furniture-like node) for the player to complete by interacting (Build action). The incremental step toward blueprint-then-build (GDD §7.4); see the blueprint flow trace below.
- **`InstantPlacementStrategy`** (MVP/debug fallback) → `BlockDef` → `VoxelGridAdapter` → voxel grid; everything else → `FurnitureLayer` spawn. Materializes immediately.

The def's shape still drives VALIDITY everywhere: `BuildController._is_furniture(id)` is `def != null and not (def is BlockDef)`, the ghost uses the same test to pick a single-cell preview vs. a footprint-center preview, and `FurnitureLayer`/`BlueprintLayer` read `FurnitureDef.dimensions` for multi-cell validity + placement.

## Files

| File | Type | Responsibility |
|---|---|---|
| `build.tscn` / `build_controller.gd` | Scene/Script | Owns cursor raycast (screen-center, player-excluded), rotation state, ghost preview, validity, and commit. Does NOT know what commit does — it routes by def kind to the strategy (blocks) or the furniture layer (everything else). |
| `build_library.gd` | Autoload | Global catalog (`id → BuildableDef`) of everything buildable. Loads `data/blocks/`, `data/buildables/`, `data/furniture/`. Delegates "unlocked" to `RunProgress`; seeds defaults at startup + on `EventBus.run_started`. See Autoloads table. |
| `ghost_preview.gd` | Script | `MeshInstance3D` (translucent, validity-tinted green/red). Mesh is driven by the selected def's `mesh`; positioned each frame by the controller — single cell corner for blocks, footprint center for furniture. |
| `rotation_state.gd` | Script | Axis cycle (R: Z→X→Y) + 90° step wheel (mouse wheel: CW = `cycle_step`, CCW = `cycle_step_back`) + the even-footprint 0.5m pivot rule (GDD §7.4). **Rotation is now wired** in `BuildController._unhandled_input` (wheel up/down + R), and the ghost yaw is applied each frame in `_physics_process`. **Still a stub:** the 0.5m pivot is unimplemented (`get_yaw_degrees` returns a Y-axis yaw = `step * 90°`), and axis rotation has no visible effect on cube blocks — it only matters for multi-cell furniture footprints today. |
| `i_block_grid.gd` | Script (interface) | Documentation-only contract: `get_block_at`, `set_block_at`, `remove_block_at`, `is_valid_placement`, `raycast_to_voxel`, `snap_transform`. Implementations duck-type; they do NOT extend it. |
| `i_placement_strategy.gd` | Script (interface) | Documentation-only contract: `commit(transform, rotation, item_id) -> bool`. Implementations duck-type; they do NOT extend it. |
| `instant_placement_strategy.gd` | Script (`RefCounted`) | MVP/debug strategy: resolves the cell from `transform.origin` and materializes directly — `BlockDef` → `VoxelGridAdapter.set_block_at`, else `FurnitureLayer.spawn`. Handles both kinds so it stays a complete fallback. Cost deduction deferred (TODO). |
| `blueprint_placement_strategy.gd` | Script (`RefCounted`) | Default strategy: spawns a `Blueprint` (via `BlueprintLayer`) for the player to complete by interacting — the incremental blueprint-then-build step (GDD §7.4). The second `IPlacementStrategy` impl alongside `InstantPlacementStrategy`. |
| `blueprint_layer.gd` | Script (`RefCounted`) | Sibling of `FurnitureLayer`. Owns blueprint spawn/remove + cell registry and the single `complete_blueprint()` entry point a future JobBoard/colonist will call. Reuses `FurnitureLayer`'s static geometry helpers. Emits `blueprint_placed`/`blueprint_removed`. |
| `blueprint.gd` / `blueprint_template.tscn` | Script/Scene | `Blueprint extends Furniture` — an interactable node carrying `target_def_id`/`target_rotation_step`/`anchor_cell`. The Build action calls its `complete()`, which forwards to `BlueprintLayer.complete_blueprint`. |
| `voxel_grid_adapter.gd` | Script (`RefCounted`) | `IBlockGrid` impl wrapping `voxel/voxel_grid.gd`. Adds `is_valid_placement` + `snap_transform` + raycast `exclude` passthrough (for player-body exclusion). |
| `furniture_layer.gd` | Script (`RefCounted`) | Free-standing furniture layer — sibling of `VoxelGridAdapter` for non-block buildables. Spawns a `Furniture` node (from `new_furniture_template.tscn`) under the world's `FurnitureContainer`; owns the anchor + footprint model (cell-box `dimensions`, yaw swaps x/z), overlap rejection, and removal-by-pointing-at-any-covered-cell. Emits `furniture_placed` / `furniture_removed` on EventBus. |
| `new_furniture_template.tscn` | Scene | Node template for spawned furniture: a root `Furniture` node (`subsystems/furniture/furniture.gd`) holding a `Mesh` `MeshInstance3D` (gets a runtime trimesh `StaticBody3D` on collision layer 1) + a `BuildBody` `StaticBody3D` with a footprint-sized `BoxShape3D` (collision layer 3). Rotated as a unit by yaw. |
| `../data/blocks/` | Data | `BlockDef` per block type (wood, scrap, stone, metal, reinforced, terrain). See [Data Schemas](data-schemas.md). |
| `../data/buildables/` | Data | Plain `BuildableDef` (player-placed objects not on the voxel grid — e.g. `pole`). |
| `../data/furniture/` | Data | `FurnitureDef` per furniture type (workbench, etc.); adds `dimensions: Vector3i` + `action_options: Array[ActionOption]`. Partial (C1) — see [Actions & Interaction](actions.md). |
| `../../ui/build_menu/build_menu.tscn` | Scene | The build menu: titled scrollable list of unlocked buildables. `BuildMenu.populate()` instances one `build_menu_entry.tscn` per def; clicking an entry emits `EventBus.buildable_selected(id)`. |
| `../../ui/build_menu/build_menu_entry.tscn` | Scene | One menu row: `Button` (whole-row click target) holding an `HBox` with a `TextureRect` (icon) + `Label` (display name). `setup(def)` hides the icon node when `def.icon == null`. Layout is .tscn-authored so icon size, spacing, and future cost/category fields are editor-tunable. |

## Signals

Build placement has no same-scene signals — the controller calls strategies/layers directly, and the world-side reactions go through the global voxel/furniture emissions:

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `build_placement_toggled(active)` | player subsystem | `BuildController` (activates/deactivates) | Yes | Enter/Exit Build Placement |
| `build_menu_toggled(open)` | player subsystem | HUD (Instructions label) | Yes | Build menu visibility |
| `buildable_selected(id)` | player subsystem (from build menu) | `BuildController` (sets `selected_id` + ghost mesh) | Yes | Select a Buildable |
| `block_placed(pos, block_id)` | `VoxelGrid` (via adapter) | colonists (pathfinding), raids (breach), Functional Rooms | No | Place Block |
| `furniture_placed(def_id, anchor)` | `FurnitureLayer` | Colony (Functional Rooms counter) | Yes | Place Furniture |
| `furniture_removed(def_id, anchor)` | `FurnitureLayer` | Colony (Functional Rooms counter) | Yes | Remove Furniture |

## Flow Trace: Place a voxel block (MVP → Instant)

**Trigger:** Player LMB-clicks (`build_place` action) in Blueprint mode with a `BlockDef` selected and valid placement.

1. `BuildController._try_commit` raycasts from screen center (player body excluded).
2. Target cell = struck voxel + face normal. Confirmed valid via `grid_adapter.is_valid_placement(cell)` (cell is air).
3. Routes to `_commit_block`: builds a `Transform3D` at the cell origin, calls `strategy.commit(transform, rotation_state, selected_id)`.
4. `InstantPlacementStrategy.commit` resolves the cell from the transform origin and calls `grid_adapter.set_block_at(cell, item_id)`.
5. Adapter delegates to `VoxelGrid.set_block_at` → emits `block_placed(pos, block_id)` (consumed by colonist pathfinding, raids, Functional Rooms).

**End state:** Block exists in the voxel grid; downstream listeners notified. Materials consumed (deferred — strategy TODO).

## Flow Trace: Place free-standing furniture

**Trigger:** Player LMB-clicks (`build_place`) in Blueprint mode with a non-block def selected (`BuildableDef` or `FurnitureDef`) and a free footprint.

1. `BuildController._try_commit` raycasts from screen center; cell = struck voxel + face normal.
2. Routes to `_commit_furniture` (the def is not a `BlockDef`).
3. `_is_footprint_free(anchor, def)`: for every cell in the (yaw-rotated) footprint, confirms `grid_adapter.is_valid_placement(cell)` AND `furniture_layer.has_at(cell)` is false. Rejects overlap with terrain, blocks, or existing furniture.
4. On success, `FurnitureLayer.spawn(def, anchor, rotation_state.step)`:
   - Instantiates `new_furniture_template.tscn` (a `Furniture` root); assigns `root.def_id = def.id` and `root.def = def` (the runtime back-ref static data is read through). Assigns `def.mesh` to the `Mesh` node and builds a footprint-sized `BoxShape3D` collision on the `BuildBody` (layer 3) + a trimesh body (layer 1).
   - When `def is FurnitureDef` and its `action_options` is non-empty, attaches an `InteractionComponent` child named exactly `"InteractionComponent"` and copies the options onto it — see [Actions & Interaction](actions.md) flow trace.
   - Positions at `FurnitureLayer.world_origin(anchor, dims, yaw)` (footprint center on XZ, anchor Y).
   - Registers every covered cell in `anchor_by_cell` (so removal by pointing at any covered cell resolves to the item) and the node in `node_by_anchor`.
   - Emits `furniture_placed(def.id, anchor)` on EventBus → Colony's Functional Rooms counter increments.

**End state:** Furniture node exists under `FurnitureContainer`; every covered cell reserved; Functional Rooms notified.

## Flow Trace: Place a blueprint → interact to build (default strategy)

**Trigger:** Player LMB-clicks (`build_place`) in Blueprint mode with any buildable selected and a valid target cell. (BlueprintPlacementStrategy is the wired strategy.)

1. `BuildController._try_commit` raycasts; per-kind validity is checked (block = air; furniture = free footprint; neither on an existing blueprint), then `strategy.commit(transform, rotation_state, selected_id)`.
2. `BlueprintPlacementStrategy.commit` resolves the cell, looks the def up in `BuildLibrary`, reads `rotation.step`, and calls `BlueprintLayer.spawn_blueprint(def, cell, step)`.
3. `BlueprintLayer` sizes the blueprint to the target's footprint (`FurnitureLayer.dimensions_of` → 1×1×1 for blocks), instantiates `blueprint_template.tscn` (a `Blueprint` root), applies a translucent hologram material over the target's mesh (unit-box fallback), attaches an `InteractionComponent` child named `"InteractionComponent"` with the single "Build" `ActionOption`, registers every covered cell, and emits `EventBus.blueprint_placed(target_def_id, anchor)`.
4. Player toggles out of BUILD_PLACEMENT (interaction is gated to NORMAL mode), aims at the blueprint, and presses E. Tap runs `action_options[0]` (Build) directly; hold opens the 1-button menu.
5. `BuildAction.execute` casts `target as Blueprint` and calls `bp.complete(actor)`, which forwards to `BlueprintLayer.complete_blueprint`.
6. `complete_blueprint` materializes the target — `BlockDef` → `VoxelGridAdapter.set_block_at` (emits `block_placed`); else `FurnitureLayer.spawn` (emits `furniture_placed`) — then frees the blueprint and emits `blueprint_removed`.

**End state:** The real buildable exists; the blueprint is gone. RMB (Deconstruct) also removes a blueprint without building (`BlueprintLayer.remove_blueprint_at`).

> **Forward-compat (JobBoard / colonist labor):** completion funnels through the single `Blueprint.complete` → `BlueprintLayer.complete_blueprint` entry point, so a future colonist work-tick / `JobBoard.complete` drives the same path (accruing HP over time instead of instantly). `blueprint_placed`/`blueprint_removed` are the signals a future JobBoard will connect to register/cancel construction Jobs — no listeners today.

## Flow Trace: Remove (block or furniture)

**Trigger:** Player RMB-clicks (`build_remove`) in Blueprint mode.

1. `BuildController._try_remove` raycasts from screen center.
2. A block occupies the **struck voxel itself**; furniture occupies the **adjacent air cell** (it has no voxel collision — placement targeted the floor cell next to the struck surface). The controller tries both so RMB works on either kind:
   - If `grid_adapter.get_block_at(struck)` is non-empty → `grid_adapter.remove_block_at(struck)` → `block_destroyed`.
   - Else → `furniture_layer.remove_at(adjacent)` → resolves the anchor from any covered cell, frees the node, clears all its cells, emits `furniture_removed`.

## Class Reference

### Class: BuildLibrary

**Extends:** Node (autoload)
**Script:** `build_library.gd`
**Description:** Global, read-only catalog of every buildable. Loads all three `BuildableDef` subclass folders into one polymorphic `id → BuildableDef` map. Holds no run-state — "what's unlocked" is delegated to `RunProgress`.
**Used by:** Build menu (lists available defs), `BuildController` (resolves `selected_id` → def for routing/ghost/commit), `InstantPlacementStrategy` (cost lookup, deferred).
**Lifecycle:** `_ready` loads the dirs, seeds `RunProgress` with `unlocked_by_default` defs, then connects `_seed_defaults` to `EventBus.run_started` (New Game: `RunProgress` was reset, defaults re-added from the in-memory catalog — no disk re-read).

**Functions:**

| Function | Description |
|---|---|
| `get_def(id: String) -> BuildableDef` | The def for `id`, or `null`. |
| `has_def(id: String) -> bool` | Catalog membership (independent of unlock state). |
| `is_unlocked(id: String) -> bool` | Thin pass-through to `RunProgress.is_unlocked`. |
| `get_unlocked() -> Array` | The defs currently available to the build menu. |
| `unlock(id: String) -> void` | Pass-through to `RunProgress.unlock` (items/skills/quests call this; callers talk to the catalog, not run-state internals). |

### Class: BuildController

**Extends:** Node3D
**Script:** `build_controller.gd`
**Description:** Build-mode controller. Active only when Player.mode == BUILD_PLACEMENT. Owns cursor raycast (screen-center, player-body-excluded), rotation state, ghost preview, and commit routing. Delegates block commit to `InstantPlacementStrategy`, furniture commit to `FurnitureLayer`, and grid queries to `VoxelGridAdapter`.
**Used by:** World (runtime wiring after player exists), EventBus (`build_placement_toggled`, `buildable_selected`).

**Deconstruct tool:** the build menu appends a "Deconstruct" tool entry whose id is the `BuildLibrary.DECONSTRUCT_ID` sentinel (not a `BuildableDef`). When it is the selected id, `_unhandled_input` routes LMB to `_try_remove()` instead of `_try_commit()` (RMB still removes, so both buttons remove), and `_physics_process` drives a red ghost on the removal target — a red unit box (`GhostPreview.show_remove_at`) for blocks, or a red overlay of the targeted piece's own mesh (`GhostPreview.show_remove_mesh_at`, fed by `FurnitureLayer.get_furniture_at`) for furniture, mirroring the erase ghost in `addons/voxel_paint/`. `_on_buildable_selected` skips `_set_ghost_mesh()` for the sentinel (no def mesh to set).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `grid_adapter` | `VoxelGridAdapter` | Runtime-wired (RefCounted can't be `@export`'d). The active grid adapter. |
| `strategy` | `IPlacementStrategy` (duck-typed) | Runtime-wired (RefCounted can't be `@export`'d). The placement strategy — `BlueprintPlacementStrategy` (default) or `InstantPlacementStrategy`. |
| `furniture_layer` | `FurnitureLayer` | Runtime-wired. The free-standing furniture layer (non-block path). |
| `blueprint_layer` | `BlueprintLayer` | Runtime-wired. Blueprint spawn/remove + completion registry (BlueprintPlacementStrategy path). |
| `camera_path` | `NodePath` | `[export]` Path to the build camera; resolved in `_ready`, or via `set_camera()`. |
| `exclude_bodies` | `Array[PhysicsBody3D]` | Bodies to skip in the cursor raycast (the player capsule). Add via `add_exclude_body()`. |
| `rotation_state` | `RotationState` | Current axis + 90° step. |
| `selected_id` | `String` | The currently selected buildable id, or `BuildLibrary.DECONSTRUCT_ID` for the Deconstruct tool. Set by `EventBus.buildable_selected`; drives ghost mesh + commit routing (and LMB-remove when it's the deconstruct sentinel). |

**Functions:**

| Function | Description |
|---|---|
| `set_active(active: bool) -> void` | Activates/deactivates the controller (called on `build_placement_toggled`); shows/hides the ghost. |
| `set_camera(camera: Camera3D) -> void` | Runtime camera wiring (controller is a sibling of the player; can't use a relative path). |
| `add_exclude_body(body: PhysicsBody3D) -> void` | Adds a body to the raycast exclusion list. |

### Class: VoxelGridAdapter

**Extends:** RefCounted
**Script:** `voxel_grid_adapter.gd`
**Description:** `IBlockGrid` implementation wrapping `voxel/voxel_grid.gd`. Keeps `BuildController` voxel-agnostic. Holds a `VoxelGrid` reference set at wiring time.
**Used by:** `BuildController` (raycast + validity queries), `InstantPlacementStrategy` (block set), `FurnitureLayer` (footprint validity queries).

**Functions:**

| Function | Description |
|---|---|
| `set_grid(grid: VoxelGrid) -> void` | Wiring. |
| `get_block_at(pos: Vector3i) -> String` | Block id at cell, or `""` for air. |
| `set_block_at(pos: Vector3i, block_id: String) -> void` | Delegates to `VoxelGrid`; emits `block_placed` there. |
| `remove_block_at(pos: Vector3i) -> void` | Delegates to `VoxelGrid`; emits `block_destroyed` there. |
| `is_valid_placement(pos: Vector3i) -> bool` | True if the cell is air. (TODO: ownership/footprint checks once multi-cell blocks exist.) |
| `raycast_to_voxel(origin, dir, max_dist, exclude: Array = []) -> Dictionary` | Physics raycast → `{position, normal, hit}`. `exclude` is an `Array[RID]` to ignore (player body). |
| `snap_transform(world_pos: Vector3) -> Vector3i` | Snap a world position to its containing cell. |

### Class: FurnitureLayer

**Extends:** RefCounted
**Script:** `furniture_layer.gd`
**Description:** Free-standing furniture placement layer — sibling of `VoxelGridAdapter` for non-block buildables. Spawns a `Furniture` node (from `new_furniture_template.tscn`) under the world's `FurnitureContainer`; owns the anchor + footprint model. Never touches `voxel_tool` — it asks `VoxelGridAdapter` whether candidate cells are free.
**Used by:** `BuildController` (non-block commit/remove), Colony (Functional Rooms, via `furniture_placed`/`furniture_removed`).

**Static helpers:**

| Function | Description |
|---|---|
| `footprint_cells(dimensions: Vector3i, yaw_quarters: int) -> Array[Vector3i]` | Cell offsets an item covers (yaw swaps width/depth; height unchanged). |
| `dimensions_of(def: BuildableDef) -> Vector3i` | Effective cell-box (def's `dimensions` if `FurnitureDef`, else `1×1×1`). |
| `world_origin(anchor, dimensions, yaw_quarters) -> Vector3` | World-space spawn origin: footprint center on XZ, anchor Y. |

**Functions:**

| Function | Description |
|---|---|
| `set_container(container: Node3D) -> void` | Wiring: where spawned nodes parent. |
| `spawn(def: BuildableDef, anchor: Vector3i, yaw_quarters: int) -> Node3D` | Place an item; returns the node (runtime type `Furniture`) or `null` if unwired/overlapping/no mesh. Emits `furniture_placed(def.id, anchor)`. |
| `remove_at(cell: Vector3i) -> bool` | Remove the item covering `cell` (any covered cell resolves to its anchor). Reads `node.def_id` for the emitted id — the canonical key, not the cosmetic node name. Emits `furniture_removed`. |
| `has_at(cell: Vector3i) -> bool` | Whether any item covers `cell`. |

### Class: Furniture

**Extends:** Node3D
**Script:** `subsystems/furniture/furniture.gd`
**Description:** Runtime instance of one placed furniture item (GDD §7.2). Holds a back-ref to its definition so static data (mesh, `display_name`, `hp`, `dimensions`) is read through the def and `.tres` balance changes propagate to already-placed instances without respawning. Only per-instance state lands here as subsystems are built.
**Used by:** `FurnitureLayer` (creates + parents instances), [Actions & Interaction](actions.md) (the interaction menu's target; `label` is the UI label source).
**Lifecycle:** Instantiated from `new_furniture_template.tscn` by `FurnitureLayer._create_furniture_node`, which sets `def_id` and `def` immediately after instantiation.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `def_id` | `String` | `[export default ""]` Canonical def id (e.g. `"workbench"`). The emitted id source in `remove_at` and the future save/load key. |
| `def` | `BuildableDef` | Runtime back-ref to the definition (not serialized). Read static data through this (`def.hp`, `def.dimensions`, `def.action_options`). |
| `label` | `String` | `[export, getter only]` Returns `def.display_name` (or `""` if `def` is null). The interaction menu reads this via `target.get("label")` so the UI stays decoupled from `FurnitureDef`. |

> **Deferred:** per-instance HP/damage (GDD §7.7), Functional Rooms counting fields (§7.8), and crafting/storage/door/bed component slots (§7.9–§7.11) are not on this class yet — added as the owning subsystems land. Placement bookkeeping (anchor → node maps, cell ownership) stays in `FurnitureLayer`.
