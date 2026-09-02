extends Node
## Run-level state holder (ARCH "Class: GameState", lines 278-308).
## Holds current day, scene id, pause state, save slot, pathfinding strategy. Emits signals on its own
## state changes — these are NOT routed through EventBus (connected directly).
## Does NOT own save logic (that's SaveSystem) or time advance (that's TimeSystem).

enum PathfindingStrategyType {
	SMOOTHED_A_STAR,
	A_STAR_8_WAY,
	A_STAR_4_WAY,
	THETA_STAR,
}

signal day_changed(new_day: int)
signal scene_changed(scene_id: String)
signal pause_state_changed(paused: bool)
signal save_slot_changed(slot_name: String)
signal pathfinding_strategy_changed(new_type: int)

const _AStar4WayScript = preload("res://subsystems/colonists/pathfinding/a_star_4_way_strategy.gd")
const _AStar8WayScript = preload("res://subsystems/colonists/pathfinding/a_star_8_way_strategy.gd")
const _SmoothedAStarScript = preload("res://subsystems/colonists/pathfinding/smoothed_a_star_strategy.gd")
const _ThetaStarScript = preload("res://subsystems/colonists/pathfinding/theta_star_strategy.gd")

@export var current_day: int = 1
var current_scene_id: String = "base"
var paused: bool = false
var save_slot: String = ""

## Global pathfinding strategy setting for all colonist agents.
var pathfinding_strategy: PathfindingStrategyType = PathfindingStrategyType.THETA_STAR

## Central RNG instance for deterministic gameplay randomness across clients.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Active local player reference (null if not spawned).
var local_player: Node = null

## Reference to the MapRoot whose children get process_mode-toggled on pause.
## Set by Main when it mounts the MapRoot. Null until then.
var map_root: Node = null


func _ready() -> void:
	rng.randomize()


## Returns the active local player node.
func get_local_player() -> Node:
	return local_player


## Sets the active local player node.
func set_local_player(p: Node) -> void:
	local_player = p


func set_paused(p: bool) -> void:
	if paused == p:
		return
	paused = p
	if map_root != null:
		map_root.process_mode = Node.PROCESS_MODE_DISABLED if p else Node.PROCESS_MODE_INHERIT
	pause_state_changed.emit(p)


## Increments the day counter; emits day_changed. Called by TimeSystem on midnight.
func advance_day() -> void:
	current_day += 1
	day_changed.emit(current_day)


## Sets the current scene id; emits scene_changed. Called by SceneManager on swap
## completion. (ARCH documents scene_changed but no setter — this fills that gap.)
func set_scene_id(scene_id: String) -> void:
	current_scene_id = scene_id
	scene_changed.emit(scene_id)


## Sets the active save slot; emits save_slot_changed. Called on New Game / Load.
func set_save_slot(slot_name: String) -> void:
	save_slot = slot_name
	save_slot_changed.emit(slot_name)


## Instantiates a new PathfindingStrategy corresponding to the active setting.
func create_pathfinding_strategy() -> PathfindingStrategy:
	match pathfinding_strategy:
		PathfindingStrategyType.A_STAR_4_WAY:
			return _AStar4WayScript.new()
		PathfindingStrategyType.A_STAR_8_WAY:
			return _AStar8WayScript.new()
		PathfindingStrategyType.THETA_STAR:
			return _ThetaStarScript.new()
		PathfindingStrategyType.SMOOTHED_A_STAR, _:
			return _SmoothedAStarScript.new()


## Sets the active pathfinding strategy and updates all live colonists.
func set_pathfinding_strategy(new_type: PathfindingStrategyType) -> void:
	if pathfinding_strategy == new_type:
		return
	pathfinding_strategy = new_type
	pathfinding_strategy_changed.emit(new_type)

	var colony: Node = get_node_or_null("/root/Colony")
	if colony != null and "colonists" in colony:
		for c in colony.colonists:
			if is_instance_valid(c) and "pathfinder" in c and c.pathfinder != null:
				c.pathfinder.set_strategy(create_pathfinding_strategy())


# --- SaveSystem contract -----------------------------------------------------
# Persisted run framing: the current day and which map is active. save_slot is
# orchestrator-owned (the active slot, not run state), paused/map_root are
# transient/runtime refs.

func serialize() -> Dictionary:
	return {
		"day": current_day,
		"scene_id": current_scene_id,
		"pathfinding_strategy": int(pathfinding_strategy),
	}


func deserialize(data: Dictionary) -> void:
	current_day = int(data.get("day", current_day))
	day_changed.emit(current_day)
	set_scene_id(data.get("scene_id", current_scene_id))
	if data.has("pathfinding_strategy"):
		set_pathfinding_strategy(int(data["pathfinding_strategy"]) as PathfindingStrategyType)
