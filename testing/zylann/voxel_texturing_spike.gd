extends Node3D
## Smooth-terrain TEXTURING spike (-> F14, terrain-visuals plan step 1): nine
## windowed runs establishing, for THIS addon build AND the official v1.7x
## binary, that the transvoxel mesher's per-voxel texture-index system
## (`texturing_mode` Mixel4/Single -> CUSTOM1) is API-present but
## NON-FUNCTIONAL: the VoxelTool painting APIs write CHANNEL_INDICES/
## CHANNEL_WEIGHTS and the data persists through save_modified_blocks, but the
## mesher always emits DEFAULT texture-0 CUSTOM1 (the uniform-0 branch) no
## matter the mode, channel, depth, or data. Retained as the F14 evidence and
## as the harness for re-testing any future addon bump:
##
##   (T1) API presence: mesher `texturing_mode` (0 none / 1 Mixel4_S4 /
##        2 Single_S4), MODE_TEXTURE_PAINT=3, texture_index/opacity/falloff,
##        `channel`; CHANNEL_INDICES=3 CHANNEL_WEIGHTS=4 CHANNEL_SDF=1; all
##        probed via ClassDB / guarded set() so a missing API degrades to a
##        printed SKIP, never a parse error.
##   (T2) Data painting + live readback (packed-u16 nibble decode by hand).
##   (T3) Persistence: two save/rebuild cycles per mode.
##   (T4) Visual CUSTOM1: debug shader on material_override + viewport pixel
##        sampling at the painted blobs (automated stand-in for eyes).
##   (T5) Mesher isolation: hand-built VoxelBuffer -> build_mesh -> inspect
##        ARRAY_CUSTOM1 bytes; the falsification sweep (mode x channel x
##        depth) that closed the question.
##
## Harness idioms are voxel_metadata_spike.gd's (F12): origin-anchored
## VoxelTerrain, parked camera + VoxelViewer near every edit site, generous
## settles, `--auto-quit=<seconds>` automation, `--keep-db`, plus this spike's
## own `--isolation-only` fast path.

const NOISE_SEED := 20260817
const NOISE_FREQUENCY := 0.012
const HEIGHT_START := -4.0
const HEIGHT_RANGE := 12.0
const SMOOTH_LAYER := 4
const BODY_LAYER := 1
const SPHERE_RADIUS := 2.5
const SETTLE_SECONDS := 2.5
const RAY_FROM_Y := 64.0
const RAY_LENGTH := 128.0
const MIXEL4_DB := "res://tmp/voxel_texturing_spike.mixel4.sqlite"
const SINGLE_DB := "res://tmp/voxel_texturing_spike.single.sqlite"
## T4 color classification margins: patch averages are classified by channel
## dominance; these are loose because blob edges blend and MSAA smears.
const DOMINANCE_RATIO := 2.0

## Runtime-resolved API (parse-safe: unknown constants would kill the script).
var _ch_indices := -1
var _ch_weights := -1
var _ch_sdf := -1
var _mode_texture_paint := -1
var _mode_mixel4 := -1
var _mode_single := -1

var _terrain: VoxelTerrain = null
var _vt: VoxelTool = null
var _camera: Camera3D = null
var _auto_quit_after := 0.0
var _keep_db := false
var _iso_only := false

## Probes per mode tag: Vector3i -> {kind, want_idx}. `control` entries record
## the unpainted default instead of asserting a value for it.
var _probes := {}
## Same probes keyed by column (Vector2i) — visual sampling recomputes surface
## heights after SDF nudges, so exact-cell keys drift; columns are stable.
var _probe_by_col := {}
## Per-mode visual expectations, one per site in site order (paint sites then
## control last) — filled by the paint phases, read by _phase_visual.
var _site_expect := {}
## Verdicts per mode tag.
var _live := {}
var _persist := {}
var _visual := {}
var _detail := {}
## Visual bookkeeping: sites per mode (survive rebuilds — the generator is
## deterministic and paint never touches SDF) and the live-mesh result, kept
## separate from _visual (the authoritative remeshed-mesh result).
var _visual_sites := {}
var _visual_live := {}
var _debug_materials := {}


func _ready() -> void:
	_read_user_args()
	_wipe_dbs()
	_phase_api()
	_phase_mesher_isolation()
	if _iso_only:
		_emit_verdict()
		if _auto_quit_after > 0.0:
			await get_tree().create_timer(_auto_quit_after).timeout
			get_tree().quit()
		return
	_build_rig()
	await _run_mode("mixel4")
	await _run_mode("single")
	_emit_verdict()
	if _auto_quit_after > 0.0:
		await get_tree().create_timer(_auto_quit_after).timeout
		get_tree().quit()


## T5 — mesher isolation: mesh hand-built VoxelBuffers directly and inspect
## the output ArrayMesh. No terrain, no stream — splits "the mesher in THIS
## build cannot honor texturing channels" from "the terrain feeds it the wrong
## data". Run 6 lessons so far: the addon's own encoders confirm the packed
## u16s, buffer writes land (readback), yet output weights are pure DEFAULTS —
## so this build's mesher may read the channels from different indices than
## upstream master (vendored v1.6/1.7 vs master drift). This pass varies the
## candidate channel indices and watches which one the mesher honors.
func _phase_mesher_isolation() -> void:
	print("--- mesher isolation (T5) ---")
	var depth8: int = ClassDB.class_get_integer_constant("VoxelBuffer", "DEPTH_8_BIT")
	var depth16: int = ClassDB.class_get_integer_constant("VoxelBuffer", "DEPTH_16_BIT")
	var gt_indices: int = VoxelTool.vec4i_to_u16_indices(Vector4i(0, 1, 2, 3))
	var gt_paint: int = VoxelTool.color_to_u16_weights(Color(0, 1, 0, 0))
	var gt_plain: int = VoxelTool.color_to_u16_weights(Color(1, 0, 0, 0))
	print("isolation: encodings — indices(0,1,2,3)=0x%04X paint-tex1=0x%04X plain-tex0=0x%04X" % [
		gt_indices, gt_paint, gt_plain,
	])
	var size := 20
	# A) Mixel4: which channel carries the weights? Solid cells paint texture
	# 1 (and carry unique index 4 so per-voxel INDICES honoring is visible too).
	var solid_i: int = VoxelTool.vec4i_to_u16_indices(Vector4i(0, 1, 2, 4))
	var air_i: int = VoxelTool.vec4i_to_u16_indices(Vector4i(0, 1, 2, 3))
	for wch: int in [_ch_weights, 5, 6, 7]:
		var buf := _make_iso_buffer(size, depth16, "mixel4", _ch_indices, wch, solid_i, air_i, gt_paint, gt_plain)
		var stats := _mesh_iso_stats(buf, 1, 2)
		var rb_solid: int = buf.get_voxel(10, 8, 10, _ch_indices)
		var rb_air: int = buf.get_voxel(10, 12, 10, _ch_indices)
		print("isolation[mixel4 weights@ch%d]: %s | readback solid=0x%04X air=0x%04X" % [
			wch, stats, rb_solid, rb_air,
		])
	# B) Single: one 8-bit index per voxel; CUSTOM1 carries the same 2-float
	# (indices, weights) pair as Mixel4. Run 8 suspicion: get_material_indices
	# ASSERTs depth==8-bit and silently returns uniform-0 otherwise — the exact
	# "pure defaults" emission observed so far. So VERIFY the channel depth
	# under three depth-assignment strategies and see which one the mesher
	# honors. Half the solid mass paints 1, half paints 2, air 0.
	for strategy: String in ["indices@ch3", "indices@ch5", "indices@ch6", "indices@ch7"]:
		var ich: int = [3, 5, 6, 7][["indices@ch3", "indices@ch5", "indices@ch6", "indices@ch7"].find(strategy)]
		var sbuf := VoxelBuffer.new()
		sbuf.create(size, size, size)
		sbuf.set_channel_depth(_ch_sdf, depth16)
		sbuf.set_channel_depth(ich, depth8)
		for x: int in size:
			for z: int in size:
				for y: int in size:
					sbuf.set_voxel_f(clampf((float(y) - 10.0) * 0.5, -2.0, 2.0), x, y, z, _ch_sdf)
					var paint := 0
					if y < 10:
						paint = 1 if x < size / 2 else 2
					sbuf.set_voxel(paint, x, y, z, ich)
		var sstats := _mesh_iso_stats(sbuf, 2, 2)
		print("isolation[single %s]: depth=%d | %s | readback solid=%d air=%d" % [
			strategy, sbuf.get_channel_depth(ich), sstats,
			sbuf.get_voxel(5, 8, 10, ich), sbuf.get_voxel(5, 12, 10, ich),
		])


func _make_iso_buffer(size: int, depth16: int, mode_tag: String, ich: int, wch: int,
		solid_i: int, air_i: int, solid_w: int, air_w: int) -> VoxelBuffer:
	var buf := VoxelBuffer.new()
	buf.create(size, size, size)
	buf.set_channel_depth(_ch_sdf, depth16)
	if mode_tag == "mixel4":
		buf.set_channel_depth(ich, depth16)
		buf.set_channel_depth(wch, depth16)
	else:
		buf.set_channel_depth(ich, ClassDB.class_get_integer_constant("VoxelBuffer", "DEPTH_8_BIT"))
	for x: int in size:
		for z: int in size:
			for y: int in size:
				buf.set_voxel_f(clampf((float(y) - 10.0) * 0.5, -2.0, 2.0), x, y, z, _ch_sdf)
				if mode_tag == "mixel4":
					buf.set_voxel(solid_i if y < 10 else air_i, x, y, z, ich)
					buf.set_voxel(solid_w if y < 10 else air_w, x, y, z, wch)
				else:
					buf.set_voxel(solid_i if y < 10 else air_i, x, y, z, ich)
	return buf


## Mesh the buffer and summarize CUSTOM1: per-BYTE-POSITION value sets, parsed
## with the mode's float stride (2 for Mixel4, 1 for Single — "2*4*uint8 as
## 2*float32, or 3*uint8 as 1*float32"). Byte position matters: Single's index
## should be byte0 of the first float; aggregated sets hide that.
func _mesh_iso_stats(buf: VoxelBuffer, mode_int: int, stride: int) -> String:
	var mesher := VoxelMesherTransvoxel.new()
	mesher.set("texturing_mode", mode_int)
	if "textures_ignore_air_voxels" in mesher:
		mesher.set("textures_ignore_air_voxels", true)
	var mesh: Mesh = mesher.build_mesh(buf, [StandardMaterial3D.new()])
	if mesh == null or mesh.get_surface_count() == 0:
		return "NO SURFACE"
	var arrays := mesh.surface_get_arrays(0)
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if custom.is_empty():
		return "verts=%d CUSTOM1 EMPTY" % verts.size()
	var byte_sets := {}
	for vi: int in custom.size() / stride:
		for f: int in stride:
			var bytes := PackedFloat32Array([custom[vi * stride + f]]).to_byte_array()
			for b: int in 4:
				var key := "f%d.b%d" % [f, b]
				if not byte_sets.has(key):
					byte_sets[key] = {}
				byte_sets[key][bytes[b]] = true
	var parts := ""
	for key: String in byte_sets:
		var vals: Array = byte_sets[key].keys()
		vals.sort()
		parts += "%s=%s " % [key, vals]
	return "verts=%d CUSTOM1 ok | %s" % [verts.size(), parts]


func _read_user_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--auto-quit="):
			_auto_quit_after = maxf(0.0, float(arg.get_slice("=", 1)))
		elif arg == "--keep-db":
			_keep_db = true
		elif arg == "--isolation-only":
			_iso_only = true


func _wipe_dbs() -> void:
	if _keep_db:
		return
	for db: String in [MIXEL4_DB, SINGLE_DB]:
		if FileAccess.file_exists(db):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(db))
	print("db: wiped %s + %s" % [MIXEL4_DB, SINGLE_DB])


# --- World ----------------------------------------------------------------------

func _build_rig() -> void:
	# Camera high and steeply down so painted column tops are rarely occluded by
	# neighboring hills; VoxelViewer rides the camera (F3: unloaded = no-op).
	_camera = Camera3D.new()
	_camera.current = true
	_camera.transform.origin = Vector3(0, 22, 22)
	add_child(_camera)
	_camera.look_at(Vector3(0, -2, 0))
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	_camera.add_child(viewer)
	print("=== terrain texturing spike | display=%s ===" % DisplayServer.get_name())


func _build_smooth_terrain(mode_tag: String) -> VoxelTerrain:
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

	var stream := VoxelStreamSQLite.new()
	stream.database_path = MIXEL4_DB if mode_tag == "mixel4" else SINGLE_DB

	var mesher := VoxelMesherTransvoxel.new()
	if "texturing_mode" in mesher:
		mesher.set("texturing_mode", 1 if mode_tag == "mixel4" else 2)
	# Run 4 lesson: unpainted voxels carry DEFAULT weights (1,0,0,0) = texture
	# 0, and surface cells interpolate matter against air — air defaults
	# outvote the paint in the mixel4 cell selection unless ignored.
	if "textures_ignore_air_voxels" in mesher:
		mesher.set("textures_ignore_air_voxels", true)

	var terrain := VoxelTerrain.new()
	if "generator" in terrain:
		terrain.set("generator", generator)
	if "mesher" in terrain:
		terrain.set("mesher", mesher)
	terrain.set("stream", stream)
	# Run 3 lesson: the default VoxelFormat's indices depth (2 bits in this
	# build) makes the mesher skip texturing entirely — assign a format with
	# the mode's required depths to BOTH the terrain and the stream (loaded and
	# generated blocks may take their buffer format from either) BEFORE any
	# block streams in.
	if ClassDB.class_exists("VoxelFormat"):
		var fmt: Object = ClassDB.instantiate("VoxelFormat")
		var depth_name := "DEPTH_16_BIT" if mode_tag == "mixel4" else "DEPTH_8_BIT"
		fmt.set("indices_depth", ClassDB.class_get_integer_constant("VoxelBuffer", depth_name))
		if mode_tag == "mixel4" and "weights_depth" in fmt:
			fmt.set("weights_depth", ClassDB.class_get_integer_constant("VoxelBuffer", "DEPTH_16_BIT"))
		if "format" in terrain:
			terrain.set("format", fmt)
		if "preferred_coordinate_format" in stream:
			stream.set("preferred_coordinate_format", fmt)
	if "collision_layer" in terrain:
		terrain.set("collision_layer", SMOOTH_LAYER)
	if "collision_mask" in terrain:
		terrain.set("collision_mask", BODY_LAYER)
	return terrain


func _teardown_terrain() -> void:
	if _terrain != null:
		_terrain.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	_terrain = null
	_vt = null


func _settle(extra := 0.0) -> void:
	# F3: mesh/collision generation is threaded; settles are generous on purpose.
	await get_tree().create_timer(SETTLE_SECONDS + extra).timeout
	await get_tree().physics_frame
	await get_tree().physics_frame


## F9: block saves commit asynchronously; poll the `-journal` file away (bounded).
func _await_journal_clear(db: String) -> void:
	var journal := db + "-journal"
	var waited := 0.0
	while FileAccess.file_exists(journal) and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	print("persist: journal clear after %.1fs (present=%s)" % [
		waited, FileAccess.file_exists(journal),
	])


# --- One mode end-to-end ----------------------------------------------------------

func _run_mode(mode_tag: String) -> void:
	print("--- mode %s ---" % mode_tag)
	_probes[mode_tag] = {}
	_probe_by_col[mode_tag] = {}
	await _teardown_terrain()
	_terrain = _build_smooth_terrain(mode_tag)
	add_child(_terrain)
	_vt = _terrain.get_voxel_tool()
	await _settle()
	# Run 8 suspect: if the terrain reset its mesher (or the property) when
	# entering the tree, every mesh is texturing-less and CUSTOM1 is absent —
	# which matches all gray evidence. Read it back from the LIVE terrain.
	var live_mesher: Variant = _terrain.get("mesher")
	var live_mode: Variant = live_mesher.get("texturing_mode") \
			if live_mesher != null and live_mesher is Object and "texturing_mode" in live_mesher \
			else "n/a"
	var want_mode := 1 if mode_tag == "mixel4" else 2
	print("%s live: mesher=%s texturing_mode=%s (want %d)%s" % [
		mode_tag, live_mesher, live_mode, want_mode,
		"" if int(live_mode) == want_mode else "  <-- LOST, re-setting",
	])
	if int(live_mode) != want_mode and live_mesher != null and live_mesher is Object:
		live_mesher.set("texturing_mode", want_mode)

	if mode_tag == "mixel4":
		await _phase_mixel4(mode_tag)
	else:
		await _phase_single(mode_tag)
	await _phase_persist(mode_tag)


# --- T1: API presence --------------------------------------------------------------

func _phase_api() -> void:
	# Runs once, before the first mode. ClassDB keeps every probe runtime-safe.
	_ch_indices = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_INDICES")
	_ch_weights = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_WEIGHTS")
	_ch_sdf = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_SDF")
	_mode_texture_paint = ClassDB.class_get_integer_constant("VoxelTool", "MODE_TEXTURE_PAINT")
	_mode_mixel4 = ClassDB.class_get_integer_constant("VoxelMesherTransvoxel", "TEXTURES_MIXEL4_S4")
	_mode_single = ClassDB.class_get_integer_constant("VoxelMesherTransvoxel", "TEXTURES_SINGLE_S4")
	var mesher := VoxelMesherTransvoxel.new()
	var has_mode_prop := "texturing_mode" in mesher
	var roundtrip := -1
	if has_mode_prop:
		mesher.set("texturing_mode", 1)
		roundtrip = int(mesher.get("texturing_mode"))
	print("api: texturing_mode prop=%s roundtrip(1)=%d | enum MIXEL4_S4=%d SINGLE_S4=%d" % [
		has_mode_prop, roundtrip, _mode_mixel4, _mode_single,
	])
	print("api: CHANNEL_INDICES=%d CHANNEL_WEIGHTS=%d CHANNEL_SDF=%d | MODE_TEXTURE_PAINT=%d" % [
		_ch_indices, _ch_weights, _ch_sdf, _mode_texture_paint,
	])
	print("api: VoxelTool helpers: u16_indices_to_vec4i=%s u16_weights_to_color=%s | VoxelFormat class=%s" % [
		ClassDB.class_has_method("VoxelTool", "u16_indices_to_vec4i"),
		ClassDB.class_has_method("VoxelTool", "u16_weights_to_color"),
		ClassDB.class_exists("VoxelFormat"),
	])
	# Format discovery: Single mode's warning says the default VoxelFormat
	# carries a 2-bit indices depth — if a *depth property is reachable from
	# terrain or stream, production can fix it without touching the addon.
	var terrain_props := _props_matching(VoxelTerrain.new(), "format")
	var stream_props := _props_matching(VoxelStreamSQLite.new(), "format")
	var fmt_depths: Array = []
	if ClassDB.class_exists("VoxelFormat"):
		for p: Dictionary in ClassDB.class_get_property_list("VoxelFormat"):
			if "depth" in String(p["name"]):
				fmt_depths.append(p["name"])
	print("api: format props — VoxelTerrain=%s VoxelStreamSQLite=%s | VoxelFormat depths=%s" % [
		terrain_props, stream_props, fmt_depths,
	])
	# Run 3 lesson: the mesher only reads texturing channels when the block's
	# INDICES depth matches the mode (16-bit Mixel4 / 8-bit Single — upstream
	# transvoxel_materials_mixel4.h asserts DEPTH_16_BIT and returns EMPTY data
	# otherwise, so CUSTOM1 never reaches the mesh). Enum values may differ from
	# upstream master in this build — resolve them at runtime.
	var depth_consts := {}
	for c: String in ClassDB.class_get_integer_constant_list("VoxelBuffer"):
		if c.begins_with("DEPTH_"):
			depth_consts[c] = ClassDB.class_get_integer_constant("VoxelBuffer", c)
	print("api: VoxelBuffer DEPTH constants=%s" % depth_consts)


func _props_matching(object: Object, needle: String) -> Array:
	var found: Array = []
	for p: Dictionary in object.get_property_list():
		if needle in String(p["name"]):
			found.append(p["name"])
	# VoxelStreamSQLite is a RefCounted Resource; only Nodes take free().
	if object is not RefCounted:
		object.free()
	return found


# --- T2/T4: Mixel4 -----------------------------------------------------------------

## Paint blobs of indices 1/2/3 on three spaced columns, read the channels back,
## then run the pixel oracle. Mixel4 semantics (upstream docs): 4x 4-bit unique
## indices in 16-bit CHANNEL_INDICES + 4x 4-bit weights in CHANNEL_WEIGHTS;
## unpainted voxels read as indices (0,1,2,3) weights (1,0,0,0) => texture 0.
func _phase_mixel4(mode_tag: String) -> void:
	if _mode_texture_paint < 0 or _ch_indices < 0:
		print("mixel4: SKIP — API absent")
		_live[mode_tag] = false
		return
	print("--- mixel4 paint (T2) ---")
	var sites := _pick_columns(4)
	if sites.size() < 4:
		print("mixel4: SKIP — not enough ground columns near origin")
		_live[mode_tag] = false
		return

	var sdf_before := _read_sdf(Vector3i(sites[0].x, int(floor(_probe_height(sites[0].x, sites[0].y))) - 1, sites[0].y))
	for i: int in 3:
		var want := i + 1
		var h := _probe_height(sites[i].x, sites[i].y)
		var center := Vector3(sites[i].x, h - 0.5, sites[i].y)
		_vt.set("mode", _mode_texture_paint)
		_vt.set("texture_index", want)
		_vt.set("texture_opacity", 1.0)
		# Run 1 lesson: falloff 1.0 (widest blend) left the OLD texture dominant
		# at probe cells in the sphere fringe; sharp falloff makes the painted
		# index dominate everywhere inside the sphere.
		_vt.set("texture_falloff", 0.15)
		_vt.do_sphere(center, SPHERE_RADIUS)
		var cell := Vector3i(sites[i].x, int(floor(h)) - 1, sites[i].y)
		_probes[mode_tag][cell] = {"kind": "paint%d" % want, "want_idx": want}
		_probe_by_col[mode_tag][sites[i]] = _probes[mode_tag][cell]
	await _settle(1.0)

	# Live readback: decode both packed u16s into nibble groups by hand.
	var live_ok := true
	for cell: Vector3i in _probes[mode_tag]:
		var probe: Dictionary = _probes[mode_tag][cell]
		var idx_u16 := _read_channel_u16(cell, _ch_indices)
		var w_u16 := _read_channel_u16(cell, _ch_weights)
		var pick := _decode_mixel4(idx_u16, w_u16)
		probe["idx_u16"] = idx_u16
		probe["w_u16"] = w_u16
		probe["decoded"] = pick
		var solid := _read_sdf(cell) <= 0.0
		probe["solid"] = solid
		print("mixel4 live: %s want=%d -> idx_u16=0x%04X w_u16=0x%04X pick=(idx %d, w %.2f) solid=%s" % [
			probe["kind"], probe["want_idx"], idx_u16, w_u16, pick["idx"], pick["w"], solid,
		])
		if not solid or pick["idx"] != probe["want_idx"] or pick["w"] < 0.4:
			live_ok = false
	var sdf_after := _read_sdf(Vector3i(sites[0].x, int(floor(_probe_height(sites[0].x, sites[0].y))) - 1, sites[0].y))
	print("mixel4 live: SDF untouched by paint: %s (%.3f -> %.3f)" % [is_equal_approx(sdf_before, sdf_after), sdf_before, sdf_after])

	# Control column: the unpainted default, recorded (not asserted).
	var ctrl := Vector3i(sites[3].x, int(floor(_probe_height(sites[3].x, sites[3].y))) - 1, sites[3].y)
	var ctrl_idx := _read_channel_u16(ctrl, _ch_indices)
	var ctrl_w := _read_channel_u16(ctrl, _ch_weights)
	_probes[mode_tag][ctrl] = {"kind": "control", "want_idx": 0, "idx_u16": ctrl_idx, "w_u16": ctrl_w}
	_probe_by_col[mode_tag][Vector2i(sites[3].x, sites[3].y)] = _probes[mode_tag][ctrl]
	print("mixel4 live: control default idx_u16=0x%04X w_u16=0x%04X -> %s" % [
		ctrl_idx, ctrl_w, _decode_mixel4(ctrl_idx, ctrl_w),
	])
	_live[mode_tag] = live_ok

	_site_expect[mode_tag] = ["red", "green", "blue", "gray"]
	await _phase_visual(mode_tag, sites)


# --- T2/T4: Single ----------------------------------------------------------------

## Single semantics (upstream docs): one 8-bit texture index in CHANNEL_INDICES,
## painted with channel + MODE_SET. The mesher warns the default VoxelFormat
## carries a 2-bit indices depth — so this run paints index 7 (needs 3 bits) as
## the format-clamp probe: if 7 survives persistence, the default stream format
## is fine as-is; if it clamps, Single mode needs VoxelFormat surgery.
func _phase_single(mode_tag: String) -> void:
	if _ch_indices < 0 or _ch_sdf < 0:
		print("single: SKIP — API absent")
		_live[mode_tag] = false
		return
	print("--- single paint (T2) ---")
	var sites := _pick_columns(3)
	if sites.size() < 3:
		print("single: SKIP — not enough ground columns near origin")
		_live[mode_tag] = false
		return

	var default_channel := int(_vt.get("channel"))
	var sdf_cell := Vector3i(sites[1].x, int(floor(_probe_height(sites[1].x, sites[1].y))) - 1, sites[1].y)
	var sdf_before := _read_sdf(sdf_cell)
	var paints := [[0, 7], [1, 1]]  # [site, index] — 7 is the >2-bit clamp probe.
	for pair: Array in paints:
		var site: int = pair[0]
		var want: int = pair[1]
		var h := _probe_height(sites[site].x, sites[site].y)
		var center := Vector3(sites[site].x, h - 0.5, sites[site].y)
		_vt.set("channel", _ch_indices)
		_vt.set("mode", VoxelTool.MODE_SET)
		_vt.set("value", want)
		# Radius +1: surface vertices blend the MATTER corner against the AIR
		# corner of their cell — the paint must reach the air shell above the
		# surface or every blob top renders ~50/50 against default texture 0.
		_vt.do_sphere(center, SPHERE_RADIUS + 1.0)
		_vt.set("channel", default_channel)
		# Tiny SDF nudge: channels-only edits don't re-mesh (run 3), and
		# production always paints alongside an SDF edit — mirror that here.
		_vt.set("mode", VoxelTool.MODE_ADD)
		_vt.set("value", 0.01)
		_vt.do_sphere(center, SPHERE_RADIUS)
		var cell := Vector3i(sites[site].x, int(floor(h)) - 1, sites[site].y)
		_probes[mode_tag][cell] = {"kind": "paint%d" % want, "want_idx": want}
		_probe_by_col[mode_tag][sites[site]] = _probes[mode_tag][cell]
	await _settle(1.0)

	var live_ok := true
	for cell: Vector3i in _probes[mode_tag]:
		var probe: Dictionary = _probes[mode_tag][cell]
		var idx := _read_channel_u16(cell, _ch_indices)
		var solid := _read_sdf(cell) <= 0.0
		probe["idx"] = idx
		probe["solid"] = solid
		print("single live: %s want=%d -> indices=%d solid=%s" % [
			probe["kind"], probe["want_idx"], idx, solid,
		])
		if idx != probe["want_idx"] or not solid:
			live_ok = false
	var sdf_after := _read_sdf(sdf_cell)
	print("single live: SDF untouched by paint: %s (%.3f -> %.3f) | default channel was %d (restored)" % [
		is_equal_approx(sdf_before, sdf_after), sdf_before, sdf_after, default_channel,
	])
	var ctrl := Vector3i(sites[2].x, int(floor(_probe_height(sites[2].x, sites[2].y))) - 1, sites[2].y)
	_probes[mode_tag][ctrl] = {"kind": "control", "want_idx": 0, "idx": _read_channel_u16(ctrl, _ch_indices)}
	_probe_by_col[mode_tag][Vector2i(sites[2].x, sites[2].y)] = _probes[mode_tag][ctrl]
	print("single live: control default indices=%d" % _probes[mode_tag][ctrl]["idx"])
	_live[mode_tag] = live_ok

	_site_expect[mode_tag] = ["yellow", "red", "gray"]
	await _phase_visual(mode_tag, sites)


# --- T4: pixel oracle ---------------------------------------------------------------

## Live-mesh check first. Run 2 lesson: the pixels come back as the shader's
## texture-0 gray everywhere — the mesh was never re-meshed after a
## channels-only paint (SDF untouched -> no remesh dirty flag). Production
## paints alongside SDF edits, and saved maps re-mesh from the stream on load,
## so the AUTHORITATIVE check is _phase_visual_remeshed after a reload.
func _phase_visual(mode_tag: String, sites: Array[Vector2i]) -> void:
	print("--- visual %s (T4, live mesh) ---" % mode_tag)
	_visual_sites[mode_tag] = sites
	if not _assign_debug_material(mode_tag):
		_visual[mode_tag] = false
		return
	_visual_live[mode_tag] = await _sample_visuals(mode_tag, sites)
	_visual[mode_tag] = _visual_live[mode_tag]


## The decisive check: sample the same sites on a terrain that meshed from the
## saved stream (run after a persistence rebuild). If colors show here, the
## mesher emits CUSTOM1 from the painted channels and the live-mesh gap is only
## the remesh trigger, not the data path.
func _phase_visual_remeshed(mode_tag: String) -> void:
	print("--- visual %s (T4, remeshed after reload) ---" % mode_tag)
	if not _visual_sites.has(mode_tag):
		return
	if not _assign_debug_material(mode_tag):
		return
	_visual[mode_tag] = await _sample_visuals(mode_tag, _visual_sites[mode_tag])


func _assign_debug_material(mode_tag: String) -> bool:
	if not _debug_materials.has(mode_tag):
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = _debug_shader_code(mode_tag)
		material.shader = shader
		_debug_materials[mode_tag] = material
	if not ("material_override" in _terrain):
		print("visual: SKIP — VoxelTerrain lacks material_override (F11 said it has it)")
		return false
	_terrain.set("material_override", _debug_materials[mode_tag])
	return true


func _debug_shader_code(_mode_tag: String) -> String:
	# BOTH modes emit the same 2-float CUSTOM1 layout (single-s4 packs the 4
	# most-represented cell materials + per-vertex lerp weights — see
	# transvoxel_materials_single_s4.h), so one argmax decode serves both.
	# Blue is avoided on purpose: the viewport image comes back sRGB-encoded,
	# which lifts dim channels (0.35 linear reads ~0.627) and would blur
	# blue/green separation in the classifier.
	return """
shader_type spatial;
render_mode unshaded;

varying vec4 v_indices;
varying vec4 v_weights;

void vertex() {
	uint a = floatBitsToUint(CUSTOM1.x);
	uint b = floatBitsToUint(CUSTOM1.y);
	v_indices = vec4(
		float(a & 255u), float((a >> 8u) & 255u),
		float((a >> 16u) & 255u), float((a >> 24u) & 255u));
	v_weights = vec4(
		float(b & 255u), float((b >> 8u) & 255u),
		float((b >> 16u) & 255u), float((b >> 24u) & 255u));
}

void fragment() {
	float ws[4];
	ws[0] = v_weights.r; ws[1] = v_weights.g;
	ws[2] = v_weights.b; ws[3] = v_weights.a;
	float is[4];
	is[0] = v_indices.r; is[1] = v_indices.g;
	is[2] = v_indices.b; is[3] = v_indices.a;
	int mi = 0;
	float mw = -1.0;
	for (int i = 0; i < 4; i++) {
		if (ws[i] > mw) {
			mw = ws[i];
			mi = i;
		}
	}
	float idx = is[mi];
	vec3 col = vec3(0.35); // texture 0 / natural
	if (idx > 0.5 && idx < 1.5) { col = vec3(1.0, 0.0, 0.0); }
	else if (idx >= 1.5 && idx < 2.5) { col = vec3(0.0, 1.0, 0.0); }
	else if (idx >= 2.5 && idx < 3.5) { col = vec3(0.0, 0.1, 1.0); }
	else if (idx > 3.5) { col = vec3(1.0, 1.0, 0.0); }
	ALBEDO = col;
}
"""


func _sample_visuals(mode_tag: String, sites: Array[Vector2i]) -> bool:
	for i: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	var visual_ok := true
	var checked := 0
	var expects: Array = _site_expect.get(mode_tag, [])
	for i: int in sites.size():
		if i >= expects.size():
			break
		var expect := String(expects[i])
		var probe := _probe_for_site(mode_tag, sites[i])
		var label: String = String(probe.get("kind", "site%d" % i))
		var hit := _surface_point(sites[i].x, sites[i].y)
		if hit.x != hit.x or _camera.is_position_behind(hit):
			print("visual: %s off-screen — skipped" % label)
			continue
		var screen: Vector2 = _camera.unproject_position(hit)
		var patch := _avg_patch(img, screen, 4)
		var got := _classify_color(patch)
		checked += 1
		print("visual: %s at %s -> patch(%s) classified %s (expect %s) %s" % [
			label, Vector2i(int(screen.x), int(screen.y)), patch, got, expect,
			"OK" if got == expect else "MISMATCH",
		])
		if got != expect:
			visual_ok = false
	if checked == 0:
		print("visual: NO SAMPLES on screen — camera framing failed")
		visual_ok = false
	return visual_ok


func _probe_for_site(mode_tag: String, site: Vector2i) -> Dictionary:
	var by_col: Dictionary = _probe_by_col.get(mode_tag, {})
	return by_col.get(site, {})


# --- T3: persistence ----------------------------------------------------------------

func _phase_persist(mode_tag: String) -> void:
	print("--- persist %s (T3) ---" % mode_tag)
	var db := MIXEL4_DB if mode_tag == "mixel4" else SINGLE_DB
	var ok := false
	for cycle: int in 2:
		_terrain.save_modified_blocks()
		await _await_journal_clear(db)
		await _teardown_terrain()
		_terrain = _build_smooth_terrain(mode_tag)
		add_child(_terrain)
		_vt = _terrain.get_voxel_tool()
		await _settle(1.0)
		ok = _readback_all(mode_tag, "cycle %d" % (cycle + 1))
		if cycle == 0:
			await _phase_visual_remeshed(mode_tag)
	_persist[mode_tag] = ok


func _readback_all(mode_tag: String, tag: String) -> bool:
	var ok := true
	var found := false
	for cell: Vector3i in _probes[mode_tag]:
		var probe: Dictionary = _probes[mode_tag][cell]
		var solid := _read_sdf(cell) <= 0.0
		probe["solid"] = solid
		if probe["kind"] == "control":
			if mode_tag == "mixel4":
				probe["idx_u16"] = _read_channel_u16(cell, _ch_indices)
				probe["w_u16"] = _read_channel_u16(cell, _ch_weights)
				print("persist[%s]: control idx_u16=0x%04X w_u16=0x%04X" % [
					tag, probe["idx_u16"], probe["w_u16"],
				])
			else:
				probe["idx"] = _read_channel_u16(cell, _ch_indices)
				print("persist[%s]: control indices=%d" % [tag, probe["idx"]])
			continue
		found = true
		var good := false
		if mode_tag == "mixel4":
			var pick := _decode_mixel4(_read_channel_u16(cell, _ch_indices), _read_channel_u16(cell, _ch_weights))
			good = solid and pick["idx"] == probe["want_idx"] and pick["w"] >= 0.4
			print("persist[%s]: %s want=%d -> pick=(idx %d, w %.2f) solid=%s %s" % [
				tag, probe["kind"], probe["want_idx"], pick["idx"], pick["w"], solid,
				"OK" if good else "LOST",
			])
		else:
			var idx := _read_channel_u16(cell, _ch_indices)
			probe["idx"] = idx
			good = solid and idx == probe["want_idx"]
			print("persist[%s]: %s want=%d -> indices=%d solid=%s %s" % [
				tag, probe["kind"], probe["want_idx"], idx, solid,
				"OK" if good else "LOST",
			])
		if not good:
			ok = false
	if not found:
		print("persist[%s]: no paint probes to check" % tag)
		return false
	return ok


# --- Verdict ------------------------------------------------------------------------

func _emit_verdict() -> void:
	print("--- VERDICT (terrain texturing spike) ---")
	print("MIXEL4: live=%s persist=%s visual(live)=%s visual(remeshed)=%s" % [
		_live.get("mixel4", false), _persist.get("mixel4", false),
		_visual_live.get("mixel4", false), _visual.get("mixel4", false),
	])
	print("SINGLE: live=%s persist=%s visual(live)=%s visual(remeshed)=%s" % [
		_live.get("single", false), _persist.get("single", false),
		_visual_live.get("single", false), _visual.get("single", false),
	])
	print("*** NO-GO (F14): painting + persistence work in BOTH modes, but the mesher ***")
	print("*** NEVER reads the per-voxel channels — CUSTOM1 always carries default ***")
	print("*** texture-0 data. Falsified across: mode x channel(3/5/6/7) x depth, ***")
	print("*** isolation (direct build_mesh) and live terrain, fresh and reloaded ***")
	print("*** blocks — and byte-identically on the official v1.7x binary.        ***")
	print("*** Visual differentiation must come from shader rules (F11) + surface ***")
	print("*** markers for authored blobs.                                        ***")


# --- Helpers ------------------------------------------------------------------------

func _read_channel_u16(pos: Vector3i, channel: int) -> int:
	if channel < 0:
		return -1
	var default_channel := int(_vt.get("channel"))
	_vt.set("channel", channel)
	var v: int = _vt.get_voxel(pos)
	_vt.set("channel", default_channel)
	return v


func _read_sdf(pos: Vector3i) -> float:
	if _ch_sdf < 0:
		return 1.0
	var default_channel := int(_vt.get("channel"))
	_vt.set("channel", _ch_sdf)
	var v: float = _vt.get_voxel_f(pos)
	_vt.set("channel", default_channel)
	return v


## Mixel4 u16 decode by hand: 4x 4-bit indices and 4x 4-bit weights, packed in
## the same slot order, so argmax pairing is nibble-order-free. Returns the
## dominant index and its weight (0..1). Skips the SPIKE guards (VoxelTool's
## u16 helpers exist upstream; manual decode keeps the script parse-safe).
func _decode_mixel4(idx_u16: int, w_u16: int) -> Dictionary:
	var best_idx := -1
	var best_w := -1.0
	for slot: int in 4:
		var idx := (idx_u16 >> (slot * 4)) & 0xF
		var w := float((w_u16 >> (slot * 4)) & 0xF) / 15.0
		if w > best_w:
			best_w = w
			best_idx = idx
	return {"idx": best_idx, "w": best_w}


func _surface_point(x: float, z: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, RAY_FROM_Y, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_LENGTH)
	query.collision_mask = SMOOTH_LAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3(NAN, NAN, NAN)
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	return p + n * 0.3


func _probe_height(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, RAY_FROM_Y, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_LENGTH)
	query.collision_mask = SMOOTH_LAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else NAN


## First `count` grounded columns in the ±12 origin box, mutually >= 12 apart
## (F8 spacing rule — one sphere never touches another's column).
func _pick_columns(count: int) -> Array[Vector2i]:
	var picked: Array[Vector2i] = []
	for x: int in range(-12, 13, 2):
		for z: int in range(-12, 13, 2):
			if picked.size() >= count:
				return picked
			var h := _probe_height(x, z)
			if h != h:
				continue
			var candidate := Vector2i(x, z)
			var far_enough := true
			for p: Vector2i in picked:
				if (p - candidate).length() < 12.0:
					far_enough = false
					break
			if far_enough:
				picked.append(candidate)
	return picked


func _avg_patch(img: Image, screen: Vector2, radius_px: int) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for dy: int in range(-radius_px, radius_px + 1):
		for dx: int in range(-radius_px, radius_px + 1):
			var px := int(screen.x) + dx
			var py := int(screen.y) + dy
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			sum += img.get_pixel(px, py)
			n += 1
	return sum / maxf(1.0, float(n)) if n > 0 else Color.BLACK


func _classify_color(c: Color) -> String:
	var r := c.r
	var g := c.g
	var b := c.b
	if absf(r - g) < 0.12 and absf(g - b) < 0.12 and absf(r - b) < 0.12:
		return "gray"
	if r > 0.3 and g > 0.3 and b < r / DOMINANCE_RATIO and b < g / DOMINANCE_RATIO:
		return "yellow"
	if r > DOMINANCE_RATIO * g and r > DOMINANCE_RATIO * b and r > 0.3:
		return "red"
	if g > DOMINANCE_RATIO * r and g > DOMINANCE_RATIO * b and g > 0.3:
		return "green"
	if b > DOMINANCE_RATIO * r and b > DOMINANCE_RATIO * g and b > 0.25:
		return "blue"
	return "other"
