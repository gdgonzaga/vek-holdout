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
		_apply_mesh(params.projectile_mesh, params.projectile_material)
	var dir_norm := direction.normalized()
	if dir_norm != Vector3.ZERO:
		_velocity = dir_norm * speed
		look_at(global_position + dir_norm, Vector3.UP if abs(dir_norm.y) < 0.99 else Vector3.FORWARD)


func _ready() -> void:
	monitoring = true
	monitorable = false
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
	if hit_node == _source_turret or (_source_turret != null and _source_turret.is_ancestor_of(hit_node)):
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
			if collider == null or collider == _source_turret or (_source_turret != null and _source_turret.is_ancestor_of(collider)):
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


func _apply_mesh(m: Mesh, mat: Material) -> void:
	var mesh_inst := MeshInstance3D.new()
	if m != null:
		mesh_inst.mesh = m
	else:
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
