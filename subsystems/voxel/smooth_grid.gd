class_name SmoothGrid
extends Node
## The natural-terrain half of the dual-voxel world (docs/TODO.md D1/D2), the
## mirror of BlockyGrid: same vocabulary, different mesher/generator. Owns a
## VoxelTerrain + VoxelMesherTransvoxel + a generator built from a
## TerrainGenDef (VoxelGeneratorNoise2D, or VoxelGeneratorImage when the def
## carries a heightmap), plus the sphere-edit primitives the conversion needs (carve
## for Phase 5 mining, add_material for smooth placement) and the cached
## height_at that Phase 3's walkability composes with the blocky probe.
##
## F8/F12/F13 (docs/VOXEL-TOOL-NOTES.md) are the authority on the semantics
## this class encodes: channel 0 is float SDF (solid <= 0, air > 0); MODE_SET
## value v writes SDF -v — value 0 is still solid and carving MUST use
## MODE_REMOVE; the mesher has no material API (one fixed look per map), so
## material IDENTITY is per-position instead: authored blobs carry it in
## per-block voxel metadata (F12: one Dictionary per 16^3 block anchored at
## the block origin), natural ground resolves through TerrainStrata's
## deterministic depth rules against the pristine surface (F13).
##
## Visuals (F11/F14): one ShaderMaterial on the terrain's material_override
## blends the two band endpoints' triplanar textures by depth below the
## pristine surface; authored blobs get Decal markers tinted
## TerrainMaterialDef.color — per-voxel texturing is verified dead (F14), so
## visual identity is indirect.
##
## Lifecycle: absent by design. Maps opt in via MapDef.terrain_gen — SceneManager
## injects it into this node before the map enters the tree; a SmoothGrid that
## reaches _ready without one removes itself ("null -> no smooth grid at all",
## so terrain-less maps play exactly as before).

signal material_placed(pos: Vector3, material_id: String)
signal material_carved(pos: Vector3)

## Collision-layer plan (docs/architecture/voxel-world.md "Collision layers"):
## the smooth terrain owns layer 3 (TerrainSmooth, bit value 4) so physics
## queries can address natural ground separately from blocky ground (layer 2)
## and World statics (layer 1).
const TERRAIN_LAYER := 3
## F7: a terrain's mask must include the body layers standing on it or body
## interaction silently stops. Player (4) and Colonist (6) stand on this too.
const TERRAIN_BODY_MASK := 8 | 32
## Queries that want the natural surface (walkability, mining, this grid's own
## height_at) mask to exactly this layer value.
const TERRAIN_LAYER_VALUE := 1 << (TERRAIN_LAYER - 1)

## MODE_SET value for add_material: writes SDF -2, matching the generator's
## deep-solid density (-1.999 probed, F8) so added ground is indistinguishable
## from generated ground in meshing and collision.
const SOLID_DENSITY := 2
## Direct-write value for carve_box: SDF +2, the mirror of SOLID_DENSITY and the
## generator's air density (+1.999 probed, F8). Written per-cell with
## set_voxel_f — a hard air stamp, never a blended brush (see carve_box).
const AIR_DENSITY := 2.0

## One terrain look per map (F11), banded by depth (the F14 fallback path —
## per-voxel texturing is non-functional, so the shader is the whole visual).
const TERRAIN_SHADER: Shader = preload("res://assets/terrain/terrain_shader.gdshader")
## Pristine-height bake feeding the shader's depth bands: R = meters, one
## pixel per meter, centered on the origin, sampled with repeat — depth bands
## drift beyond the window, which only far terrain sees.
const HEIGHT_BAKE_SIZE := 512
const HEIGHT_BAKE_SPAN := 512.0

## Path/name of the VoxelTerrain node, relative to this SmoothGrid. The map
## template parents VoxelTerrain as a direct child.
@export var terrain_path: NodePath = ^"VoxelTerrain"

## Generator params; injected by SceneManager from MapDef.terrain_gen before
## the map enters the tree. Null at _ready = this map has no smooth terrain.
@export var terrain_gen: TerrainGenDef = null

## Fallback identity when neither the sidecar nor strata answers a solid
## position (maps without an injected catalog behave exactly as before: one
## def for all natural ground).
@export var default_material: TerrainMaterialDef = null

@onready var _terrain: VoxelTerrain = get_node_or_null(terrain_path) as VoxelTerrain
var _voxel_tool: VoxelTool
var _default_material_warned := false

## Cached heightfield for D4 walkability: column -> {"h": float, "n": Vector3}.
## Populated lazily by height_at; evicted on edits and block streaming so
## pathing never answers from stale ground ("edits keep pathing honest").
var _height_cache: Dictionary = {}

## Per-position identity state (terrain_mining/plan.md). The pristine cache
## never evicts — the GENERATED surface cannot change, so depth stays stable
## under digging; authored edits carry sidecar identity instead of moving it
## (the load-bearing "two identity sources can't disagree" invariant).
var _pristine_cache: Dictionary = {}
var _strata: TerrainStrata = null
var _catalog_by_id: Dictionary = {}
## Generator-mirror inputs for _pristine_height: the def's own prepared image
## (heightmap maps) or a noise sampler with the generator's exact params (F13).
var _heightmap_image: Image = null
var _noise_sampler: FastNoiseLite = null
## F12 block size (from the terrain's mesh_block_size); 0 until first use.
var _block_size := 0

## Visual state (F11/F14): band endpoints for the terrain shader, the surface
## material id whose blobs skip marking (they match the terrain's own top
## band), and the marker registry — "origin|id" keys funnel BOTH spawn paths
## (add_material and block_loaded) so nothing double-spawns.
var _band_materials: Dictionary = {}
var _surface_material_id := ""
var _marker_keys: Dictionary = {}
var _marker_root: Node3D = null
static var _shared_marker_texture: ImageTexture = null
static var _shared_white_texture: ImageTexture = null

func _ready() -> void:
	if terrain_gen == null:
		# MapDef.terrain_gen is null — the map opted out of natural terrain.
		# Free quietly; Map.get_smooth_grid() then returns null to consumers.
		queue_free()
		return
	# Own the smooth layer before any collision blocks stream in (F7: layer and
	# mask must move together, guarded set() for the GDExtension property).
	if "collision_layer" in _terrain:
		_terrain.set("collision_layer", TERRAIN_LAYER_VALUE)
		_terrain.set("collision_mask", TERRAIN_BODY_MASK)
	else:
		push_warning("SmoothGrid: VoxelTerrain lacks collision_layer; smooth terrain stays on the default layer")

	# One prepared image feeds both the generator and _pristine_height — F13's
	# lockstep rule: strata and generator must describe the same def. Noise
	# maps mirror the generator's sampler the same way (F13 closed form).
	_heightmap_image = _prepare_heightmap_image(terrain_gen)
	if _heightmap_image == null:
		_noise_sampler = FastNoiseLite.new()
		_noise_sampler.seed = terrain_gen.noise_seed
		_noise_sampler.frequency = terrain_gen.noise_frequency
	if "generator" in _terrain:
		_terrain.set("generator", _build_generator(terrain_gen, _heightmap_image))
	if "mesher" in _terrain:
		_terrain.set("mesher", VoxelMesherTransvoxel.new())

	_apply_visuals()
	_marker_root = Node3D.new()
	_marker_root.name = "TerrainMarkers"
	add_child(_marker_root)
	_damage_decal_root = Node3D.new()
	_damage_decal_root.name = "DamageDecals"
	add_child(_damage_decal_root)

	_voxel_tool = _terrain.get_voxel_tool()

	# D4 invalidation hooks (F8 signatures): block streaming swaps voxel data
	# under cached columns — a loaded block may carry sqlite edits, an unloaded
	# one takes its columns with it. Whole-cache clear: correct and cheap next
	# to per-block column math; the cache repopulates on demand. block_loaded
	# ALSO drives marker reconstruction (F14 sidecar -> Decal on reload).
	if _terrain.has_signal("block_loaded"):
		_terrain.block_loaded.connect(_on_block_loaded)
	if _terrain.has_signal("block_unloaded"):
		_terrain.block_unloaded.connect(_clear_height_cache)

# --- generator construction ---------------------------------------------------

## Generator for the def's terrain: heightmap-driven when the def carries a
## readable image, noise otherwise. Both paths write the same span fields, so a
## def can switch modes without touching height_start/height_range. Takes the
## ALREADY-prepared image so generator and _pristine_height share one source.
func _build_generator(def: TerrainGenDef, heightmap: Image) -> Resource:
	if heightmap != null:
		return _build_heightmap_generator(def, heightmap)
	return _build_noise_generator(def)

## Noise path — the original TerrainGenDef pipeline (seed + frequency).
func _build_noise_generator(def: TerrainGenDef) -> Resource:
	var noise := FastNoiseLite.new()
	noise.seed = def.noise_seed
	noise.frequency = def.noise_frequency
	var generator := VoxelGeneratorNoise2D.new()
	# Guarded sets — verified names (base spike + F8), kept defensive anyway so a
	# future addon bump degrades to defaults instead of crashing map load.
	if "noise" in generator:
		generator.set("noise", noise)
	if "height_start" in generator:
		generator.set("height_start", def.height_start)
	if "height_range" in generator:
		generator.set("height_range", def.height_range)
	return generator

## Heightmap path — external-tool authoring. Property names probed in this
## addon build (tmp/heightmap_gen_probe.gd): image, height_start, height_range, offset.
## Center the heightmap image on the world origin (0,0) by offsetting by half size,
## preventing wrapping seams along the X=0 and Z=0 axes.
func _build_heightmap_generator(def: TerrainGenDef, heightmap: Image) -> Resource:
	var generator := VoxelGeneratorImage.new()
	# Same guarded-set contract as the noise builder.
	if "image" in generator:
		generator.set("image", heightmap)
	if "height_start" in generator:
		generator.set("height_start", def.height_start)
	if "height_range" in generator:
		generator.set("height_range", def.height_range)
	if "offset" in generator:
		generator.set("offset", heightmap.get_size() / 2)
	return generator

## Heightmap pixels as the generator wants them: uncompressed L8 so the value
## read is the authored grayscale regardless of source texture format. Static
## so a future blocky-grid image generator in this subsystem can promote it to
## a shared helper by moving, not rewriting. Null tex / unreadable pixels ->
## null (the caller falls back to noise; the error is reported here).
static func _prepare_heightmap_image(def: TerrainGenDef) -> Image:
	if def == null or def.heightmap == null:
		return null
	var image := def.heightmap.get_image()
	if image == null:
		push_error("SmoothGrid: terrain_gen.heightmap has no readable pixels — falling back to noise")
		return null
	if image.is_compressed():
		if image.decompress() != OK:
			push_error("SmoothGrid: terrain_gen.heightmap is compressed and cannot decompress — falling back to noise")
			return null
	
	# The map editor's L8 quantization causes ~0.2m offsets (e.g. 128/255 = 0.5019 -> +0.196m).
	# Convert to float and snap physical heights back to the nearest whole meter to
	# recover the authored integer height and align the generator with the Blocky grid.
	image.convert(Image.FORMAT_RF)
	var width := image.get_width()
	var height := image.get_height()
	for y: int in range(height):
		for x: int in range(width):
			var v: float = image.get_pixel(x, y).r
			var h: float = def.height_start + v * def.height_range
			var snapped_h: float = roundf(h)
			var new_v: float = (snapped_h - def.height_start) / def.height_range
			image.set_pixel(x, y, Color(new_v, new_v, new_v, 1.0))
			
	return image

# --- read / edit surface (D1 mirror of BlockyGrid's block API) -----------------

## Material id at pos, or "" for air. Resolution order (terrain_mining/plan.md):
## authored sidecar (F12 per-block dict at the block origin) -> TerrainStrata's
## deterministic natural material (F13 depth rules) -> default_material.
## True if pos contains solid terrain (whole-cell SDF + column-height decision,
## see is_solid_cell).
func is_solid_at(pos: Vector3i) -> bool:
	var vt := _voxel_tool
	var get_voxel_f := Callable(vt, "get_voxel_f") if vt != null and vt.has_method("get_voxel_f") else Callable()
	return is_solid_cell(get_voxel_f, Callable(self, "height_at"), pos)


## The 8 lattice samples spanning a cell's volume — a cell's corners, i.e. the
## exact sample span carve_box stamps when it digs that cell.
const _CELL_CORNERS: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1),
]


## Whole-cell solidity decision shared by every terrain probe (walkability,
## dig designation, job validity). A cell is carved air only when ALL 8 of its
## corner samples read air: carve_box stamps a dug cell's full corner span,
## which bleeds one lattice plane into the neighbouring walls — a min-corner
## probe reads those wall cells as air and the pathfinder routes straight
## through them (the 1-wide-stairway-through-the-wall bug). Any solid corner
## defers to the column height, so surface cells keep the heightfield
## arbitration. Static and side-effect-free so suites pin the lattice math
## (box_samples precedent); either Callable may be invalid (no voxel tool /
## no physics) and the chain degrades exactly like the old inline probe.
static func is_solid_cell(get_voxel_f: Callable, height_at_fn: Callable, pos: Vector3i, threshold: float = 0.5) -> bool:
	if get_voxel_f.is_valid():
		var all_air := true
		for corner: Vector3i in _CELL_CORNERS:
			if float(get_voxel_f.call(pos + corner)) <= -0.01:
				all_air = false
				break
		if all_air:
			return false
	var h: float = height_at_fn.call(float(pos.x) + 0.5, float(pos.z) + 0.5)
	if not is_nan(h):
		return h >= float(pos.y) + threshold
	if get_voxel_f.is_valid():
		return float(get_voxel_f.call(pos)) <= -threshold
	return false


func get_material_at(pos: Vector3i) -> String:
	if _voxel_tool == null or not _voxel_tool.has_method("get_voxel_f"):
		return ""
	# Air first: F12 — carved cells keep stale metadata, so an air-checkless
	# reader would resurrect material out of holes.
	if _voxel_tool.get_voxel_f(pos) > 0.0:
		return ""
	if _voxel_tool.has_method("get_voxel_metadata"):
		var block: Variant = _voxel_tool.get_voxel_metadata(_block_origin(pos))
		if block is Dictionary and block.has(pos):
			return String(block[pos])
	if _strata != null:
		var natural := _strata.material_id_at(pos)
		if natural != "":
			return natural
	if default_material == null:
		if not _default_material_warned:
			push_warning("SmoothGrid: no default_material assigned — get_material_at returns \"\" for solid ground")
			_default_material_warned = true
		return ""
	return default_material.id


## The def for the material at pos (null for air) — DigAction's entry point:
## hp/yields resolve per position, not per map. Ids absent from the catalog
## (def deleted) answer null; callers treat that as "no stats, no yields".
func get_material_def_at(pos: Vector3i) -> TerrainMaterialDef:
	var id := get_material_at(pos)
	if id == "":
		return null
	if _catalog_by_id.has(id):
		return _catalog_by_id[id]
	if default_material != null and default_material.id == id:
		return default_material
	return null


## The def for the first solid sample in a box edit's range (null when the whole
## range is air). DigAction's BOX entry point: the dig center is the struck
## cell's center but a multi-sample box may straddle materials, so hp/yields
## resolve from the first sample that actually answers — a center-sample lookup
## would silently drop yields on edge digs whose center sample is air.
func get_first_material_def_in_box(min_pos: Vector3, max_pos: Vector3) -> TerrainMaterialDef:
	for sample: Vector3i in box_samples(min_pos, max_pos):
		var def := get_material_def_at(sample)
		if def != null:
			return def
	return null


## Injected where terrain_gen already flows (SceneManager at runtime, the map
## editor when authoring), sourced from BuildLibrary.get_terrain_materials() —
## this subsystem reads no catalogs itself (AGENTS.md rule 3). No injection
## means no strata: natural ground answers default_material, exactly the
## pre-mining behavior. Also feeds the visuals: band endpoints for the
## terrain shader and the marker-skip surface material.
func set_material_catalog(materials: Array) -> void:
	_catalog_by_id = {}
	for m: TerrainMaterialDef in materials:
		if m != null and m.id != "":
			_catalog_by_id[m.id] = m
	_strata = TerrainStrata.new()
	var seed := terrain_gen.noise_seed if terrain_gen != null else 0
	_strata.setup(materials, seed, Callable(self, "_pristine_height"))
	_band_materials = _pick_band_materials(_catalog_by_id.values())
	_surface_material_id = ""
	if _band_materials.has("surface"):
		_surface_material_id = String(_band_materials["surface"].id)
	# Catalog injection may precede the tree (both injectors do), so _terrain
	# can be unset — _ready's _apply_visuals covers that order.
	if _terrain != null and "material_override" in _terrain:
		var override: Variant = _terrain.get("material_override")
		if override is ShaderMaterial:
			_push_band_uniforms(override)

## Add a sphere of solid ground (SDF -SOLID_DENSITY) at world pos, carrying
## material_id in the F12 sidecar — the ONLY smooth-add path in the codebase
## (editor sculpts, smooth placement, structure stamps all route here: the
## "identity sources can't disagree" invariant). Also spawns the blob's
## visual marker (F14): a Decal tinted from the material's color.
func add_material(pos: Vector3, material_id: String, radius: float) -> void:
	if _voxel_tool == null:
		return
	_voxel_tool.mode = VoxelTool.MODE_ADD
	_voxel_tool.value = SOLID_DENSITY
	_voxel_tool.do_sphere(pos, radius)
	var origins := _write_material_sidecar(pos, radius, material_id)
	for origin: Vector3i in origins:
		_spawn_markers_for_block(origin)
	_evict_columns_near(pos, radius)
	material_placed.emit(pos, material_id)

## Carve a sphere of terrain away at world pos. The mining primitive (Phase 5
## dig action). MODE_REMOVE, never MODE_SET — F8: value 0 is still solid.
## Carved cells keep stale sidecar entries (F12); get_material_at's air-first
## check makes them permanently inert.
func carve(pos: Vector3, radius: float) -> void:
	if _voxel_tool == null:
		return
	_voxel_tool.mode = VoxelTool.MODE_REMOVE
	_voxel_tool.do_sphere(pos, radius)
	_evict_columns_near(pos, radius)
	material_carved.emit(pos)


## Carve a box of terrain away: every SAMPLE inside [min_pos, max_pos] gets a
## HARD air write. Samples, not "cells" — on smooth terrain an integer
## coordinate is a lattice corner value, and the mesh surface between solid
## and air samples can pass through cells whose own min-corner sample is
## already air (incline edges, steep faces). Clearing just one sample leaves
## those surfaces standing; clearing every sample in the box guarantees no
## surface can survive inside it. Also deliberately not `do_box` — the
## box/sphere brushes are SDF blends that leave partial-density fringe cells
## at the cut, and a lone partial cell meshes as an unremovable "pyramid"
## spike. The visible hole is the sample span dilated ~half a sample into the
## remaining solid (the mesher interpolates between the last solid and first
## air sample), symmetric around the ghost box. Carved cells keep stale
## sidecar entries (F12, inert via the air-first read); writes outside the
## streamed area are silent no-ops (F3, same as any brush).
func carve_box(min_pos: Vector3, max_pos: Vector3) -> void:
	if _voxel_tool == null:
		return
	var local_min := _terrain.to_local(min_pos)
	var local_max := _terrain.to_local(max_pos)
	var targets := box_sample_targets(local_min, local_max)
	if targets.is_empty():
		return
	for sample: Vector3i in targets:
		var target_sdf: float = targets[sample]
		var current := _voxel_tool.get_voxel_f(sample)
		if target_sdf > current:
			_voxel_tool.set_voxel_f(sample, target_sdf)

	_evict_columns_in_box(min_pos, max_pos)
	material_carved.emit((min_pos + max_pos) * 0.5)


## The samples a box edit covers: integer positions are LATTICE SAMPLES, so a
## sample counts when it lies inside the CLOSED box — ceil(min_pos) through
## floor(max_pos) per axis. A snapped 1x1x1 dig (bounds exactly on cell edges)
## therefore clears all 8 corners of the struck cell; a snapped 3x3x3 clears
## the 4x4x4 sample span matching the ghost's world extent. Static and
## side-effect-free so suites can pin the math.
static func box_samples(min_pos: Vector3, max_pos: Vector3) -> Array[Vector3i]:
	var samples: Array[Vector3i] = []
	for x: int in range(int(ceil(min_pos.x)), int(floor(max_pos.x)) + 1):
		for y: int in range(int(ceil(min_pos.y)), int(floor(max_pos.y)) + 1):
			for z: int in range(int(ceil(min_pos.z)), int(floor(max_pos.z)) + 1):
				samples.append(Vector3i(x, y, z))
	return samples


## The SDF a box carve stamps per covered sample (box_samples span): the box's
## lowest plane gets 0.0 so the floor aligns exactly with the integer grid
## (0.0 = surface), everything above gets a hard AIR stamp. Returned as
## sample -> target SDF; carve_box applies them with monotonic air-only writes
## (a shared plane between two stacked digs keeps its AIR, never re-solidifies
## back to 0.0). Static and side-effect-free so suites pin the stamp math.
static func box_sample_targets(min_pos: Vector3, max_pos: Vector3) -> Dictionary:
	var targets := {}
	var samples := box_samples(min_pos, max_pos)
	if samples.is_empty():
		return targets
	var min_y := samples[0].y
	for s: Vector3i in samples:
		if s.y < min_y:
			min_y = s.y
	for s: Vector3i in samples:
		targets[s] = 0.0 if s.y == min_y else AIR_DENSITY
	return targets


## Snap a dig target to the nearest SOLID lattice sample to `world_pos` (the
## hit point nudged into the surface). Searches the struck cell's own 8 corner
## samples FIRST — they are the samples that mesh the surface under the
## crosshair, so the anchor stays within half a cube of the aim and the ghost
## steps one lattice cell at a time as the crosshair moves; the wider 3x3x3
## ring only answers grazing hits whose struck cell is all-air. Returns
## world_pos unchanged when nothing nearby is solid (aim at air — the dig
## then clears nothing, the honest answer). F15: anchoring on a solid sample
## guarantees the dig bites (no air-over-air no-ops on incline edges) and a
## 1x1x1 dig clears exactly ONE sample (~1 m bite) — box_samples of a box
## centered on the returned integer position is exactly that sample (a
## 3-box: its 3x3x3 neighborhood).
func nearest_solid_sample(world_pos: Vector3) -> Vector3:
	return nearest_solid_sample_in(world_pos, func(pos: Vector3i) -> bool:
		return _voxel_tool != null and _voxel_tool.get_voxel_f(pos) <= 0.0)


## The selection logic, split out with an `is_solid` callable so suites can
## pin it without a live VoxelTerrain (the RecordingSmoothGrid seam pattern).
static func nearest_solid_sample_in(world_pos: Vector3, is_solid: Callable) -> Vector3:
	var base := Vector3i(int(floor(world_pos.x)), int(floor(world_pos.y)), int(floor(world_pos.z)))
	for margin: int in [0, 1]:
		var best := base
		var best_distance := INF
		var found := false
		for x: int in range(base.x - margin, base.x + 2 + margin):
			for y: int in range(base.y - margin, base.y + 2 + margin):
				for z: int in range(base.z - margin, base.z + 2 + margin):
					var sample := Vector3i(x, y, z)
					if not is_solid.call(sample):
						continue
					var distance: float = (Vector3(sample) - world_pos).length_squared()
					if distance < best_distance:
						best_distance = distance
						best = sample
						found = true
		if found:
			return Vector3(best)
	return world_pos


# --- F12 material sidecar --------------------------------------------------------

## Origin of the voxel block containing pos (floor division — negative
## coordinates truncate the wrong way with plain `/`). The origin is the
## durable metadata slot: F12 proved only the lowest-position entry per block
## survives save_modified_blocks().
func _block_origin(pos: Vector3i) -> Vector3i:
	if _block_size == 0:
		_block_size = 16
		if "mesh_block_size" in _terrain:
			_block_size = maxi(1, int(_terrain.get("mesh_block_size")))
	return Vector3i(
		int(floor(float(pos.x) / _block_size)) * _block_size,
		int(floor(float(pos.y) / _block_size)) * _block_size,
		int(floor(float(pos.z) / _block_size)) * _block_size,
	)


## The sidecar dict for a block ({} when none was authored yet).
func _block_materials(origin: Vector3i) -> Dictionary:
	if _voxel_tool == null or not _voxel_tool.has_method("get_voxel_metadata"):
		return {}
	var block: Variant = _voxel_tool.get_voxel_metadata(origin)
	return block if block is Dictionary else {}


## Sidecar write for an add-sphere: read-modify-write ONE Dictionary per
## touched block, anchored at the block origin, merging with prior authored
## material. The solid check keeps air cells (sphere corners) untagged. Editor
## sculpt + placement + stamper inherit persistence free — their existing
## save_modified_blocks() calls carry the dicts into terrain.sqlite (F12).
## Returns the touched block origins (the marker spawn path consumes them).
func _write_material_sidecar(pos: Vector3, radius: float, material_id: String) -> Array[Vector3i]:
	var origins: Array[Vector3i] = []
	if material_id == "" or _voxel_tool == null or not _voxel_tool.has_method("set_voxel_metadata") \
			or not _voxel_tool.has_method("get_voxel_f"):
		return origins
	var min_p := pos - Vector3.ONE * radius
	var max_p := pos + Vector3.ONE * radius
	var block_dicts := {}
	for x: int in range(int(floor(min_p.x)), int(floor(max_p.x)) + 1):
		for y: int in range(int(floor(min_p.y)), int(floor(max_p.y)) + 1):
			for z: int in range(int(floor(min_p.z)), int(floor(max_p.z)) + 1):
				var cell := Vector3i(x, y, z)
				if _voxel_tool.get_voxel_f(cell) > 0.0:
					continue
				var origin := _block_origin(cell)
				if not block_dicts.has(origin):
					block_dicts[origin] = _block_materials(origin)
					origins.append(origin)
				block_dicts[origin][cell] = material_id
	for origin: Vector3i in block_dicts:
		_voxel_tool.set_voxel_metadata(origin, block_dicts[origin])
	return origins


# --- terrain visuals (F11/F14) -----------------------------------------------------

## One look per map, set from data: the terrain shader (F11's material_override
## hook) blends the band endpoints' triplanar textures by depth below the
## pristine surface. Per-voxel texturing is dead (F14), so this shader plus
## blob markers IS the whole visual system. Catalog-derived uniforms land via
## set_material_catalog, which may run before or after this.
func _apply_visuals() -> void:
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("height_map", _bake_height_texture())
	material.set_shader_parameter("bake_span", HEIGHT_BAKE_SPAN)
	_push_band_uniforms(material)
	if "material_override" in _terrain:
		_terrain.set("material_override", material)


## Shader-rule band endpoints (F14): the surface material (smallest min_depth)
## and the dominant deep material (highest spawn_weight among defs that start
## at/below the surface material's max_depth). Deterministic — ties break on
## id, like TerrainStrata's scan-order immunity. Mirrors the strata vocabulary
## without duplicating its per-voxel math. Static + pure — the visuals suite
## tests it.
static func _pick_band_materials(defs: Array) -> Dictionary:
	var surface: TerrainMaterialDef = null
	for m: TerrainMaterialDef in defs:
		if m == null or m.id == "":
			continue
		if surface == null or m.min_depth < surface.min_depth \
				or (m.min_depth == surface.min_depth and m.id < surface.id):
			surface = m
	if surface == null:
		return {}
	var deep: TerrainMaterialDef = null
	for m: TerrainMaterialDef in defs:
		if m == null or m.id == "" or m == surface:
			continue
		if m.min_depth < surface.max_depth:
			continue
		if deep == null or m.spawn_weight > deep.spawn_weight \
				or (m.spawn_weight == deep.spawn_weight and m.id < deep.id):
			deep = m
	return {"surface": surface, "deep": deep}


func _push_band_uniforms(material: ShaderMaterial) -> void:
	var surface: TerrainMaterialDef = _band_materials.get("surface")
	var deep: TerrainMaterialDef = _band_materials.get("deep")
	material.set_shader_parameter("ground_tex", _band_texture(surface))
	material.set_shader_parameter("rock_tex", _band_texture(deep))
	material.set_shader_parameter("ground_tint", _band_tint(surface, Color(0.545, 0.435, 0.278)))
	material.set_shader_parameter("rock_tint", _band_tint(deep, Color(0.541, 0.541, 0.561)))
	var center := 3.0
	if surface != null:
		center = float(surface.max_depth)
	material.set_shader_parameter("band_center_depth", center)


## A real texture carries its own color, so it is never tinted (WHITE); the
## textureless fallback path paints the def's flat color instead. Static +
## pure — the visuals suite tests it.
static func _band_texture(def: TerrainMaterialDef) -> Texture2D:
	if def != null and def.texture != null:
		return def.texture
	return _white_texture()


static func _band_tint(def: TerrainMaterialDef, fallback: Color) -> Color:
	if def != null and def.texture != null:
		return Color.WHITE
	if def != null and def.color != Color.WHITE:
		return def.color
	return fallback


static func _white_texture() -> ImageTexture:
	if _shared_white_texture == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color.WHITE)
		_shared_white_texture = ImageTexture.create_from_image(image)
	return _shared_white_texture


## Pristine-surface height bake (RF float, R = meters) for the shader's depth
## bands. Mirrors _compute_pristine exactly (F13 noise / F10 heightmap wrap)
## minus the per-column cache — 262k cached columns would balloon memory.
func _bake_height_texture() -> ImageTexture:
	var image := Image.create(HEIGHT_BAKE_SIZE, HEIGHT_BAKE_SIZE, false, Image.FORMAT_RF)
	var half := HEIGHT_BAKE_SIZE / 2
	for z: int in HEIGHT_BAKE_SIZE:
		for x: int in HEIGHT_BAKE_SIZE:
			var h := _compute_pristine(x - half, z - half)
			image.set_pixel(x, z, Color(h if h == h else 0.0, 0.0, 0.0))
	return ImageTexture.create_from_image(image)


# --- authored-blob markers (F14) ---------------------------------------------------

## One Decal per (block origin, material) of authored terrain, tinted from the
## material's color — the visual identity the mesher can't provide. Spawned
## from add_material for immediate feedback and reconstructed from the F12
## sidecar as blocks load (_on_block_loaded), so markers survive map reloads
## with zero extra save state. Skips the surface material (its blobs match the
## terrain's own top band). Known v1 limits (docs/architecture/mining.md): a
## marker can go stale after its blob is carved away, and each marker is a
## projector — heavy editor paint sessions may eventually want a cap.
func _spawn_markers_for_block(origin: Vector3i) -> void:
	if _voxel_tool == null or not _voxel_tool.has_method("get_voxel_metadata"):
		return
	var dict := _block_materials(origin)
	if dict.is_empty():
		return
	var by_material := {}
	for cell: Vector3i in dict:
		var material_id := String(dict[cell])
		if material_id == "" or material_id == _surface_material_id:
			continue
		if not by_material.has(material_id):
			by_material[material_id] = []
		by_material[material_id].append(cell)
	for material_id: String in by_material:
		var key := "%s|%s" % [origin, material_id]
		if _marker_keys.has(key):
			continue
		_marker_keys[key] = true
		_spawn_marker_decal(by_material[material_id], _catalog_by_id.get(material_id))


func _spawn_marker_decal(positions: Array, def: TerrainMaterialDef) -> void:
	if def == null or positions.is_empty() or _marker_root == null:
		return
	var sphere := marker_sphere_for(positions)
	var decal := Decal.new()
	## This Godot names the decal textures texture_albedo/texture_normal/...
	## (not albedo_texture) — property names verified against the build.
	decal.texture_albedo = marker_texture()
	decal.modulate = def.color
	decal.size = Vector3(sphere.radius * 2.0 + 2.0, sphere.radius * 2.0 + 2.0, 12.0)
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	# Decal projects along its local -Z; aim it straight down so the disc
	# lands on the terrain under the blob.
	decal.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), sphere.center + Vector3.UP * 5.0)
	_marker_root.add_child(decal)


## Bounding sphere of a marker's authored positions: centroid + max distance,
## clamped to decal-friendly sizes. Static + pure — the visuals suite tests it.
static func marker_sphere_for(positions: Array) -> Dictionary:
	var center := Vector3.ZERO
	for cell: Vector3i in positions:
		center += Vector3(cell)
	center /= float(positions.size())
	var radius := 0.0
	for cell: Vector3i in positions:
		radius = maxf(radius, (Vector3(cell) - center).length())
	return {"center": center, "radius": clampf(radius, 1.5, 6.0)}


## Shared white radial-falloff disc; per-material identity comes from
## Decal.modulate, so one texture serves every material.
static func marker_texture() -> ImageTexture:
	if _shared_marker_texture == null:
		var size := 64
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y: int in size:
			for x: int in size:
				var r := Vector2(x - float(size - 1) / 2.0, y - float(size - 1) / 2.0).length() / (float(size) / 2.0)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf((1.0 - r) * 1.6, 0.0, 1.0)))
		_shared_marker_texture = ImageTexture.create_from_image(image)
	return _shared_marker_texture


## Pristine (generator-only) surface height at column (x, z) — the depth basis
## for strata: depth = pristine surface - y is stable under digging, so mining
## deeper always exposes deeper materials. Mirrors the generator exactly (F13
## closed form for noise; the def's own image for heightmaps, same repeat
## semantics as F10) and never evicts: the generated surface cannot change.
func _pristine_height(x: float, z: float) -> float:
	var col := Vector2i(int(floor(x)), int(floor(z)))
	if _pristine_cache.has(col):
		return _pristine_cache[col]
	var h := _compute_pristine(col.x, col.y)
	if h == h:  # not NAN
		_pristine_cache[col] = h
	return h


func _compute_pristine(x: int, z: int) -> float:
	if terrain_gen == null:
		return NAN
	if _heightmap_image != null:
		var size := _heightmap_image.get_size()
		if size.x <= 0 or size.y <= 0:
			return NAN
		var px := wrapi(x + int(size.x) / 2, 0, int(size.x))
		var pz := wrapi(z + int(size.y) / 2, 0, int(size.y))
		var v := _heightmap_image.get_pixel(px, pz).r
		return terrain_gen.height_start + v * terrain_gen.height_range
	if _noise_sampler == null:
		return NAN
	var n := _noise_sampler.get_noise_2d(x, z)
	return terrain_gen.height_start + (n * 0.5 + 0.5) * terrain_gen.height_range

# --- Terrain damage & mining (real-time LMB mining) ---------------------------

## Cached damage per position: Vector3i -> { "hp": float, "last_hit_ms": int, "max_hp": int }
var _hp_by_pos: Dictionary = {}
var _damage_decal_root: Node3D = null
var _damage_decals: Dictionary = {} # Vector3i -> Decal
static var _crack_textures: Array[ImageTexture] = []

## Grace period in seconds before a damaged voxel begins regenerating HP.
const HEAL_GRACE_PERIOD_SEC := 2.0


## Computes the current effective HP of a damaged voxel at pos, taking into account
## damage decay / regeneration (TerrainMaterialDef.minutes_to_full_heal).
## If healed to full HP, erases the entry, removes decal, and returns max_hp.
func _get_effective_hp(pos: Vector3i, material: TerrainMaterialDef) -> float:
	if not _hp_by_pos.has(pos):
		return float(material.hp if material != null else (default_material.hp if default_material != null else 100))
	var entry: Dictionary = _hp_by_pos[pos]
	if material != null and material.minutes_to_full_heal <= 0.0:
		return float(entry.get("hp", float(material.hp)))
	var full_heal_sec: float = (material.minutes_to_full_heal * 60.0) if material != null else 15.0
	if full_heal_sec <= 0.0:
		return float(entry.get("hp", 100.0))
	var now_ms: int = Time.get_ticks_msec()
	var elapsed_sec: float = float(now_ms - int(entry.get("last_hit_ms", now_ms))) / 1000.0
	var max_hp: float = float(entry.get("max_hp", material.hp if material != null else 100))
	if elapsed_sec <= HEAL_GRACE_PERIOD_SEC:
		return float(entry.get("hp", max_hp))
	var heal_elapsed: float = elapsed_sec - HEAL_GRACE_PERIOD_SEC
	var heal_rate: float = max_hp / maxf(1.0, full_heal_sec - HEAL_GRACE_PERIOD_SEC)
	var current_hp: float = float(entry.get("hp", max_hp)) + heal_rate * heal_elapsed
	if current_hp >= max_hp:
		_hp_by_pos.erase(pos)
		_remove_damage_decal(pos)
		return max_hp
	_update_damage_decal(pos, 1.0 - (current_hp / max_hp))
	return current_hp


## Current effective HP at pos (or max HP if undamaged / air).
func get_hp_at(pos: Vector3i) -> int:
	var material: TerrainMaterialDef = get_material_def_at(pos)
	if material == null:
		material = default_material
	return int(ceil(_get_effective_hp(pos, material)))


## Max HP of the material at pos.
func get_max_hp_at(pos: Vector3i) -> int:
	var material: TerrainMaterialDef = get_material_def_at(pos)
	if material == null:
		material = default_material
	return material.hp if material != null else 100


## Applies damage to the terrain voxel at pos.
## If HP reaches 0, carves the voxel, grants yields to actor, records mining skill,
## and returns {"destroyed": true, "material": material, "remaining_hp": 0, "max_hp": max_hp}.
## If HP > 0, returns {"destroyed": false, "material": material, "remaining_hp": remaining_hp, "max_hp": max_hp}.
func apply_damage_at(pos: Vector3i, amount: int, actor: Node = null, normal: Vector3 = Vector3.UP) -> Dictionary:
	var material: TerrainMaterialDef = get_material_def_at(pos)
	if material == null:
		material = default_material
	var max_hp: int = material.hp if material != null else 100
	var current_hp: float = _get_effective_hp(pos, material)
	var new_hp: float = current_hp - float(amount)
	
	if new_hp <= 0.0:
		_hp_by_pos.erase(pos)
		_remove_damage_decal(pos)
		carve_box(Vector3(pos), Vector3(pos) + Vector3.ONE)
		if material != null and actor != null:
			var pocket := _pocket_of(actor)
			if pocket != null:
				for entry: ItemAmount in material.yields:
					pocket.add(entry.item_def.id, entry.count)
			var skill_set := _skills_of(actor)
			if skill_set != null:
				skill_set.record_use_for_labor("mining")
		return {
			"destroyed": true,
			"material": material,
			"remaining_hp": 0,
			"max_hp": max_hp
		}
	
	_hp_by_pos[pos] = {
		"hp": new_hp,
		"last_hit_ms": Time.get_ticks_msec(),
		"max_hp": max_hp
	}
	_update_damage_decal(pos, 1.0 - (new_hp / float(max_hp)), normal)
	return {
		"destroyed": false,
		"material": material,
		"remaining_hp": int(ceil(new_hp)),
		"max_hp": max_hp
	}


func _update_damage_decal(pos: Vector3i, damage_ratio: float, normal: Vector3 = Vector3.UP) -> void:
	if damage_ratio <= 0.0:
		_remove_damage_decal(pos)
		return
	var root := _get_or_create_damage_decal_root()
	if root == null:
		return
	var stage := 0
	if damage_ratio >= 0.7:
		stage = 2
	elif damage_ratio >= 0.35:
		stage = 1
	var decal: Decal = _damage_decals.get(pos)
	if decal == null or not is_instance_valid(decal) or decal.is_queued_for_deletion():
		decal = Decal.new()
		decal.name = "Crack_%d_%d_%d" % [pos.x, pos.y, pos.z]
		decal.size = Vector3(1.2, 1.2, 1.2)
		decal.upper_fade = 0.05
		decal.lower_fade = 0.05
		
		# Orient decal projection along the struck surface normal
		var n := normal.normalized() if not normal.is_zero_approx() else Vector3.UP
		var basis: Basis
		if absf(n.dot(Vector3.UP)) > 0.95:
			basis = Basis(Vector3.RIGHT, -PI / 2.0 * signf(n.y if n.y != 0.0 else 1.0))
		else:
			basis = Basis.looking_at(-n, Vector3.UP)
		
		var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
		decal.transform = Transform3D(basis, center)
		root.add_child(decal)
		_damage_decals[pos] = decal
	
	decal.texture_albedo = _get_crack_texture(stage)


func _get_or_create_damage_decal_root() -> Node3D:
	if _damage_decal_root == null or not is_instance_valid(_damage_decal_root):
		_damage_decal_root = Node3D.new()
		_damage_decal_root.name = "DamageDecals"
		add_child(_damage_decal_root)
	return _damage_decal_root


func _remove_damage_decal(pos: Vector3i) -> void:
	if _damage_decals.has(pos):
		var decal: Decal = _damage_decals[pos]
		if decal != null and is_instance_valid(decal) and not decal.is_queued_for_deletion():
			decal.queue_free()
		_damage_decals.erase(pos)


func _clear_all_damage_decals() -> void:
	for pos: Vector3i in _damage_decals.keys():
		var decal: Decal = _damage_decals[pos]
		if decal != null and is_instance_valid(decal) and not decal.is_queued_for_deletion():
			decal.queue_free()
	_damage_decals.clear()


static func _get_crack_texture(stage: int) -> ImageTexture:
	if _crack_textures.is_empty():
		_crack_textures = _build_crack_textures()
	var clamped := clampi(stage, 0, _crack_textures.size() - 1)
	return _crack_textures[clamped]


static func _build_crack_textures() -> Array[ImageTexture]:
	var textures: Array[ImageTexture] = []
	var size := 128
	var seeds := [12345, 67890, 54321]
	var root_counts := [4, 8, 14]
	var seg_counts := [8, 14, 24]
	var widths := [2, 3, 4]
	var crack_color := Color(0.04, 0.04, 0.04, 0.98)
	var sub_color := Color(0.12, 0.12, 0.12, 0.88)

	for s: int in 3:
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = seeds[s]
		var num_roots: int = root_counts[s]
		var num_segs: int = seg_counts[s]
		var width: int = widths[s]

		for r: int in num_roots:
			var cx := rng.randi_range(30, size - 30)
			var cy := rng.randi_range(30, size - 30)
			var base_angle := rng.randf_range(0.0, TAU)
			for seg: int in num_segs:
				var angle := base_angle + rng.randf_range(-0.6, 0.6)
				var length := rng.randf_range(8.0, 26.0)
				var nx := clampi(int(round(float(cx) + cos(angle) * length)), 4, size - 5)
				var ny := clampi(int(round(float(cy) + sin(angle) * length)), 4, size - 5)
				_draw_thick_line_on_image(image, cx, cy, nx, ny, crack_color, width)
				if s >= 1 and rng.randf() > 0.4:
					var b_angle := angle + rng.randf_range(-1.2, 1.2)
					var b_len := length * 0.7
					var bx := clampi(int(round(float(nx) + cos(b_angle) * b_len)), 4, size - 5)
					var by := clampi(int(round(float(ny) + sin(b_angle) * b_len)), 4, size - 5)
					_draw_thick_line_on_image(image, nx, ny, bx, by, sub_color, maxi(1, width - 1))
				cx = nx
				cy = ny
				base_angle = angle

		textures.append(ImageTexture.create_from_image(image))
	return textures


static func _draw_thick_line_on_image(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color, thickness: int = 1) -> void:
	if thickness <= 1:
		_draw_line_on_image(img, x0, y0, x1, y1, col)
		return
	var half := thickness / 2
	for ox: int in range(-half, half + 1):
		for oy: int in range(-half, half + 1):
			_draw_line_on_image(img, x0 + ox, y0 + oy, x1 + ox, y1 + oy, col)


static func _draw_line_on_image(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while true:
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			img.set_pixel(x, y, col)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


func _pocket_of(actor: Node) -> Inventory:
	var colonist := actor as Colonist
	if colonist != null and colonist.inventory != null:
		return colonist.inventory
	var player := actor as Player
	if player != null and player.inventory != null:
		return player.inventory
	if actor != null and "inventory" in actor and actor.get("inventory") is Inventory:
		return actor.get("inventory")
	return null


func _skills_of(actor: Node) -> SkillSet:
	var colonist := actor as Colonist
	if colonist != null:
		return colonist.skill_set
	var player := actor as Player
	if player != null:
		return player.skill_set
	if actor != null and "skill_set" in actor and actor.get("skill_set") is SkillSet:
		return actor.get("skill_set")
	return null


# --- queries --------------------------------------------------------------------

## Ray against the natural surface only (mask = TerrainSmooth). Returns float
## values, not cells — smooth normals are non-axis-aligned (F7) and consumers
## derive their own cells: { position: Vector3, normal: Vector3, hit: bool }.
func raycast_to_surface(origin: Vector3, dir: Vector3, max_dist: float, exclude: Array = []) -> Dictionary:
	var space := _terrain.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	query.collision_mask = TERRAIN_LAYER_VALUE
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if not exclude.is_empty():
		query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"position": Vector3.ZERO, "normal": Vector3.ZERO, "hit": false}
	return {"position": hit.position, "normal": hit.normal, "hit": true}

## Ray origin height / length for height_at: far above anything authorable, so
## one straight-down ray covers the whole column.
const HEIGHT_RAY_FROM_Y := 512.0
const HEIGHT_RAY_LENGTH := 1024.0

## World-space height of the natural surface at column (x, z), NAN when the
## smooth terrain doesn't reach it. Cached per column (D4's heightfield);
## invalidated by edits and block streaming. `normal_out` receives the surface
## normal — the slope gate for Phase 3 walkability reads it.
func height_at(x: float, z: float, normal_out: Array = []) -> float:
	var col := Vector2i(int(floor(x)), int(floor(z)))
	if _height_cache.has(col):
		var entry: Dictionary = _height_cache[col]
		normal_out.append(entry["n"])
		return entry["h"]
	var space := _terrain.get_world_3d().direct_space_state
	var from := Vector3(x, HEIGHT_RAY_FROM_Y, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * HEIGHT_RAY_LENGTH)
	query.collision_mask = TERRAIN_LAYER_VALUE
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	_height_cache[col] = {"h": hit.position.y, "n": hit.normal}
	normal_out.append(hit.normal)
	return hit.position.y

# --- accessors --------------------------------------------------------------------

func get_terrain() -> VoxelTerrain:
	return _terrain

func get_voxel_tool() -> VoxelTool:
	return _voxel_tool

# --- invalidation -------------------------------------------------------------------

## Edit-sphere eviction: any cached column whose center is within radius + the
## diagonal of one column could have changed surface.
func _evict_columns_near(pos: Vector3, radius: float) -> void:
	var reach := radius + 1.5
	var min_col := Vector2i(int(floor(pos.x - reach)), int(floor(pos.z - reach)))
	var max_col := Vector2i(int(floor(pos.x + reach)), int(floor(pos.z + reach)))
	for col: Vector2i in _height_cache.keys():
		if col.x >= min_col.x and col.x <= max_col.x and col.y >= min_col.y and col.y <= max_col.y:
			_height_cache.erase(col)


func _evict_columns_in_box(min_pos: Vector3, max_pos: Vector3) -> void:
	var reach := 1.5
	var min_col := Vector2i(int(floor(min_pos.x - reach)), int(floor(min_pos.z - reach)))
	var max_col := Vector2i(int(floor(max_pos.x + reach)), int(floor(max_pos.z + reach)))
	for col: Vector2i in _height_cache.keys():
		if col.x >= min_col.x and col.x <= max_col.x and col.y >= min_col.y and col.y <= max_col.y:
			_height_cache.erase(col)

func _clear_height_cache(_block_position: Vector3i = Vector3i.ZERO) -> void:
	_height_cache.clear()
	_clear_all_damage_decals()


## Block streaming both invalidates the height cache (D4) and re-exposes F12
## sidecar data — the marker reconstruction path that makes Decals survive map
## reloads (F14).
func _on_block_loaded(origin: Vector3i) -> void:
	_height_cache.clear()
	_spawn_markers_for_block(origin)

# --- SaveSystem contract -------------------------------------------------------------

## v1 no-op: the smooth terrain's whole state lives in its sqlite stream
## (stream-saved blocks override the generator, F8) — there is no in-memory
## metadata to snapshot, unlike BlockyGrid's HP table. Kept so SaveSystem can
## treat both grids uniformly when Phase 4 generalizes the two-stream flush.
func serialize() -> Dictionary:
	return {"version": 1}

func deserialize(_data: Dictionary) -> void:
	pass
