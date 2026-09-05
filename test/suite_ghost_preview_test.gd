class_name SuiteGhostPreviewTest
extends GdUnitTestSuite

const GhostPreviewClass = preload("res://subsystems/core/ghost_preview.gd")

func test_ghost_preview_preserves_custom_mesh() -> void:
	var ghost: GhostPreview = auto_free(GhostPreviewClass.new())
	add_child(ghost)
	var custom_mesh := ArrayMesh.new()
	ghost.mesh = custom_mesh
	ghost.show_at(Vector3(1, 2, 3), true)
	assert_object(ghost.mesh).is_equal(custom_mesh)

func test_ghost_preview_falls_back_to_default_mesh_when_null() -> void:
	var ghost: GhostPreview = auto_free(GhostPreviewClass.new())
	add_child(ghost)
	ghost.mesh = null
	ghost.show_at(Vector3(1, 2, 3), true)
	assert_object(ghost.mesh).is_not_null()

func test_build_controller_sets_ghost_mesh_for_stairs() -> void:
	var ctrl: BuildController = auto_free(preload("res://subsystems/build/build.tscn").instantiate())
	add_child(ctrl)
	ctrl._on_buildable_selected("wood_stairs")
	var def := BuildLibrary.get_def("wood_stairs")
	assert_object(def).is_not_null()
	assert_object(def.mesh).is_not_null()
	assert_object(ctrl._ghost.mesh).is_equal(def.mesh)
func test_ghost_preview_shows_scene_hologram() -> void:
	var ghost: GhostPreview = auto_free(GhostPreviewClass.new())
	add_child(ghost)

	var scene_root := Node3D.new()
	scene_root.name = "SceneRoot"
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	scene_root.add_child(mi)
	mi.owner = scene_root

	var packed := PackedScene.new()
	packed.pack(scene_root)
	scene_root.free()

	ghost.show_scene_at(Vector3(5, 1, 5), packed, 90.0, true)
	assert_object(ghost.mesh).is_null()
	assert_vector(ghost.global_position).is_equal(Vector3(5, 1, 5))
	assert_float(ghost.rotation_degrees.y).is_equal(90.0)
	assert_bool(ghost.visible).is_true()

