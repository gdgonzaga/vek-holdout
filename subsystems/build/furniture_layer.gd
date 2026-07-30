class_name FurnitureLayer
extends RefCounted
## Free-standing furniture placement layer (ARCH "Build" subsystem).
##
## The sibling of VoxelGridAdapter for non-block buildables. Where the adapter
## writes unit-cube voxel blocks into the blocky grid, this layer spawns a
## free-standing Node3D (MeshInstance3D) under the world's FurnitureContainer.
## It never touches voxel_tool — it asks the VoxelGridAdapter whether candidate
## cells are free (is_valid_placement) and reads the def's mesh/dimensions.
##
## Footprint model (GDD §7.2/§7.4): a furniture item occupies a cell-box
## `dimensions` (x=width, y=height, z=depth) rooted at an anchor cell. Rotation
## (yaw_quarters 0..3) swaps x/z on the floor plane. Cells the box covers are
## registered so overlapping placement is rejected and removal by pointing at any
## occupied cell works.
##
## Runtime-wired (RefCounted can't be @export'd): the world/test constructs it,
## calls set_container(), and assigns it to BuildController.furniture_layer.

var _container: Node3D = null   # set via set_container(); where spawned nodes parent.
# anchor (Vector3i) -> MeshInstance3D. One entry per placed item.
var _node_by_anchor: Dictionary = {}
# occupied cell (Vector3i) -> anchor (Vector3i). Maps every covered cell back to the
# item that owns it, so removal by pointing at any covered cell resolves to the item.
var _anchor_by_cell: Dictionary = {}

const _new_furniture_template: PackedScene = preload("res://subsystems/build/new_furniture_template.tscn")


func set_container(container: Node3D) -> void:
	_container = container


## Cell offsets (relative to the anchor) the item covers, given its cell-box and
## a 0..3 yaw in 90-degree quarters. Yaw swaps width(x)/depth(z); height(y) is
## unaffected. For 1x1x1 the result is always just {0,0,0}.
static func footprint_cells(dimensions: Vector3i, yaw_quarters: int) -> Array[Vector3i]:
	var w: int = dimensions.x
	var d: int = dimensions.z
	# Odd yaw quarters (1,3) swap the floor-plane axes.
	if yaw_quarters % 2 != 0:
		var t := w
		w = d
		d = t
	var out: Array[Vector3i] = []
	out.resize(w * dimensions.y * d)
	var i := 0
	for y in dimensions.y:
		for x in w:
			for z in d:
				out[i] = Vector3i(x, y, z)
				i += 1
	return out


## Effective cell-box for a def, defaulting to 1x1x1 for non-FurnitureDef
## buildables (e.g. pole, a plain BuildableDef with just a mesh).
static func dimensions_of(def: BuildableDef) -> Vector3i:
	if def is FurnitureDef:
		return (def as FurnitureDef).dimensions
	return Vector3i.ONE


## World-space origin (Vector3) for a spawned item: footprint center on XZ,
## anchor Y up. Matches the voxel corner convention (cell (0,0,0) -> origin
## (0,0,0)) but centers multi-cell footprints. Note: source art meshes are
## real-world scaled, not unit-cube, so a per-def vertical offset may be needed
## later (see docs/HOWTO-transfer-animpic-models.md). None for now.
static func world_origin(anchor: Vector3i, dimensions: Vector3i, yaw_quarters: int) -> Vector3:
	var w: int = dimensions.x
	var d: int = dimensions.z
	if yaw_quarters % 2 != 0:
		var t := w
		w = d
		d = t
	# Center of the footprint on the floor plane; anchor cell origin on Y.
	var cx := float(anchor.x) + float(w) * 0.5
	var cz := float(anchor.z) + float(d) * 0.5
	return Vector3(cx, float(anchor.y), cz)


## Place `def` anchored at `anchor` with the given yaw. Returns the spawned node
## or null if unwired/overlapping. Emits EventBus.furniture_placed on success.
func spawn(def: BuildableDef, anchor: Vector3i, yaw_quarters: int) -> Node3D:
	if _container == null or def == null:
		return null
	var dims := dimensions_of(def)
	for off in footprint_cells(dims, yaw_quarters):
		if _anchor_by_cell.has(anchor + off):
			return null   # overlaps an existing item
	if def.mesh == null:
		push_error("FurnitureLayer: def '%s' has no mesh" % def.id)
		return null
	var node := _create_furniture_node(def, dims, yaw_quarters)
	node.name = "Furniture_%s" % def.id
	_container.add_child(node)
	node.global_position = world_origin(anchor, dims, yaw_quarters)
	_node_by_anchor[anchor] = node
	for off in footprint_cells(dims, yaw_quarters):
		_anchor_by_cell[anchor + off] = anchor
	EventBus.furniture_placed.emit(def.id, anchor)
	return node

func _create_furniture_node(def: BuildableDef, dims: Vector3i, yaw_quarters: int) -> Node3D:
	# Create a parent Node3D to hold mesh and collision.
	var root := _new_furniture_template.instantiate()
	var mesh_node: MeshInstance3D = root.find_child("Mesh")
	mesh_node.mesh = def.mesh
	
	mesh_node.create_trimesh_collision()
	
	var mesh_static_body: StaticBody3D = mesh_node.get_child(0) as StaticBody3D
	mesh_static_body.name = "WorldStaticBody"
	mesh_static_body.set_collision_layer_value(1, true)
	mesh_static_body.collision_mask = 0
	
	var build_collider := root.get_node("BuildBody/BuildCollider") as CollisionObject3D
	if build_collider != null:
		var box := BoxShape3D.new()
		box.size = Vector3(dims.x, dims.y, dims.z)
		build_collider.shape = box
		# Center the box in its footprint cells (root Y is the footprint bottom).
		build_collider.position = Vector3(0, dims.y * 0.5, 0)
		var build_body = root.get_node("BuildBody") as StaticBody3D
		build_body.set_collision_layer_value(3, true)
	
	# Apply rotation to root so both mesh and collision rotate together.
	if yaw_quarters != 0:
		root.rotate_y(float(yaw_quarters) * PI * 0.5)
	return root


## Remove the item covering `cell` (any covered cell resolves to its anchor).
## Returns true if something was removed. Emits EventBus.furniture_removed.
func remove_at(cell: Vector3i) -> bool:
	var anchor: Variant = _anchor_by_cell.get(cell)
	if anchor == null:
		return false
	var node: Node3D = _node_by_anchor.get(anchor)
	var def_id := node.name.substr("Furniture_".length()) if node != null else ""
	if node != null:
		node.queue_free()
	# Clear every cell this anchor covered (we don't know dims here, so sweep by value).
	var cells_to_clear: Array = []
	for c in _anchor_by_cell.keys():
		if _anchor_by_cell[c] == anchor:
			cells_to_clear.append(c)
	for c in cells_to_clear:
		_anchor_by_cell.erase(c)
	_node_by_anchor.erase(anchor)
	EventBus.furniture_removed.emit(def_id, anchor)
	return true


func has_at(cell: Vector3i) -> bool:
	return _anchor_by_cell.has(cell)
