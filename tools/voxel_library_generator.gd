@tool
class_name VoxelLibraryGenerator
extends RefCounted
## Utility to generate rotated VoxelBlockyModelMesh entries from a BlockDef
## and register them into a VoxelBlockyLibrary.


static func generate_block_models(block_def: BlockDef) -> Array[VoxelBlockyModelMesh]:
	var out: Array[VoxelBlockyModelMesh] = []
	if block_def == null:
		return out
	
	var mesh_to_use: Mesh = block_def.base_mesh if block_def.base_mesh != null else block_def.mesh
	var mat_override: Material = null
	if block_def.texture != null:
		if block_def.texture_variation:
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://assets/blocks/block_shader.gdshader")
			mat.set_shader_parameter("albedo_tex", block_def.texture)
			mat_override = mat
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = block_def.texture
			mat_override = mat

	match block_def.rotation_mode:
		BlockDef.RotationMode.NONE:
			var model := _create_model(mesh_to_use, 0, "%s_0" % block_def.id, mat_override)
			out.append(model)

		BlockDef.RotationMode.FULL_3D:
			for i in range(24):
				var model := _create_model(mesh_to_use, i, "%s_%d" % [block_def.id, i], mat_override)
				out.append(model)

		BlockDef.RotationMode.YAW_ONLY:
			for idx in BlockDef.YAW_INDICES:
				var model := _create_model(mesh_to_use, idx, "%s_%d" % [block_def.id, idx], mat_override)
				out.append(model)

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


static func _create_model(mesh_res: Mesh, ortho_idx: int, model_name: String, mat_override: Material) -> VoxelBlockyModelMesh:
	var model := VoxelBlockyModelMesh.new()
	model.mesh = mesh_res
	if "mesh_ortho_rotation_index" in model:
		model.mesh_ortho_rotation_index = ortho_idx
	elif "mesh_ortho_rotation" in model:
		model.set("mesh_ortho_rotation", ortho_idx)
	model.resource_name = model_name
	if mat_override != null:
		model.material_override_0 = mat_override
	if "collision_enabled_0" in model:
		model.set("collision_enabled_0", true)
	return model
