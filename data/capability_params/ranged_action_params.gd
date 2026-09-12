class_name RangedActionParams
extends CombatActionParams
## Capability parameters for ranged combat actions (e.g. rifles, muskets, crossbows).
## Defines ammunition consumption, projectile/hitscan properties, spread deviation,
## and bullet tracer visual effects.

@export var ammo_item_id: String = ""
@export var ammo_cost: int = 1
@export var is_hitscan: bool = true
@export var spread_angle_degrees: float = 0.0
@export var show_tracer: bool = true

## Physical projectile fields, used when is_hitscan is false (ProjectileSpec.from_ranged_action).
## Mirrors the TurretParams "Projectile" group so hand-fired and turret-fired
## weapons share the same underlying Projectile mechanics.
@export_group("Projectile")
@export var projectile_scene: PackedScene = null
@export var projectile_mesh: Mesh = null
@export var projectile_material: Material = null
@export var projectile_speed: float = 40.0
@export var projectile_type: ProjectileSpec.Kind = ProjectileSpec.Kind.REGULAR
@export var explosion_radius: float = 0.0
@export var enable_projectile_trail: bool = true
@export var enable_explosion_particles: bool = true


func execute(actor: Node) -> void:
	if actor == null:
		return

	# 1. Ammo Consumption: Deduct ammo from actor inventory if ammo_item_id is specified.
	if not _consume_ammo(actor):
		return

	var world_3d: World3D = null
	if actor is Node3D:
		world_3d = (actor as Node3D).get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return

	var aim_origin: Vector3 = Vector3.ZERO
	var dir: Vector3 = Vector3.FORWARD
	var range_dist: float = range_meters if range_meters > 0.0 else 500.0

	# Determine aiming ray from Player camera or actor transform
	if actor.has_method("get_camera") and actor.get_camera() != null:
		var cam: Camera3D = actor.get_camera()
		var viewport: Viewport = actor.get_viewport() if actor.is_inside_tree() else null
		var center: Vector2 = viewport.get_visible_rect().size / 2.0 if viewport != null else Vector2.ZERO
		aim_origin = cam.project_ray_origin(center) if viewport != null else cam.global_position
		dir = cam.project_ray_normal(center) if viewport != null else -cam.global_transform.basis.z
	elif actor.has_method("get_aim_origin") and actor.has_method("get_aim_direction"):
		aim_origin = actor.get_aim_origin()
		dir = actor.get_aim_direction()
	elif actor is Node3D:
		var node3d := actor as Node3D
		aim_origin = node3d.global_position + Vector3(0, 1.0, 0)
		dir = -node3d.global_transform.basis.z
	else:
		return

	# 2. Spread Application: Apply random spread deviation cone if configured.
	if spread_angle_degrees > 0.0:
		dir = _apply_spread(dir, spread_angle_degrees)

	# Visual tracer starts 1.0m above actor position (chest height)
	var tracer_origin: Vector3 = (actor as Node3D).global_position + Vector3(0, 1.0, 0) if actor is Node3D else aim_origin

	if is_hitscan:
		var query := PhysicsRayQueryParameters3D.create(aim_origin, aim_origin + dir * range_dist)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		if actor is CollisionObject3D:
			query.exclude = [(actor as CollisionObject3D).get_rid()]

		var hit := world_3d.direct_space_state.intersect_ray(query)
		var end_pos: Vector3 = hit.position if not hit.is_empty() else aim_origin + dir * range_dist

		# 3. Tracer Visualization: Spawning tracer line if visual tracer is enabled.
		if show_tracer:
			_spawn_bullet_tracer(actor, tracer_origin, end_pos)

		if not hit.is_empty():
			# 4. Impact Effects: Spawning impact spark particles on hit surface normal.
			_spawn_impact_effect(actor, hit.position, hit.normal)
			var collider: Node = hit.collider as Node
			if collider != null:
				var target: Node = collider
				while target != null:
					if target.has_method("take_damage"):
						target.take_damage(int(damage), actor)
						break
					var health := target.get_node_or_null("HealthComponent") as HealthComponent
					if health != null:
						health.take_damage(int(damage), actor)
						break
					target = target.get_parent()
	else:
		# 3. Physical Projectile: Spawns a shared Projectile (also used by
		# TurretComponent) for weapons modeled as slow, visible flying
		# ammunition (crossbows, bomb launchers) rather than instant bullets.
		var projectile := Projectile.new()
		var spawn_parent: Node = actor.get_tree().current_scene if (actor.is_inside_tree() and actor.get_tree().current_scene != null) else actor.get_parent()
		spawn_parent.add_child(projectile)
		var spec := ProjectileSpec.from_ranged_action(self)
		projectile.setup(Transform3D(Basis(), tracer_origin), dir, spec, actor)


func _consume_ammo(actor: Node) -> bool:
	if ammo_item_id == "":
		return true
	if actor.has_method("remove_item"):
		if actor.has_method("has_item"):
			if not actor.has_item(ammo_item_id, ammo_cost):
				return false
		var removed: int = actor.remove_item(ammo_item_id, ammo_cost)
		return removed >= ammo_cost
	return true


func _apply_spread(direction: Vector3, spread_deg: float) -> Vector3:
	var spread_rad := deg_to_rad(spread_deg)
	var yaw := (randf() * 2.0 - 1.0) * spread_rad
	var pitch := (randf() * 2.0 - 1.0) * spread_rad
	var basis := Basis.looking_at(direction, Vector3.UP)
	var perturbed := basis * Vector3(sin(yaw), sin(pitch), -cos(yaw) * cos(pitch))
	return perturbed.normalized()


func _spawn_bullet_tracer(actor: Node, start_pos: Vector3, end_pos: Vector3) -> void:
	var tree := actor.get_tree() if actor != null and actor.is_inside_tree() else null
	if tree == null or tree.current_scene == null:
		return

	var dist := start_pos.distance_to(end_pos)
	if dist < 0.1:
		return

	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = dist

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.3, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat

	tree.current_scene.add_child(mesh_inst)

	var mid_point := (start_pos + end_pos) / 2.0
	mesh_inst.global_position = mid_point

	var forward_dir := start_pos.direction_to(end_pos)
	if forward_dir != Vector3.ZERO:
		var up_vec := Vector3.UP if abs(forward_dir.y) < 0.99 else Vector3.FORWARD
		mesh_inst.look_at(end_pos, up_vec)
		mesh_inst.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	var tween := mesh_inst.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tween.tween_callback(mesh_inst.queue_free)


func _spawn_impact_effect(actor: Node, impact_pos: Vector3, normal: Vector3) -> void:
	var tree := actor.get_tree() if actor != null and actor.is_inside_tree() else null
	if tree == null or tree.current_scene == null:
		return

	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = normal if normal != Vector3.ZERO else Vector3.UP
	mat.spread = 45.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 8.0
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	mat.color = Color(1.0, 0.7, 0.2)

	var draw_mesh := BoxMesh.new()
	draw_mesh.size = Vector3(0.04, 0.04, 0.04)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(1.0, 0.8, 0.2)
	draw_mesh.material = draw_mat

	particles.process_material = mat
	particles.draw_pass_1 = draw_mesh
	particles.amount = 8
	particles.lifetime = 0.2
	particles.one_shot = true
	particles.explosiveness = 1.0

	tree.current_scene.add_child(particles)
	particles.global_position = impact_pos
	particles.emitting = true

	var timer := tree.create_timer(0.3)
	timer.timeout.connect(particles.queue_free)
