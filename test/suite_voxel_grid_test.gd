extends GdUnitTestSuite

## VoxelGrid collision ownership + height_at against a bare (generator-less)
## VoxelTerrain, so no block streaming is involved: the layer assignment is
## asserted straight out of _ready, and height_at is exercised with plain
## StaticBody stand-ins placed on the right/wrong collision layers.

## Grid + bare VoxelTerrain in the scene tree. The terrain child is parented
## BEFORE the grid enters the tree so the grid's @onready terrain_path resolves.
func _build_grid() -> VoxelGrid:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var grid: VoxelGrid = auto_free(VoxelGrid.new())
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
	assert_int(int(terrain.get("collision_layer"))).is_equal(VoxelGrid.TERRAIN_LAYER)
	assert_int(int(terrain.get("collision_mask"))).is_equal(VoxelGrid.TERRAIN_BODY_MASK)


## height_at answers the highest surface on the TerrainBlocky layer and reports
## its normal; World-layer statics on other columns are ignored by the mask.
func test_height_at_hits_blocky_layer_only() -> void:
	var grid := _build_grid()
	_add_box(grid.get_parent(), VoxelGrid.TERRAIN_LAYER, Vector3(0, 10, 0))
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
