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

	if _cooldown_remaining <= 0.0:
		var target := find_closest_target()
		if target != null:
			if _try_consume_ammo():
				_fire_at(target)
				_cooldown_remaining = 1.0 / maxf(params.fire_rate, 0.001)


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

	var spawn_pos := global_position + Vector3(0, 0.5, 0)
	var origin_xform := Transform3D(Basis(), spawn_pos)
	var dir := spawn_pos.direction_to(target.global_position)
	if dir == Vector3.ZERO:
		dir = -global_transform.basis.z

	projectile.setup(origin_xform, dir, params, self)
	projectile_fired.emit(projectile, target)
	return projectile
