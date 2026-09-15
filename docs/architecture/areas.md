# Subsystem: Areas & Orders

The Areas & Orders subsystem provides player-designated persistent regions in the 3D world (Dwarf Fortress burrow-style zones) and batch flora work orders (Remove Plants, Chop Trees, Forage, Cancel Orders). Designated regions back future retreat behavior (such as the GDD Shelter raid stance), alarm response points, and movement restriction boundaries. In this release, the subsystem provides designation tools, CRUD management, multi-box areas (Paint and Erase via integer box partitioning), and save/load persistence; AI, pathfinder, and behavioral consumption are explicitly deferred to a future pass.

**Design notes:**
- **Orders & Designation Menu (Hotkey T):** Pressing `T` opens a modal menu (`ui/designation_menu/`) displaying one-time batch flora orders (Remove Plant, Chop Tree, Forage, Cancel Orders) and persistent Area CRUD (New Area, Paint Area, Erase Area).
- **Navigation Pattern (Build Menu Pattern):** Pressing `T` in normal gameplay opens the menu. Selecting an order or area action enters 3D placement mode and captures the mouse. Pressing `T` while in 3D placement mode re-opens the menu. Pressing `Esc` in 3D placement mode exits straight back to normal gameplay.
- **Two-click AABB Drag-Box:** In 3D placement mode, two ground clicks define opposite corners of an axis-aligned 3D box. The volume applies to the selected tool (batch-marking matching flora, creating an area, painting into an area, or carving out from an area).
- **Multi-Box Area Representation:** An `Area` consists of an array of non-overlapping 3D boxes (`boxes: Array[Dictionary]`, each `{"min": Vector3i, "max": Vector3i}`). Painting adds new boxes, and erasing carves out volumes via 3D integer CSG box partitioning (producing up to 6 non-overlapping sub-boxes). If an area has all its boxes erased, it is automatically removed from `AreaManager`.
- **In-World Area Highlights:** While the Paint or Erase tool is active for a target area, all existing boxes of that area are rendered in the world as translucent 3D box meshes (cyan for Paint, orange/red for Erase).
- **Overhead 3D Moodlet Visualizers:** Flora marked with work orders display unshaded, billboard-mode 3D labels overhead (`[CHOP]` in gold, `[FORAGE]` in green, `[CLEAR]` in red) that remain legible from any angle and clean up immediately upon completion or cancellation.
- **Colony Autoload Ownership:** `AreaManager` is owned as a child node of `Colony`, mirroring `JobBoard` and `StorageRegistry`. Area state serializes directly into the `"areas"` key of `Colony.serialize()`.

## Files

| File | Type | Responsibility |
|---|---|---|
| `subsystems/areas/area.gd` | Script | RefCounted plain data class representing an Area entity (id, display name, boxes collection, member colonist IDs). Provides multi-box add/erase CSG logic, point containment checks, outer bounds calculation, and dictionary serialization. |
| `subsystems/areas/area_manager.gd` | Script | Node child of Colony managing the registered collection of Areas. Handles CRUD, sequential naming, painting, erasing (auto-deletion when empty), colonist member assignment/removal, spatial cell queries, and persistence. |
| `subsystems/areas/area_designation_controller.gd` / `.tscn` | Scene/Script | 3D placement controller active during `Player.Mode.AREA_DESIGNATION`. Casts screen-center raycasts, manages two-click stage state machine, drives the live `GhostPreview` box, renders in-world area highlight meshes, and dispatches committed actions to `AreaManager` or `FurnitureLayer`. |
| `ui/designation_menu/designation_menu.gd` / `.tscn` | Scene/Script | Modal menu opened by hotkey `T`. Provides quick hotkeys 1-4 for flora orders, "+ New Area" button, and scrollable area roster with "Paint" and "Erase" actions. Registers with `UiGate`. |
| `ui/area_designation_hud/area_designation_hud.gd` / `.tscn` | Scene/Script | Passive HUD overlay mounted on `HUDLayer` (CanvasLayer 10). Displays active tool title (e.g. "CHOP TREES", "PAINT AREA (AREA 1)"), current stage ("Pick First Corner", "Pick Second Corner"), and controls guide. |
| `ui/colony_management/area_card.gd` / `.tscn` | Scene/Script | Colony Management UI card representing a single designated Area. Provides in-place renaming, box count and outer bounds display, member colonist management (add/remove), and area deletion. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `area_designation_toggled(active: bool)` | `Player` | `AreaDesignationController`, `AreaDesignationHud` | Yes | Controls activation of 3D placement mode and HUD visibility. |
| `area_designation_stage_changed(stage_name: String)` | `AreaDesignationController` | `AreaDesignationHud` | Yes | Emitted when transitioning between "pick corner A" and "pick corner B". |
| `area_designation_tool_selected(tool_id: String, target_area_id: String)` | `DesignationMenu` | `Player`, `AreaDesignationController` | Yes | Emitted on menu selection to enter 3D placement mode with the chosen tool. |
| `area_designation_tool_changed(tool_id: String, tool_label: String)` | `AreaDesignationController` | `AreaDesignationHud` | Yes | Emitted when active placement tool or target area changes to update HUD labels. |
| `area_modified()` | `AreaCard` | `ColonyManagement` | No | Direct scene signal to trigger area roster refresh on rename, member change, or deletion. |

## Flow Trace: Selecting Orders or Areas from Menu

**Trigger:** The player presses `T` during normal gameplay.

1. `InputComponent` receives `area_designation_toggle` and emits `area_designation_toggle_pressed`.
2. `Player` instantiates `DesignationMenu` onto `UILayer`.
3. `DesignationMenu` calls `UiGate.open_modal(self)` on `_ready()`, releasing the mouse cursor and gating gameplay inputs.
4. The player chooses an action via key (1: Remove Plants, 2: Chop Trees, 3: Forage, 4: Cancel Orders) or clicks an Area button ("+ New Area", "Paint", "Erase").
5. `DesignationMenu` emits `EventBus.area_designation_tool_selected(tool_id, target_area_id)` and closes (`queue_free()`), releasing the modal lock.
6. `Player` sets `mode = Mode.AREA_DESIGNATION` and emits `EventBus.area_designation_toggled(true)`.
7. `AreaDesignationController` sets `active_tool` and `target_area_id`, emits `EventBus.area_designation_tool_changed(tool_id, tool_label)`, and activates. If painting or erasing, it creates translucent highlight box meshes in the world showing the area's current footprint.
8. `AreaDesignationHud` updates its header to the active tool name and shows stage instructions.
9. First LMB click locks Corner A (`_stage = Stage.CORNER_A_PICKED`).
10. Moving the cursor stretches the `GhostPreview` box across X, Y, and Z (RMB cancels the locked Corner A and reverts to Stage 1).
11. Second LMB click commits the volume:
    - **New Area:** Calls `Colony.area_manager.create_area(min_cell, max_cell)`.
    - **Paint Area:** Calls `Colony.area_manager.paint_area(target_area_id, min_cell, max_cell)` and updates highlight meshes.
    - **Erase Area:** Calls `Colony.area_manager.erase_area(target_area_id, min_cell, max_cell)` and updates highlights.
    - **Chop Trees:** Queries `FurnitureLayer`, filters for trees (`has_tag("tree")`), sets `order_type = "chop"`, displays `[CHOP]` billboard, and creates harvesting job.
    - **Forage:** Queries `FurnitureLayer`, filters for bushes (`has_tag("bush")`), sets `order_type = "forage"`, displays `[FORAGE]` billboard, and creates harvesting job.
    - **Remove Plants:** Queries `FurnitureLayer` for all wild flora, sets `order_type = "remove"`, displays `[CLEAR]` billboard, and creates harvesting job.
    - **Cancel Orders:** Queries `FurnitureLayer` in the volume, unmarks harvestable flora, and clears billboards.
12. The controller resets to `Stage.IDLE` so the player can drag additional boxes immediately.
13. Pressing `T` leaves placement mode and returns to `DesignationMenu`; pressing `Esc` exits straight back to normal gameplay.

## Class Reference

### Class: Area

**Extends:** `RefCounted`  
**Script:** `subsystems/areas/area.gd`  
**Description:** Data entity encapsulating a designated world area composed of one or more 3D axis-aligned boxes. Holds assigned colonist IDs.  
**Used by:** `AreaManager`, `AreaDesignationController`, `AreaCard`  

**Properties:**

| Property | Type | Description |
|---|---|---|
| `id` | `String` | Unique UUID string. |
| `display_name` | `String` | User-visible area name (e.g. "Area 1", "Safe Room"). |
| `boxes` | `Array[Dictionary]` | Collection of non-overlapping boxes, each formatted as `{"min": Vector3i, "max": Vector3i}`. |
| `member_colonist_ids` | `Array[String]` | List of colonist IDs assigned to this area. |

**Functions:**

| Function | Description |
|---|---|
| `add_box(min_cell: Vector3i, max_cell: Vector3i) -> void` | Appends a normalized bounding box to the area's box collection. |
| `erase_box(erase_min: Vector3i, erase_max: Vector3i) -> void` | Subtracts a bounding box from the area using 3D integer CSG partitioning. |
| `is_empty_area() -> bool` | Returns true if the area contains zero boxes. |
| `contains_cell(cell: Vector3i) -> bool` | Returns true if `cell` falls inside any box belonging to this area. |
| `get_outer_bounds() -> Dictionary` | Computes `{min: Vector3i, max: Vector3i}` encompassing all constituent boxes. |
| `serialize() -> Dictionary` | Serializes fields to a JSON-compatible dictionary. |
| `static func from_dict(data: Dictionary) -> Area` | Factory constructing an Area from serialized dictionary data. |

### Class: AreaManager

**Extends:** `Node`  
**Script:** `subsystems/areas/area_manager.gd`  
**Description:** Manages the lifecycle, registry, spatial lookup, and persistence of all designated areas. Child node of `Colony`.  
**Used by:** `Colony`, `AreaDesignationController`, `ColonyManagement`, `DesignationMenu`  

**Functions:**

| Function | Description |
|---|---|
| `create_area(min_cell: Vector3i, max_cell: Vector3i, display_name: String = "") -> Area` | Normalizes corner coordinates, generates UUID, registers, and returns the new Area. |
| `paint_area(area_id: String, min_cell: Vector3i, max_cell: Vector3i) -> Area` | Adds a box volume to an existing area. |
| `erase_area(area_id: String, min_cell: Vector3i, max_cell: Vector3i) -> Area` | Subtracts a volume from an existing area, deleting the area if all boxes are removed. |
| `rename_area(area_id: String, new_name: String) -> void` | Renames the area with the specified ID. |
| `delete_area(area_id: String) -> void` | Removes the area from the registry. |
| `get_area(area_id: String) -> Area` | Returns the Area instance for `area_id`, or null if not found. |
| `get_all_areas() -> Array[Area]` | Returns all registered Area instances. |
| `get_areas_at(cell: Vector3i) -> Array[Area]` | Returns all areas containing `cell`. |
| `is_point_in_any_area(cell: Vector3i) -> bool` | Returns true if `cell` is inside at least one registered area. |
| `add_member(area_id: String, colonist_id: String) -> void` | Assigns a colonist to the area (deduplicated). |
| `remove_member(area_id: String, colonist_id: String) -> void` | Unassigns a colonist from the area. |
| `remove_member_from_all_areas(colonist_id: String) -> void` | Removes a colonist from all areas (called on colonist death/departure). |
| `get_members(area_id: String) -> Array[String]` | Returns duplicate array of assigned colonist IDs for the area. |
| `serialize() -> Dictionary` | Serializes all areas and the name counter. |
| `deserialize(data: Dictionary) -> void` | Restores areas and name counter from saved dictionary. |
| `reset_for_new_game() -> void` | Clears all registered areas and resets counter. |

### Class: AreaDesignationController

**Extends:** `Node3D`  
**Script:** `subsystems/areas/area_designation_controller.gd`  
**Description:** 3D viewport tool handling raycasting, stage state machine, preview rendering, in-world area highlight rendering, and action commits.  
**Used by:** `MapWiring`, `SceneManager`, `Player`  

**Functions:**

| Function | Description |
|---|---|
| `set_active(active: bool) -> void` | Activates or deactivates the designation controller. |
| `set_tool(tool_id: String, area_id: String = "") -> void` | Configures the active tool and target area ID, refreshing HUD readout and highlights. |
| `set_camera(camera: Camera3D) -> void` | Injects the player camera for raycasting. |
| `add_exclude_body(body: PhysicsBody3D) -> void` | Adds a physics body (player capsule) to raycast exclusion list. |
| `static func compute_area_bounds(corner_a: Vector3i, corner_b: Vector3i) -> Dictionary` | Pure static helper returning `{"min_cell": Vector3i, "max_cell": Vector3i}` normalized across X, Y, and Z. |
