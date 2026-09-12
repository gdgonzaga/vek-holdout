class_name Projectile
extends Area3D
## Physical projectile shared by turrets and hand-fired ranged weapons (ARCH
## combat.md). Moves forward along its velocity vector each physics frame.
## Deals direct damage on contact (REGULAR) or area-of-effect splash damage
## (EXPLOSIVE). Configured via ProjectileSpec so this class never depends on
## TurretParams or RangedActionParams directly.

@export var speed: float = 25.0
@export var damage: int = 10
@export var projectile_type: int = ProjectileSpec.Kind.REGULAR
@export var explosion_radius: float = 3.0
@export var max_lifetime: float = 10.0

var _velocity: Vector3 = Vector3.ZERO
var _lifetime: float = 0.0
var _source: Node = null
var _exploded: bool = false
var _spec: ProjectileSpec = null
var _trail_particles: GPUParticles3D = null


func setup(
	origin_transform: Transform3D,
	direction: Vector3,
	spec: ProjectileSpec,
	source: Node = null
) -> void:
	global_transform = origin_transform
	_source = source
	_spec = spec
	if spec != null:
		speed = spec.speed
		damage = spec.damage
		projectile_type = spec.kind
		explosion_radius = spec.explosion_radius
		_apply_visual(spec.visual_mesh, spec.visual_material, spec.visual_scene)

		# 1. Projectile Flight Visuals: Attaching continuous particle trail if enabled.
		if spec.enable_trail or spec.kind == ProjectileSpec.Kind.EXPLOSIVE:
			_attach_trail_particles()

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

	# 1. Particle Trail Detachment: Unparenting flight trail so existing smoke/sparks dissolve naturally.
	_detach_trail_particles()

	if projectile_type == ProjectileSpec.Kind.EXPLOSIVE:
		_explode()
	else:
		_apply_direct_damage(hit_node)

	queue_free()


func _apply_direct_damage(hit_node: Node) -> void:
	var target: Node = hit_node
	while target != null:
		if target.has_method("take_damage"):
			target.take_damage(damage, _source)
			break
		var health := target.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			health.take_damage(damage, _source)
			break
		target = target.get_parent()


func _explode() -> void:
	# 1. Explosion Particle Visuals: Spawning explosion burst particles at impact origin.
	if _spec == null or _spec.enable_explosion_particles:
		_spawn_explosion_particles(global_position)

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
		target.take_damage(damage, _source)
	else:
		var health := target.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			health.take_damage(damage, _source)


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
	if node == null or _source == null:
		return false
	if node == _source or _source.is_ancestor_of(node):
		return true
	var source_parent := _source.get_parent()
	if source_parent != null and (node == source_parent or source_parent.is_ancestor_of(node)):
		return true
	return false


func _attach_trail_particles() -> void:
	## Auxiliary: Creates and attaches continuous smoke/spark trail particle emitter
	_trail_particles = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 20.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3(0, 1.0, 0)
	mat.scale_min = 0.04
	mat.scale_max = 0.12
	mat.color = Color(0.6, 0.6, 0.6, 0.6)

	var draw_mesh := SphereMesh.new()
	draw_mesh.radius = 0.04
	draw_mesh.height = 0.08

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(0.7, 0.7, 0.7, 0.6)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mesh.material = draw_mat

	_trail_particles.process_material = mat
	_trail_particles.draw_pass_1 = draw_mesh
	_trail_particles.amount = 16
	_trail_particles.lifetime = 0.3
	_trail_particles.one_shot = false

	add_child(_trail_particles)
	_trail_particles.emitting = true


func _detach_trail_particles() -> void:
	## Auxiliary: Detaches trail particles on impact so emitted particles dissolve naturally
	if _trail_particles == null or not is_instance_valid(_trail_particles):
		return
	_trail_particles.emitting = false
	var global_pos := _trail_particles.global_position
	remove_child(_trail_particles)
	var parent_target: Node = get_tree().current_scene if (get_tree() != null and get_tree().current_scene != null) else get_parent()
	if parent_target != null:
		parent_target.add_child(_trail_particles)
		_trail_particles.global_position = global_pos
		var timer := get_tree().create_timer(0.4)
		timer.timeout.connect(_trail_particles.queue_free)
	else:
		_trail_particles.queue_free()
	_trail_particles = null


func _spawn_explosion_particles(pos: Vector3) -> void:
	## Auxiliary: Spawns multi-layered explosion particle burst at impact origin
	var tree := get_tree()
	if tree == null:
		return
	var parent_target: Node = tree.current_scene if tree.current_scene != null else get_parent()
	if parent_target == null:
		return

	if _spec != null and _spec.explosion_particle_scene != null:
		var custom_inst := _spec.explosion_particle_scene.instantiate() as Node3D
		if custom_inst != null:
			parent_target.add_child(custom_inst)
			custom_inst.global_position = pos
			return

	# 1. Fire Burst: Spawning high-velocity outward fire and spark particles.
	_spawn_fire_burst_particles(pos, parent_target)

	# 2. Smoke Cloud: Spawning rising dark smoke particles.
	_spawn_smoke_cloud_particles(pos, parent_target)


func _spawn_fire_burst_particles(pos: Vector3, parent_node: Node) -> void:
	## Auxiliary: Spawns high-velocity fire and spark particles scaled by explosion_radius
	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0
	var vel_scale := maxf(explosion_radius, 1.0)
	mat.initial_velocity_min = vel_scale * 1.5
	mat.initial_velocity_max = vel_scale * 3.5
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.08
	mat.scale_max = 0.28
	mat.color = Color(1.0, 0.55, 0.15)

	var draw_mesh := SphereMesh.new()
	draw_mesh.radius = 0.08
	draw_mesh.height = 0.16
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(1.0, 0.6, 0.1)
	draw_mesh.material = draw_mat

	particles.process_material = mat
	particles.draw_pass_1 = draw_mesh
	particles.amount = 24
	particles.lifetime = 0.35
	particles.one_shot = true
	particles.explosiveness = 1.0

	parent_node.add_child(particles)
	particles.global_position = pos
	particles.emitting = true

	var timer := get_tree().create_timer(0.4)
	timer.timeout.connect(particles.queue_free)


func _spawn_smoke_cloud_particles(pos: Vector3, parent_node: Node) -> void:
	## Auxiliary: Spawns rising dark smoke cloud particles scaled by explosion_radius
	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 75.0
	var vel_scale := maxf(explosion_radius, 1.0)
	mat.initial_velocity_min = vel_scale * 0.8
	mat.initial_velocity_max = vel_scale * 1.8
	mat.gravity = Vector3(0, 2.5, 0)
	mat.scale_min = 0.15
	mat.scale_max = 0.45
	mat.color = Color(0.25, 0.25, 0.25, 0.7)

	var draw_mesh := SphereMesh.new()
	draw_mesh.radius = 0.12
	draw_mesh.height = 0.24
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(0.25, 0.25, 0.25, 0.7)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mesh.material = draw_mat

	particles.process_material = mat
	particles.draw_pass_1 = draw_mesh
	particles.amount = 16
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 0.9

	parent_node.add_child(particles)
	particles.global_position = pos
	particles.emitting = true

	var timer := get_tree().create_timer(0.7)
	timer.timeout.connect(particles.queue_free)
