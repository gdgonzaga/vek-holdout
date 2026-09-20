class_name MapTerrainAuthoring
extends RefCounted
## File-level rules for a map's TerrainGenDef. The editor may only mutate a def
## stored at data/maps/<id>/terrain_gen.tres ("map-owned"); shared baselines in
## data/terrain/ are copied there on first edit so one map's tweak can never
## change another map. Pure/static so the rules are testable without the editor.

const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")

const TERRAIN_FILE: String = "terrain_gen.tres"
## Same defaults the launcher's create form shows (min -6 m, max +10 m).
const DEFAULT_HEIGHT_START: float = -6.0
const DEFAULT_HEIGHT_RANGE: float = 16.0


# =================
# Primary Functions
# =================

static func map_terrain_path(maps_dir: String, map_id: String) -> String:
	return maps_dir.path_join(map_id).path_join(TERRAIN_FILE)


static func is_map_owned(def: TerrainGenDef, maps_dir: String, map_id: String) -> bool:
	return def != null and def.resource_path == map_terrain_path(maps_dir, map_id)


## In-memory only: the copy gets its file when persist_owned runs.
static func ensure_map_owned(def: TerrainGenDef, map_id: String) -> TerrainGenDef:
	if def == null or _looks_map_owned(def, map_id):
		return def
	# 1. Copy: duplicate so the shared baseline keeps its values and identity.
	var copy := def.duplicate() as TerrainGenDef
	copy.id = map_id + "_terrain"
	copy.display_name = map_id.capitalize() + " Terrain"
	# 2. Embed: a heightmap borrowed from another file becomes an embedded ImageTexture so the map folder stays self-contained.
	_embed_heightmap(copy)
	return copy


## take_over_path makes this instance the cache entry for the file, so a later
## load() returns it instead of a stale earlier instance (Godot 4.7.2 verified).
static func persist_owned(def: TerrainGenDef, maps_dir: String, map_id: String) -> Error:
	if def == null:
		return ERR_INVALID_PARAMETER
	var path := map_terrain_path(maps_dir, map_id)
	def.take_over_path(path)
	var err := ResourceSaver.save(def, path)
	if err != OK:
		push_warning("MapTerrainAuthoring: failed to save '%s' (error %d)" % [path, err])
	return err


static func apply_edits(def: TerrainGenDef, edits: Dictionary) -> void:
	if def == null:
		return
	# 1. Span: only when the drawer reported it.
	_apply_span(def, edits)
	# 2. Noise: only when the drawer reported it.
	_apply_noise(def, edits)
	# 3. Snap: re-quantize the stored image only on an explicit request.
	_apply_snap(def, edits)


static func apply_water(def: TerrainGenDef, enabled: bool, level: float) -> void:
	if def == null:
		return
	def.water_enabled = enabled
	def.water_level = level


static func build_heightmap_def(map_id: String, image: Image, height_start: float, height_range: float, snap_to_grid: bool) -> TerrainGenDef:
	# 1. Normalize: snapped or plain L8 so the generator reads the same pixels the preview shows.
	var prepared := _prepare_heightmap_image(image, height_start, height_range, snap_to_grid)
	var def := TerrainGenDef.new()
	def.id = map_id + "_terrain"
	def.display_name = map_id.capitalize() + " Terrain"
	def.height_start = height_start
	def.height_range = height_range
	def.heightmap = ImageTexture.create_from_image(prepared)
	return def


# ===================
# Auxiliary Functions
# ===================

static func _looks_map_owned(def: TerrainGenDef, map_id: String) -> bool:
	## Auxiliary: local to this map by folder segment (independent of the maps dir constant) or in-memory only.
	# A def with no resource path exists only in memory (a fresh copy or replacement), so it is already this map's; a shared baseline always has a path.
	return def.resource_path.is_empty() or def.resource_path.ends_with("/%s/%s" % [map_id, TERRAIN_FILE])


static func _embed_heightmap(def: TerrainGenDef) -> void:
	## Auxiliary: replaces a borrowed heightmap texture with an embedded copy.
	if def.heightmap == null:
		return
	var image := def.heightmap.get_image()
	if image == null:
		return
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_L8)
	def.heightmap = ImageTexture.create_from_image(image)


static func _apply_span(def: TerrainGenDef, edits: Dictionary) -> void:
	## Auxiliary: heightmap defs only. A noise def's height band is not editable in the drawer, so a span key must never rewrite it.
	if def.heightmap == null:
		return
	if edits.has("height_start"):
		def.height_start = float(edits["height_start"])
	if edits.has("height_range"):
		def.height_range = float(edits["height_range"])


static func _apply_noise(def: TerrainGenDef, edits: Dictionary) -> void:
	## Auxiliary: noise defs only; a heightmap def ignores seed and frequency.
	if def.heightmap != null:
		return
	if edits.has("noise_seed"):
		def.noise_seed = int(edits["noise_seed"])
	if edits.has("noise_frequency"):
		def.noise_frequency = float(edits["noise_frequency"])


static func _apply_snap(def: TerrainGenDef, edits: Dictionary) -> void:
	## Auxiliary: quantizes the stored heightmap to 1 m tiers when snap was requested.
	if not bool(edits.get("snap_to_grid", false)) or def.heightmap == null:
		return
	var raw := def.heightmap.get_image()
	if raw == null:
		return
	var snapped_img := EditorLauncherClass.quantize_heightmap_image(raw, def.height_start, def.height_range, 1.0)
	def.heightmap = ImageTexture.create_from_image(snapped_img)


static func _prepare_heightmap_image(image: Image, height_start: float, height_range: float, snap_to_grid: bool) -> Image:
	## Auxiliary: snapped image, or a decompressed L8 copy.
	if snap_to_grid:
		return EditorLauncherClass.quantize_heightmap_image(image, height_start, height_range, 1.0)
	var copy := image.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.convert(Image.FORMAT_L8)
	return copy
