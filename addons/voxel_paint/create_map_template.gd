@tool
extends EditorScript
## One-shot script: builds subsystems/maps/map_template.tscn — the blank authored
## map scene that VoxelPaint writes into.
##
## Run via editor File → Run (Ctrl+Shift+X) with any scene open. Produces:
##   MapTemplate (Node3D, world.gd, database_path exported)
##     VoxelGrid (Node, voxel_grid.gd)
##       VoxelTerrain (generator, mesher with library)
##     ColonistContainer, EnemyContainer, FurnitureContainer, EnvironmentContainer
##     BuildController (instanced from build.tscn)
##     SpawnPoints → PlayerSpawn (Marker3D)
##
## The baked mesher library (data/blocks/voxel_library.tres) is the decisive
## ingredient for in-editor rendering (Fact 5).
## The stream is wired by world.gd _ready() from the database_path export —
## no manual VoxelStreamSQLite sub-resource needed in the .tscn.

const OUTPUT_PATH := "res://data/maps/new_map/ : d:8map.tscn"
const LIBRARY_PATH := "res://data/blocks/voxel_library.tres"


func _run() -> void:
	var root := Node3D.new()
	root.name = "MapTemplate"
	root.set_script(load("res://subsystems/voxel/world.gd"))

	# -- VoxelGrid --
	var grid := Node.new()
	grid.name = "VoxelGrid"
	grid.set_script(load("res://subsystems/voxel/voxel_grid.gd"))
	root.add_child(grid)
	grid.owner = root

	# -- VoxelTerrain --
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"

	# Generator: flat ground (same as base world).
	var gen := VoxelGeneratorFlat.new()
	gen.channel = 0
	terrain.generator = gen

	# Mesher: blocky with baked library.
	var mesher := VoxelMesherBlocky.new()
	var baked_lib: Resource = load(LIBRARY_PATH)
	if baked_lib != null:
		mesher.library = baked_lib
		print("MapTemplate: mesher library set from ", LIBRARY_PATH)
	else:
		push_warning("MapTemplate: could not load ", LIBRARY_PATH, " — editor rendering will be blank")
	terrain.mesher = mesher

	# No stream set here — world.gd _ready() creates it from database_path export.

	grid.add_child(terrain)
	terrain.owner = root

	# -- Containers (match world.tscn structure) --
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
