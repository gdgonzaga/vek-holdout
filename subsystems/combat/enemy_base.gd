class_name EnemyBase
extends CharacterBody3D
## Base class for all hostile entities (ARCH combat.md).
## Requires a HealthComponent child node.

@export var speed: float = 5.0
@export var gravity: float = 9.8

@onready var health_component: HealthComponent = $HealthComponent

var pathfinder: VoxelPathfinder
var bt_player: BTPlayer

const _ARRIVAL_THRESHOLD: float = 0.2
const _STEP_ARRIVAL_THRESHOLD: float = 0.08
var _path: Array[Vector3] = []
var _path_index: int = 0


func _ready() -> void:
	add_to_group(&"enemies")
	
	# 1. Health Initialization: Binding entity death signals.
	_setup_health_component()
	
	# 2. AI Component Wiring: Ensuring pathfinder and behavior tree player exist.
	_setup_ai_components()


func _physics_process(delta: float) -> void:
	# 1. Locomotion: Updating velocity vector along the active waypoint path.
	_follow_path(delta)
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


## Feed a world-space waypoint path from VoxelPathfinder or BT tasks.
func set_path(path: Array) -> void:
	_path.assign(path)
	_path_index = 0


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
	## Auxiliary: Instantiates or binds VoxelPathfinder and BTPlayer components.
	pathfinder = get_node_or_null("VoxelPathfinder") as VoxelPathfinder
	if not pathfinder:
		pathfinder = VoxelPathfinder.new()
		pathfinder.name = "VoxelPathfinder"
		add_child(pathfinder)
		
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


func _follow_path(delta: float) -> void:

	## Auxiliary: Advances along waypoints in _path, updating horizontal velocity.
	if _path_index >= _path.size():
		velocity.x = 0.0
		velocity.z = 0.0
		return
		
	var to_target: Vector3 = _path[_path_index] - global_position
	to_target.y = 0.0
	
	var threshold := _ARRIVAL_THRESHOLD
	var has_prev_step := _path_index > 0 and absf(_path[_path_index].y - _path[_path_index - 1].y) > 0.2
	var has_next_step := _path_index + 1 < _path.size() and absf(_path[_path_index + 1].y - _path[_path_index].y) > 0.2
	if has_prev_step or has_next_step:
		threshold = _STEP_ARRIVAL_THRESHOLD
		
	if to_target.length() <= threshold:
		_path_index += 1
		if _path_index >= _path.size():
			velocity.x = 0.0
			velocity.z = 0.0
			return
		to_target = _path[_path_index] - global_position
		to_target.y = 0.0
		
	var dir: Vector3 = to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

