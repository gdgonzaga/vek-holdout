extends Node
## Global signal relay for cross-scene events only (ARCH lines 92-108).
## No state. The full authoritative registry is declared here so later subsystems
## never need to edit this file — they only connect/emit.
##
## State-change signals (day_changed, pause_state_changed, etc.) do NOT go here;
## those live on GameState and are connected directly.

# --- Run lifecycle ---
signal run_started()                             # New Game flow -> seeders re-add defaults to RunProgress

# --- Time / day ---
signal day_rolled_over(new_day: int)              # TimeSystem -> SaveSystem, HUD, raids

# --- Raids ---
signal raid_started(raid_data: Dictionary)        # raids -> HUD, Colony, colonists
signal raid_ended(outcome: Dictionary)            # raids -> HUD, Colony, save_system

# --- Expeditions ---
signal expedition_started(crew: Array, poi_id: String)  # expeditions -> SceneManager, Colony, colonists
signal expedition_ended(result: Dictionary)             # expeditions -> SceneManager, Colony, HUD

# --- Map swaps ---
signal map_loading(map_id: String)            # SceneManager -> HUD (loading screen)
signal map_loaded(map_id: String)             # SceneManager -> everyone (map ready)
signal map_unloading(map_id: String)          # SceneManager -> save/cleanup

# --- Character death ---
signal colonist_died(colonist_id: String)         # combat -> Colony, HUD, Memorial
signal player_died(context: String)               # combat -> GameState, HUD
signal game_over()                                # GameState -> SceneManager

# --- Player / build / inventory ---
signal blueprint_mode_toggled(active: bool)       # player -> BuildController, HUD
signal buildable_selected(id: String)             # player -> BuildController (sets selected_id)
signal furniture_placed(def_id: String, anchor: Vector3i)  # FurnitureLayer -> Colony (Functional Rooms, later)
signal furniture_removed(def_id: String, anchor: Vector3i) # FurnitureLayer -> Colony
signal item_picked_up(item_id: String, count: int) # inventory -> HUD
signal job_logged(entry: Dictionary)              # colonists (Job Board) -> Job Log UI
