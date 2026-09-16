class_name MeleeActionParams
extends CombatActionParams
## Capability parameters for close-quarters melee combat actions (e.g. baton, sword, axe).
## Configures swing timing (windup, active hitbox window) and impact feedback.

@export var windup_seconds: float = 0.15
@export var active_seconds: float = 0.2
@export var hit_audio_event: String = ""


## Melee's own windup+active window must elapse before the swing is done,
## so the lockout has to cover it too -- cooldown_seconds alone is only the
## recovery time tacked on afterward.
func get_lockout_duration() -> float:
	return windup_seconds + active_seconds + cooldown_seconds


func execute(actor: Node) -> void:
	if actor == null or not actor.is_inside_tree():
		return

	# 1. Windup Delay: Wait for windup animation portion before opening the active hitbox window.
	if windup_seconds > 0.0:
		await actor.get_tree().create_timer(windup_seconds).timeout

	if actor == null or not actor.is_inside_tree():
		return

	# 2. Active Window Execution: Sweep 3D hitbox volume over active_seconds, dealing damage to targets hit.
	_process_active_hitbox_window(actor)


# =============================================================================
# Auxiliary Functions (Step-down narrative order)
# =============================================================================

## Auxiliary: Sweeps the active 3D hitbox volume over active_seconds and applies damage to struck targets
func _process_active_hitbox_window(actor: Node) -> void:
	var damaged_targets: Array[Node] = []
	var elapsed_time: float = 0.0
	var check_interval: float = 0.05
	var duration: float = maxf(active_seconds, 0.05)

	while elapsed_time < duration:
		# 1. Aim Ray Evaluation: Resolve current aiming origin and direction from actor or camera.
		var aim: Dictionary = _resolve_aim(actor)
		var aim_origin: Vector3 = aim.get("origin", Vector3.ZERO)
		var dir: Vector3 = aim.get("dir", Vector3.FORWARD)

		# 2. Hitbox Query: Query 3D space volume and physics raycast for targets in attack range.
		_evaluate_hitbox_and_damage(actor, aim_origin, dir, damaged_targets)

		if active_seconds <= 0.0:
			break

		await actor.get_tree().create_timer(check_interval).timeout
		elapsed_time += check_interval


## Auxiliary: Resolves position origin and forward direction for melee attack targeting
func _resolve_aim(actor: Node) -> Dictionary:
	var aim_origin: Vector3 = Vector3.ZERO
	var dir: Vector3 = Vector3.FORWARD

	var cam: Camera3D = null
	if actor.has_method("get_camera"):
		cam = actor.get_camera()

	if cam != null:
		var viewport: Viewport = actor.get_viewport() if actor.is_inside_tree() else null
		var center: Vector2 = viewport.get_visible_rect().size / 2.0 if viewport != null else Vector2.ZERO
		aim_origin = (actor as Node3D).global_position + Vector3(0, 1.2, 0) if actor is Node3D else cam.global_position
		dir = cam.project_ray_normal(center) if viewport != null else -cam.global_transform.basis.z
	elif actor.has_method("get_aim_origin") and actor.has_method("get_aim_direction"):
		aim_origin = actor.get_aim_origin()
		dir = actor.get_aim_direction()
	elif actor is Node3D:
		var node3d := actor as Node3D
		aim_origin = node3d.global_position + Vector3(0, 1.0, 0)
		dir = -node3d.global_transform.basis.z

	return {"origin": aim_origin, "dir": dir}


## Auxiliary: Queries 3D physics space using both shape sweep and raycast, applying damage to new targets
func _evaluate_hitbox_and_damage(actor: Node, aim_origin: Vector3, dir: Vector3, damaged_targets: Array[Node]) -> void:
	if not (actor is Node3D):
		return
	var world_3d: World3D = (actor as Node3D).get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return

	var space := world_3d.direct_space_state
	var range_dist: float = range_meters if range_meters > 0.0 else 2.0

	# Shape query for 3D volume hitbox
	var shape_query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.2, range_dist)
	shape_query.shape = box

	var center_pos := aim_origin + dir * (range_dist * 0.5)
	# 1. Box Orientation: Build the sweep box's rotation from the aim direction
	# alone (never from world position) -- Transform3D.looking_at(target, ...)
	# treats its argument as an absolute point, so passing center_pos + dir
	# previously let the actor's distance from world-origin corrupt the
	# hitbox facing (the box drifted off-aim everywhere except near 0,0,0).
	var box_basis: Basis = _direction_to_basis(dir)
	shape_query.transform = Transform3D(box_basis, center_pos)

	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = true
	if actor is CollisionObject3D:
		shape_query.exclude = [(actor as CollisionObject3D).get_rid()]

	var hits: Array[Dictionary] = space.intersect_shape(shape_query, 16)

	# Raycast fallback for precise impact particle position
	var ray_query := PhysicsRayQueryParameters3D.create(aim_origin, aim_origin + dir * range_dist)
	ray_query.collide_with_bodies = true
	ray_query.collide_with_areas = true
	if actor is CollisionObject3D:
		ray_query.exclude = [(actor as CollisionObject3D).get_rid()]
	var ray_hit := space.intersect_ray(ray_query)

	for hit in hits:
		var collider: Node = hit.get("collider") as Node
		if collider == null:
			continue
		var target: Node = _resolve_damage_target(collider)
		if target != null and target != actor and not damaged_targets.has(target):
			damaged_targets.append(target)
			var impact_pos: Vector3 = ray_hit.get("position", center_pos) if not ray_hit.is_empty() else center_pos
			var impact_normal: Vector3 = ray_hit.get("normal", Vector3.UP) if not ray_hit.is_empty() else Vector3.UP

			# 1. Impact Visuals: Spawn impact particles at hit location.
			_spawn_impact_effect(actor, impact_pos, impact_normal)

			# 2. Damage Application: Deliver damage payload to the target.
			_apply_damage_to_target(actor, target, damage)


## Auxiliary: Safe direction-to-basis conversion for the hitbox sweep transform;
## falls back to identity for the degenerate up/down cases Basis.looking_at() rejects
func _direction_to_basis(dir: Vector3) -> Basis:
	if dir == Vector3.ZERO or dir.is_equal_approx(Vector3.UP) or dir.is_equal_approx(Vector3.DOWN):
		return Basis()
	return Basis.looking_at(dir, Vector3.UP)


## Auxiliary: Walks up node parent hierarchy to resolve a valid damage recipient
func _resolve_damage_target(collider: Node) -> Node:
	var cur: Node = collider
	while cur != null:
		if cur.has_method("take_damage") or cur.get_node_or_null("HealthComponent") != null:
			return cur
		cur = cur.get_parent()
	return null


## Auxiliary: Applies damage to a resolved target object or via its HealthComponent
func _apply_damage_to_target(actor: Node, target: Node, dmg: float) -> void:
	if target.has_method("take_damage"):
		print("[MeleeActionParams] Dealing %d damage to %s via take_damage" % [int(dmg), target.name])
		target.take_damage(int(dmg), actor)
	else:
		var health := target.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			print("[MeleeActionParams] Dealing %d damage to %s via HealthComponent" % [int(dmg), target.name])
			health.take_damage(int(dmg), actor)


## Auxiliary: Spawns short-lived spark particle effect at the impact location
func _spawn_impact_effect(actor: Node, impact_pos: Vector3, normal: Vector3) -> void:
	var tree := actor.get_tree() if actor != null and actor.is_inside_tree() else null
	if tree == null or tree.current_scene == null:
		return

	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = normal if normal != Vector3.ZERO else Vector3.UP
	mat.spread = 45.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	mat.color = Color(1.0, 0.8, 0.2)

	var draw_mesh := BoxMesh.new()
	draw_mesh.size = Vector3(0.04, 0.04, 0.04)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(1.0, 0.8, 0.2)
	draw_mesh.material = draw_mat

	particles.process_material = mat
	particles.draw_pass_1 = draw_mesh
	particles.amount = 6
	particles.lifetime = 0.2
	particles.one_shot = true
	particles.explosiveness = 1.0

	tree.current_scene.add_child(particles)
	particles.global_position = impact_pos
	particles.emitting = true

	var timer := tree.create_timer(0.3)
	timer.timeout.connect(particles.queue_free)
