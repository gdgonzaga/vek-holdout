class_name CombatActionParams
extends EquipActionParams
## Capability parameters for combat actions (e.g. guns, melee weapons).
## Defines hitscan/projectile properties, damage, range, and spread, and
## executes raycasts against potential combat targets with bullet tracer visuals.

@export var damage: float = 10.0
@export var range_meters: float = 500.0
@export var is_hitscan: bool = true
@export var projectile_scene: PackedScene = null
@export var spread_angle_degrees: float = 0.0
@export var ammo_item_id: String = ""
@export var show_tracer: bool = true


func execute(actor: Node) -> void:
	if actor == null:
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
	elif actor is Node3D:
		var node3d := actor as Node3D
		aim_origin = node3d.global_position + Vector3(0, 1.75, 0)
		dir = -node3d.global_transform.basis.z
	else:
		return

	# Visual tracer starts 1.75m above actor position (player feet)
	var tracer_origin: Vector3 = (actor as Node3D).global_position + Vector3(0, 1.75, 0) if actor is Node3D else aim_origin

	var query := PhysicsRayQueryParameters3D.create(aim_origin, aim_origin + dir * range_dist)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if actor is CollisionObject3D:
		query.exclude = [(actor as CollisionObject3D).get_rid()]

	var hit := world_3d.direct_space_state.intersect_ray(query)
	var end_pos: Vector3 = hit.position if not hit.is_empty() else aim_origin + dir * range_dist

	# 1. Tracer Visualization: Spawning tracer line if visual tracer is enabled.
	if show_tracer:
		_spawn_bullet_tracer(actor, tracer_origin, end_pos)

	if not hit.is_empty():
		# 2. Impact Effects: Spawning impact spark particles on hit surface normal.
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
