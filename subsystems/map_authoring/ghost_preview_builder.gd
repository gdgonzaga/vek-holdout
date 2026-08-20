class_name GhostPreviewBuilder
extends RefCounted
## Generates optimized 3D preview meshes for MagicaVoxel (.vox) structure assets.
##
## Constructs an ArrayMesh representing the voxel volume with vertex colors,
## semi-transparent unshaded shading, face culling on internal voxels, and
## custom visual tints for mapped air/ignore palette entries (ARCH "Map Editor").

const DEFAULT_ALPHA: float = 0.75
const AIR_ALPHA: float = 0.35
const AIR_COLOR: Color = Color(1.0, 0.25, 0.25, AIR_ALPHA)


## Creates the default standard material used for ghost structure rendering.
static func create_ghost_material(alpha: float = DEFAULT_ALPHA) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat


## Builds an ArrayMesh representing vox_data with palette coloring and face culling.
## If mapping is provided, respects IGNORE (skips voxel) and AIR (translucent red cutout) targets.
static func build_mesh(vox_data: VoxData, mapping: VoxPaletteMapping = null) -> Mesh:
	if vox_data == null or vox_data.voxel_map.is_empty():
		return ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Pre-filter active voxels to avoid repetitive dictionary lookups
	var active_voxels: Dictionary = {}
	var voxel_colors: Dictionary = {}

	for pos: Vector3i in vox_data.voxel_map.keys():
		var color_idx: int = vox_data.get_voxel(pos)
		if color_idx <= 0:
			continue

		var hex := vox_data.get_hex_color(color_idx)
		var entry: VoxPaletteEntry = mapping.get_target_for_index(color_idx, hex) if mapping != null else null

		# Skip IGNORE voxels completely in the preview
		if entry != null and entry.target_type == VoxPaletteEntry.TargetType.IGNORE:
			continue

		active_voxels[pos] = true

		var col := vox_data.get_color(color_idx)
		if entry != null and entry.target_type == VoxPaletteEntry.TargetType.AIR:
			voxel_colors[pos] = AIR_COLOR
		else:
			voxel_colors[pos] = Color(col.r, col.g, col.b, DEFAULT_ALPHA)

	# Face definitions: [normal, neighbor_offset, v0, v1, v2, v3]
	# Counter-clockwise winding facing outward from the unit cube
	for pos: Vector3i in active_voxels.keys():
		var col: Color = voxel_colors.get(pos, Color.WHITE)
		var px := float(pos.x)
		var py := float(pos.y)
		var pz := float(pos.z)

		# +X Face
		if not active_voxels.has(pos + Vector3i(1, 0, 0)):
			st.set_normal(Vector3.RIGHT)
			st.set_color(col)
			_add_quad(
				st,
				Vector3(px + 1.0, py, pz),
				Vector3(px + 1.0, py + 1.0, pz),
				Vector3(px + 1.0, py + 1.0, pz + 1.0),
				Vector3(px + 1.0, py, pz + 1.0)
			)

		# -X Face
		if not active_voxels.has(pos + Vector3i(-1, 0, 0)):
			st.set_normal(Vector3.LEFT)
			st.set_color(col)
			_add_quad(
				st,
				Vector3(px, py, pz + 1.0),
				Vector3(px, py + 1.0, pz + 1.0),
				Vector3(px, py + 1.0, pz),
				Vector3(px, py, pz)
			)

		# +Y Face
		if not active_voxels.has(pos + Vector3i(0, 1, 0)):
			st.set_normal(Vector3.UP)
			st.set_color(col)
			_add_quad(
				st,
				Vector3(px, py + 1.0, pz + 1.0),
				Vector3(px + 1.0, py + 1.0, pz + 1.0),
				Vector3(px + 1.0, py + 1.0, pz),
				Vector3(px, py + 1.0, pz)
			)

		# -Y Face
		if not active_voxels.has(pos + Vector3i(0, -1, 0)):
			st.set_normal(Vector3.DOWN)
			st.set_color(col)
			_add_quad(
				st,
				Vector3(px, py, pz),
				Vector3(px + 1.0, py, pz),
				Vector3(px + 1.0, py, pz + 1.0),
				Vector3(px, py, pz + 1.0)
			)

		# +Z Face
		if not active_voxels.has(pos + Vector3i(0, 0, 1)):
			st.set_normal(Vector3.BACK)
			st.set_color(col)
			_add_quad(
				st,
				Vector3(px, py, pz + 1.0),
				Vector3(px + 1.0, py + 1.0, pz + 1.0),
				Vector3(px + 1.0, py, pz + 1.0),
				Vector3(px, py, pz + 1.0)
			)

		# -Z Face
		if not active_voxels.has(pos + Vector3i(0, 0, -1)):
			st.set_normal(Vector3.FORWARD)
			st.set_color(col)
			_add_quad(
				st,
				Vector3(px + 1.0, py, pz),
				Vector3(px, py, pz),
				Vector3(px, py + 1.0, pz),
				Vector3(px + 1.0, py + 1.0, pz)
			)

	var mesh: ArrayMesh = st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, create_ghost_material())
	return mesh


## Adds two triangles forming a quad to the SurfaceTool using counter-clockwise vertex order.
static func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)

	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)
