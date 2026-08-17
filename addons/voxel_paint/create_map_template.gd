@tool
extends EditorScript
## One-shot script: builds subsystems/maps/map_template.tscn — the blank authored
## map scene that VoxelPaint writes into.
##
## Run via editor File → Run (Ctrl+Shift+X) with any scene open. Produces:
##   MapTemplate (Node3D, map.gd)
##     BlockyGrid (Node, blocky_grid.gd)
##       VoxelTerrain (mesher with baked library, NO generator — structures only)
##     SmoothGrid (Node, smooth_grid.gd, default_material = ground.tres)
##       VoxelTerrain (Transvoxel mesher; generator from MapDef.terrain_gen at
##                     runtime — voxel_paint_plugin._create_map_def stamps the
##                     default deep-ground def into new maps; terrain.sqlite
##                     stamped per map)
##     ColonistContainer, EnemyContainer, FurnitureContainer, EnvironmentContainer
##     BuildController (instanced from build.tscn)
##     SpawnPoints → PlayerSpawn (Marker3D)
##
## The INITIAL TERRAIN is the smooth grid's: natural rolling ground, 50 m deep
## by default (data/terrain/default_ground.tres). The blocky terrain generates
## nothing — it exists for authored structures, which is why it keeps the
## mesher + baked library (data/blocks/voxel_library.tres): that library is the
## decisive ingredient for in-editor rendering of painted blocks (Fact 5).
## No VoxelStreamSQLite is baked in — per-map streams are injected at stamp
## time by voxel_paint_plugin._stamp_map_scene.

const OUTPUT_PATH := "res://subsystems/maps/map_template.tscn"
const LIBRARY_PATH := "res://data/blocks/voxel_library.tres"


func _run() -> void:
	var root := Node3D.new()
	root.name = "MapTemplate"
	root.set_script(load("res://subsystems/voxel/map.gd"))

	# -- BlockyGrid --
	# Structures only (dual-voxel D1): NO generator — the blocky layer starts as
	# air and holds exactly what gets painted into its per-map sqlite stream.
	# Initial terrain is the smooth grid's business (MapDef.terrain_gen). The
	# mesher + baked library stay: they are what renders painted blocks in the
	# editor viewport (Fact 5).
	var grid := Node.new()
	grid.name = "BlockyGrid"
	grid.set_script(load("res://subsystems/voxel/blocky_grid.gd"))
	root.add_child(grid)
	grid.owner = root

	# -- VoxelTerrain --
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"

	# Mesher: blocky with baked library.
	var mesher := VoxelMesherBlocky.new()
	var baked_lib: Resource = load(LIBRARY_PATH)
	if baked_lib != null:
		mesher.library = baked_lib
		print("MapTemplate: mesher library set from ", LIBRARY_PATH)
	else:
		push_warning("MapTemplate: could not load ", LIBRARY_PATH, " — editor rendering will be blank")
	terrain.mesher = mesher

	# No stream set here — per-map streams are injected at stamp time by
	# voxel_paint_plugin._stamp_map_scene.

	grid.add_child(terrain)
	terrain.owner = root

	# -- SmoothGrid (the initial terrain) --
	# Every stamped scene carries it; a MapDef without terrain_gen makes the node
	# free itself at _ready, so terrain-less maps are unaffected (dual-voxel
	# D1/D2). New maps get terrain_gen defaulted to the deep-ground def by
	# voxel_paint_plugin._create_map_def; no generator is baked here because
	# SmoothGrid._ready builds VoxelGeneratorNoise2D from the injected
	# TerrainGenDef — the editor viewport can't render Transvoxel terrain anyway
	# (F5/F8), so there is nothing to preview.
	var smooth := Node.new()
	smooth.name = "SmoothGrid"
	smooth.set_script(load("res://subsystems/voxel/smooth_grid.gd"))
	var ground_mat: Resource = load("res://data/terrain/materials/ground.tres")
	if ground_mat != null:
		smooth.set("default_material", ground_mat)
	root.add_child(smooth)
	smooth.owner = root

	var smooth_terrain := VoxelTerrain.new()
	smooth_terrain.name = "VoxelTerrain"
	smooth_terrain.mesher = VoxelMesherTransvoxel.new()
	smooth.add_child(smooth_terrain)
	smooth_terrain.owner = root

	# -- DirectionalLight3D (sun) --
	# Transform mirrors the light in the old hand-authored map scenes: a ~60°
	# sun angle with shadows on. Without a light the editor viewport and any
	# runtime scene stamped from this template render pitch black.
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.transform = Transform3D(
		Vector3(-0.8660254, -0.43301278, 0.25),
		Vector3(0, 0.49999997, 0.86602545),
		Vector3(-0.50000006, 0.75, -0.43301266),
		Vector3.ZERO
	)
	light.shadow_enabled = true
	root.add_child(light)
	light.owner = root

	# -- Containers (match map.tscn structure) --
	for container_name in ["ColonistContainer", "EnemyContainer", "FurnitureContainer", "EnvironmentContainer"]:
		var c := Node3D.new()
		c.name = container_name
		root.add_child(c)
		c.owner = root

	# -- BuildController (instance of build.tscn) --
	var build_scene: PackedScene = load("res://subsystems/build/build.tscn")
	if build_scene != null:
		var ctrl := build_scene.instantiate()
		ctrl.name = "BuildController"
		root.add_child(ctrl)
		ctrl.owner = root
	else:
		push_error("MapTemplate: could not load build.tscn")

	# -- SpawnPoints --
	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	root.add_child(spawns)
	spawns.owner = root

	var player_spawn := Marker3D.new()
	player_spawn.name = "PlayerSpawn"
	player_spawn.transform = Transform3D(
		Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
		Vector3(0, 5, 0)
	)
	spawns.add_child(player_spawn)
	player_spawn.owner = root

	# -- Save --
	var result := PackedScene.new()
	result.pack(root)
	var err := ResourceSaver.save(result, OUTPUT_PATH)
	if err == OK:
		print("MapTemplate: saved to ", OUTPUT_PATH)
		EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("MapTemplate: failed to save (error %d)" % err)

	root.queue_free()
