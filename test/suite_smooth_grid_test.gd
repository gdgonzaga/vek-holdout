extends GdUnitTestSuite

## SmoothGrid ownership + queries against a bare (generator-fed but
## stream-less) world, mirroring suite_blocky_grid_test.gd's stand-in idiom:
## layer assignment straight out of _ready, height/ray queries exercised with
## StaticBody stand-ins on the right/wrong collision layers, and the
## raycast_to_voxel `surface` contract (BlockyGrid side) pinned — the smooth-hit
## shape (pre-derived placement cell, zero normal) is what BuildController's
## _placement_cell branches on. Also pins the generator-mode branch: noise defs
## (every existing map) vs heightmap defs (external-tool authoring).

## Grid + bare VoxelTerrain in the tree. The terrain child is parented BEFORE
## the grid enters the tree so the grid's @onready terrain_path resolves.
func _build_grid(with_gen: bool) -> SmoothGrid:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var grid: SmoothGrid = auto_free(SmoothGrid.new())
	if with_gen:
		var gen := TerrainGenDef.new()
		gen.noise_seed = 7
		grid.terrain_gen = gen
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


## No terrain_gen = "this map has no smooth terrain": the node frees itself so
## Map.get_smooth_grid() consumers see nothing (docs/TODO.md D2 null rule).
func test_frees_itself_without_terrain_gen() -> void:
	var grid := _build_grid(false)
	assert_int(grid.get_child_count()).is_equal(1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(grid)).is_false()


## _ready assigns the smooth terrain's exclusive layer (3, value 4) and the F7
## body mask — read back via get() because collision_layer on VoxelTerrain is a
## GDExtension property.
func test_terrain_owns_smooth_layer() -> void:
	var grid := _build_grid(true)
	var terrain := grid.get_terrain()
	assert_int(int(terrain.get("collision_layer"))).is_equal(SmoothGrid.TERRAIN_LAYER_VALUE)
	assert_int(int(terrain.get("collision_mask"))).is_equal(SmoothGrid.TERRAIN_BODY_MASK)


## height_at answers only the TerrainSmooth layer: a layer-4 stand-in hits, a
## blocky-layer (2) stand-in in another column is invisible to it.
func test_height_at_hits_smooth_layer_only() -> void:
	var grid := _build_grid(true)
	_add_box(grid.get_parent(), 4, Vector3(0, 10, 0))
	_add_box(grid.get_parent(), 2, Vector3(20, 30, 20))  # blocky stand-in — ignored
	await _run_frames(2)
	var normals: Array = []
	var height := grid.height_at(0, 0, normals)
	assert_float(height).is_equal_approx(10.5, 0.01)
	assert_array(normals).has_size(1)
	assert_that(normals[0]).is_equal(Vector3.UP)
	assert_bool(is_nan(grid.height_at(20, 20))).is_true()


## raycast_to_surface masks to TerrainSmooth and keeps float values: a sloped
## stand-in (rotated box) must return its true normal, not a rounded one.
func test_raycast_to_surface_returns_float_normal() -> void:
	var grid := _build_grid(true)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	grid.get_parent().add_child(body)
	var shape := CollisionShape3D.new()
	body.add_child(shape)
	var box := BoxShape3D.new()
	box.size = Vector3(4, 1, 4)
	shape.shape = box
	body.position = Vector3(0, 10, 0)
	body.rotation_degrees = Vector3(0, 0, 30)
	await _run_frames(2)
	var hit := grid.raycast_to_surface(Vector3(0, 60, 0), Vector3.DOWN, 128.0)
	assert_bool(hit["hit"]).is_true()
	var n: Vector3 = hit["normal"]
	# 30° tilt: |n.y| = cos(30°) — impossible for any axis-aligned int normal.
	assert_float(absf(n.y)).is_equal_approx(0.866, 0.01)


## The raycast_to_voxel surface contract, BlockyGrid side (StaticBody stand-ins
## on each layer): blocky/body hits resolve as before and carry their tag; a
## smooth hit returns the PRE-DERIVED placement cell with a zero normal (D3).
func test_raycast_to_voxel_surface_tags() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var grid: BlockyGrid = auto_free(BlockyGrid.new())
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	grid.add_child(terrain)
	root.add_child(grid)

	# Three stand-ins on distinct layers, spread along X so one horizontal ray
	# can't chain-hit them; query each with its own downward ray.
	_add_box(root, 2, Vector3(0, 10, 0))    # blocky layer
	_add_box(root, 1, Vector3(20, 10, 0))   # World static
	_add_box(root, 4, Vector3(40, 10, 0))   # smooth layer
	await _run_frames(2)

	var hit_blocky := grid.raycast_to_voxel(Vector3(0, 60, 0), Vector3.DOWN, 128.0)
	assert_bool(hit_blocky["hit"]).is_true()
	assert_str(hit_blocky["surface"]).is_equal("blocky")
	assert_that(hit_blocky["position"]).is_equal(Vector3i(0, 10, 0))
	assert_that(hit_blocky["normal"]).is_equal(Vector3i(0, 1, 0))

	var hit_body := grid.raycast_to_voxel(Vector3(20, 60, 0), Vector3.DOWN, 128.0)
	assert_str(hit_body["surface"]).is_equal("body")
	assert_that(hit_body["position"]).is_equal(Vector3i(20, 10, 0))

	# Smooth stand-in top at y=10.5, normal UP: placement cell = floor(10.5+0.5)
	# = 11 — the empty cell above the surface, already derived.
	var hit_smooth := grid.raycast_to_voxel(Vector3(40, 60, 0), Vector3.DOWN, 128.0)
	assert_str(hit_smooth["surface"]).is_equal("smooth")
	assert_that(hit_smooth["position"]).is_equal(Vector3i(40, 11, 0))
	assert_that(hit_smooth["normal"]).is_equal(Vector3i.ZERO)
	var smooth_point: Vector3 = hit_smooth["smooth_point"]
	assert_float(smooth_point.y).is_equal_approx(10.5, 0.01)


## BuildController._placement_cell: blocky/body hits offset by the face normal;
## smooth hits are taken as-is (pre-derived cell, D3).
func test_placement_cell_branches_on_surface() -> void:
	var ctrl: BuildController = auto_free(BuildController.new())
	var blocky_cell := ctrl._placement_cell({
		"position": Vector3i(3, 1, 2), "normal": Vector3i(0, 1, 0), "hit": true, "surface": "blocky",
	})
	assert_that(blocky_cell).is_equal(Vector3i(3, 2, 2))
	var smooth_cell := ctrl._placement_cell({
		"position": Vector3i(5, 11, 0), "normal": Vector3i.ZERO, "hit": true, "surface": "smooth",
	})
	assert_that(smooth_cell).is_equal(Vector3i(5, 11, 0))
	# Legacy dicts without a surface tag (old callers/doubles) keep blocky math.
	var legacy_cell := ctrl._placement_cell({
		"position": Vector3i(0, 0, 0), "normal": Vector3i(0, 1, 0), "hit": true,
	})
	assert_that(legacy_cell).is_equal(Vector3i(0, 1, 0))


## MapWiring.smooth_stand_hint over a real SmoothGrid: the hint derives stand
## cells from the same heightfield walkability reads, and answers MAX where
## the terrain doesn't reach (the finder's flat-assumption fallback).
func test_smooth_stand_hint_over_real_grid() -> void:
	var grid := _build_grid(true)
	_add_box(grid.get_parent(), 4, Vector3(0, 10, 0))
	await _run_frames(2)
	var hint := MapWiring.smooth_stand_hint(grid)
	# Box top at 10.5 -> stand cell floor(10.5) = 10; column keyed by floor(x).
	assert_that(hint.call(0.0, 0.0)).is_equal(Vector3i(0, 10, 0))
	assert_that(hint.call(50.0, 50.0)).is_equal(Vector3i.MAX)


## Map.ground_height_at (dual-voxel Phase 3 spawns): one downward ray over
## both terrain layers — the highest surface wins, non-terrain layers (World
## furniture statics, bodies) never answer.
func test_map_ground_height_takes_highest_terrain() -> void:
	var map: Map = auto_free(Map.new())
	var grid: BlockyGrid = auto_free(BlockyGrid.new())
	grid.name = "BlockyGrid"
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	grid.add_child(terrain)
	map.add_child(grid)
	for child_name in ["ColonistContainer", "EnemyContainer", "FurnitureContainer"]:
		var slot := Node3D.new()
		slot.name = child_name
		map.add_child(slot)
	add_child(map)

	# Same column: blocky surface at 10.5, smooth hill top at 20.5, a World
	# static even higher that must be invisible to the terrain-only mask.
	_add_box(map, 2, Vector3(0, 10, 0))
	_add_box(map, 4, Vector3(0, 20, 0))
	_add_box(map, 1, Vector3(0, 30, 0))
	await _run_frames(2)
	assert_float(map.ground_height_at(0, 0)).is_equal_approx(20.5, 0.01)
	# Blocky wins where no smooth hill covers the column.
	_add_box(map, 2, Vector3(60, 10, 0))
	await _run_frames(2)
	assert_float(map.ground_height_at(60, 0)).is_equal_approx(10.5, 0.01)
	assert_bool(is_nan(map.ground_height_at(-60, 0))).is_true()


## VoxelGridAdapter.is_ground_supported over a real SmoothGrid (blocky half is
## bare terrain = air everywhere): support within one cell of the surface,
## none above it, none where the terrain doesn't reach.
func test_adapter_is_ground_supported_on_smooth() -> void:
	var grid := _build_grid(true)
	_add_box(grid.get_parent(), 4, Vector3(0, 10, 0))
	await _run_frames(2)
	# In-tree blocky half (air everywhere — no generator, no stream) so the
	# adapter's blocky branch reads a real, live grid.
	var blocky: BlockyGrid = auto_free(BlockyGrid.new())
	var blocky_terrain := VoxelTerrain.new()
	blocky_terrain.name = "VoxelTerrain"
	blocky.add_child(blocky_terrain)
	grid.get_parent().add_child(blocky)
	var adapter := VoxelGridAdapter.new()
	adapter.set_grid(blocky)
	adapter.set_smooth_grid(grid)
	# Box top at 10.5: the smooth-hit placement cell floor(10.5 + 0.5) = 11 and
	# the cell the surface passes through stay within the one-cell window.
	assert_bool(adapter.is_ground_supported(Vector3i(0, 11, 0))).is_true()
	assert_bool(adapter.is_ground_supported(Vector3i(0, 10, 0))).is_true()
	# Two cells above the surface: floating — rejected.
	assert_bool(adapter.is_ground_supported(Vector3i(0, 13, 0))).is_false()
	# Column the smooth terrain doesn't reach, no blocky voxel below: rejected.
	assert_bool(adapter.is_ground_supported(Vector3i(50, 11, 0))).is_false()

	# Underground cavity floor under the surface at Y=10.5:
	# Add a lower box with top at Y=2.5. Top-down height_at(0, 0) still reports 10.5,
	# but the lower cavity floor at Y=2.5 supports cell at Y=3.
	_add_box(grid.get_parent(), 4, Vector3(0, 2, 0))
	await _run_frames(2)
	assert_bool(adapter.is_ground_supported(Vector3i(0, 3, 0))).is_true()
	assert_bool(adapter.is_ground_supported(Vector3i(0, 2, 0))).is_true()
	# Midair in the cavity between Y=3 and Y=10: rejected.
	assert_bool(adapter.is_ground_supported(Vector3i(0, 6, 0))).is_false()


## Grid whose def drives generation from a heightmap: a synthetic L8 image
## wrapped in an ImageTexture — the same shape the map editor embeds.
func _build_heightmap_grid() -> SmoothGrid:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var grid: SmoothGrid = auto_free(SmoothGrid.new())
	var gen := TerrainGenDef.new()
	# Non-default span so the generator wiring is observable, not coincidental.
	gen.height_start = -6.0
	gen.height_range = 20.0
	var img := Image.create(16, 16, false, Image.FORMAT_L8)
	img.fill(Color(0.5, 0.5, 0.5))
	gen.heightmap = ImageTexture.create_from_image(img)
	grid.terrain_gen = gen
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	grid.add_child(terrain)
	root.add_child(grid)
	return grid


## Heightmap-driven defs build a VoxelGeneratorImage wired from the def's span
## and pixels. Property names were probed in this addon build
## (tmp/heightmap_gen_probe.gd) — a mismatch must fail here loudly, not degrade
## the terrain silently.
func test_heightmap_def_builds_image_generator() -> void:
	var grid := _build_heightmap_grid()
	var generator = grid.get_terrain().get("generator")
	assert_bool(generator is VoxelGeneratorImage).is_true()
	assert_float(float(generator.get("height_start"))).is_equal_approx(-6.0, 0.001)
	assert_float(float(generator.get("height_range"))).is_equal_approx(20.0, 0.001)
	assert_that(generator.get("offset")).is_equal(Vector2i(8, 8))
	var image: Image = generator.get("image")
	assert_that(image).is_not_null()
	assert_that(image.get_size()).is_equal(Vector2i(16, 16))


## Noise regression: a def without a heightmap keeps the Noise2D pipeline every
## existing map was authored against.
func test_noise_def_still_builds_noise_generator() -> void:
	var grid := _build_grid(true)
	var generator = grid.get_terrain().get("generator")
	assert_bool(generator is VoxelGeneratorNoise2D).is_true()


## _prepare_heightmap_image: whatever the source texture's format, the generator
## receives Image.FORMAT_RF (snapped to whole-meter physical heights).
func test_prepare_heightmap_image_normalizes_and_snaps() -> void:
	var def := TerrainGenDef.new()
	def.height_start = 0.0
	def.height_range = 100.0
	var rgb := Image.create(2, 2, false, Image.FORMAT_RGB8)
	# Value of 0.052 * 100 = 5.2 meters -> snaps to 5.0 meters -> 0.05 pixel value
	rgb.fill(Color(0.052, 0.052, 0.052))
	def.heightmap = ImageTexture.create_from_image(rgb)
	
	var prepared: Image = SmoothGrid._prepare_heightmap_image(def)
	assert_that(prepared).is_not_null()
	assert_int(prepared.get_format()).is_equal(Image.FORMAT_RF)
	assert_float(prepared.get_pixel(0, 0).r).is_equal_approx(0.05, 0.001)


## _prepare_heightmap_image: null def or null heightmap stays null so
## the caller falls back to the noise path.
func test_prepare_heightmap_image_null_and_passthrough() -> void:
	assert_that(SmoothGrid._prepare_heightmap_image(null)).is_null()
	var def := TerrainGenDef.new()
	assert_that(SmoothGrid._prepare_heightmap_image(def)).is_null()
