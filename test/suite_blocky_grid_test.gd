extends GdUnitTestSuite

## BlockyGrid collision ownership + height_at against a bare (generator-less)
## VoxelTerrain, so no block streaming is involved: the layer assignment is
## asserted straight out of _ready, and height_at is exercised with plain
## StaticBody stand-ins placed on the right/wrong collision layers.

const Fixtures := preload("res://test/helpers/rotation_fixtures.gd")

## Grid + bare VoxelTerrain in the scene tree. The terrain child is parented
## BEFORE the grid enters the tree so the grid's @onready terrain_path resolves.
func _build_grid() -> BlockyGrid:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var grid: BlockyGrid = auto_free(BlockyGrid.new())
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	grid.add_child(terrain)
	root.add_child(grid)
	return grid


## Axis-aligned box body on the given layer bit value, colliding with nothing.
func _add_box(parent: Node3D, layer_value: int, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer_value
	body.collision_mask = 0
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	body.add_child(shape)
	var box := BoxShape3D.new()
	box.size = Vector3(4, 1, 4)
	shape.shape = box
	body.position = center


func _run_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## _ready assigns the terrain's exclusive layer (2) and the body mask F7
## requires (Player | Colonist) — read back via get() because collision_layer
## on VoxelTerrain is a GDExtension property.
func test_terrain_owns_blocky_layer() -> void:
	var grid := _build_grid()
	var terrain := grid.get_terrain()
	assert_int(int(terrain.get("collision_layer"))).is_equal(BlockyGrid.TERRAIN_LAYER)
	assert_int(int(terrain.get("collision_mask"))).is_equal(BlockyGrid.TERRAIN_BODY_MASK)


## height_at answers the highest surface on the TerrainBlocky layer and reports
## its normal; World-layer statics on other columns are ignored by the mask.
func test_height_at_hits_blocky_layer_only() -> void:
	var grid := _build_grid()
	_add_box(grid.get_parent(), BlockyGrid.TERRAIN_LAYER, Vector3(0, 10, 0))
	_add_box(grid.get_parent(), 1, Vector3(20, 30, 20))  # World static — ignored
	await _run_frames(2)
	var normals: Array = []
	var height := grid.height_at(0, 0, normals)
	assert_float(height).is_equal_approx(10.5, 0.01)
	assert_array(normals).has_size(1)
	assert_that(normals[0]).is_equal(Vector3.UP)


## No TerrainBlocky surface in the column (only a World-layer body) → NAN,
## the documented "no ground here" answer.
func test_height_at_nan_without_blocky_ground() -> void:
	var grid := _build_grid()
	_add_box(grid.get_parent(), 1, Vector3(0, 10, 0))  # wrong layer only
	await _run_frames(2)
	assert_bool(is_nan(grid.height_at(0, 0))).is_true()


## Stored voxel values must be plain VoxelBlockyLibrary model indices — the
## mesher renders value N as library model N, so anything else (e.g. packed
## type+rotation bits) persists to the sqlite stream but never meshes or
## collides. Regression for invisible stamped structures (2026-08-20).
func test_set_block_at_stores_renderable_library_index() -> void:
	var grid := _build_grid()
	var lib: BlockLibrary = auto_free(BlockLibrary.new())
	var base_indices := lib.get_base_indices()
	assert_bool(base_indices.is_empty()).is_false()
	var target_index: int = base_indices[0]
	var target_id := lib.get_id(target_index)
	assert_str(target_id).is_not_empty()

	# Writes only land where blocks are streamed in (F3) — a generator-less,
	# stream-less terrain never materializes editable blocks, so attach a
	# scratch sqlite stream + a viewer at the target cell.
	DirAccess.make_dir_recursive_absolute("user://tmp_bg_test")
	DirAccess.remove_absolute("user://tmp_bg_test/map.sqlite")
	var stream := VoxelStreamSQLite.new()
	stream.database_path = "user://tmp_bg_test/map.sqlite"
	grid.get_terrain().stream = stream
	var viewer := VoxelViewer.new()
	viewer.position = Vector3(3.5, 4.5, 3.5)
	viewer.requires_visuals = false
	viewer.requires_collisions = false
	grid.get_parent().add_child(viewer)
	for _i in range(20):
		await get_tree().physics_frame

	grid.set_block_at(Vector3i(3, 4, 3), target_id)
	for _i in range(60):
		if grid.get_raw_voxel(Vector3i(3, 4, 3)) != 0:
			break
		await get_tree().physics_frame

	var raw := grid.get_raw_voxel(Vector3i(3, 4, 3))
	assert_int(raw).is_equal(target_index)
	assert_int(raw).is_less(lib.get_voxel_library().get_models().size())
	assert_str(grid.get_block_at(Vector3i(3, 4, 3))).is_equal(target_id)
	assert_int(grid.get_block_rotation(Vector3i(3, 4, 3))).is_equal(0)


## Grid fixture mount: overrides the library factory so rotation variants can
## be exercised without touching data/blocks/ (whose order is save-stable).
class FixtureBlockyGrid extends BlockyGrid:
	var fixture_library: BlockLibrary = null

	func _make_library() -> BlockLibrary:
		return fixture_library


## set_block with a rotation stores the baked VARIANT index (renderable,
## within library bounds); type/rotation/id read back decomposed. Full
## rotation round-trip through the real grid.
func test_set_block_with_rotation_roundtrips_through_variant_index() -> void:
	var lib := BlockLibrary.new(Fixtures.make_block_dir("grid_rt"))
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var grid: FixtureBlockyGrid = auto_free(FixtureBlockyGrid.new())
	grid.fixture_library = lib
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	grid.add_child(terrain)
	root.add_child(grid)

	# F3: writes need a streamed terrain + viewer to land.
	DirAccess.make_dir_recursive_absolute("user://tmp_bg_test_rot")
	DirAccess.remove_absolute("user://tmp_bg_test_rot/map.sqlite")
	var stream := VoxelStreamSQLite.new()
	stream.database_path = "user://tmp_bg_test_rot/map.sqlite"
	grid.get_terrain().stream = stream
	var viewer := VoxelViewer.new()
	viewer.position = Vector3(3.5, 4.5, 3.5)
	viewer.requires_visuals = false
	viewer.requires_collisions = false
	root.add_child(viewer)
	for _i in range(20):
		await get_tree().physics_frame

	var yaw_base: int = grid.get_library().get_index("yawwedge")
	var target := Vector3i(3, 4, 3)
	grid.set_block(target, yaw_base, 22)  # 90-degree yaw
	for _i in range(60):
		if grid.get_raw_voxel(target) != 0:
			break
		await get_tree().physics_frame

	var raw := grid.get_raw_voxel(target)
	assert_int(raw).is_not_equal(yaw_base)
	assert_int(raw).is_less(grid.get_library().get_voxel_library().get_models().size())
	assert_int(grid.get_block_type(target)).is_equal(yaw_base)
	assert_int(grid.get_block_rotation(target)).is_equal(22)
	assert_str(grid.get_block_at(target)).is_equal("yawwedge")
	assert_bool(grid.get_block_basis(target).is_equal_approx(Basis(Vector3.UP, PI / 2.0))).is_true()

	# Rotation 0 keeps storing the plain base index.
	grid.set_block(target, yaw_base, 0)
	assert_int(grid.get_raw_voxel(target)).is_equal(yaw_base)
