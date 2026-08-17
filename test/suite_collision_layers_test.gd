extends GdUnitTestSuite

## Dual-voxel collision-layer plan (docs/TODO.md D3, docs/architecture/
## voxel-world.md "Collision layers"): layer 1 World, 2 TerrainBlocky, 3
## TerrainSmooth (reserved), 4 Player, 5 Build, 6 Colonist. Scenes store
## layer/mask BIT VALUES — these assertions pin them so a future remap can't
## move a layer without its masks (F7: split layer/mask changes silently break
## body-vs-terrain collision). Scenes are instantiated WITHOUT entering the
## tree — only serialized property values are read, no _ready side effects.

func test_player_body_layers() -> void:
	var scene: PackedScene = load("res://subsystems/player/player.tscn")
	var body := auto_free(scene.instantiate()) as CharacterBody3D
	assert_int(body.collision_layer).is_equal(8)  # layer 4 Player
	assert_int(body.collision_mask).is_equal(7)   # World | TerrainBlocky | TerrainSmooth


func test_colonist_body_layers() -> void:
	var scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var body := auto_free(scene.instantiate()) as CharacterBody3D
	assert_int(body.collision_layer).is_equal(32)  # layer 6 Colonist
	assert_int(body.collision_mask).is_equal(7)


func test_build_interaction_templates_use_build_layer() -> void:
	var paths := [
		"res://subsystems/build/blueprint_template.tscn",
		"res://subsystems/build/new_furniture_template.tscn",
	]
	for path in paths:
		var scene: PackedScene = load(path)
		var root := auto_free(scene.instantiate()) as Node3D
		var build_body := root.get_node("BuildBody") as StaticBody3D
		assert_int(build_body.collision_layer).is_equal(16)  # layer 5 Build
		assert_int(build_body.collision_mask).is_equal(0)
