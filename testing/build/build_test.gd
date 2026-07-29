extends Node
## Build subsystem ghost-preview test.
##
## Instances world.tscn + player.tscn + build.tscn, wires the BuildController's
## grid adapter to the world's VoxelGrid and its camera to the player's rig.
##
## Controls: B toggles build mode (ghost appears/disappears). Look at the terrain
## — the ghost follows the cursor and tints green (valid) / red (invalid). LMB
## places a block on a valid cell (InstantPlacementStrategy -> VoxelGrid).
## Movement/sprint/jump work as before.

func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)

	var world: Node = preload("res://voxel/world.tscn").instantiate()
	add_child(world)

	# Player onto the terrain.
	var player: Node3D = preload("res://player/player.tscn").instantiate()
	player.global_position = Vector3(0, 5, 0)
	world.add_child(player)

	# VoxelViewer so terrain streams + collision around the player.
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	player.add_child(viewer)

	# BuildController as a sibling of the player under WorldRoot (ARCH line 67).
	var build: Node = preload("res://build/build.tscn").instantiate()
	world.add_child(build)

	# Wire the adapter to the world's VoxelGrid and the controller's camera to the
	# player's rig. Deferred a frame so child _ready calls (rig camera build) have
	# run before we ask for the camera.
	await get_tree().process_frame
	var grid: VoxelGrid = world.get_grid()
	var adapter := VoxelGridAdapter.new()
	adapter.set_grid(grid)
	build.grid_adapter = adapter
	# Strategy goes through the adapter (ARCH flow trace: strategy -> adapter).
	var strategy := InstantPlacementStrategy.new()
	strategy.set_grid(adapter)
	build.strategy = strategy
	build.set_camera(player.get_camera())
	# Exclude the player capsule so the camera ray hits terrain, not the player.
	build.add_exclude_body(player)

	# HUD hint.
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(10, 10)
	label.text = "B: open build menu -> pick a block -> ghost appears\nEsc: close menu without building\nWASD/Shift/Space: move"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)
