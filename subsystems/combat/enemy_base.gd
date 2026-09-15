class_name EnemyBase
extends CharacterBody3D
## Base class for all hostile entities (ARCH combat.md).
## Requires a HealthComponent child node.

@export var speed: float = 5.0
@export var gravity: float = 9.8
@export var moodlet_defs: Array[MoodletDef] = []

@onready var health_component: HealthComponent = $HealthComponent

## True once health_component has reached 0 HP (ARCH combat.md — mirrors the
## same flag on Player/Colonist so threat-scanning tasks can skip dead
## targets uniformly across actor types).
var is_dead: bool:
	get:
		return health_component.is_dead if health_component != null else false

var pathfinder: VoxelPathfinder
var bt_player: BTPlayer

const _StepClimberScript = preload("res://subsystems/core/step_climber.gd")
const _VisualizerScript = preload("res://subsystems/combat/enemy_moodlet_visualizer.gd")

const _ARRIVAL_THRESHOLD: float = 0.3
const _STEP_ARRIVAL_THRESHOLD: float = 0.2
var _path: Array[Vector3] = []
var _path_index: int = 0

var _stuck_timer: float = 0.0
var _wiggle_timer: float = 0.0
var _wiggle_dir: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group(&"enemies")
	floor_snap_length = 0.5
	collision_mask = 7
	if collision_layer == 4:
		collision_layer = 64
	
	# 1. Health Initialization: Binding entity death signals.
	_setup_health_component()
	
	# 2. AI Component Wiring: Ensuring pathfinder, step climber, and behavior tree player exist.
	_setup_ai_components()
	
	# 3. Moodlet Visualizer Setup: Ensuring billboard visualizer node is mounted.
	_setup_moodlet_visualizer()


func _physics_process(delta: float) -> void:
	# 1. Locomotion: Updating velocity vector along the active waypoint path.
	_follow_path(delta)
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


## Implements the IStatProvider contract (subsystems/core/i_stat_provider.gd)
## for its stat methods only — enemies have no activity moodlets, so
## get_current_activity is left at the interface's default.
##
## Returns the normalized (0.0 to 1.0) ratio for a given stat, or -1.0 if not found/uninitialized.
func get_stat_ratio(stat_name: StringName) -> float:
	# 1. Primary Resolution: Match against health ratio.
	return _resolve_stat_ratio(stat_name)


## Returns the raw scalar value for a given stat, or -1.0 if not found/uninitialized.
func get_stat_value(stat_name: StringName) -> float:
	# 1. Raw Resolution: Query raw numerical value for health or maximum health points.
	return _resolve_stat_value(stat_name)


## Returns all currently active moodlets evaluated from moodlet_defs in order.
## Each element is a Dictionary: { "def": MoodletDef, "index": int, "texture": Texture2D, "name": String }
func get_active_moodlets() -> Array[Dictionary]:
	if moodlet_defs.is_empty():
		return []
	
	# 1. Moodlet Collection: Iterate and collect active moodlets from definitions.
	return _evaluate_all_moodlets()


## Feed a world-space waypoint path from VoxelPathfinder or BT tasks.
func set_path(path: Array) -> void:
	_path.assign(path)
	_path_index = 0
	_stuck_timer = 0.0
	_wiggle_timer = 0.0


## Returns true when all waypoints in the path have been reached.
func has_arrived() -> bool:
	return _path_index >= _path.size()


## Convenience forwarder to HealthComponent.
func take_damage(amount: int, source: Node = null) -> void:
	if not health_component:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component:
		health_component.take_damage(amount, source)


func _on_entity_died(_entity: Node) -> void:
	queue_free()


## Persistence for SaveSystem.
func serialize() -> Dictionary:
	var data := {
		"position": [
			position.x, position.y, position.z
		],
		"velocity": [
			velocity.x, velocity.y, velocity.z
		],
	}
	if not health_component:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component:
		data["health"] = health_component.serialize()
	return data


func deserialize(data: Dictionary) -> void:
	if data.has("position"):
		var p: Array = data["position"]
		if p.size() >= 3:
			position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if data.has("velocity"):
		var v: Array = data["velocity"]
		if v.size() >= 3:
			velocity = Vector3(float(v[0]), float(v[1]), float(v[2]))
	if not health_component:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component and data.has("health"):
		health_component.deserialize(data["health"])


# =============================================================================
# Auxiliary Functions (Narrative Flow / Step-Down)
# =============================================================================

func _setup_health_component() -> void:
	## Auxiliary: Resolves HealthComponent and connects entity_died signal.
	if not health_component:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component:
		if not health_component.entity_died.is_connected(_on_entity_died):
			health_component.entity_died.connect(_on_entity_died)
	else:
		push_warning("EnemyBase: missing HealthComponent child node on %s" % name)


func _setup_ai_components() -> void:
	## Auxiliary: Instantiates or binds VoxelPathfinder, StepClimber, and BTPlayer components.
	pathfinder = get_node_or_null("VoxelPathfinder") as VoxelPathfinder
	if not pathfinder:
		pathfinder = VoxelPathfinder.new()
		pathfinder.name = "VoxelPathfinder"
		add_child(pathfinder)

	var step_climber := get_node_or_null("StepClimber") as StepClimber
	if not step_climber:
		step_climber = _StepClimberScript.new() as StepClimber
		step_climber.name = "StepClimber"
		step_climber.hop_height = 1.3
		step_climber.step_height = 0.5
		add_child(step_climber)
		
	bt_player = get_node_or_null("BTPlayer") as BTPlayer
	if not bt_player:
		bt_player = BTPlayer.new()
		bt_player.name = "BTPlayer"
		bt_player.set_scene_root_hint(self)
		bt_player.agent_node = NodePath("..")
		var tree_res: BehaviorTree = load("res://data/ai/trees/enemy_swarmer.tres") as BehaviorTree
		if tree_res:
			bt_player.behavior_tree = tree_res
		add_child(bt_player)


func _setup_moodlet_visualizer() -> void:
	## Auxiliary: Instantiates and binds EnemyMoodletVisualizer if not already attached.
	var visualizer := get_node_or_null("EnemyMoodletVisualizer") as EnemyMoodletVisualizer
	if not visualizer:
		visualizer = _VisualizerScript.new() as EnemyMoodletVisualizer
		visualizer.name = "EnemyMoodletVisualizer"
		add_child(visualizer)


func _follow_path(delta: float) -> void:
	## Auxiliary: Advances along waypoints in _path, updating horizontal velocity.
	if _path_index >= _path.size():
		velocity.x = 0.0
		velocity.z = 0.0
		_stuck_timer = 0.0
		_wiggle_timer = 0.0
		return
		
	var to_target: Vector3 = _path[_path_index] - global_position
	to_target.y = 0.0
	
	var threshold := _ARRIVAL_THRESHOLD
	var has_prev_step := _path_index > 0 and absf(_path[_path_index].y - _path[_path_index - 1].y) > 0.2
	var has_next_step := _path_index + 1 < _path.size() and absf(_path[_path_index + 1].y - _path[_path_index].y) > 0.2
	if has_prev_step or has_next_step:
		threshold = _STEP_ARRIVAL_THRESHOLD
		
	threshold = maxf(threshold, speed * delta * 1.2)
		
	if to_target.length() <= threshold:
		_path_index += 1
		_stuck_timer = 0.0
		_wiggle_timer = 0.0
		if _path_index >= _path.size():
			velocity.x = 0.0
			velocity.z = 0.0
			return
		to_target = _path[_path_index] - global_position
		to_target.y = 0.0
		
	var dir: Vector3 = to_target.normalized()

	# 1. Obstacle Recovery: Applies slight sideways wiggle if body is pressed against a wall.
	if _wiggle_timer > 0.0:
		_wiggle_timer -= delta
		dir = _wiggle_dir
	else:
		var horiz_vel := Vector2(velocity.x, velocity.z)
		if is_on_wall() and horiz_vel.length_squared() < (speed * 0.1) ** 2:
			_stuck_timer += delta
			if _stuck_timer > 0.3:
				_stuck_timer = 0.0
				_wiggle_timer = 0.4 + randf() * 0.2
				var wall_normal := get_wall_normal()
				wall_normal.y = 0.0
				if wall_normal.length_squared() > 0.01:
					_wiggle_dir = Vector3(-wall_normal.z, 0.0, wall_normal.x).normalized()
					if randf() < 0.5:
						_wiggle_dir = -_wiggle_dir
				else:
					_wiggle_dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed


func _resolve_stat_ratio(stat_name: StringName) -> float:
	## Auxiliary: Resolves normalized 0.0 to 1.0 ratio for health.
	match stat_name:
		&"hp", &"health":
			if not health_component:
				health_component = get_node_or_null("HealthComponent") as HealthComponent
			if health_component != null and health_component.max_hp > 0:
				return float(health_component.current_hp) / float(health_component.max_hp)
			return 0.0
		_:
			return -1.0


func _resolve_stat_value(stat_name: StringName) -> float:
	## Auxiliary: Resolves raw numerical value for health or max health.
	match stat_name:
		&"hp", &"health":
			if not health_component:
				health_component = get_node_or_null("HealthComponent") as HealthComponent
			if health_component != null:
				return float(health_component.current_hp)
			return -1.0
		&"max_hp", &"max_health":
			if not health_component:
				health_component = get_node_or_null("HealthComponent") as HealthComponent
			if health_component != null:
				return float(health_component.max_hp)
			return -1.0
		_:
			return -1.0


func _evaluate_all_moodlets() -> Array[Dictionary]:
	## Auxiliary: Delegates moodlet evaluation to the shared layout resolver
	## (also used by Colonist/WildFlora — keeps the active-list shape and the
	## null-texture filter in one place instead of three drifting copies).
	return MoodletLayoutResolver.evaluate_active_moodlets(self, moodlet_defs)

