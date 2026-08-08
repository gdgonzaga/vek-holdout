extends Node3D
## Interaction system test: walk up to a cube and press E to interact.
##
## Spawns map + player + VoxelViewer (same boilerplate as player_test.gd) plus a
## simple StaticBody3D cube with an InteractionComponent. The component offers one
## ActionOption (PrintAction). Pressing E opens the interaction UI; clicking the
## button prints "Action executed" to output.
##
## The every-frame crosshair check in Player should also print
## "[interact] targeting: <name>" when the cube is under the crosshair.


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

	# -- Interactable cube -----------------------------------------------------
	var body := StaticBody3D.new()
	body.name = "TestCube"
	body.position = Vector3(3, 1.0, 0)
	map.add_child(body)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.6, 1.0)
	mat.emission_energy_multiplier = 0.3
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	body.add_child(col)

	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	interaction.display_name = "Test Cube"
	body.add_child(interaction)

	var option := ActionOption.new()
	option.action = load("res://data/actions/print_action.tres")
	interaction.action_options = [option]

	# -- HUD hint ---------------------------------------------------------------
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(10, 10)
	label.text = "E: interact with the blue cube\nLook at the cube: console prints targeting info"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)
