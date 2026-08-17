extends Node3D
## Runtime spike: does SMOOTH voxel terrain (VoxelMesherTransvoxel) render,
## collide, and coexist with a BLOCKY terrain at RUNTIME in this addon build?
##
## docs/VOXEL-TOOL-NOTES.md F5 proved VoxelGeneratorGraph + VoxelMesherTransvoxel
## produces no geometry in the EDITOR viewport; runtime was never tested. The
## proposed "smooth terrain + blocky structures" conversion is dead unless
## smooth meshing works at runtime, so this scene validates exactly that.
##
## The world is built entirely in code (smooth terrain cannot be authored
## visually in this build). Layout: both islands share the origin — the smooth
## noise hills (-4..8) poke through the infinite blocky plate (top at y=0).
## DO NOT offset a VoxelTerrain node in this build: a translated terrain
## collides at the offset position but renders NO meshes (found by bisect,
## 2026-08-17). Collision layers separate the two — smooth = bit 3 (mask 4),
## blocky = bit 4 (mask 8) — and every raycast logs which terrain's layer
## answered, so attribution needs no collider identity.
##
## CLI user args (after `--`): `--lod` builds the smooth island as
## VoxelLodTerrain instead of VoxelTerrain; `--auto-quit=<seconds>` quits N
## seconds after diagnostics finish (used by the automated headless run);
## `--no-smooth` / `--no-blocky` disable an island, `--no-layers` skips
## collision layer/mask sets — the last three are bisect switches for
## isolating misbehavior.
##
## Controls: WASD move, Space/C up/down, Shift fast, mouse look (click to grab,
## Esc to release), Q to quit.

const SMOOTH_LAYER := 4  ## Collision bit 3.
const BLOCKY_LAYER := 8  ## Collision bit 4.
const PROBE_LAYER := 1   ## Default layer — the dropped spheres live here.
## Ray mask that sees both terrains but never the probe spheres.
const TERRAIN_RAY_MASK := SMOOTH_LAYER | BLOCKY_LAYER
## Column scan grid: rays classify by which terrain's layer answers FIRST.
## Where the noise dips below the blocky plate top (y=0), blocky answers.
const SCAN_STEP := 4
const SCAN_RADIUS := 40
const DETAIL_LINES_PER_ISLAND := 3
const RAY_FROM_Y := 60.0
const RAY_LENGTH := 120.0
const SETTLE_SECONDS := 2.0

var _smooth_terrain: Node3D = null
var _blocky_terrain: VoxelTerrain = null
var _smooth_sphere: RigidBody3D = null
var _blocky_sphere: RigidBody3D = null
var _camera: Camera3D
var _label: Label
var _diagnostics := PackedStringArray()
var _use_lod := false
var _auto_quit_after := 0.0
var _enable_smooth := true
var _enable_blocky := true
var _set_layers := true

var _smooth_hit_count := 0
var _blocky_hit_count := 0
var _smooth_own_first := false
var _blocky_own_first := false
var _smooth_non_axis_normals := 0

func _ready() -> void:
	_read_user_args()
	_build_world()
	_drop_probes()
	await _run_phase_one()
	await _run_phase_two()

func _read_user_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--lod":
			_use_lod = true
		elif arg == "--no-smooth":
			_enable_smooth = false
		elif arg == "--no-blocky":
			_enable_blocky = false
		elif arg == "--no-layers":
			_set_layers = false
		elif arg.begins_with("--auto-quit="):
			_auto_quit_after = maxf(0.0, float(arg.get_slice("=", 1)))

func _build_world() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)

	_smooth_terrain = _build_smooth_terrain() if _enable_smooth else null
	if _smooth_terrain != null:
		add_child(_smooth_terrain)

	_blocky_terrain = _build_blocky_terrain() if _enable_blocky else null
	if _blocky_terrain != null:
		add_child(_blocky_terrain)

	# Fly camera framed for whichever islands exist; a single VoxelViewer on it
	# drives streaming + collision for every terrain in the tree.
	_camera = Camera3D.new()
	_camera.current = true
	if _blocky_terrain != null and _smooth_terrain == null:
		_camera.transform.origin = Vector3(0, 12, 14)
		_camera.rotation_degrees = Vector3(-35, 0, 0)
	else:
		_camera.transform.origin = Vector3(0, 22, 62)
		_camera.rotation_degrees = Vector3(-18, 0, 0)
	add_child(_camera)

	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	_camera.add_child(viewer)

	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_color_shadow", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_label)

	_log("=== smooth terrain spike | variant=%s headless=%s ===" % [
		"VoxelLodTerrain" if _use_lod else "VoxelTerrain",
		DisplayServer.get_name(),
	])

func _build_smooth_terrain() -> Node3D:
	if not ClassDB.class_exists("VoxelMesherTransvoxel") or not ClassDB.class_exists("VoxelGeneratorNoise2D"):
		_log("smooth FAIL: VoxelMesherTransvoxel / VoxelGeneratorNoise2D missing from this build")
		return null

	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	var generator := VoxelGeneratorNoise2D.new()
	# Property names vary across voxel_tool versions; guard every set so a miss
	# degrades to defaults instead of crashing the spike. Read back so a silent
	# miss is visible in the diagnostics.
	if "noise" in generator:
		generator.set("noise", noise)
	if "height_start" in generator:
		generator.set("height_start", -4.0)
	if "height_range" in generator:
		generator.set("height_range", 12.0)
	_log("generator props: noise=%s height_start=%s height_range=%s" % [
		str(generator.get("noise")) if "noise" in generator else "MISSING",
		str(generator.get("height_start")) if "height_start" in generator else "MISSING",
		str(generator.get("height_range")) if "height_range" in generator else "MISSING",
	])

	var mesher := VoxelMesherTransvoxel.new()

	var terrain: Node3D
	if _use_lod:
		if not ClassDB.class_exists("VoxelLodTerrain"):
			_log("smooth FAIL: VoxelLodTerrain missing from this build")
			return null
		var lod := VoxelLodTerrain.new()
		if "lod_count" in lod:
			lod.set("lod_count", 4)
		terrain = lod
	else:
		terrain = VoxelTerrain.new()
	if "generator" in terrain:
		terrain.set("generator", generator)
	if "mesher" in terrain:
		terrain.set("mesher", mesher)
	# Layer separates the islands for attribution; the mask must still include
	# the probe bodies' layer or body-vs-terrain collision silently stops
	# (raycasts only test query-mask vs layer, so they'd still hit — sneaky).
	if _set_layers and "collision_layer" in terrain:
		terrain.set("collision_layer", SMOOTH_LAYER)
	if _set_layers and "collision_mask" in terrain:
		terrain.set("collision_mask", PROBE_LAYER)
	var layer_set := not (_set_layers and "collision_layer" in terrain) or int(terrain.get("collision_layer")) == SMOOTH_LAYER
	_log("smooth terrain: class=%s collision_layer set=%s (now=%s) generator=%s mesher=%s" % [
		terrain.get_class(),
		str(layer_set),
		str(terrain.get("collision_layer")) if "collision_layer" in terrain else "MISSING",
		str(terrain.get("generator") != null),
		str(terrain.get("mesher") != null),
	])
	return terrain

func _build_blocky_terrain() -> VoxelTerrain:
	# Minimal blocky control island, same recipe as voxel_test.gd: air + one
	# aligned unit cube, flat generator emitting voxel type 1.
	var library := VoxelBlockyLibrary.new()
	var air := VoxelBlockyModelEmpty.new()
	var solid := VoxelBlockyModelMesh.new()
	solid.mesh = _build_aligned_cube()
	if "collision_enabled_0" in solid:
		solid.set("collision_enabled_0", true)
	library.add_model(air)     # index 0
	library.add_model(solid)   # index 1
	library.bake()

	var generator := VoxelGeneratorFlat.new()
	generator.channel = 0
	if "voxel_type" in generator:
		generator.set("voxel_type", 1)

	var mesher := VoxelMesherBlocky.new()
	mesher.library = library

	var terrain := VoxelTerrain.new()
	terrain.generator = generator
	terrain.mesher = mesher
	# NOTE: stays at the origin — translated VoxelTerrain nodes collide but
	# don't render in this build (see file header).
	if _set_layers and "collision_layer" in terrain:
		terrain.set("collision_layer", BLOCKY_LAYER)
	if _set_layers and "collision_mask" in terrain:
		terrain.set("collision_mask", PROBE_LAYER)
	var layer_set := not (_set_layers and "collision_layer" in terrain) or int(terrain.get("collision_layer")) == BLOCKY_LAYER
	_log("blocky terrain: collision_layer set=%s (now=%s)" % [
		str(layer_set),
		str(terrain.get("collision_layer")) if "collision_layer" in terrain else "MISSING",
	])
	return terrain

func _drop_probes() -> void:
	# Spheres dropped over each island. Angular axes are locked so they cannot
	# roll down the smooth slopes forever; linear damping lets friction park
	# them, making "came to rest" a meaningful collision signal.
	if _smooth_terrain != null:
		_smooth_sphere = _make_probe_sphere()
		_smooth_sphere.position = Vector3(0, 25, 0)
		add_child(_smooth_sphere)

	if _blocky_terrain != null:
		_blocky_sphere = _make_probe_sphere()
		_blocky_sphere.position = Vector3(24, 25, 3)
		add_child(_blocky_sphere)

func _make_probe_sphere() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.linear_damp = 1.0
	# Body-body collision checks layer/mask in BOTH directions, so the probe
	# must mask in the terrain layers or it falls through them.
	body.collision_layer = PROBE_LAYER
	body.collision_mask = 0xFFFFFFFF
	# Angular axes are locked so the sphere cannot roll down the smooth slopes
	# forever; linear damping lets friction park it, making "came to rest" a
	# meaningful collision signal.
	body.axis_lock_angular_x = true
	body.axis_lock_angular_y = true
	body.axis_lock_angular_z = true

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.4
	shape.shape = sphere_shape
	body.add_child(shape)

	var mesh_node := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.4
	sphere_mesh.height = 0.8
	mesh_node.mesh = sphere_mesh
	body.add_child(mesh_node)
	return body

# --- Diagnostics ---

func _run_phase_one() -> void:
	# Let the viewer stream chunks + collision in before probing. Voxel writes
	# need ~40 frames to land (F3); mesh/collision generation is similarly
	# threaded, so settle generously before reading anything.
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check_render()
	_check_raycast()
	_refresh_label()

func _run_phase_two() -> void:
	await get_tree().create_timer(2.5).timeout
	_check_rest()
	_emit_verdict()
	_refresh_label()
	if _auto_quit_after > 0.0:
		# Automated windowed runs: capture visual proof of rendering before
		# quitting. Meaningless under the headless dummy renderer.
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_capture_screenshot()
		await get_tree().create_timer(_auto_quit_after).timeout
		get_tree().quit()

## Throwaway spike: writes straight into the repo's gitignored tmp/ so an
## automated run leaves visual evidence next to its log. Not a save-system path.
func _capture_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var tag := _config_tag()
	var path := "/store/backups/act/godot/vek-holdout/tmp/spike_%s.png" % (
		tag if tag != "" else ("lodterrain" if _use_lod else "voxelterrain")
	)
	var err := img.save_png(path)
	_log("screenshot: %s" % ("saved " + path if err == OK else "ERROR %d" % err))

func _config_tag() -> String:
	var parts := PackedStringArray()
	if _use_lod:
		parts.append("lod")
	if not _enable_smooth:
		parts.append("nosmooth")
	if not _enable_blocky:
		parts.append("noblocky")
	if not _set_layers:
		parts.append("nolayers")
	return "_".join(parts)

func _check_render() -> void:
	# aabb proved useless as a render signal in this build: it stays zero even
	# when the known-good blocky control visibly renders (voxel_test A/B).
	# Rendering is judged from the screenshot, never from these numbers.
	var smooth_aabb := _terrain_aabb(_smooth_terrain)
	_log("smooth aabb (informational, not a verdict): (%s)" % smooth_aabb.size)

	var blocky_aabb := _terrain_aabb(_blocky_terrain)
	_log("blocky aabb (informational, not a verdict): (%s)" % blocky_aabb.size)

	# Informational: engine-side timing stats if exposed.
	if _smooth_terrain != null and _smooth_terrain.has_method("get_statistics"):
		var stats: Dictionary = _smooth_terrain.call("get_statistics")
		var text := str(stats)
		if text.length() > 400:
			text = text.substr(0, 400) + "..."
		_log("smooth stats: %s" % text)

func _check_raycast() -> void:
	# Grid-scan columns and classify each by which terrain's collision layer
	# answers first — robust against not knowing where the noise dips below
	# the plate. Coexistence is proven when BOTH layers get first-hits.
	if not _set_layers:
		_log("column scan: attribution disabled (--no-layers)")
		return
	var smooth_lines := 0
	var blocky_lines := 0
	for x: int in range(-SCAN_RADIUS, SCAN_RADIUS + 1, SCAN_STEP):
		for z: int in range(-SCAN_RADIUS, SCAN_RADIUS + 1, SCAN_STEP):
			var hit := _raycast_down(x, z, TERRAIN_RAY_MASK)
			if hit.is_empty():
				continue
			var collider: Object = hit["collider"]
			var layer: int = collider.get("collision_layer") if "collision_layer" in collider else -1
			if layer == SMOOTH_LAYER:
				_smooth_hit_count += 1
				_smooth_own_first = true
				var n: Vector3 = hit["normal"]
				if (n - n.round()).length() >= 0.01:
					_smooth_non_axis_normals += 1
				if smooth_lines < DETAIL_LINES_PER_ISLAND:
					smooth_lines += 1
					_log("smooth-first (%d, %d): y=%.3f normal=(%.2f, %.2f, %.2f)" % [
						x, z, hit["position"].y, n.x, n.y, n.z,
					])
			elif layer == BLOCKY_LAYER:
				_blocky_hit_count += 1
				_blocky_own_first = true
				if blocky_lines < DETAIL_LINES_PER_ISLAND:
					blocky_lines += 1
					_log("blocky-first (%d, %d): y=%.3f normal=(%.2f, %.2f, %.2f)" % [
						x, z, hit["position"].y,
						hit["normal"].x, hit["normal"].y, hit["normal"].z,
					])
	_log("column scan: smooth-first=%d blocky-first=%d (of %d columns)" % [
		_smooth_hit_count, _blocky_hit_count,
		(2 * SCAN_RADIUS / SCAN_STEP + 1) * (2 * SCAN_RADIUS / SCAN_STEP + 1),
	])

func _check_rest() -> void:
	_probe_report("smooth sphere", _smooth_sphere, -10.0)
	_probe_report("blocky sphere", _blocky_sphere, -5.0)

func _probe_report(probe_name: String, body: RigidBody3D, min_rest_y: float) -> void:
	if body == null:
		_log("%s: n/a" % probe_name)
		return
	var speed := body.linear_velocity.length()
	var resting := speed < 0.15 and body.global_position.y > min_rest_y
	_log("%s: %s (y=%.2f, speed=%.2f)" % [
		probe_name, "RESTING" if resting else "NOT resting", body.global_position.y, speed,
	])

func _emit_verdict() -> void:
	# The blocky island is the control: it is known-good tech (the whole game
	# runs on it), so if IT fails, the harness is broken, not the terrain.
	# Disabled islands (--no-smooth/--no-blocky bisect runs) report SKIP and
	# don't gate the verdict.
	var control_txt: String
	if _blocky_terrain == null:
		control_txt = "SKIP (disabled)"
	elif _blocky_own_first:
		control_txt = "PASS"
	else:
		control_txt = "FAIL — run invalid, check the setup"
	var control_ok := control_txt == "PASS" or control_txt == "SKIP (disabled)"

	var smooth_collision_ok := _smooth_own_first
	var coexist_ok := _smooth_own_first and _blocky_own_first
	var go := control_ok and coexist_ok and (_smooth_terrain == null or smooth_collision_ok)

	_log("--- VERDICT (%s) ---" % ("VoxelLodTerrain" if _use_lod else "VoxelTerrain"))
	_log("blocky control (collision): %s" % control_txt)
	_log("smooth collision: %s | coexistence (both layers answer first on their own island): %s | rendering: judged from the screenshot, not this log" % [
		"SKIP" if _smooth_terrain == null else ("PASS" if smooth_collision_ok else "FAIL"),
		"SKIP" if (_smooth_terrain == null or _blocky_terrain == null) else ("PASS" if coexist_ok else "FAIL"),
	])
	_log("smooth non-axis-aligned normals on slopes: %d/%d hits (build-cursor snap will need them)" % [
		_smooth_non_axis_normals, _smooth_hit_count,
	])
	_log("*** GO: two-terrain design is viable in this build ***" if go else "*** NO-GO: smooth terrain fails at runtime in this build ***")

func _raycast_down(world_x: float, world_z: float, mask: int) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := Vector3(world_x, RAY_FROM_Y, world_z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_LENGTH)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = mask if mask != 0 else 0xFFFFFFFF
	return space.intersect_ray(query)

func _terrain_aabb(terrain: Node3D) -> AABB:
	if terrain == null or not ("aabb" in terrain):
		return AABB()
	return terrain.get("aabb")

func _log(line: String) -> void:
	_diagnostics.append(line)
	print(line)

func _refresh_label() -> void:
	if _label:
		_label.text = "\n".join(_diagnostics)

# --- Fly camera input (same as voxel_test.gd) ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.keycode == KEY_Q and event.pressed:
		get_tree().quit()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera.rotation_degrees.y -= event.relative.x * 0.2
		_camera.rotation_degrees.x -= event.relative.y * 0.2
		_camera.rotation_degrees.x = clampf(_camera.rotation_degrees.x, -89.0, 89.0)

func _process(delta: float) -> void:
	if _camera == null:
		return
	var speed := 20.0 if Input.is_key_pressed(KEY_SHIFT) else 8.0
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

# Hand-built unit cube spanning (0,0,0)->(1,1,1) — the convention the blocky
# mesher's fast path keys on (see voxel_test.gd / VOXEL-TOOL-NOTES).
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
