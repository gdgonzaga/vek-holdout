@tool
class_name VoxelLibraryGenerator
extends RefCounted
## Bakes rotation-variant VoxelBlockyModelMesh entries for a BlockDef.
##
## All variant models SHARE the def's mesh and differ only in
## mesh_ortho_rotation_index — the mesher rotates the geometry at bake time,
## so authors ship one unrotated mesh per block (see VoxelBlockEncoder's class
## doc for the orientation-index convention). create_block_model() is the
## single model-creation path, shared with BlockLibrary's runtime baking;
## generate_block_models()/register_block_in_library() cover editor-tool
## registration into a baked .tres library.


## One variant model for the def at the given orthogonal orientation.
static func create_block_model(block_def: BlockDef, ortho_index: int) -> VoxelBlockyModelMesh:
	var model := VoxelBlockyModelMesh.new()
	model.mesh = block_def.get_mesh()
	if "mesh_ortho_rotation_index" in model:
		model.mesh_ortho_rotation_index = ortho_index
	elif "mesh_ortho_rotation" in model:
		model.set("mesh_ortho_rotation", ortho_index)
	model.resource_name = "%s_%d" % [block_def.id, ortho_index]
	if block_def.custom_material != null:
		model.material_override_0 = block_def.custom_material
	elif PbrTextureSet.has_any(block_def.pbr):
		# Resolve material for the block model via factory, choosing between variation shader or standard PBR.
		model.material_override_0 = _build_pbr_material(block_def)

	# Configure collision generation (disabled for fluids like water).
	if "collision_enabled_0" in model:
		model.set("collision_enabled_0", block_def.collision_enabled)

	# Configure transparency index (0 = opaque, > 0 = transparent).
	if "transparency_index" in model:
		model.set("transparency_index", block_def.transparency_index)

	# Configure neighbor culling (fluids cull touching faces of the same model).
	if "culls_neighbors_of_same_type" in model:
		model.set("culls_neighbors_of_same_type", block_def.culls_neighbors_of_same_type)

	return model


static func _build_pbr_material(block_def: BlockDef) -> Material:
	## Auxiliary: Chooses between variation ShaderMaterial and StandardMaterial3D based on block definition flags.
	if block_def.texture_variation:
		return PbrMaterialFactory.variation(block_def.pbr)
	return PbrMaterialFactory.standard(block_def.pbr)


## Every variant the def's rotation mode needs, in slot order
## (slot = quarter-turn for YAW_ONLY, ortho index for FULL_3D).
static func generate_block_models(block_def: BlockDef) -> Array[VoxelBlockyModelMesh]:
	var out: Array[VoxelBlockyModelMesh] = []
	if block_def == null:
		return out

	match block_def.rotation_mode:
		BlockDef.RotationMode.NONE:
			out.append(create_block_model(block_def, 0))

		BlockDef.RotationMode.FULL_3D:
			for i in range(24):
				out.append(create_block_model(block_def, i))

		BlockDef.RotationMode.YAW_ONLY:
			for idx in BlockDef.YAW_INDICES:
				out.append(create_block_model(block_def, idx))

	return out


## Register the def's models into a baked editor library starting at
## `start_index` (padding with empties when the library is shorter).
static func register_block_in_library(block_def: BlockDef, library: VoxelBlockyLibrary, start_index: int) -> void:
	if block_def == null or library == null:
		return
	var new_models: Array[VoxelBlockyModelMesh] = generate_block_models(block_def)
	var existing: Array = library.get_models()
	while existing.size() < start_index:
		existing.append(VoxelBlockyModelEmpty.new())
	for i in range(new_models.size()):
		var target_idx: int = start_index + i
		if target_idx < existing.size():
			existing[target_idx] = new_models[i]
		else:
			existing.append(new_models[i])
	library.set_models(existing)
