extends Node3D
## Zylann voxel_tool smoke test.
##
## Builds a minimal blocky voxel world in code (terrain + library + mesher +
## fly camera + viewer), then runs a round-trip diagnostic:
##   set_voxel -> get_voxel   (proves the data API works)
##   VoxelTool.raycast        (informational — known-unreliable per gotchas/)
##   Godot physics intersect_ray (informational — needs collision enabled)
## Results are printed to the console and shown on an in-scene label.
##
## Controls: WASD move, Space/C up/down, Shift fast, mouse look (click to grab,
## Esc to release).

const GROUND_VOXEL := 1
const PLACED_VOXEL := 1

var _terrain: VoxelTerrain
var _camera: Camera3D
var _label: Label
var _diagnostics := PackedStringArray()

func _ready() -> void:
	_build_world()
	_run_diagnostics()

func _build_world() -> void:
	# Lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)

	# Block mesh MUST occupy local (0,0,0)->(1,1,1). Zylann's blocky mesher has a
	# standard-cube fast path keyed on that exact bounds; a centered cube (e.g. one
	# built from BoxMesh, which spans -0.5..0.5) silently breaks the fast path and
	# forces the slow generic mesher — so the whole world builds chunk-by-chunk.
	# The dirt.obj asset is already authored to the 0..1 convention; prefer it and
	# only fall back to a hand-built aligned cube if the asset hasn't imported yet.
	#var cube: Mesh = load("res://assets/blocks/dirt.obj")
	#if cube == null:
	#	push_warning("dirt.obj not imported yet; using inline aligned cube. Reopen the project to import the asset for the fast mesher path.")
	#	cube = _build_aligned_cube()
	var cube := _build_aligned_cube()

	# Minimal blocky library: index 0 = air, index 1 = solid cube.
	var library := VoxelBlockyLibrary.new()
	var air := VoxelBlockyModelEmpty.new()
	var solid := VoxelBlockyModelMesh.new()
	solid.mesh = cube
	# Enable collision on surface 0 if the model exposes it (API varies across
	# voxel_tool versions; guard so this never hard-fails).
	if "collision_enabled_0" in solid:
		solid.set("collision_enabled_0", true)
	library.add_model(air)     # index 0
	library.add_model(solid)   # index 1
	library.bake()

	# Flat generator: solid ground filled with voxel type 1.
	var generator := VoxelGeneratorFlat.new()
	generator.channel = 0
	if "voxel_type" in generator:
		generator.set("voxel_type", GROUND_VOXEL)

	var mesher := VoxelMesherBlocky.new()
	mesher.library = library

	_terrain = VoxelTerrain.new()
	_terrain.generator = generator
	_terrain.mesher = mesher
	add_child(_terrain)

	# Fly camera + voxel viewer (viewer drives streaming + collision generation).
	_camera = Camera3D.new()
	_camera.current = true
	_camera.transform.origin = Vector3(0, 12, 14)
	_camera.rotation_degrees = Vector3(-35, 0, 0)
	add_child(_camera)

	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	# Try to enable collision; name varies by version.
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	_camera.add_child(viewer)

	# In-world + on-screen diagnostics surface.
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_label)

func _run_diagnostics() -> void:
	# Defer until the terrain has had a couple of frames to stream data in.
	await get_tree().create_timer(0.25).timeout

	var vt: VoxelTool = _terrain.get_voxel_tool()
	vt.mode = VoxelTool.MODE_SET

	var place_pos := Vector3i(2, 4, 2)
	vt.set_voxel(place_pos, PLACED_VOXEL)
	var readback := vt.get_voxel(place_pos)
	var round_trip_ok := (readback == PLACED_VOXEL)

	var ground_pos := Vector3i(0, -1, 0)
	var ground_read := vt.get_voxel(ground_pos)
	var ground_ok := (ground_read == GROUND_VOXEL)

	# Informational: VoxelTool.raycast (known-unreliable per gotchas/).
	var vt_hit := false
	if vt.has_method("raycast"):
		var from := Vector3(place_pos) + Vector3(0.5, 5.0, 0.5)
		var res = vt.raycast(from, Vector3.DOWN, 20.0)
		vt_hit = res != null

	# Informational: Godot physics raycast (needs collision bodies generated).
	var phys_hit := false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var pfrom := Vector3(place_pos) + Vector3(0.5, 5.0, 0.5)
	var query := PhysicsRayQueryParameters3D.create(pfrom, pfrom + Vector3.DOWN * 20.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	phys_hit = not hit.is_empty()

	_diagnostics.append("=== Zylann voxel_tool smoke test ===")
	_diagnostics.append("set/get round-trip @ %s : %s (read=%d, want=%d)" % [str(place_pos), "PASS" if round_trip_ok else "FAIL", readback, PLACED_VOXEL])
	_diagnostics.append("flat generator ground @ %s : %s (read=%d, want=%d)" % [str(ground_pos), "PASS" if ground_ok else "FAIL", ground_read, GROUND_VOXEL])
	_diagnostics.append("VoxelTool.raycast: %s" % ("hit" if vt_hit else "no hit (expected per gotchas/)"))
	_diagnostics.append("physics intersect_ray: %s" % ("hit" if phys_hit else "no hit (collision may not be enabled)"))
	_diagnostics.append("controls: WASD move, Space/C up-down, Shift fast")
	_diagnostics.append("click to grab mouse, Esc to release")
	_refresh_label()

func _refresh_label() -> void:
	if _label:
		_label.text = "\n".join(_diagnostics)

# --- Fly camera input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera.rotation_degrees.y -= event.relative.x * 0.2
		_camera.rotation_degrees.x -= event.relative.y * 0.2
		_camera.rotation_degrees.x = clamp(_camera.rotation_degrees.x, -89.0, 89.0)

func _process(delta: float) -> void:
	if _camera == null:
		return
	var speed := 12.0 if Input.is_key_pressed(KEY_SHIFT) else 5.0
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := _camera.global_transform.basis.x
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move += forward
	if Input.is_key_pressed(KEY_S): move -= forward
	if Input.is_key_pressed(KEY_D): move += right
	if Input.is_key_pressed(KEY_A): move -= right
	if Input.is_key_pressed(KEY_SPACE): move += Vector3.UP
	if Input.is_key_pressed(KEY_C): move += Vector3.DOWN
	if move != Vector3.ZERO:
		_camera.global_position += move.normalized() * speed * delta

# Hand-built unit cube spanning (0,0,0)->(1,1,1). Matches the convention
# dirt.obj is authored to. Only used if the asset isn't imported yet.
static func _build_aligned_cube() -> ArrayMesh:
	var positions := PackedVector3Array([
		Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0), # -Y
		Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1), # +Y
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0), # -X
		Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), # +X
		Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), # -Z
		Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), # +Z
	])
	var normals := PackedVector3Array()
	for n in [Vector3.DOWN, Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD]:
		for i in 4:
			normals.append(n)
	var indices := PackedInt32Array([
		0, 1, 2, 0, 2, 3,
		4, 5, 6, 4, 6, 7,
		8, 9, 10, 8, 10, 11,
		12, 13, 14, 12, 14, 15,
		16, 17, 18, 16, 18, 19,
		20, 21, 22, 20, 22, 23,
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
