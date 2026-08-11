extends Node
## Build subsystem ghost-preview test.
##
## Instances map.tscn + player.tscn + build.tscn, wires the BuildController's
## grid adapter to the map's VoxelGrid and its camera to the player's rig.
##
## Controls: B opens the build menu (ghost appears after picking a buildable).
## B again from placement returns to the menu; B from the menu exits build mode.
## Look at the terrain — the ghost follows the cursor and tints green (valid) /
## red (invalid). LMB places a block on a valid cell. Wheel rotates (furniture),
## R cycles the rotation axis. Movement/sprint/jump work as before.

func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)

	var map: Node = preload("res://subsystems/voxel/map.tscn").instantiate()
	add_child(map)

	# Player onto the terrain.
	var player: Node3D = preload("res://subsystems/player/player.tscn").instantiate()
	player.global_position = Vector3(0, 5, 0)
	map.add_child(player)

	# VoxelViewer so terrain streams + collision around the player.
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	player.add_child(viewer)

	# BuildController as a sibling of the player under MapRoot (ARCH line 67).
	var build: Node = preload("res://subsystems/build/build.tscn").instantiate()
	map.add_child(build)

	# Wire the adapter to the map's VoxelGrid and the controller's camera to the
	# player's rig. Deferred a frame so child _ready calls (rig camera build) have
	# run before we ask for the camera.
	await get_tree().process_frame
	var grid: VoxelGrid = map.get_grid()
	var adapter := VoxelGridAdapter.new()
	adapter.set_grid(grid)
	build.grid_adapter = adapter
	# Strategy goes through the adapter (ARCH flow trace: strategy -> adapter).
	var strategy := InstantPlacementStrategy.new()
	strategy.set_grid(adapter)
	build.strategy = strategy
	# FurnitureLayer parents spawned Node3Ds under the map's FurnitureContainer.
	var furniture := FurnitureLayer.new()
	furniture.set_container(map.get_furniture_container())
	build.furniture_layer = furniture
	build.set_camera(player.get_camera())
	# Exclude the player capsule so the camera ray hits terrain, not the player.
	build.add_exclude_body(player)

	# HUD hint.
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(10, 10)
	label.text = "B: open build menu -> pick a buildable -> ghost appears\nB again: back to menu (placing) or exit (in menu)\nLMB: place (blocks = voxel, pole/workbench = free-standing)\nRMB: remove\nWheel: rotate (visible on furniture) · R: cycle axis\nWASD/Shift/Space: move"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)
