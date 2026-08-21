extends Node3D
## Terrain-identity spike (P1 + P2 of tmp/terrain_mining/plan2.md): establishes,
## for THIS addon build, the two facts the per-position terrain material system
## is built on, before any production code lands:
##
##   (P1 -> F12) VoxelTool per-voxel metadata:
##     - do set_voxel_metadata / get_voxel_metadata exist, and do they accept a
##       String (the material id we want to store)?
##     - does metadata on voxels inside an EDITED block persist through
##       save_modified_blocks() + full terrain teardown/rebuild (same db)?
##     - does metadata on a never-edited, generated-only block persist? (i.e.
##       does a metadata-only write mark the block modified? If not, the rule is
##       "pair metadata with a voxel edit" — add_material always does.)
##     - what does MODE_REMOVE leave behind at positions that had metadata?
##
##   (P2 -> F13) VoxelGeneratorNoise2D height formula: which closed form matches
##     the raycast surface, so SmoothGrid can compute PRISTINE heights (depth =
##     original surface - y, the mining strata basis) in GDScript without
##     querying the C++ generator.
##
## Harness idioms are smooth_edit_spike.gd's (F8): origin-anchored VoxelTerrain,
## one VoxelViewer parked within a few units of every edit site (F3: writes to
## un-streamed coordinates are silent no-ops), generous settles, layer-masked
## downward physics raycasts, `--auto-quit=<seconds>` automation, `--keep-db`.
## No fly camera: every verdict here is measured, none is visual.

const NOISE_SEED := 20260817
const NOISE_FREQUENCY := 0.012
const HEIGHT_START := -4.0
const HEIGHT_RANGE := 12.0
const SMOOTH_LAYER := 4   ## Production layer 3 (bit value 4, "TerrainSmooth").
const BODY_LAYER := 1
const SPHERE_RADIUS := 2.5
const SETTLE_SECONDS := 2.5
const RAY_FROM_Y := 64.0
const RAY_LENGTH := 128.0
const DB_PATH := "res://tmp/voxel_metadata_spike.sqlite"
## P2 tolerance: the raycast hits the meshed SDF iso-surface (transvoxel
## interpolates linearly), so a correct formula should sit well under this.
const FORMULA_TOLERANCE := 0.3

var _terrain: VoxelTerrain = null
var _noise: FastNoiseLite
var _auto_quit_after := 0.0
var _keep_db := false

# P1 bookkeeping: position -> {"meta": set value, "kind": probe category}
var _probe_positions := {}

# Verdicts.
var _api_set := false
var _api_get := false
var _live_roundtrip := false
var _var_variants := ""
var _persist_edited := false   ## all (1a) per-voxel tags survived (full per-voxel durability)
var _persist_dict := false     ## the (1c) Dictionary VALUE survived (per-block-map workaround)
var _rev_first_value := ""
var _rev_lowest_value := ""
var _best_formula := "none"
var _best_formula_mae := NAN
var _hm_formula := "unprobed"


func _ready() -> void:
	_read_user_args()
	_wipe_db()
	_build_world()
	await _settle()
	_phase_formula()
	_phase_api()
	await _phase_metadata()
	await _phase_persist()
	await _phase_heightmap_formula()
	_emit_verdict()
	if _auto_quit_after > 0.0:
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
	print("db: wiped %s" % DB_PATH)


## F9: block saves commit asynchronously; a `<db>-journal` file present means
## the commit is still in flight. Poll until it clears (bounded).
func _await_journal_clear() -> void:
	var journal := DB_PATH + "-journal"
	var waited := 0.0
	while FileAccess.file_exists(journal) and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	print("persist: journal clear after %.1fs (present=%s)" % [
		waited, FileAccess.file_exists(journal),
	])


# --- World ----------------------------------------------------------------------

func _build_world() -> void:
	_terrain = _build_smooth_terrain()
	add_child(_terrain)

	# Parked camera + viewer near the origin: every probe site is chosen within a
	# few units so F3's "unloaded writes are no-ops" cannot eat a probe.
	var camera := Camera3D.new()
	camera.current = true
	camera.transform.origin = Vector3(0, 20, 30)
	add_child(camera)
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	camera.add_child(viewer)

	print("=== terrain identity spike | headless=%s db=%s ===" % [
		DisplayServer.get_name(), DB_PATH,
	])


func _build_smooth_terrain() -> VoxelTerrain:
	_noise = FastNoiseLite.new()
	_noise.seed = NOISE_SEED
	_noise.frequency = NOISE_FREQUENCY
	var generator := VoxelGeneratorNoise2D.new()
	if "noise" in generator:
		generator.set("noise", _noise)
	if "height_start" in generator:
		generator.set("height_start", HEIGHT_START)
	if "height_range" in generator:
		generator.set("height_range", HEIGHT_RANGE)

	var stream := VoxelStreamSQLite.new()
	stream.database_path = DB_PATH

	var terrain := VoxelTerrain.new()
	if "generator" in terrain:
		terrain.set("generator", generator)
	if "mesher" in terrain:
		terrain.set("mesher", VoxelMesherTransvoxel.new())
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


# --- P2: generator height formula ------------------------------------------------

## Compare raycast surface heights against closed-form candidates over a column
## grid. Whichever candidate's mean absolute error sits under FORMULA_TOLERANCE
## becomes the pristine-height formula SmoothGrid replicates.
func _phase_formula() -> void:
	print("--- formula (P2) ---")
	var errs := {"A(start+(n*.5+.5)*range)": 0.0, "B(start+n*range)": 0.0, "C(double-freq A)": 0.0}
	var columns := 0
	for x: int in range(-16, 17, 2):
		for z: int in range(-16, 17, 2):
			var h := _probe_height(x, z)
			if h != h:  # NAN — column not streamed in
				continue
			var n := _noise.get_noise_2d(x, z)
			var n2 := _noise.get_noise_2d(x * NOISE_FREQUENCY, z * NOISE_FREQUENCY)
			errs["A(start+(n*.5+.5)*range)"] += absf(h - (HEIGHT_START + (n * 0.5 + 0.5) * HEIGHT_RANGE))
			errs["B(start+n*range)"] += absf(h - (HEIGHT_START + n * HEIGHT_RANGE))
			errs["C(double-freq A)"] += absf(h - (HEIGHT_START + (n2 * 0.5 + 0.5) * HEIGHT_RANGE))
			columns += 1
	if columns == 0:
		print("formula: NO COLUMNS streamed in — viewer/raycast broken?")
		return
	for key: String in errs:
		var mae: float = errs[key] / columns
		print("formula %-24s MAE=%.3f" % [key, mae])
		if _best_formula_mae != _best_formula_mae or mae < _best_formula_mae:
			_best_formula_mae = mae
			_best_formula = key
	print("formula: best = %s (MAE=%.3f) -> %s" % [
		_best_formula, _best_formula_mae,
		"MATCH" if _best_formula_mae < FORMULA_TOLERANCE else "NO MATCH — pristine height needs the fallback",
	])


# --- P1: voxel metadata ----------------------------------------------------------

func _phase_api() -> void:
	print("--- metadata api (P1) ---")
	var vt := _terrain.get_voxel_tool()
	_api_set = vt.has_method("set_voxel_metadata")
	_api_get = vt.has_method("get_voxel_metadata")
	print("metadata api: set_voxel_metadata=%s get_voxel_metadata=%s" % [_api_set, _api_get])


## Live probes. Runs 1-4 established: API + Variant values work live; carve
## leaves stale metadata in air; across save/reload exactly ONE entry per block
## survives — apparently the FIRST set. This run pins the rules precisely:
##   (1a) reverse-order multi-tag, distinct values — first-set vs lowest-pos;
##   (1b) deep singles at y=-1/-17/-18 — 16³ block boundary + first-per-block;
##   (1c) one Dictionary VALUE — the per-block-map workaround candidate;
##   (4)  live round-trip + Variant breadth (regression guard).
func _phase_metadata() -> void:
	if not (_api_set and _api_get):
		print("metadata: SKIP — API absent")
		return
	print("--- metadata live (P1) ---")
	var vt := _terrain.get_voxel_tool()

	# Sites: distinct columns, mutually >= 12 apart so r=2.5 spheres never touch.
	var sites := _pick_columns(4)
	if sites.size() < 4:
		print("metadata: SKIP — not enough ground columns near origin")
		return

	# (1a) Tag the blob column top-down (FIRST set = highest y; prior runs'
	# survivors were always the first set). If the first-set rule holds, the
	# highest-y value survives — flipping runs 1-4's lowest-y survivor.
	var add_h := _probe_height(sites[0].x, sites[0].y)
	for y: int in [int(floor(add_h)) + 2, int(floor(add_h)) + 1, int(floor(add_h))]:
		var value := "rock_y%d" % y
		if _rev_first_value == "":
			_rev_first_value = value
		_rev_lowest_value = value
		var pos := Vector3i(sites[0].x, y, sites[0].y)
		vt.set_voxel_metadata(pos, value)
		_probe_positions[pos] = {"meta": value, "kind": "edited"}
	vt.mode = VoxelTool.MODE_SET
	vt.value = 1
	vt.do_sphere(Vector3(sites[0].x, add_h + 1.0, sites[0].y), SPHERE_RADIUS)
	await _settle()

	# (1b) Block-size cross-check: y=-8 and y=-9 share a 16-block but split
	# across 8-blocks — the survivor pattern must match mesh_block_size.
	var block_size := 16
	if "mesh_block_size" in _terrain:
		block_size = int(_terrain.get("mesh_block_size"))
	print("metadata: terrain mesh_block_size=%d (expect only -9 if 16, both if 8)" % block_size)
	for y: int in [-8, -9]:
		var pos := Vector3i(sites[1].x, y, sites[1].y)
		vt.set_voxel_metadata(pos, "deep_y%d" % y)
		_probe_positions[pos] = {"meta": "deep_y%d" % y, "kind": "boundary"}

	# (1c) The production anchor: one Dictionary VALUE at the block ORIGIN (the
	# lowest corner — under the lowest-entry-wins rule nothing else in the
	# block can outrank it, and posmod handles negative coordinates).
	var dict_col := Vector3i(sites[2].x, 0, sites[2].y)
	var dict_origin := Vector3i(
		int(floor(float(dict_col.x) / block_size)) * block_size,
		int(floor(float(dict_col.y) / block_size)) * block_size,
		int(floor(float(dict_col.z) / block_size)) * block_size
	)
	var dict_value := {"a": "gold", "b": 7}
	vt.set_voxel_metadata(dict_origin, dict_value)
	_probe_positions[dict_origin] = {"meta": dict_value, "kind": "dictval"}
	print("metadata: dict anchored at block origin %s (col %s, bs=%d)" % [
		dict_origin, dict_col, block_size,
	])

	# (4) Live round-trip + Variant breadth on a spare column.
	var live_h := _probe_height(sites[3].x, sites[3].y)
	var live_pos := Vector3i(sites[3].x, int(floor(live_h)) - 3, sites[3].y)
	vt.set_voxel_metadata(live_pos, "iron")
	_live_roundtrip = vt.get_voxel_metadata(live_pos) == "iron"
	var int_back: Variant = null
	var dict_back: Variant = null
	vt.set_voxel_metadata(live_pos, 42)
	int_back = vt.get_voxel_metadata(live_pos)
	vt.set_voxel_metadata(live_pos, {"id": "x", "n": 1})
	dict_back = vt.get_voxel_metadata(live_pos)
	vt.set_voxel_metadata(live_pos, "iron")
	_var_variants = "int->%s(%s) dict->%s(%s)" % [
		int_back, typeof(int_back), dict_back, typeof(dict_back),
	]
	print("metadata: live String round-trip=%s | variants: %s" % [_live_roundtrip, _var_variants])
	print("metadata: tagged — 1a top-down col %s (first=%s lowest=%s) | 1b deep singles | 1c dict value" % [
		sites[0], _rev_first_value, _rev_lowest_value,
	])


# --- P2b: VoxelGeneratorImage height formula (heightmap maps' pristine height) ---

const HM_SIZE := 32

## The heightmap analogue of _phase_formula: a synthetic image with a strong
## horizontal gradient (pixel columns differ by 8/255, so a one-pixel mapping
## error shows up as a large height error) run through VoxelGeneratorImage
## with SmoothGrid's exact generator settings, raycast vs three offset
## conventions. Whichever matches is what _compute_pristine must replicate.
func _phase_heightmap_formula() -> void:
	print("--- heightmap formula (P2b) ---")
	_terrain.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var img := Image.create(HM_SIZE, HM_SIZE, false, Image.FORMAT_L8)
	for px: int in HM_SIZE:
		for pz: int in HM_SIZE:
			img.set_pixel(px, pz, Color(float((px * 8) % 256) / 255.0, 0, 0))
	var generator := VoxelGeneratorImage.new()
	if "image" in generator:
		generator.set("image", img)
	if "height_start" in generator:
		generator.set("height_start", HEIGHT_START)
	if "height_range" in generator:
		generator.set("height_range", HEIGHT_RANGE)
	if "offset" in generator:
		generator.set("offset", img.get_size() / 2)

	var stream := VoxelStreamSQLite.new()
	stream.database_path = DB_PATH + ".hm"
	_terrain = VoxelTerrain.new()
	if "generator" in _terrain:
		_terrain.set("generator", generator)
	if "mesher" in _terrain:
		_terrain.set("mesher", VoxelMesherTransvoxel.new())
	_terrain.set("stream", stream)
	if "collision_layer" in _terrain:
		_terrain.set("collision_layer", SMOOTH_LAYER)
	if "collision_mask" in _terrain:
		_terrain.set("collision_mask", BODY_LAYER)
	add_child(_terrain)
	await _settle()

	var half := HM_SIZE / 2
	var errs := {"plus(x+half)": 0.0, "minus(x-half)": 0.0, "none(x)": 0.0}
	var columns := 0
	for x: int in range(-14, 15, 2):
		for z: int in range(-14, 15, 2):
			var h := _probe_height(x, z)
			if h != h:
				continue
			var p_plus := img.get_pixel(wrapi(x + half, 0, HM_SIZE), wrapi(z + half, 0, HM_SIZE)).r
			var p_minus := img.get_pixel(wrapi(x - half, 0, HM_SIZE), wrapi(z - half, 0, HM_SIZE)).r
			var p_none := img.get_pixel(wrapi(x, 0, HM_SIZE), wrapi(z, 0, HM_SIZE)).r
			errs["plus(x+half)"] += absf(h - (HEIGHT_START + p_plus * HEIGHT_RANGE))
			errs["minus(x-half)"] += absf(h - (HEIGHT_START + p_minus * HEIGHT_RANGE))
			errs["none(x)"] += absf(h - (HEIGHT_START + p_none * HEIGHT_RANGE))
			columns += 1
	if columns == 0:
		print("heightmap formula: NO COLUMNS — viewer/raycast broken?")
		return
	var best := ""
	var best_mae := INF
	for key: String in errs:
		var mae: float = errs[key] / columns
		print("heightmap formula %-16s MAE=%.3f" % [key, mae])
		if mae < best_mae:
			best_mae = mae
			best = key
	print("heightmap formula: best = %s (MAE=%.3f) -> %s" % [
		best, best_mae, "MATCH" if best_mae < FORMULA_TOLERANCE else "NO MATCH — fix _compute_pristine",
	])
	_hm_formula = "%s (MAE=%.3f)" % [best, best_mae]


# --- P1: persistence -------------------------------------------------------------

func _phase_persist() -> void:
	if _probe_positions.is_empty():
		print("persist: SKIP — nothing probed")
		return
	print("--- persistence (P1) ---")
	var cycle1 := await _save_rebuild_read("cycle 1")
	# Second save/rebuild of the SAME world state: rules that hold in both
	# cycles are the durable rules; anything recovering only in cycle 2 would
	# be a dirty-flag artifact instead.
	var cycle2 := await _save_rebuild_read("cycle 2")
	_persist_edited = _kind_ok(cycle1, "edited") or _kind_ok(cycle2, "edited")
	_persist_dict = _kind_ok(cycle1, "dictval") or _kind_ok(cycle2, "dictval")

	# Pattern analysis on the steady-state cycle: which (1a) value survived
	# (set-order vs position-order rule), and the (1b) block-boundary shape.
	var survivors := {}
	for key: String in cycle2:
		if cycle2[key]["value"] != null:
			survivors[key] = str(cycle2[key]["value"])
	var edited_survivors: Array = []
	var boundary_survivors: Array = []
	for key: String in survivors:
		if key.begins_with("edited:"):
			edited_survivors.append(survivors[key])
		elif key.begins_with("boundary:"):
			boundary_survivors.append(survivors[key])
	print("analysis: edited survivors=%s | first-set was %s, lowest was %s -> order-rule=%s position-rule=%s" % [
		edited_survivors, _rev_first_value, _rev_lowest_value,
		edited_survivors == [_rev_first_value], edited_survivors == [_rev_lowest_value],
	])
	print("analysis: boundary survivors=%s (only -9 => 16-size blocks confirmed; -8 lost to -9's lower position)" % [
		boundary_survivors,
	])


func _save_rebuild_read(tag: String) -> Dictionary:
	_terrain.save_modified_blocks()
	print("persist[%s]: save_modified_blocks() called" % tag)
	# F9 discipline: the sqlite commit is not done when the call returns — a hot
	# `-journal` beside the db means it is still in flight. Wait it out before
	# tearing the terrain down, or the rebuild can race a half-committed save.
	await _await_journal_clear()
	_terrain.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_terrain = _build_smooth_terrain()
	add_child(_terrain)
	await _settle()
	await get_tree().create_timer(2.0).timeout

	var vt := _terrain.get_voxel_tool()
	var results := {}
	for pos: Vector3i in _probe_positions:
		var info: Dictionary = _probe_positions[pos]
		var value: Variant = vt.get_voxel_metadata(pos)
		var solid := vt.get_voxel_f(pos) <= 0.0
		var key: String = "%s:%s" % [info["kind"], pos]
		results[key] = {"value": value, "solid": solid, "wanted": info["meta"]}
		print("persist[%s]: %s -> meta=%s solid=%s" % [tag, key, value, solid])
	return results


func _kind_ok(results: Dictionary, kind: String) -> bool:
	# Every position of this category must have come back solid with its value.
	var found := false
	for key: String in results:
		if not key.begins_with(kind + ":"):
			continue
		found = true
		var r: Dictionary = results[key]
		if not r["solid"] or r["value"] != r["wanted"]:
			return false
	return found


func _emit_verdict() -> void:
	print("--- VERDICT (terrain identity spike) ---")
	print("(P2) pristine-height formula: %s (MAE=%.3f)" % [
		"MATCH %s" % _best_formula if _best_formula_mae < FORMULA_TOLERANCE else "NO MATCH",
		_best_formula_mae,
	])
	print("(P2b) heightmap pristine formula: %s" % _hm_formula)
	print("(P1) api set/get: %s/%s | live String round-trip: %s" % [_api_set, _api_get, _live_roundtrip])
	print("(P1) variants: %s" % _var_variants)
	print("(P1) persist per-voxel tags: %s" % ("PASS (full per-voxel durability)" if _persist_edited else "FAIL (one-per-block rule holds — see analysis)"))
	print("(P1) persist Dictionary VALUE: %s" % ("PASS (per-block map workaround viable)" if _persist_dict else "FAIL"))
	var via := "per-voxel metadata" if _persist_edited else ("per-block Dictionary metadata" if _persist_dict else "NONE")
	var go := _api_set and _api_get and _live_roundtrip and (_persist_edited or _persist_dict)
	print("*** %s ***" % ("GO: material sidecar = %s" % via if go else "NO-GO — fall back to the binary sidecar file (plan risk register)"))


# --- Helpers ---------------------------------------------------------------------

func _probe_height(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, RAY_FROM_Y, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_LENGTH)
	query.collision_mask = SMOOTH_LAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else NAN


## First `count` grounded columns in the ±12 origin box, each >= 12 units from
## the previous picks (F8 spacing rule, one notch tighter to fit four sites).
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
