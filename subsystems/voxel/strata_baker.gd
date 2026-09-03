class_name StrataBaker
extends RefCounted

const StrataBakeResult = preload("res://subsystems/voxel/strata_bake_result.gd")
## Volumetric bake engine for natural terrain ore strata (Option B2).
##
## Evaluates a configured TerrainStrata across a bounded 3D axis-aligned box
## and outputs an ImageTexture3D (FORMAT_R8) carrying discrete palette indices.
## Because the 3D texture is evaluated directly against TerrainStrata's
## material_id_at rules, the visuals rendered by the terrain shader match
## mining item drops with 100% spatial fidelity.
##
## Slices along the Z axis can be computed concurrently via WorkerThreadPool,
## reducing map load times to negligible fractions of a second.

const DEFAULT_BACKGROUND_IDS: Array[String] = ["ground", "rock"]


## Builds a deterministic mapping of material ID -> byte palette index (0..255).
## Materials matching background_ids map to 0 (macro-strata ground/rock blend in shader).
## Sub-surface ores are assigned positive sequential integers (1..255).
static func build_palette(materials: Array, background_ids: Array = DEFAULT_BACKGROUND_IDS) -> Dictionary:
	var palette: Dictionary = {}
	var valid_defs: Array[TerrainMaterialDef] = []
	for m in materials:
		if m is TerrainMaterialDef and m.id != "":
			valid_defs.append(m)
	# Sort deterministically by id so palette indexing is seed- and scan-order immune.
	valid_defs.sort_custom(func(a: TerrainMaterialDef, b: TerrainMaterialDef) -> bool:
		return a.id < b.id)

	var next_index := 1
	for m: TerrainMaterialDef in valid_defs:
		if m.id in background_ids:
			palette[m.id] = 0
		else:
			palette[m.id] = mini(next_index, 255)
			next_index += 1
	return palette


## Bakes an axis-aligned 3D volume into an ImageTexture3D.
##
## - origin: world-space integer coordinate of the minimum corner (UVW 0, 0, 0).
## - size: volume dimensions in voxels/meters (width=X, height=Y, depth=Z).
## - threaded: if true, evaluates Z slices concurrently on WorkerThreadPool.
## - keep_images: if true, retains the CPU Image slices in the result for CPU inspection/testing.
static func bake(
	strata: TerrainStrata,
	palette_by_id: Dictionary,
	origin: Vector3i,
	size: Vector3i,
	pristine_height: Callable = Callable(),
	threaded: bool = true,
	keep_images: bool = false
) -> StrataBakeResult:
	if strata == null or size.x <= 0 or size.y <= 0 or size.z <= 0:
		push_error("StrataBaker: Invalid strata or non-positive volume size %s" % str(size))
		return null

	var id_by_palette: Dictionary = {}
	for id_str: String in palette_by_id:
		var idx: int = palette_by_id[id_str]
		if idx > 0 and not id_by_palette.has(idx):
			id_by_palette[idx] = id_str

	# Resolve pristine height callable if omitted
	if not pristine_height.is_valid() and strata.has_method("get_pristine_height"):
		pristine_height = strata.get_pristine_height()

	# Pre-warm pristine height cache on the calling thread across the 2D footprint (x, z).
	# This ensures multi-threaded slice tasks only perform thread-safe read hits on the cache.
	if pristine_height.is_valid():
		for z_local: int in size.z:
			var wz := origin.z + z_local
			for x_local: int in size.x:
				pristine_height.call(origin.x + x_local, wz)

	var slices: Array[Image] = []
	slices.resize(size.z)

	var compute_slice := func(z_local: int) -> void:
		var wz := origin.z + z_local
		var buffer := PackedByteArray()
		buffer.resize(size.x * size.y)
		var idx := 0
		for y_local: int in size.y:
			var wy := origin.y + y_local
			for x_local: int in size.x:
				var wx := origin.x + x_local
				var mat_id := strata.material_id_at(Vector3i(wx, wy, wz))
				var p_idx: int = palette_by_id.get(mat_id, 0)
				buffer[idx] = p_idx
				idx += 1
		slices[z_local] = Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, buffer)

	# Execute slice generation
	if threaded and size.z > 1 and WorkerThreadPool != null:
		var group_id := WorkerThreadPool.add_group_task(compute_slice, size.z)
		WorkerThreadPool.wait_for_group_task_completion(group_id)
	else:
		for z_local: int in size.z:
			compute_slice.call(z_local)

	# Texture3D creation must happen on the main/calling thread
	var tex := ImageTexture3D.new()
	var err := tex.create(Image.FORMAT_R8, size.x, size.y, size.z, false, slices)
	if err != OK:
		push_error("StrataBaker: Failed to create ImageTexture3D with code %d" % err)
		return null

	var result := StrataBakeResult.new()
	result.texture = tex
	result.origin = origin
	result.size = size
	result.palette_by_id = palette_by_id
	result.id_by_palette = id_by_palette
	if keep_images:
		result.slices = slices
	return result
