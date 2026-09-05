class_name TurretProjectile
extends Area3D
## Physical projectile fired by turrets (ARCH combat.md).
## Moves forward along its velocity vector each physics frame. Deals direct
## damage on contact (REGULAR) or area-of-effect splash damage (EXPLOSIVE).

@export var speed: float = 25.0
@export var damage: int = 10
@export var projectile_type: TurretParams.ProjectileType = TurretParams.ProjectileType.REGULAR
@export var explosion_radius: float = 3.0
@export var max_lifetime: float = 10.0

var _velocity: Vector3 = Vector3.ZERO
var _lifetime: float = 0.0
var _source_turret: Node = null
var _exploded: bool = false


func setup(
	origin_transform: Transform3D,
	direction: Vector3,
	params: TurretParams,
	source: Node = null
) -> void:
	global_transform = origin_transform
	_source_turret = source
	if params != null:
		speed = params.projectile_speed
		damage = params.damage
		projectile_type = params.projectile_type
		explosion_radius = params.explosion_radius
		var scene_to_use: PackedScene = params.projectile_scene
		var mesh_to_use: Mesh = params.projectile_mesh
		var mat_to_use: Material = params.projectile_material
		if scene_to_use == null and mesh_to_use == null and params.ammo_type != null:
			scene_to_use = params.ammo_type.scene
			mesh_to_use = params.ammo_type.mesh
			if mat_to_use == null:
				mat_to_use = params.ammo_type.material
		_apply_visual(mesh_to_use, mat_to_use, scene_to_use)
	var dir_norm := direction.normalized()
	if dir_norm != Vector3.ZERO:
		_velocity = dir_norm * speed
		var up := Vector3.UP if abs(dir_norm.y) < 0.99 else Vector3.FORWARD
		if is_inside_tree():
			look_at(global_position + dir_norm, up)
		else:
			basis = Basis.looking_at(dir_norm, up)


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_mask = 1 | 2 | 4 | 64
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	global_position += _velocity * delta
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	_handle_impact(body)


func _on_area_entered(area: Area3D) -> void:
	_handle_impact(area)


func _handle_impact(hit_node: Node) -> void:
	if _exploded:
		return
	if _is_source_or_descendant(hit_node):
		return

	_exploded = true
	if projectile_type == TurretParams.ProjectileType.EXPLOSIVE:
		_explode()
	else:
		_apply_direct_damage(hit_node)

	queue_free()


func _apply_direct_damage(hit_node: Node) -> void:
	var target: Node = hit_node
	while target != null:
		if target.has_method("take_damage"):
			target.take_damage(damage, _source_turret)
			break
		var health := target.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			health.take_damage(damage, _source_turret)
			break
		target = target.get_parent()


func _explode() -> void:
	var damaged_targets: Array[Node] = []
	var world_3d := get_world_3d()
	if world_3d != null and world_3d.direct_space_state != null:
		var space_state := world_3d.direct_space_state
		var shape := SphereShape3D.new()
		shape.radius = explosion_radius

		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = global_transform
		query.collide_with_bodies = true
		query.collide_with_areas = true

		var hits := space_state.intersect_shape(query, 64)
		for hit in hits:
			var collider: Node = hit.collider as Node
			if collider == null or _is_source_or_descendant(collider):
				continue
			var root_target := _find_damageable(collider)
			if root_target != null and not damaged_targets.has(root_target):
				damaged_targets.append(root_target)
				_damage_target(root_target)

	# Fallback/supplement for test harness or entities not caught in physics intersect_shape
	var tree := get_tree()
	if tree != null:
		for enemy in tree.get_nodes_in_group(&"enemies"):
			if enemy is Node3D and is_instance_valid(enemy):
				if damaged_targets.has(enemy):
					continue
				var dist := global_position.distance_to((enemy as Node3D).global_position)
				if dist <= explosion_radius:
					damaged_targets.append(enemy)
					_damage_target(enemy)


func _damage_target(target: Node) -> void:
	if target.has_method("take_damage"):
		target.take_damage(damage, _source_turret)
	else:
		var health := target.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			health.take_damage(damage, _source_turret)


func _find_damageable(node: Node) -> Node:
	var curr := node
	while curr != null:
		if curr.has_method("take_damage") or curr.has_node("HealthComponent"):
			return curr
		curr = curr.get_parent()
	return null


func _apply_visual(m: Mesh, mat: Material, scn: PackedScene = null) -> void:
	if scn != null:
		var inst := scn.instantiate() as Node3D
		if inst != null:
			var aabb := _calculate_node_aabb(inst)
			if aabb.size.y > aabb.size.z * 1.5 and aabb.size.y > aabb.size.x * 1.5:
				inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			if mat != null:
				_apply_mat_recursive(inst, mat)
			add_child(inst)
	elif m != null:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = m
		var aabb := m.get_aabb()
		# If mesh is modeled along +Y (upright, like arrows), pitch down 90 deg around X
		# so its tip faces forward along -Z.
		if aabb.size.y > aabb.size.z * 1.5 and aabb.size.y > aabb.size.x * 1.5:
			mesh_inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		if mat != null:
			mesh_inst.material_override = mat
		add_child(mesh_inst)
	else:
		var mesh_inst := MeshInstance3D.new()
		var default_sphere := SphereMesh.new()
		default_sphere.radius = 0.1
		default_sphere.height = 0.2
		mesh_inst.mesh = default_sphere
		if mat != null:
			mesh_inst.material_override = mat
		add_child(mesh_inst)

	if get_node_or_null("CollisionShape3D") == null:
		var col_shape := CollisionShape3D.new()
		var sphere_col := SphereShape3D.new()
		sphere_col.radius = 0.2
		col_shape.shape = sphere_col
		add_child(col_shape)


func _calculate_node_aabb(root_node: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var curr: Node = stack.pop_back()
		if curr is MeshInstance3D and curr.mesh != null:
			var local_aabb: AABB = curr.mesh.get_aabb()
			var transformed_aabb: AABB = curr.transform * local_aabb
			if first:
				combined = transformed_aabb
				first = false
			else:
				combined = combined.merge(transformed_aabb)
		for child in curr.get_children():
			stack.append(child)
	return combined if not first else AABB()


func _apply_mat_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_mat_recursive(child, mat)


func _is_source_or_descendant(node: Node) -> bool:
	if node == null or _source_turret == null:
		return false
	if node == _source_turret or _source_turret.is_ancestor_of(node):
		return true
	var source_parent := _source_turret.get_parent()
	if source_parent != null and (node == source_parent or source_parent.is_ancestor_of(node)):
		return true
	return false
