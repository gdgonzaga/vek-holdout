extends GdUnitTestSuite

## VisualBounds (subsystems/core/visual_bounds.gd): center mass from visible meshes.

const EPSILON := Vector3(0.001, 0.001, 0.001)


func test_center_follows_offset_mesh() -> void:
	var root := _add_root(Vector3(2.0, 0.0, -3.0))
	_add_box(root, Vector3(0.0, 1.5, 0.0), Vector3.ONE)

	assert_vector(VisualBounds.world_center(root)).is_equal_approx(Vector3(2.0, 1.5, -3.0), EPSILON)


func test_center_spans_every_visible_mesh() -> void:
	var root := _add_root(Vector3.ZERO)
	_add_box(root, Vector3(0.0, 0.5, 0.0), Vector3.ONE)
	_add_box(root, Vector3(0.0, 3.5, 0.0), Vector3.ONE)

	assert_vector(VisualBounds.world_center(root)).is_equal_approx(Vector3(0.0, 2.0, 0.0), EPSILON)


func test_center_respects_root_rotation() -> void:
	var root := _add_root(Vector3.ZERO)
	root.rotate_y(PI * 0.5)
	_add_box(root, Vector3(1.0, 0.5, 0.0), Vector3.ONE)

	assert_vector(VisualBounds.world_center(root)).is_equal_approx(Vector3(0.0, 0.5, -1.0), EPSILON)


func test_hidden_meshes_are_ignored() -> void:
	var root := _add_root(Vector3.ZERO)
	_add_box(root, Vector3(0.0, 1.0, 0.0), Vector3.ONE)
	var hidden := _add_box(root, Vector3(0.0, 10.0, 0.0), Vector3.ONE)
	hidden.visible = false

	assert_vector(VisualBounds.world_center(root)).is_equal_approx(Vector3(0.0, 1.0, 0.0), EPSILON)


func test_no_meshes_falls_back_to_origin() -> void:
	var root := _add_root(Vector3(4.0, 1.0, 0.0))

	assert_vector(VisualBounds.world_center(root)).is_equal_approx(Vector3(4.0, 1.0, 0.0), EPSILON)


## Auxiliary: An empty Node3D in the test tree at the given position
func _add_root(pos: Vector3) -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	root.global_position = pos
	return root


## Auxiliary: A box mesh child at a local offset
func _add_box(parent: Node3D, local_pos: Vector3, size: Vector3) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = box
	parent.add_child(mesh_node)
	mesh_node.position = local_pos
	return mesh_node
