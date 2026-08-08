extends Node3D
## Interaction system test: walk up to a piece of furniture and press E to interact.
##
## Spawns map + player + VoxelViewer (same boilerplate as player_test.gd), then
## places the authored `data/furniture/test_block_furniture_with_interaction.tres`
## FurnitureDef via FurnitureLayer.spawn. Because that def carries action_options,
## spawn() auto-attaches an InteractionComponent (named exactly
## "InteractionComponent") copied from the def — no manual component wiring here.
## Pressing E opens the interaction UI; clicking a button runs the bound GameAction
## (prints "Action executed" to output).
##
## The every-frame crosshair check in Player should also print
## "[interact] targeting: <name>" when the furniture is under the crosshair.


func _ready() -> void:
	# -- Environment ----------------------------------------------------------
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)

	var map: Node3D = preload("res://subsystems/voxel/map.tscn").instantiate()
	add_child(map)

	var player: Node3D = preload("res://subsystems/player/player.tscn").instantiate()
	player.global_position = Vector3(0, 5, 0)
	map.add_child(player)

	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	player.add_child(viewer)

	# -- Interactable furniture ------------------------------------------------
	# Spawn the authored FurnitureDef via FurnitureLayer — the real placement path.
	# spawn() builds the Furniture node (mesh + collision) and, because the def has
	# non-empty action_options, attaches the InteractionComponent the player's
	# crosshair resolves. anchor (2,0,-1) + dims (2,1,2) centers it at world (3,0,0).
	var def := load("res://data/furniture/test_block_furniture_with_interaction.tres") as FurnitureDef
	var furniture := FurnitureLayer.new()
	furniture.set_container(map.get_furniture_container())
	var node: Node3D = furniture.spawn(def, Vector3i(2, 0, -1), 0)
	if node == null:
		push_error("interaction_test: furniture spawn failed (check def mesh / container wiring)")

	# -- HUD hint ---------------------------------------------------------------
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(10, 10)
	label.text = "E: interact with the Test block furniture\nLook at it: console prints targeting info\nSpawned via FurnitureLayer from test_block_furniture_with_interaction.tres"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)
