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
	var mesh_to_use: Mesh = block_def.base_mesh if block_def.base_mesh != null else block_def.mesh
	model.mesh = mesh_to_use
	if "mesh_ortho_rotation_index" in model:
		model.mesh_ortho_rotation_index = ortho_index
	elif "mesh_ortho_rotation" in model:
		model.set("mesh_ortho_rotation", ortho_index)
	model.resource_name = "%s_%d" % [block_def.id, ortho_index]
	if block_def.texture != null:
		if block_def.texture_variation:
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://assets/blocks/block_shader.gdshader")
			mat.set_shader_parameter("albedo_tex", block_def.texture)
			model.material_override_0 = mat
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = block_def.texture
			model.material_override_0 = mat
	# Collision generation property name varies across voxel_tool versions.
	if "collision_enabled_0" in model:
		model.set("collision_enabled_0", true)
	return model


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


static func register_block_in_library(block_def: BlockDef, library: VoxelBlockyLibrary) -> void:
	if block_def == null or library == null:
		return
	var new_models: Array[VoxelBlockyModelMesh] = generate_block_models(block_def)
	var start_id: int = block_def.base_library_id
	var existing: Array = library.get_models()
	while existing.size() < start_id:
		existing.append(VoxelBlockyModelEmpty.new())
	for i in range(new_models.size()):
		var target_idx: int = start_id + i
		if target_idx < existing.size():
			existing[target_idx] = new_models[i]
		else:
			existing.append(new_models[i])
	library.set_models(existing)
