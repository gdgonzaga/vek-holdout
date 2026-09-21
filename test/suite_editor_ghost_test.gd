class_name SuiteEditorGhostTest
extends GdUnitTestSuite
## Tests for EditorGhost: primitive and custom mesh previewing, sculpt sphere scaling,
## rotation axis orientation and coloring, and visibility management.


func test_show_sphere_radius_and_scale_invariant() -> void:
	var ghost: EditorGhost = auto_free(EditorGhost.new())
	add_child(ghost)
	ghost.setup()

	ghost.show_sphere(Vector3(1, 2, 3), 2.5, false)
	assert_bool(ghost.mesh_instance.visible).is_true()
	assert_bool(ghost.mesh_instance.mesh is SphereMesh).is_true()

	var sphere := ghost.mesh_instance.mesh as SphereMesh
	assert_float(sphere.radius * ghost.mesh_instance.scale.x).is_equal_approx(2.5, 0.001)
	assert_float(sphere.height * ghost.mesh_instance.scale.y).is_equal_approx(5.0, 0.001)
	assert_vector(ghost.mesh_instance.global_position).is_equal(Vector3(1, 2, 3))
	assert_that(ghost.material.albedo_color).is_equal(EditorGhost.COLOR_TERRAIN_PAINT)

	ghost.show_sphere(Vector3(1, 2, 3), 2.5, true)
	assert_that(ghost.material.albedo_color).is_equal(EditorGhost.COLOR_TERRAIN_ERASE)


func test_show_box_mesh_and_colors() -> void:
	var ghost: EditorGhost = auto_free(EditorGhost.new())
	add_child(ghost)
	ghost.setup()

	var basis := Basis.IDENTITY.scaled(Vector3(3, 3, 3))
	ghost.show_box(Vector3(10, 5, 20), basis, false)

	assert_bool(ghost.mesh_instance.visible).is_true()
	assert_object(ghost.mesh_instance.mesh).is_equal(ghost.box_mesh)
	assert_vector(ghost.mesh_instance.global_position).is_equal(Vector3(10, 5, 20))
	assert_vector(ghost.mesh_instance.scale).is_equal(Vector3(3, 3, 3))
	assert_that(ghost.material.albedo_color).is_equal(EditorGhost.COLOR_BLOCK_PAINT)

	ghost.show_box(Vector3(10, 5, 20), basis, true)
	assert_that(ghost.material.albedo_color).is_equal(EditorGhost.COLOR_BLOCK_ERASE)


func test_hide_all_hides_both_nodes() -> void:
	var ghost: EditorGhost = auto_free(EditorGhost.new())
	add_child(ghost)
	ghost.setup()

	ghost.show_box(Vector3.ZERO, Basis.IDENTITY, false)
	ghost.show_axis(Vector3.ZERO, 0)
	assert_bool(ghost.mesh_instance.visible).is_true()
	assert_bool(ghost.axis_line.visible).is_true()

	ghost.hide_all()
	assert_bool(ghost.mesh_instance.visible).is_false()
	assert_bool(ghost.axis_line.visible).is_false()


func test_show_axis_colors_by_axis() -> void:
	var ghost: EditorGhost = auto_free(EditorGhost.new())
	add_child(ghost)
	ghost.setup()

	# Y axis (0): Green
	ghost.show_axis(Vector3(2, 0, 2), 0)
	assert_bool(ghost.axis_line.visible).is_true()
	assert_vector(ghost.axis_line.global_position).is_equal(Vector3(2, 0, 2))
	assert_that(ghost.axis_line_mat.albedo_color).is_equal(Color(0.2, 1.0, 0.2, 0.95))

	# X axis (1): Red
	ghost.show_axis(Vector3(2, 0, 2), 1)
	assert_that(ghost.axis_line_mat.albedo_color).is_equal(Color(1.0, 0.2, 0.2, 0.95))

	# Z axis (2): Blue
	ghost.show_axis(Vector3(2, 0, 2), 2)
	assert_that(ghost.axis_line_mat.albedo_color).is_equal(Color(0.2, 0.6, 1.0, 0.95))

	ghost.hide_axis()
	assert_bool(ghost.axis_line.visible).is_false()


func test_show_custom_mesh_and_furniture() -> void:
	var ghost: EditorGhost = auto_free(EditorGhost.new())
	add_child(ghost)
	ghost.setup()

	var custom_mesh := BoxMesh.new()
	ghost.show_custom_mesh(custom_mesh, Vector3(5, 5, 5), Basis.IDENTITY, false)
	assert_bool(ghost.mesh_instance.visible).is_true()
	assert_object(ghost.mesh_instance.mesh).is_equal(custom_mesh)
	assert_vector(ghost.mesh_instance.global_position).is_equal(Vector3(5, 5, 5))
	assert_that(ghost.material.albedo_color).is_equal(EditorGhost.COLOR_BLOCK_PAINT)

	var furn_mesh := CylinderMesh.new()
	ghost.show_furniture(furn_mesh, Vector3(10, 0, 10), 1, false)
	assert_object(ghost.mesh_instance.mesh).is_equal(furn_mesh)
	assert_vector(ghost.mesh_instance.global_position).is_equal(Vector3(10, 0, 10))
	assert_float(ghost.mesh_instance.global_rotation.y).is_equal_approx(deg_to_rad(90), 0.001)
	assert_that(ghost.material.albedo_color).is_equal(EditorGhost.COLOR_FURNITURE_PAINT)


func test_show_capsule() -> void:
	var ghost: EditorGhost = auto_free(EditorGhost.new())
	add_child(ghost)
	ghost.setup()

	ghost.show_capsule(Vector3(3, 0, 3), Color(0.2, 1.0, 0.2, 0.5))
	assert_bool(ghost.mesh_instance.visible).is_true()
	assert_bool(ghost.mesh_instance.mesh is CapsuleMesh).is_true()
	assert_vector(ghost.mesh_instance.global_position).is_equal(Vector3(3, 0.9, 3))
	assert_that(ghost.material.albedo_color).is_equal(Color(0.2, 1.0, 0.2, 0.5))
