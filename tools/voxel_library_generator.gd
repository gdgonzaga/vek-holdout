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
	elif block_def.texture != null or block_def.normal_texture != null or block_def.roughness_texture != null or block_def.metalness_texture != null or block_def.displacement_texture != null or block_def.orme_texture != null:
		if block_def.texture_variation:
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://assets/shaders/block_shader.gdshader")
			mat.set_shader_parameter("albedo_tex", block_def.texture)
			mat.set_shader_parameter("normal_tex", block_def.normal_texture)
			mat.set_shader_parameter("roughness_tex", block_def.roughness_texture)
			mat.set_shader_parameter("metallic_tex", block_def.metalness_texture)
			mat.set_shader_parameter("disp_tex", block_def.displacement_texture)
			mat.set_shader_parameter("orme_tex", block_def.orme_texture)
			model.material_override_0 = mat
		else:
			var mat := StandardMaterial3D.new()
			if block_def.texture != null:
				mat.albedo_texture = block_def.texture
			if block_def.normal_texture != null:
				mat.normal_enabled = true
				mat.normal_texture = block_def.normal_texture
			if block_def.orme_texture != null:
				mat.ao_enabled = true
				mat.ao_texture = block_def.orme_texture
				mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
				mat.roughness_texture = block_def.orme_texture
				mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
				mat.metallic = 1.0
				mat.metallic_texture = block_def.orme_texture
				mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			else:
				if block_def.roughness_texture != null:
					mat.roughness_texture = block_def.roughness_texture
				if block_def.metalness_texture != null:
					mat.metallic = 1.0
					mat.metallic_texture = block_def.metalness_texture
			if block_def.displacement_texture != null:
				mat.heightmap_enabled = true
				mat.heightmap_texture = block_def.displacement_texture
			model.material_override_0 = mat

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
