class_name WorldItem
extends RigidBody3D
## Represents an item dropped into the 3D world with physical simulation.
## Supports manual player pickup via InteractionComponent, and intentional
## pickup by colonists executing hauling jobs.

const SCENE_PATH := "res://subsystems/inventory/world_item.tscn"

@export var item_id: String = ""
@export var count: int = 1
@export var forbidden: bool = false: set = set_forbidden
@export var urgent_haul: bool = false: set = set_urgent_haul

signal forbidden_changed(is_forbidden: bool)
signal urgent_haul_changed(is_urgent: bool)
signal reservation_changed(is_reserved: bool, claimer: Variant)
signal count_changed(new_count: int)

@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
@onready var interaction: InteractionComponent = get_node_or_null("InteractionComponent") as InteractionComponent

var _pickup_option: ActionOption
var _forbid_option: ActionOption
var _reserved_by: Variant = null


func _ready() -> void:
	add_to_group("world_items")
	collision_layer = 16  # Layer 5 (Build/Interactable)
	collision_mask = 7   # Layers 1 (World) | 2 (Blocky) | 3 (Smooth)
	continuous_cd = true

	_setup_interaction()
	update_visuals_and_interaction()
	_register_with_colony()


func _exit_tree() -> void:
	_unregister_from_colony()
	unreserve()


func setup(p_item_id: String, p_count: int = 1, p_forbidden: bool = false) -> void:
	item_id = p_item_id
	count = maxi(1, p_count)
	forbidden = p_forbidden
	if is_node_ready():
		update_visuals_and_interaction()
		_register_with_colony()


func set_forbidden(value: bool) -> void:
	if forbidden == value:
		return
	forbidden = value
	if forbidden:
		unreserve()
	forbidden_changed.emit(forbidden)
	if is_node_ready():
		update_visuals_and_interaction()


func is_forbidden() -> bool:
	return forbidden


func set_urgent_haul(value: bool) -> void:
	if urgent_haul == value:
		return
	urgent_haul = value
	urgent_haul_changed.emit(urgent_haul)


func is_urgent_haul() -> bool:
	return urgent_haul


## Attempts to reserve this item for a worker or job. Returns true if reservation was granted.
func reserve(claimer: Variant) -> bool:
	if forbidden or count <= 0:
		return false
	if is_reserved():
		return _is_same_claimer(_reserved_by, claimer)
	_reserved_by = claimer
	reservation_changed.emit(true, claimer)
	return true


## Releases the active reservation if claimer matches (or if claimer is null / forced release).
func unreserve(claimer: Variant = null) -> void:
	if not is_reserved():
		return
	if claimer == null or _is_same_claimer(_reserved_by, claimer):
		var prev: Variant = _reserved_by
		_reserved_by = null
		reservation_changed.emit(false, prev)


## True if this item is currently reserved by an active claimer.
func is_reserved() -> bool:
	if _reserved_by == null:
		return false
	if _reserved_by is Object and not is_instance_valid(_reserved_by):
		_reserved_by = null
		return false
	return true


## Returns the active claimer, or null if unreserved.
func get_claimer() -> Variant:
	return _reserved_by if is_reserved() else null


## True if this item is reserved by `claimer`.
func is_reserved_by(claimer: Variant) -> bool:
	return is_reserved() and _is_same_claimer(_reserved_by, claimer)


## True if item is eligible to be picked up and hauled into storage.
func is_available_for_hauling() -> bool:
	return not forbidden and not is_reserved() and count > 0 and is_inside_tree() and not is_queued_for_deletion()


## Hides visual mesh and disables collisions without freeing node immediately (used during multi-step transfers).
func hide_item() -> void:
	visible = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = FREEZE_MODE_STATIC
	freeze = true
	sleeping = true
	collision_layer = 0
	collision_mask = 0
	var col := collision_shape
	if col == null:
		col = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.disabled = true
		col.set_deferred("disabled", true)
	if interaction != null:
		interaction.process_mode = Node.PROCESS_MODE_DISABLED
	remove_from_group("world_items")


func show_item() -> void:
	visible = true
	freeze = false
	sleeping = false
	collision_layer = 16
	collision_mask = 7
	var col := collision_shape
	if col == null:
		col = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.disabled = false
		col.set_deferred("disabled", false)
	if interaction != null:
		interaction.process_mode = Node.PROCESS_MODE_INHERIT
	add_to_group("world_items")


func _is_same_claimer(a: Variant, b: Variant) -> bool:
	if a == b:
		return true
	if a is Object and b is Object:
		return a == b
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	return false


func _register_with_colony() -> void:
	var colony: Node = get_node_or_null("/root/Colony")
	if colony != null and colony.has_method("register_world_item"):
		colony.call("register_world_item", self)


func _unregister_from_colony() -> void:
	var colony: Node = get_node_or_null("/root/Colony")
	if colony != null and colony.has_method("unregister_world_item"):
		colony.call("unregister_world_item", self)


func _setup_interaction() -> void:
	if interaction == null:
		interaction = get_node_or_null("InteractionComponent") as InteractionComponent
	if interaction == null:
		interaction = InteractionComponent.new()
		interaction.name = "InteractionComponent"
		add_child(interaction)

	var pickup_act := PickupAction.new()
	_pickup_option = ActionOption.new()
	_pickup_option.action = pickup_act

	var forbid_act := ToggleForbiddenAction.new()
	_forbid_option = ActionOption.new()
	_forbid_option.action = forbid_act

	interaction.action_options = [_pickup_option, _forbid_option]


func update_visuals_and_interaction() -> void:
	var def := ItemDB.get_def(item_id) if ItemDB != null else null
	var display_name := def.id if def != null and def.id != "" else (item_id if item_id != "" else "Item")

	if interaction != null:
		var status := " [Forbidden]" if forbidden else ""
		interaction.display_name = "%s (x%d)%s" % [display_name, count, status]
		interaction.info_text = "Forbidden from hauling" if forbidden else ""

	if mesh_instance != null:
		_apply_mesh(def)
	_apply_collision(def)


func _apply_mesh(def: ItemDef) -> void:
	if def != null and def.mesh != null:
		mesh_instance.mesh = def.mesh
		mesh_instance.scale = def.visual_scale if def.visual_scale != Vector3.ZERO else Vector3.ONE
		if def.material != null:
			mesh_instance.material_override = def.material
		else:
			mesh_instance.material_override = null
	else:
		if mesh_instance.mesh == null or not (mesh_instance.mesh is BoxMesh):
			var box := BoxMesh.new()
			box.size = Vector3(0.3, 0.3, 0.3)
			mesh_instance.mesh = box
		mesh_instance.scale = Vector3.ONE
		if mesh_instance.material_override == null:
			mesh_instance.material_override = StandardMaterial3D.new()

	if forbidden:
		var mat := mesh_instance.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh_instance.material_override = mat
		mat.albedo_color = Color(0.85, 0.25, 0.2)
	elif def == null or (def.mesh == null and def.material == null):
		var mat := mesh_instance.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.8, 0.65, 0.4)


func _apply_collision(def: ItemDef) -> void:
	if collision_shape == null:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		return

	var box := BoxShape3D.new()
	if def != null and def.mesh != null:
		var aabb: AABB = def.mesh.get_aabb()
		var v_scale: Vector3 = def.visual_scale if def.visual_scale != Vector3.ZERO else Vector3.ONE
		box.size = Vector3(
			maxf(0.15, absf(aabb.size.x * v_scale.x)),
			maxf(0.15, absf(aabb.size.y * v_scale.y)),
			maxf(0.15, absf(aabb.size.z * v_scale.z))
		)
		collision_shape.position = aabb.get_center() * v_scale
	else:
		box.size = Vector3(0.3, 0.3, 0.3)
		collision_shape.position = Vector3.ZERO
	collision_shape.shape = box


func wake_up() -> void:
	freeze = false
	sleeping = false


static func get_nearby_unreserved(tree: SceneTree, center: Vector3, p_item_id: String = "", radius: float = 12.0) -> Array[WorldItem]:
	var result: Array[WorldItem] = []
	if tree == null:
		return result
	var radius_sq := radius * radius
	for node in tree.get_nodes_in_group("world_items"):
		var item := node as WorldItem
		if item != null and is_instance_valid(item) and item.is_inside_tree() and not item.is_queued_for_deletion():
			if not item.is_forbidden() and not item.is_reserved() and item.count > 0 and item.visible:
				if p_item_id == "" or item.item_id == p_item_id:
					if item.global_position.distance_squared_to(center) <= radius_sq:
						result.append(item)
	return result


static func wake_items_near(tree: SceneTree, center: Vector3, radius: float = 2.5) -> void:
	if tree == null:
		return
	var radius_sq := radius * radius
	for node in tree.get_nodes_in_group("world_items"):
		var item := node as WorldItem
		if item != null and is_instance_valid(item) and item.is_inside_tree():
			if item.global_position.distance_squared_to(center) <= radius_sq:
				item.wake_up()


static func spawn_at(
	tree_or_node: Variant,
	p_item_id: String,
	p_count: int,
	pos: Vector3,
	impulse_dir: Vector3 = Vector3.UP,
	strength: float = 2.5
) -> WorldItem:
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		push_error("WorldItem: Could not load scene at %s" % SCENE_PATH)
		return null

	var item := scene.instantiate() as WorldItem
	item.setup(p_item_id, p_count)
	item.position = pos

	var parent: Node = null
	if tree_or_node is SceneTree:
		if tree_or_node.current_scene != null:
			parent = tree_or_node.current_scene
		elif tree_or_node.root != null:
			parent = tree_or_node.root
	elif tree_or_node is Node:
		parent = tree_or_node

	if parent != null:
		var items_layer := parent.find_child("ItemsLayer", true, false)
		if items_layer != null:
			items_layer.add_child(item)
		else:
			parent.add_child(item)

	var effective_impulse_dir := impulse_dir

	if item.is_inside_tree() and item.get_world_3d() != null:
		var space_state := item.get_world_3d().direct_space_state
		if space_state != null:
			# 1. Cast ray downward to find ground/slope surface and normal
			var ray_query := PhysicsRayQueryParameters3D.create(
				pos + Vector3(0.0, 1.5, 0.0),
				pos - Vector3(0.0, 2.0, 0.0),
				7  # Layers 1 (World) | 2 (Blocky) | 3 (Smooth)
			)
			var ray_hit := space_state.intersect_ray(ray_query)
			var surface_normal := Vector3.UP

			if not ray_hit.is_empty():
				surface_normal = (ray_hit.get("normal", Vector3.UP) as Vector3).normalized()
				var half_height := 0.15
				var col_shape := item.collision_shape
				if col_shape == null:
					col_shape = item.get_node_or_null("CollisionShape3D") as CollisionShape3D
				if col_shape != null and col_shape.shape is BoxShape3D:
					half_height = (col_shape.shape as BoxShape3D).size.y * 0.5
				var hit_pos: Vector3 = ray_hit.get("position", pos)
				item.global_position = hit_pos + surface_normal * (half_height + 0.1)

			# 2. Check if shape still overlaps any geometry and depenetrate outward
			var col_shape_check := item.collision_shape
			if col_shape_check == null:
				col_shape_check = item.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if col_shape_check != null and col_shape_check.shape != null:
				var shape_query := PhysicsShapeQueryParameters3D.new()
				shape_query.shape = col_shape_check.shape
				shape_query.transform = item.global_transform
				shape_query.collision_mask = 7

				var rest_info := space_state.get_rest_info(shape_query)
				if not rest_info.is_empty():
					var push_normal: Vector3 = (rest_info.get("normal", Vector3.UP) as Vector3).normalized()
					if push_normal.is_zero_approx():
						push_normal = surface_normal
					var contact_point: Vector3 = rest_info.get("point", item.global_position)
					var half_extent := 0.2
					if col_shape_check.shape is BoxShape3D:
						half_extent = (col_shape_check.shape as BoxShape3D).size.length() * 0.5
					item.global_position = contact_point + push_normal * (half_extent + 0.1)
					surface_normal = push_normal

			effective_impulse_dir = (impulse_dir.normalized() + surface_normal).normalized()

		if strength > 0.0:
			var rand_offset := Vector3(randf_range(-0.2, 0.2), randf_range(0.3, 0.7), randf_range(-0.2, 0.2))
			var final_impulse := (effective_impulse_dir + rand_offset).normalized() * strength
			item.apply_central_impulse(final_impulse)
			item.apply_torque_impulse(Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)))

	return item
