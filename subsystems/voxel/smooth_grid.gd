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
## F8 (docs/VOXEL-TOOL-NOTES.md) is the authority on the edit semantics this
## class encodes: channel 0 is float SDF (solid <= 0, air > 0); MODE_SET value v
## writes SDF -v — so value 0 is still solid and carving MUST use MODE_REMOVE;
## the mesher has no material API (one fixed appearance; identity lives in
## TerrainMaterialDef, not in voxel values).
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

## Path/name of the VoxelTerrain node, relative to this SmoothGrid. The map
## template parents VoxelTerrain as a direct child.
@export var terrain_path: NodePath = ^"VoxelTerrain"

## Generator params; injected by SceneManager from MapDef.terrain_gen before
## the map enters the tree. Null at _ready = this map has no smooth terrain.
@export var terrain_gen: TerrainGenDef = null

## The identity get_material_at reports for solid ground. F8: voxel values are
## pure density — there is no per-voxel material channel to read, so v1 reports
## one def for any solid position (the D1-documented fallback, now the ceiling).
@export var default_material: TerrainMaterialDef = null

@onready var _terrain: VoxelTerrain = get_node(terrain_path)
var _voxel_tool: VoxelTool
var _default_material_warned := false

## Cached heightfield for D4 walkability: column -> {"h": float, "n": Vector3}.
## Populated lazily by height_at; evicted on edits and block streaming so
## pathing never answers from stale ground ("edits keep pathing honest").
var _height_cache: Dictionary = {}

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

	if "generator" in _terrain:
		_terrain.set("generator", _build_generator(terrain_gen))
	if "mesher" in _terrain:
		_terrain.set("mesher", VoxelMesherTransvoxel.new())

	_voxel_tool = _terrain.get_voxel_tool()

	# D4 invalidation hooks (F8 signatures): block streaming swaps voxel data
	# under cached columns — a loaded block may carry sqlite edits, an unloaded
	# one takes its columns with it. Whole-cache clear: correct and cheap next
	# to per-block column math; the cache repopulates on demand.
	if _terrain.has_signal("block_loaded"):
		_terrain.block_loaded.connect(_clear_height_cache)
	if _terrain.has_signal("block_unloaded"):
		_terrain.block_unloaded.connect(_clear_height_cache)

# --- generator construction ---------------------------------------------------

## Generator for the def's terrain: heightmap-driven when the def carries a
## readable image, noise otherwise. Both paths write the same span fields, so a
## def can switch modes without touching height_start/height_range.
func _build_generator(def: TerrainGenDef) -> Resource:
	var heightmap := _prepare_heightmap_image(def.heightmap)
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
## addon build (tmp/heightmap_gen_probe.gd): image, height_start, height_range.
func _build_heightmap_generator(def: TerrainGenDef, heightmap: Image) -> Resource:
	var generator := VoxelGeneratorImage.new()
	# Same guarded-set contract as the noise builder.
	if "image" in generator:
		generator.set("image", heightmap)
	if "height_start" in generator:
		generator.set("height_start", def.height_start)
	if "height_range" in generator:
		generator.set("height_range", def.height_range)
	return generator

## Heightmap pixels as the generator wants them: uncompressed L8 so the value
## read is the authored grayscale regardless of source texture format. Static
## so a future blocky-grid image generator in this subsystem can promote it to
## a shared helper by moving, not rewriting. Null tex / unreadable pixels ->
## null (the caller falls back to noise; the error is reported here).
static func _prepare_heightmap_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var image := tex.get_image()
	if image == null:
		push_error("SmoothGrid: terrain_gen.heightmap has no readable pixels — falling back to noise")
		return null
	if image.is_compressed():
		if image.decompress() != OK:
			push_error("SmoothGrid: terrain_gen.heightmap is compressed and cannot decompress — falling back to noise")
			return null
	image.convert(Image.FORMAT_L8)
	return image

# --- read / edit surface (D1 mirror of BlockyGrid's block API) -----------------

## Material id at pos, or "" for air. F8: values are pure density — no material
## channel exists — so any solid position reports default_material's id.
func get_material_at(pos: Vector3i) -> String:
	if _voxel_tool == null or not _voxel_tool.has_method("get_voxel_f"):
		return ""
	if _voxel_tool.get_voxel_f(pos) > 0.0:
		return ""
	if default_material == null:
		if not _default_material_warned:
			push_warning("SmoothGrid: no default_material assigned — get_material_at returns \"\" for solid ground")
			_default_material_warned = true
		return ""
	return default_material.id

## Add a sphere of solid ground (SDF -SOLID_DENSITY) at world pos. The smooth-
## placement primitive (Phase 5 build mode); material_id rides the signal for
## inventory/yields, not the voxels — F8: no identity channel exists.
func add_material(pos: Vector3, material_id: String, radius: float) -> void:
	if _voxel_tool == null:
		return
	_voxel_tool.mode = VoxelTool.MODE_ADD
	_voxel_tool.value = SOLID_DENSITY
	_voxel_tool.do_sphere(pos, radius)
	_evict_columns_near(pos, radius)
	material_placed.emit(pos, material_id)

## Carve a sphere of terrain away at world pos. The mining primitive (Phase 5
## dig action). MODE_REMOVE, never MODE_SET — F8: value 0 is still solid.
func carve(pos: Vector3, radius: float) -> void:
	if _voxel_tool == null:
		return
	_voxel_tool.mode = VoxelTool.MODE_REMOVE
	_voxel_tool.do_sphere(pos, radius)
	_evict_columns_near(pos, radius)
	material_carved.emit(pos)

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

func _clear_height_cache(_block_position: Vector3i = Vector3i.ZERO) -> void:
	_height_cache.clear()

# --- SaveSystem contract -------------------------------------------------------------

## v1 no-op: the smooth terrain's whole state lives in its sqlite stream
## (stream-saved blocks override the generator, F8) — there is no in-memory
## metadata to snapshot, unlike BlockyGrid's HP table. Kept so SaveSystem can
## treat both grids uniformly when Phase 4 generalizes the two-stream flush.
func serialize() -> Dictionary:
	return {"version": 1}

func deserialize(_data: Dictionary) -> void:
	pass
