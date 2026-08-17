extends Node3D
## Extended runtime spike: is the SMOOTH terrain EDITABLE and PERSISTENT in this
## addon build? The base spike (smooth_terrain_spike.gd, F7) proved render +
## collide + coexist; the dual-voxel conversion (docs/TODO.md Phase 2) additionally
## needs, before smooth_grid.gd can be designed:
##
##   (a) VoxelTool.do_sphere CARVE and ADD both change the collision surface
##       (rendering judged from the screenshot, per F7 headless/mesh limits).
##   (b) A VoxelStreamSQLite + save_modified_blocks() round-trip: edits survive
##       a full terrain teardown/rebuild, with saved blocks overriding the
##       generator (smooth analogue of F2, proven there for blocky).
##   (c) The D2 material representation: can VoxelMesherTransvoxel map distinct
##       voxel values to distinct materials in this build, or is it single-
##       material (→ the documented fallback: one visual material + stored
##       identity in defs)?
##   (d) The exact block-loaded/unloaded signal names on VoxelTerrain (D4's
##       heightfield-cache invalidation hooks need them).
##
## Verdicts land in docs/VOXEL-TOOL-NOTES.md as F8. Answers are measured with
## layer-masked downward physics raycasts (headless-safe); the material question
## is additionally read off the mesher API + mesh surfaces, and confirmed
## visually from the screenshot in windowed runs.
##
## The world is smooth-only — coexistence is settled (F7); adding a blocky
## island here would only add noise. Terrain stays at the origin (F7: translated
## terrains render nothing). Collision layer = bit 3 value 4 (production
## "TerrainSmooth", project.godot layer names), mask = 1 so a dropped probe
## body would collide (F7 bidirectional rule) — this spike only raycasts, but
## keeps the mask correct anyway as documentation-by-example.
##
## CLI user args (after `--`): `--auto-quit=<seconds>` quits N seconds after the
## verdict (automated runs); `--keep-db` does not delete tmp/spike DB first
## (inspect a previous run's database).
##
## Controls: WASD move, Space/C up/down, Shift fast, mouse look (click to grab,
## Esc to release), Q to quit.

const NOISE_SEED := 20260817
const NOISE_FREQUENCY := 0.012
const HEIGHT_START := -4.0
const HEIGHT_RANGE := 12.0
const SMOOTH_LAYER := 4   ## Production layer 3 (bit value 4, "TerrainSmooth").
const BODY_LAYER := 1     ## Probe bodies' layer (F7: terrain mask must include it).
const SPHERE_RADIUS := 2.5
const SETTLE_SECONDS := 2.5
## Ray origin/length for column height probes (height_at-style).
const RAY_FROM_Y := 64.0
const RAY_LENGTH := 128.0
const DB_PATH := "res://tmp/smooth_edit_spike.sqlite"
const REBUILD_TOLERANCE := 0.5

var _terrain: VoxelTerrain = null
var _mode_hint := ""
var _camera: Camera3D
var _label: Label
var _diagnostics := PackedStringArray()
var _auto_quit_after := 0.0
var _keep_db := false

# Verdict accumulators.
var _carve_ok := false
var _add_ok := false
var _persist_ok := false
var _signals_found: PackedStringArray = []
var _signal_hits := {}                    # signal name -> emission count
var _material_verdict := "undetermined"
var _add_value_used := -1                 # which voxel value produced a solid bump
var _carve_col := Vector3i.ZERO
var _add_col := Vector3i.ZERO
var _h_carve_before := NAN
var _h_add_before := NAN
var _h_carve_after := NAN
var _h_add_after := NAN
var _h_control_before := NAN              # untouched column, generator sanity ref
var _control_col := Vector3i.ZERO

func _ready() -> void:
	_read_user_args()
	_wipe_db()
	_build_world()
	await _settle()
	_phase_discovery()
	_phase_baseline()
	await _phase_carve()
	await _phase_add()
	await _phase_persist()
	_emit_verdict()
	_refresh_label()
	if _auto_quit_after > 0.0:
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_capture_screenshot()
		await get_tree().create_timer(_auto_quit_after).timeout
		get_tree().quit()

func _read_user_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--auto-quit="):
			_auto_quit_after = maxf(0.0, float(arg.get_slice("=", 1)))
		elif arg == "--keep-db":
			_keep_db = true

func _wipe_db() -> void:
	if _keep_db:
		return
	if FileAccess.file_exists(DB_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DB_PATH))
		_log("db: wiped %s" % DB_PATH)

# --- World --------------------------------------------------------------------

func _build_world() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)

	_terrain = _build_smooth_terrain()
	add_child(_terrain)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.transform.origin = Vector3(0, 20, 46)
	_camera.rotation_degrees = Vector3(-25, 0, 0)
	add_child(_camera)

	# One viewer drives streaming + collision around the origin — the edit sites
	# are chosen within a few units of it so F3's "unloaded writes are no-ops"
	# cannot silently eat a do_sphere.
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	_camera.add_child(viewer)

	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_color_shadow", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_label)

	_log("=== smooth EDIT spike | headless=%s db=%s ===" % [
		DisplayServer.get_name(), DB_PATH,
	])

func _build_smooth_terrain() -> VoxelTerrain:
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED
	noise.frequency = NOISE_FREQUENCY
	var generator := VoxelGeneratorNoise2D.new()
	if "noise" in generator:
		generator.set("noise", noise)
	if "height_start" in generator:
		generator.set("height_start", HEIGHT_START)
	if "height_range" in generator:
		generator.set("height_range", HEIGHT_RANGE)

	var mesher := VoxelMesherTransvoxel.new()
	_materials_probe(mesher)

	var stream := VoxelStreamSQLite.new()
	stream.database_path = DB_PATH

	var terrain := VoxelTerrain.new()
	if "generator" in terrain:
		terrain.set("generator", generator)
	if "mesher" in terrain:
		terrain.set("mesher", mesher)
	terrain.set("stream", stream)
	if "collision_layer" in terrain:
		terrain.set("collision_layer", SMOOTH_LAYER)
	if "collision_mask" in terrain:
		terrain.set("collision_mask", BODY_LAYER)
	return terrain

func _settle() -> void:
	# F3: mesh/collision generation is threaded; settles are generous on purpose.
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	await get_tree().physics_frame
	await get_tree().physics_frame

# --- Phase: API discovery (answers (d), informs (a)/(c)) -----------------------

func _phase_discovery() -> void:
	_log("--- discovery ---")

	# (d) Block-loaded signal names. Everything the D4 cache invalidation can
	# hook must appear here. Counted via per-signal methods — a bound name arg
	# would slot into an absorber (bound args append AFTER signal args), which
	# is exactly how run 1 lost 9928 emissions into a "<null>" bucket.
	_connect_block_signals()
	_log("terrain block signals: %s" % (
		"[no signals matching 'block' — D4 hook needs another mechanism]" if _signals_found.is_empty()
		else ", ".join(_signals_found)
	))

	# VoxelTool surface: which modes + value semantics exist in this build. The
	# mode enum is read from the property's hint string ("MODE_SET:0,...") —
	# this Godot build lacks the ClassDB constant-listing statics, and a static
	# VoxelTool.MODE_REMOVE reference would fail to parse if absent.
	var vt := _terrain.get_voxel_tool()
	for p: Dictionary in vt.get_property_list():
		if p["name"] == "mode":
			_mode_hint = str(p.get("hint_string", ""))
	_log("VoxelTool mode enum: %s (current=%s)" % [
		_mode_hint if _mode_hint != "" else "(no enum hint)", vt.mode,
	])
	var vt_methods: PackedStringArray = []
	for m: Dictionary in vt.get_method_list():
		var n: String = m["name"]
		if n.begins_with("do_") or n.begins_with("get_voxel") or n.begins_with("set_voxel"):
			vt_methods.append(n)
	_log("VoxelTool brush/read methods: %s" % ", ".join(vt_methods))

	# Channel semantics around a known surface — reveals whether solid is
	# positive/negative and int/float in this build (informs get_material_at).
	if _probe_height(0, 0) == _probe_height(0, 0):  # not NAN — column (0,0) exists
		var h := _probe_height(0, 0)
		_log("channel values at (0,0): deep=%s surface=%s air=%s" % [
			_read_voxel(vt, Vector3(0, h - 2.0, 0)),
			_read_voxel(vt, Vector3(0, h, 0)),
			_read_voxel(vt, Vector3(0, h + 2.0, 0)),
		])

func _read_voxel(vt: VoxelTool, world: Vector3) -> String:
	var pos := Vector3i(int(floor(world.x)), int(floor(world.y)), int(floor(world.z)))
	var txt := "int="
	if vt.has_method("get_voxel"):
		txt += str(vt.get_voxel(pos))
	if vt.has_method("get_voxel_f"):
		txt += " float=%.3f" % vt.get_voxel_f(pos)
	return txt

## Discover + connect the block-streaming signals, resetting counters. Arity is
## logged — D4's invalidation hooks need the exact signature, not just the name.
func _connect_block_signals() -> void:
	_signals_found = PackedStringArray()
	_signal_hits = {}
	for sig: Dictionary in _terrain.get_signal_list():
		var sig_name: String = sig["name"]
		if sig_name.find("block") < 0:
			continue
		_signals_found.append(sig_name)
		_signal_hits[sig_name] = 0
		_log("signal %s: %d args %s" % [sig_name, sig["args"].size(), sig["args"]])
		match sig_name:
			"block_loaded":
				_terrain.connect(sig_name, _count_block_loaded)
			"block_unloaded":
				_terrain.connect(sig_name, _count_block_unloaded)
			"mesh_block_entered":
				_terrain.connect(sig_name, _count_mesh_entered)
			"mesh_block_exited":
				_terrain.connect(sig_name, _count_mesh_exited)
			_:
				_log("signal %s: no counter wired (new in this build?)" % sig_name)

func _count_block_loaded(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_bump("block_loaded")

func _count_block_unloaded(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_bump("block_unloaded")

func _count_mesh_entered(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_bump("mesh_block_entered")

func _count_mesh_exited(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_bump("mesh_block_exited")

func _bump(name: String) -> void:
	_signal_hits[name] = int(_signal_hits.get(name, 0)) + 1

## Parse "NAME:value" pairs out of a property enum hint string. -1 = not present.
func _enum_value(hint: String, const_name: String) -> int:
	for pair: String in hint.split(","):
		var bits := pair.split(":")
		if bits.size() == 2 and bits[0].strip_edges() == const_name:
			return int(bits[1])
	return -1

# --- Phase: baseline -----------------------------------------------------------

func _phase_baseline() -> void:
	_log("--- baseline ---")
	# Pick edit columns near the origin (streamed-in by the viewer): first solid
	# column = carve site; the next column >= 10 units away = add site; one more
	# column >= 12 from BOTH edits = untouched control (edit spheres are r=2.5,
	# so 12 guarantees no contamination of the persistence comparison).
	var found := 0
	for x: int in range(-12, 13, 2):
		for z: int in range(-12, 13, 2):
			var h := _probe_height(x, z)
			if h != h:  # NAN — no smooth ground in this column
				continue
			if found == 0:
				_carve_col = Vector3i(x, 0, z)
				_h_carve_before = h
				found += 1
			elif found == 1 and Vector2(x - _carve_col.x, z - _carve_col.z).length() >= 10.0:
				_add_col = Vector3i(x, 0, z)
				_h_add_before = h
				found += 1
			elif found == 2 \
					and Vector2(x - _carve_col.x, z - _carve_col.z).length() >= 12.0 \
					and Vector2(x - _add_col.x, z - _add_col.z).length() >= 12.0:
				_control_col = Vector3i(x, 0, z)
				_h_control_before = h
				found += 1
				break
		if found >= 3:
			break
	_log("carve col %s h=%.3f | add col %s h=%.3f | control col %s h=%.3f" % [
		Vector2(_carve_col.x, _carve_col.z), _h_carve_before,
		Vector2(_add_col.x, _add_col.z), _h_add_before,
		Vector2(_control_col.x, _control_col.z), _h_control_before,
	])

# --- Phase: carve (a) ----------------------------------------------------------

func _phase_carve() -> void:
	_log("--- carve ---")
	var vt := _terrain.get_voxel_tool()
	# MODE_REMOVE is the semantic carve. The mode enum hint parsed above lists
	# it ("Add,Remove,Set"), so the static constant exists in this build. Fallback
	# if the drop check fails: MODE_SET with a negative value writes positive
	# SDF (= air — channel probe showed air=+1.999, deep=-1.999, solid <= 0).
	var used := "MODE_REMOVE"
	vt.mode = VoxelTool.MODE_REMOVE
	_log("carve: %s at (%d, %.2f, %d) radius %.1f" % [
		used, _carve_col.x, _h_carve_before + 0.5, _carve_col.z, SPHERE_RADIUS,
	])
	vt.do_sphere(Vector3(_carve_col.x, _h_carve_before + 0.5, _carve_col.z), SPHERE_RADIUS)
	await _settle()
	_h_carve_after = _probe_height(_carve_col.x, _carve_col.z)
	var delta := _h_carve_after - _h_carve_before
	_carve_ok = delta == delta and delta <= -(SPHERE_RADIUS * 0.5)
	if not _carve_ok:
		# Fallback carve: solid <= 0 in this channel, so SDF +2 (= value -2 via
		# the density-sign convention observed: value v writes SDF -v) is air.
		used = "MODE_SET value=-2"
		vt.mode = VoxelTool.MODE_SET
		vt.value = -2
		vt.do_sphere(Vector3(_carve_col.x, _h_carve_before + 0.5, _carve_col.z), SPHERE_RADIUS)
		await _settle()
		_h_carve_after = _probe_height(_carve_col.x, _carve_col.z)
		delta = _h_carve_after - _h_carve_before
		_carve_ok = delta == delta and delta <= -(SPHERE_RADIUS * 0.5)
		_log("carve fallback %s: delta=%.3f" % [used, delta])
	_log("carve: before=%.3f after=%.3f delta=%.3f -> %s" % [
		_h_carve_before, _h_carve_after, delta, "PASS" if _carve_ok else "FAIL",
	])

# --- Phase: add (a) + materials (c) --------------------------------------------

func _phase_add() -> void:
	_log("--- add ---")
	var center := Vector3(_add_col.x, _h_add_before + SPHERE_RADIUS * 0.5, _add_col.z)
	# Solid-value candidates for MODE_SET on smooth terrain. Which one bites
	# depends on the channel semantics discovered above (int SDF vs float
	# density); try in order, first collision rise wins.
	for value: int in [1, 100, 1000]:
		var vt := _terrain.get_voxel_tool()
		vt.mode = VoxelTool.MODE_SET
		vt.value = value
		vt.do_sphere(center, SPHERE_RADIUS)
		await _settle()
		var h := _probe_height(_add_col.x, _add_col.z)
		var delta := h - _h_add_before
		_log("add try value=%d: before=%.3f after=%.3f delta=%.3f" % [
			value, _h_add_before, h, delta,
		])
		if delta == delta and delta >= SPHERE_RADIUS * 0.5:
			_add_ok = true
			_add_value_used = value
			_h_add_after = h
			break
	_log("add: -> %s (value=%d)" % ["PASS" if _add_ok else "FAIL", _add_value_used])

	# (c) If a second distinct value can also produce solid ground, materials
	# could ride the value channel; whether the MESHER distinguishes them is the
	# actual D2 question — read it off the mesh surfaces now.
	await _materials_verdict()

# --- Phase: persistence (b) ----------------------------------------------------

func _phase_persist() -> void:
	_log("--- persistence ---")
	if not (_carve_ok or _add_ok):
		_log("persist: SKIP — nothing edited successfully")
		return
	_terrain.save_modified_blocks()
	_log("persist: save_modified_blocks() flushed (carve=%.3f add=%.3f control=%.3f)" % [
		_h_carve_after, _h_add_after, _h_control_before,
	])
	# Full teardown + rebuild: same generator params, same stream. If the stream
	# did NOT override the generator, heights revert to the baseline.
	_terrain.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_terrain = _build_smooth_terrain()
	# Re-connect the signal counters — the old terrain node (and its signal
	# emissions) died with the teardown; the counters reset inside.
	_connect_block_signals()
	add_child(_terrain)
	await _settle()

	var h_carve := _probe_height(_carve_col.x, _carve_col.z)
	var h_add := _probe_height(_add_col.x, _add_col.z)
	var h_control := _probe_height(_control_col.x, _control_col.z)
	var carve_held := absf(h_carve - _h_carve_after) < REBUILD_TOLERANCE if _carve_ok else true
	var add_held := absf(h_add - _h_add_after) < REBUILD_TOLERANCE if _add_ok else true
	var control_held := absf(h_control - _h_control_before) < REBUILD_TOLERANCE
	_persist_ok = carve_held and add_held and control_held
	_log("persist: rebuilt carve=%.3f (want %.3f) add=%.3f (want %.3f) control=%.3f (want %.3f)" % [
		h_carve, _h_carve_after, h_add, _h_add_after, h_control, _h_control_before,
	])
	_log("persist: carve_held=%s add_held=%s control_held=%s -> %s" % [
		carve_held, add_held, control_held, "PASS" if _persist_ok else "FAIL",
	])
	_log("persist: block-signal emissions during rebuild: %s" % str(_signal_hits))

# --- Materials (c) --------------------------------------------------------------

## Enumerate what VoxelMesherTransvoxel exposes material-wise, and try to assign
## two distinct Materials for two distinct voxel values. What exists here decides
## the data/terrain/materials schema (D2): per-value materials if supported,
## otherwise single visual material + identity-in-def fallback.
func _materials_probe(mesher: VoxelMesherTransvoxel) -> void:
	var all_props: PackedStringArray = []
	var mat_props: PackedStringArray = []
	for p: Dictionary in mesher.get_property_list():
		var n: String = p["name"]
		all_props.append(n)
		if n.find("material") >= 0:
			mat_props.append(n)
	var mat_methods: PackedStringArray = []
	for m: Dictionary in mesher.get_method_list():
		var n: String = m["name"]
		if n.find("material") >= 0:
			mat_methods.append(n)
	_materials_props = mat_props
	_materials_methods = mat_methods
	_log("mesher all props: %s" % ", ".join(all_props))
	_log("mesher material props: %s" % (", ".join(mat_props) if not mat_props.is_empty() else "(none)"))
	_log("mesher material methods: %s" % (", ".join(mat_methods) if not mat_methods.is_empty() else "(none)"))

var _materials_props: PackedStringArray = []
var _materials_methods: PackedStringArray = []

func _materials_verdict() -> void:
	# Run 1 established: terrain meshes are NOT node children (surface walk found
	# zero MeshInstance3D), and the mesher exposes no material API at all. So the
	# D2 question reduces to: can any distinct-value write at least coexist
	# geometrically (future identity encoding), and the verdict is API-based.
	var has_material_api := false
	for n: String in _materials_props:
		if n != "script":
			has_material_api = true
	if not _materials_methods.is_empty():
		has_material_api = true

	if _add_ok:
		# A second distinct value bumped beside the first: both must rise, proving
		# magnitude is a free parameter (SDF density), not an id switch.
		var other := 2 if _add_value_used != 2 else 3
		var second := Vector3(_add_col.x + 6, _h_add_before + SPHERE_RADIUS * 0.5, _add_col.z)
		var h2_before := _probe_height(second.x, second.z)
		var vt := _terrain.get_voxel_tool()
		vt.mode = VoxelTool.MODE_SET
		vt.value = other
		vt.do_sphere(second, SPHERE_RADIUS)
		await _settle()
		var h2 := _probe_height(second.x, second.z)
		var rose := h2 == h2 and h2 - h2_before >= SPHERE_RADIUS * 0.5
		_log("materials: second bump value=%d rose=%s (before=%.3f after=%.3f)" % [
			other, rose, h2_before, h2,
		])
		if has_material_api:
			_material_verdict = "material API present (see mesher props/methods) — per-value visuals worth designing"
		elif rose:
			_material_verdict = "NO material API on VoxelMesherTransvoxel in this build; values are pure density — D2: defs carry identity/hardness only, ONE visual appearance (fallback is the ceiling, not a fallback)"
		else:
			_material_verdict = "NO material API and only value=%d writes solid — identity encoding needs another channel entirely" % _add_value_used
	else:
		_material_verdict = "undetermined (add failed — material question moot until writes work)"
	_log("materials verdict: %s" % _material_verdict)

# --- Verdict -------------------------------------------------------------------

func _emit_verdict() -> void:
	var signals_txt := (
		"verified: %s" % str(_signal_hits) if not _signals_found.is_empty()
		else "NOT FOUND on VoxelTerrain in this build"
	)
	_log("--- VERDICT (smooth edit spike) ---")
	_log("(a) carve: %s | add: %s (value=%d)" % [
		"PASS" if _carve_ok else "FAIL", "PASS" if _add_ok else "FAIL", _add_value_used,
	])
	_log("(b) stream round-trip: %s" % ("PASS" if _persist_ok else ("SKIP" if not (_carve_ok or _add_ok) else "FAIL")))
	_log("(c) materials: %s" % _material_verdict)
	_log("(d) block signals: %s" % signals_txt)
	var go := (_carve_ok or _add_ok) and _persist_ok
	_log("*** %s ***" % ("GO: smooth terrain is editable + persistent in this build" if go
			else "NO-GO / PARTIAL — read F8 before building smooth_grid.gd"))

# --- Shared helpers --------------------------------------------------------------

func _probe_height(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, RAY_FROM_Y, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_LENGTH)
	query.collision_mask = SMOOTH_LAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else NAN

func _capture_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "/store/backups/act/godot/vek-holdout/tmp/spike_smooth_edit.png"
	var err := img.save_png(path)
	_log("screenshot: %s" % ("saved " + path if err == OK else "ERROR %d" % err))

func _log(line: String) -> void:
	_diagnostics.append(line)
	print(line)

func _refresh_label() -> void:
	if _label:
		_label.text = "\n".join(_diagnostics)

# --- Fly camera input (same as smooth_terrain_spike.gd) --------------------------

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
