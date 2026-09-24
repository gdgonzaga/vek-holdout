extends Node3D
## GPU frame-time bench for the terrain shader (docs/superpowers/plans/2026-09-24-pbr-texture-sets-v2.md).
## Loads the real base map (real SmoothGrid, real terrain shader), orbits a camera
## advanced per FRAME (so runs are comparable regardless of frame rate), and prints
## mean and p95 GPU milliseconds.
## Needs a real display. Surface path (default):
##   godot --path . --resolution 1920x1080 res://testing/terrain_bench/terrain_bench.tscn -- --label=baseline
## Ore-face path (orbit close around a world position, for example an ore-rich wall):
##   ... -- --label=baseline-ore --focus=12,-6,30 --radius=10 --height=2
## Other options: --warmup=<frames> --samples=<frames> --screenshot=<png path>

const MAP_ID := "base"
const DEFAULT_FOCUS := Vector3(0.0, 5.0, 0.0)
const DEFAULT_RADIUS := 40.0
const DEFAULT_HEIGHT := 25.0
const ORBIT_RADIANS_PER_FRAME := 0.004
const DEFAULT_WARMUP_FRAMES := 1200
const DEFAULT_SAMPLE_FRAMES := 900

var _label := "unlabeled"
var _focus := DEFAULT_FOCUS
var _radius := DEFAULT_RADIUS
var _height := DEFAULT_HEIGHT
var _warmup_frames := DEFAULT_WARMUP_FRAMES
var _sample_frames := DEFAULT_SAMPLE_FRAMES
var _screenshot_path := ""
var _camera: Camera3D = null
var _frame := 0
var _gpu_ms := PackedFloat32Array()


func _ready() -> void:
	# 1. CLI options, so baseline and pbr runs are told apart and the camera path can move onto an ore face.
	_read_options()
	# 2. The real map with the same terrain injection SceneManager.swap_map performs.
	_load_map()
	# 3. Sky lighting and reflections so specular cost exists in both runs.
	_build_environment()
	# 4. Camera plus a VoxelViewer, which drives terrain streaming.
	_build_camera()
	# 5. GPU timing on the main viewport, vsync off so frames are not capped.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _process(_delta: float) -> void:
	_frame += 1
	# 1. Deterministic orbit position for this frame index.
	_place_camera(_frame)
	if _frame == _warmup_frames + 1:
		# 2. Optional screenshot of the first measured frame, for a quick look at the result.
		_save_screenshot()
	if _frame > _warmup_frames:
		_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	if _frame >= _warmup_frames + _sample_frames:
		# 3. Summary line the plan's results table is filled from.
		_report()
		get_tree().quit()


func _read_options() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--label="):
			_label = value
		elif arg.begins_with("--focus="):
			_focus = _parse_vector3(value)
		elif arg.begins_with("--radius="):
			_radius = float(value)
		elif arg.begins_with("--height="):
			_height = float(value)
		elif arg.begins_with("--warmup="):
			_warmup_frames = int(value)
		elif arg.begins_with("--samples="):
			_sample_frames = int(value)
		elif arg.begins_with("--screenshot="):
			_screenshot_path = value


func _parse_vector3(text: String) -> Vector3:
	var parts := text.split(",")
	if parts.size() != 3:
		printerr("terrain_bench: --focus expects x,y,z; using the default focus")
		return DEFAULT_FOCUS
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _load_map() -> void:
	var map_def: MapDef = MapLibrary.get_def(MAP_ID)
	var map: Node = load(map_def.scene_path).instantiate()
	var smooth := map.get_node_or_null("SmoothGrid") as SmoothGrid
	if smooth != null:
		smooth.terrain_gen = map_def.terrain_gen
		smooth.set_material_catalog(BuildLibrary.get_terrain_materials())
	if map is Map:
		(map as Map).set_world_bounds(map_def.world_bounds)
	add_child(map)


func _build_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.shadow_enabled = false
	add_child(sun)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	_camera.add_child(viewer)
	_place_camera(0)


func _place_camera(frame: int) -> void:
	var angle := float(frame) * ORBIT_RADIANS_PER_FRAME
	_camera.position = _focus + Vector3(cos(angle) * _radius, _height, sin(angle) * _radius)
	_camera.look_at(_focus)


func _save_screenshot() -> void:
	if _screenshot_path == "":
		return
	var image := get_viewport().get_texture().get_image()
	if image == null:
		printerr("terrain_bench: no viewport image (dummy renderer?)")
		return
	image.save_png(_screenshot_path)


func _report() -> void:
	var sorted_ms := _gpu_ms.duplicate()
	sorted_ms.sort()
	var total := 0.0
	for value: float in _gpu_ms:
		total += value
	var mean := total / maxf(1.0, float(_gpu_ms.size()))
	var p95 := sorted_ms[int(float(sorted_ms.size()) * 0.95)] if not sorted_ms.is_empty() else 0.0
	print("BENCH label=%s gpu_mean_ms=%.3f gpu_p95_ms=%.3f frames=%d focus=%s radius=%.1f" % [
			_label, mean, p95, _gpu_ms.size(), _focus, _radius])
