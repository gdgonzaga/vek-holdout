extends GdUnitTestSuite

## Physics tests for StepClimber (ARCH "Subsystem: Player" / "Subsystem:
## Colonists"): stepping onto a low lip, hopping onto a full block, and staying
## blocked against a too-tall wall. Worlds are built in code on a flat floor and
## driven forward with a tiny velocity-driver node, awaiting physics frames.

## Drives the body toward +X. Mirrors Colonist._physics_process exactly —
## gravity only added while airborne, velocity.y never touched while grounded —
## so a StepClimber hop impulse set after the move survives the next tick's
## stale is_on_floor(). Must be added BEFORE the StepClimber child so the
## climber ticks after the move and sees this frame's wall/floor state.
class Drive extends Node:
	var body: CharacterBody3D

	func _physics_process(delta: float) -> void:
		if not body.is_on_floor():
			body.velocity.y -= 9.8 * delta
		body.velocity.x = 3.5
		body.velocity.z = 0.0
		body.move_and_slide()


## Floor + obstacle slab + capsule body (Player/Colonist dimensions) carrying a
## StepClimber and the Drive. The body starts on the floor just west of the
## slab's face and walks into it. Returned tree is freed via auto_free(root).
func _build_world(obstacle_size: Vector3, obstacle_center: Vector3, hop: float) -> CharacterBody3D:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var floor_body := StaticBody3D.new()
	root.add_child(floor_body)
	var floor_shape := CollisionShape3D.new()
	floor_body.add_child(floor_shape)
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(24, 1, 24)
	floor_shape.shape = floor_box
	floor_body.position = Vector3(0, -0.5, 0)
	var slab := StaticBody3D.new()
	root.add_child(slab)
	var slab_shape := CollisionShape3D.new()
	slab.add_child(slab_shape)
	var slab_box := BoxShape3D.new()
	slab_box.size = obstacle_size
	slab_shape.shape = slab_box
	slab.position = obstacle_center
	var body := CharacterBody3D.new()
	root.add_child(body)
	var shape_node := CollisionShape3D.new()
	body.add_child(shape_node)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	shape_node.shape = capsule
	shape_node.position = Vector3(0, 0.8, 0)
	var drive := Drive.new()
	drive.body = body
	body.add_child(drive)
	var climber := StepClimber.new()
	climber.step_height = 0.5
	climber.hop_height = hop
	body.add_child(climber)
	body.global_position = Vector3(0, 0.02, 0)
	return body


func _run_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## A 10 cm lip is stepped over: the body ends up standing on the slab's top at
## the lip's height, having advanced past its face. This is the "few-cm mesh"
## case plain move_and_slide treats as a wall.
func test_steps_over_low_lip() -> void:
	var body := _build_world(Vector3(10, 0.1, 4), Vector3(6, 0.05, 0), 0.0)
	await _run_frames(60)
	assert_float(body.global_position.y).is_between(0.05, 0.16)
	assert_float(body.global_position.x).is_greater(1.2)


## A full 1 m block is hopped when hop_height covers it: the body arcs over the
## face and lands standing on top. Colonists rely on this (no manual jump).
func test_hops_onto_full_block() -> void:
	var body := _build_world(Vector3(10, 1.0, 6), Vector3(6, 0.5, 0), 1.05)
	await _run_frames(90)
	assert_float(body.global_position.y).is_between(0.9, 1.1)
	assert_float(body.global_position.x).is_greater(1.5)


## A 2 m wall is neither stepped nor hopped: the body stays on the floor,
## pressed against the face, with no repeated hop impulses (cooldown).
func test_tall_wall_blocks() -> void:
	var body := _build_world(Vector3(10, 2.0, 6), Vector3(6, 1.0, 0), 1.05)
	await _run_frames(60)
	assert_float(body.global_position.y).is_between(-0.05, 0.05)
	assert_float(body.global_position.x).is_less(1.0)


## A 25 cm step staircase (4 steps, 1 m total rise) is climbed step-by-step
## without getting stuck at the bottom.
func test_steps_up_25cm_staircase() -> void:
	var body := _build_staircase_world(4, 0.25, 0.25)
	await _run_frames(90)
	assert_float(body.global_position.y).is_between(0.9, 1.1)
	assert_float(body.global_position.x).is_greater(2.0)


func _build_staircase_world(step_count: int = 4, step_h: float = 0.25, step_d: float = 0.25) -> CharacterBody3D:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var floor_body := StaticBody3D.new()
	root.add_child(floor_body)
	var floor_shape := CollisionShape3D.new()
	floor_body.add_child(floor_shape)
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(24, 1, 24)
	floor_shape.shape = floor_box
	floor_body.position = Vector3(0, -0.5, 0)

	for i in range(step_count):
		var step_body := StaticBody3D.new()
		root.add_child(step_body)
		var shape_node := CollisionShape3D.new()
		step_body.add_child(shape_node)
		var box := BoxShape3D.new()
		var height := step_h * (i + 1)
		box.size = Vector3(4.0, height, 4.0)
		shape_node.shape = box
		step_body.position = Vector3(1.0 + i * step_d + 2.0, height * 0.5, 0)

	var body := CharacterBody3D.new()
	root.add_child(body)
	var shape_node := CollisionShape3D.new()
	body.add_child(shape_node)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	shape_node.shape = capsule
	shape_node.position = Vector3(0, 0.8, 0)
	var drive := Drive.new()
	drive.body = body
	body.add_child(drive)
	var climber := StepClimber.new()
	climber.step_height = 0.5
	climber.hop_height = 0.0
	body.add_child(climber)
	body.global_position = Vector3(0, 0.02, 0)
	return body
