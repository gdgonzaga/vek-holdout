class_name VisualBounds
extends RefCounted

## Pure geometry helpers over a node's visible meshes (ARCH "Subsystem:
## Colonists" flow "Look at Work and Combat Targets").
##
## Used to find a target's center mass. Collision shapes are not used: furniture
## lists its mesh's trimesh collider (origin at floor level) ahead of the
## footprint box, so "first collision shape" lands on the floor, not the center.


# =================
# Primary Functions
# =================

## World-space center of the merged bounds of every visible MeshInstance3D in
## root's subtree (root included). Returns root's origin when nothing is visible.
static func world_center(root: Node3D) -> Vector3:
	# 1. Mesh Collection: Gather the world-space bounds of each visible mesh under root.
	var boxes := _visible_mesh_world_aabbs(root)
	if boxes.is_empty():
		return root.global_position

	# 2. Bounds Merge: Combine them so multi-part targets resolve to one center.
	return _merge_aabbs(boxes).get_center()


# ===================
# Auxiliary Functions
# ===================

## Auxiliary: World AABBs of visible, mesh-bearing MeshInstance3Ds in root's subtree
static func _visible_mesh_world_aabbs(root: Node3D) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		var mesh_node := node as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null and mesh_node.is_visible_in_tree():
			boxes.append(mesh_node.global_transform * mesh_node.get_aabb())
	return boxes


## Auxiliary: Smallest AABB enclosing every box (boxes must not be empty)
static func _merge_aabbs(boxes: Array[AABB]) -> AABB:
	var merged := boxes[0]
	for box in boxes:
		merged = merged.merge(box)
	return merged
