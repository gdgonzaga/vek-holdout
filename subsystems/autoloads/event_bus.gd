extends Node
## Global signal relay for cross-scene events only (ARCH lines 92-108).
## No state. The full authoritative registry is declared here so later subsystems
## never need to edit this file — they only connect/emit.
##
## State-change signals (day_changed, pause_state_changed, etc.) do NOT go here;
## those live on GameState and are connected directly.

# --- Run lifecycle ---
signal run_started() # New Game flow -> seeders re-add defaults to RunProgress

# --- Time / day ---
signal day_rolled_over(new_day: int) # TimeSystem -> SaveSystem, HUD, raids

# --- Raids ---
signal raid_started(raid_data: Dictionary) # raids -> HUD, Colony, colonists
signal raid_ended(outcome: Dictionary) # raids -> HUD, Colony, save_system

# --- Expeditions ---
signal expedition_started(crew: Array, poi_id: String) # expeditions -> SceneManager, Colony, colonists
signal expedition_ended(result: Dictionary) # expeditions -> SceneManager, Colony, HUD

# --- Map swaps ---
signal map_loading(map_id: String) # SceneManager -> HUD (loading screen)
signal map_loaded(map_id: String) # SceneManager -> everyone (map ready)
signal map_unloading(map_id: String) # SceneManager -> save/cleanup

# --- Character death ---
signal colonist_died(colonist_id: String) # combat -> Colony, HUD, Memorial
signal player_died(context: String) # combat -> GameState, HUD
signal game_over() # GameState -> SceneManager

# --- Player / build / inventory ---
signal build_placement_toggled(active: bool) # player -> BuildController, HUD
signal build_menu_toggled(open: bool) # player -> HUD (build menu visibility for the Instructions label)
signal buildable_selected(id: String) # player -> BuildController (sets selected_id)
signal furniture_placed(def_id: String, anchor: Vector3i) # FurnitureLayer -> Colony (Functional Rooms, later)
signal furniture_removed(def_id: String, anchor: Vector3i) # FurnitureLayer -> Colony
signal blueprint_placed(target_def_id: String, anchor: Vector3i, blueprint: Node) # BlueprintLayer -> Colony (construction/haul Job + target node)
signal blueprint_removed(target_def_id: String, anchor: Vector3i) # BlueprintLayer -> JobBoard (cancel, later)
signal blueprint_materials_ready(target_def_id: String, anchor: Vector3i, blueprint: Node) # Blueprint.deposit_from -> Colony (spawn construction; single-fire per blueprint)
signal crafting_materials_ready(station: Node, anchor: Vector3i) # crafting station deposit_from -> Colony (spawn craft job; declared now, emitted by the planned CraftingStation)
signal item_picked_up(item_id: String, count: int) # inventory -> HUD
signal job_logged(entry: Dictionary) # colonists (Job Board) -> Job Log UI
