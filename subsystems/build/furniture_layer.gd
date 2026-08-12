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
## Runtime-wired (RefCounted can't be @export'd): the map/test constructs it,
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

func _create_furniture_node(def: BuildableDef, dims: Vector3i, yaw_quarters: int) -> Furniture:
	# Create a parent Node3D to hold mesh and collision.
	var root: Furniture = _new_furniture_template.instantiate()
	root.def_id = def.id
	root.def = def
	var mesh_node: MeshInstance3D = root.find_child("Mesh")
	mesh_node.mesh = def.mesh
	# Build the albedo material from def.texture. Skipped when null so meshes that
	# carry their own embedded material (e.g. OBJ with .mtl) keep it; without this,
	# material-less meshes (e.g. extracted GLTF) render with Godot's white default.
	# NOTE: do not call a build_material() helper on the def from a @tool context —
	# editor tool-script instances load stale compiled bytecode after a script edit
	# (has_method returns true but the call throws). Access `texture` directly.
	if def.texture != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = def.texture
		mesh_node.material_override = mat

	mesh_node.create_trimesh_collision()
	
	var mesh_static_body: StaticBody3D = mesh_node.get_child(0) as StaticBody3D
	mesh_static_body.name = "MapStaticBody"
	mesh_static_body.set_collision_layer_value(1, true)
	mesh_static_body.collision_mask = 0
	
	# BuildCollider is a CollisionShape3D (a CollisionObject3D's child), NOT a
	# CollisionObject3D — cast accordingly. Without this the cast returned null and
	# the cell-aligned box below was never configured, leaving furniture with only
	# the per-mesh trimesh (which doesn't fill footprint cells reliably). This box
	# is what the build/deconstruct ray stops on, since that ray queries every
	# collision layer and the box is sized exactly to the footprint.
	var build_shape := root.get_node("BuildBody/BuildCollider") as CollisionShape3D
	if build_shape != null:
		var box := BoxShape3D.new()
		box.size = Vector3(dims.x, dims.y, dims.z)
		build_shape.shape = box
		# Center the box in its footprint cells (root Y is the footprint bottom).
		build_shape.position = Vector3(0, dims.y * 0.5, 0)
		var build_body = root.get_node("BuildBody") as StaticBody3D
		build_body.set_collision_layer_value(3, true)
	
	# Apply rotation to root so both mesh and collision rotate together.
	if yaw_quarters != 0:
		root.rotate_y(float(yaw_quarters) * PI * 0.5)

	# Attach interaction only when the def offers actions (FurnitureDef only).
	# Player._find_interaction_component expects a direct child named exactly
	# "InteractionComponent"; component.display_name is the UI fallback.
	if def is FurnitureDef and not (def as FurnitureDef).action_options.is_empty():
		var interaction := InteractionComponent.new()
		interaction.name = "InteractionComponent"
		root.add_child(interaction)
		interaction.action_options = (def as FurnitureDef).action_options

	# Attach storage contents only when the def declares storage params.
	# StorageInventory reads def.storage_params.capacity in its _ready, so it
	# must be added after root.def is set (above) and enter the tree.
	if def is FurnitureDef and (def as FurnitureDef).storage_params != null:
		var storage := StorageInventory.new()
		storage.name = "StorageInventory"
		root.add_child(storage)
	return root


## Remove the item covering `cell` (any covered cell resolves to its anchor).
## Returns true if something was removed. Emits EventBus.furniture_removed.
func remove_at(cell: Vector3i) -> bool:
	var anchor: Variant = _anchor_by_cell.get(cell)
	if anchor == null:
		return false
	var node: Furniture = _node_by_anchor.get(anchor)
	var def_id := node.def_id if node != null else ""
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


## The Furniture instance covering `cell` (any covered cell resolves to its root
## node), or null. Used by the deconstruct ghost to overlay the targeted piece's
## own mesh + transform.
func get_furniture_at(cell: Vector3i) -> Furniture:
	var anchor: Variant = _anchor_by_cell.get(cell)
	if anchor == null:
		return null
	return _node_by_anchor.get(anchor)


# --- SaveSystem contract -----------------------------------------------------
# One record per placed item: placement (anchor + yaw) plus the node's own
# state (def_id, storage contents) via Furniture.serialize. deserialize rebuilds
# the layer from such a list — it clears first, so it is a true inverse of
# serialize and the caller does not need to manage pre-existing entries.

## Snapshot every placed item as a list of records.
func serialize() -> Dictionary:
	var items: Array = []
	for anchor in _node_by_anchor:
		var node: Furniture = _node_by_anchor[anchor]
		if node == null:
			continue
		var rec: Dictionary = node.serialize()
		rec["anchor"] = [anchor.x, anchor.y, anchor.z]
		rec["yaw"] = int(round(node.rotation_degrees.y / 90.0)) % 4
		items.append(rec)
	return {"items": items}


## Clear the layer, then respawn every item from a serialize() dict. Unknown
## def ids are skipped with a warning. Each respawned node's per-instance state
## (storage contents) is restored via Furniture.deserialize.
func deserialize(data: Dictionary) -> void:
	_clear()
	for rec in data.get("items", []):
		var def := BuildLibrary.get_def(rec.get("def_id", ""))
		if def == null:
			push_warning("FurnitureLayer: unknown def_id '%s' in save data" % rec.get("def_id", ""))
			continue
		var a: Array = rec.get("anchor", [0, 0, 0])
		var anchor := Vector3i(int(a[0]), int(a[1]), int(a[2]))
		var node := spawn(def, anchor, int(rec.get("yaw", 0)))
		if node != null:
			node.deserialize(rec)


## Free every spawned node and reset both registries. Used by deserialize so a
## restore fully replaces current contents.
func _clear() -> void:
	for anchor in _node_by_anchor.keys():
		var node = _node_by_anchor[anchor]
		if node != null and is_instance_valid(node):
			node.queue_free()
	_node_by_anchor.clear()
	_anchor_by_cell.clear()
