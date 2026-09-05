class_name TurretComponent
extends Node3D
## Automated defensive turret capability component (GDD §7.10, ARCH combat.md).
## Attached under a Furniture by FurnitureLayer when its def declares turret_params.
## Scans for hostile targets within range, consumes ammunition from local or
## colony storage, and fires physical projectiles at the closest hostile.

signal projectile_fired(projectile: TurretProjectile, target: Node3D)

## Back-reference to the capability definition. Set from parent Furniture def at _ready.
var params: TurretParams = null

var _cooldown_remaining: float = 0.0


func _ready() -> void:
	_apply_turret_params()


func _apply_turret_params() -> void:
	var furniture := get_parent() as Furniture
	if furniture == null or furniture.def == null:
		return
	if furniture.def is FurnitureDef:
		var fdef := furniture.def as FurnitureDef
		if fdef.turret_params != null:
			params = fdef.turret_params


func _physics_process(delta: float) -> void:
	_tick(delta)


## Tick cooldown and targeting logic. Extracted so unit tests can step manually.
func _tick(delta: float) -> void:
	if params == null:
		return

	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

	var target := find_closest_target()
	if target != null:
		_aim_at(target, delta)
		if _cooldown_remaining <= 0.0:
			if _try_consume_ammo():
				_fire_at(target)
				_cooldown_remaining = 1.0 / maxf(params.fire_rate, 0.001)


## Smoothly rotates TurretYaw and TurretPitch towards the target position.
func _aim_at(target: Node3D, delta: float) -> void:
	if target == null or params == null:
		return

	var yaw_node := _find_yaw_node()
	var pitch_node := _find_pitch_node()
	var speed := maxf(params.turn_speed, 0.01)

	# 1. YAW ROTATION (Horizontal around local Y axis)
	if yaw_node != null:
		var local_target := yaw_node.to_local(target.global_position)
		var target_yaw_angle := atan2(-local_target.x, -local_target.z)
		yaw_node.rotation.y = rotate_toward(
			yaw_node.rotation.y,
			yaw_node.rotation.y + target_yaw_angle,
			speed * delta
		)

	# 2. PITCH ROTATION (Vertical around local X axis)
	if pitch_node != null:
		var local_target := pitch_node.to_local(target.global_position)
		var distance_xz := Vector2(local_target.x, local_target.z).length()
		var target_pitch_angle := atan2(local_target.y, distance_xz)

		var min_pitch := deg_to_rad(params.min_pitch_deg)
		var max_pitch := deg_to_rad(params.max_pitch_deg)
		var desired_pitch := clampf(target_pitch_angle, min_pitch, max_pitch)

		pitch_node.rotation.x = rotate_toward(
			pitch_node.rotation.x,
			desired_pitch,
			speed * delta
		)


func _find_yaw_node() -> Node3D:
	var parent_node := get_parent()
	if parent_node != null:
		var yaw := parent_node.find_child("TurretYaw", true, false) as Node3D
		if yaw == null:
			yaw = parent_node.find_child("Yaw", true, false) as Node3D
		if yaw != null:
			return yaw
	var local_yaw := find_child("TurretYaw", true, false) as Node3D
	if local_yaw == null:
		local_yaw = find_child("Yaw", true, false) as Node3D
	return local_yaw


func _find_pitch_node() -> Node3D:
	var parent_node := get_parent()
	if parent_node != null:
		var pitch := parent_node.find_child("TurretPitch", true, false) as Node3D
		if pitch == null:
			pitch = parent_node.find_child("Pitch", true, false) as Node3D
		if pitch != null:
			return pitch
	var local_pitch := find_child("TurretPitch", true, false) as Node3D
	if local_pitch == null:
		local_pitch = find_child("Pitch", true, false) as Node3D
	return local_pitch


## Finds the closest active hostile entity within range.
func find_closest_target() -> Node3D:
	if params == null:
		return null

	var tree := get_tree()
	if tree == null:
		return null

	var enemies := tree.get_nodes_in_group(&"enemies")
	var best_target: Node3D = null
	var best_dist_sq: float = params.range * params.range

	for node in enemies:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var enemy_node := node as Node3D

		# Check if dead
		var health := enemy_node.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.is_dead:
			continue

		var dist_sq := global_position.distance_squared_to(enemy_node.global_position)
		if dist_sq <= best_dist_sq:
			best_target = enemy_node
			best_dist_sq = dist_sq

	return best_target


## Consumes 1 unit of required ammunition. Checks local StorageInventory first,
## then falls back to Colony.storage_registry. Returns true if consumed or if no ammo required.
func _try_consume_ammo() -> bool:
	if params == null or params.ammo_type == null:
		return true

	var ammo_id := params.ammo_type.id
	if ammo_id == "":
		return true

	# 1. Local storage on the same furniture
	var parent_node := get_parent()
	if parent_node != null:
		var local_storage := parent_node.get_node_or_null("StorageInventory") as StorageInventory
		if local_storage != null and local_storage.has_item(ammo_id, 1):
			return local_storage.remove(ammo_id, 1) == 0

	# 2. Colony communal storage registry
	if Colony != null and Colony.storage_registry != null:
		var crate := Colony.storage_registry.find_source([ammo_id], global_position)
		if crate != null:
			var crate_inv := Colony.storage_registry.inventory_of(crate)
			if crate_inv != null and crate_inv.has_item(ammo_id, 1):
				return crate_inv.remove(ammo_id, 1) == 0

	return false


## Returns the world position from which projectiles are launched.
## Checks for a node named "Muzzle" under the parent furniture hierarchy first.
## If absent, falls back to evaluating params.muzzle_offset relative to the turret's orientation.
func get_muzzle_position() -> Vector3:
	var muzzle_node := _find_muzzle_node()
	if muzzle_node != null:
		return muzzle_node.global_position

	var offset := params.muzzle_offset if params != null else Vector3(0, 2.0, 0)
	return global_transform * offset


func _find_muzzle_node() -> Node3D:
	var parent_node := get_parent()
	if parent_node != null:
		var muzzle := parent_node.find_child("Muzzle", true, false) as Node3D
		if muzzle != null:
			return muzzle
	return find_child("Muzzle", true, false) as Node3D


func _fire_at(target: Node3D) -> TurretProjectile:
	var projectile := TurretProjectile.new()
	var spawn_parent: Node = null
	if get_tree() != null and get_tree().current_scene != null:
		spawn_parent = get_tree().current_scene
	elif get_parent() != null:
		spawn_parent = get_parent()
	else:
		spawn_parent = self

	spawn_parent.add_child(projectile)

	var spawn_pos := get_muzzle_position()
	var origin_xform := Transform3D(Basis(), spawn_pos)
	var dir := spawn_pos.direction_to(target.global_position)
	if dir == Vector3.ZERO:
		dir = -global_transform.basis.z

	var source_node: Node = get_parent() if get_parent() != null else self
	projectile.setup(origin_xform, dir, params, source_node)
	projectile_fired.emit(projectile, target)
	return projectile
