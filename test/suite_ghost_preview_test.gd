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
