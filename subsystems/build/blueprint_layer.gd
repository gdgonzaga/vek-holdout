class_name BlueprintLayer
extends RefCounted
## Manages blueprint entities — the non-physical "plan" form of a buildable
## (GDD §7.4 Blueprint mode). A blueprint is an interactable Blueprint node
## (extends Furniture): the player points at it and presses E to run the Build
## action, which materializes the target (instant for now).
##
## Sibling of FurnitureLayer, but kept separate so blueprint spawn/remove never
## trips furniture_placed/furniture_removed (and thus the Functional Rooms
## counter / GameLog). Reuses FurnitureLayer's static geometry helpers
## (footprint_cells, world_origin, dimensions_of) so footprint math has one home.
##
## Forward-compat: emits blueprint_placed / blueprint_removed on EventBus — the
## seam a future JobBoard will listen to to register/cancel construction Jobs.
## Completion (complete_blueprint) is the single entry point a colonist work-tick
## / JobBoard.complete calls later.

var _container: Node3D = null             # set via set_container(); where spawned nodes parent.
var _grid: VoxelGridAdapter = null        # set via set_grid(); used to materialize block targets.
var _furniture_layer: FurnitureLayer = null # set via set_furniture_layer(); for furniture targets.
# anchor (Vector3i) -> Blueprint node.
var _node_by_anchor: Dictionary = {}
# occupied cell (Vector3i) -> anchor (Vector3i). Maps every covered cell back to
# the blueprint that owns it, so removal by pointing at any covered cell works.
var _anchor_by_cell: Dictionary = {}

const _blueprint_template: PackedScene = preload("res://subsystems/build/blueprint_template.tscn")
const _build_option_path := "res://data/action_options/build_action_option.tres"
const _add_materials_option_path := "res://data/action_options/add_materials_action_option.tres"
var _build_option: ActionOption = null
var _add_materials_option: ActionOption = null

static var _hologram_mat: StandardMaterial3D = null


func set_container(container: Node3D) -> void:
	_container = container


func set_grid(grid: VoxelGridAdapter) -> void:
	_grid = grid


func set_furniture_layer(fl: FurnitureLayer) -> void:
	_furniture_layer = fl


func has_at(cell: Vector3i) -> bool:
	return _anchor_by_cell.has(cell)


## The Blueprint instance covering `cell` (any covered cell resolves to it), or
## null. Mirrors FurnitureLayer.get_furniture_at — used by the deconstruct ghost.
func get_blueprint_at(cell: Vector3i) -> Blueprint:
	var anchor: Variant = _anchor_by_cell.get(cell)
	if anchor == null:
		return null
	return _node_by_anchor.get(anchor)


## Spawn a blueprint for `target_def` anchored at `anchor` with `yaw_quarters`.
## The blueprint occupies the target's footprint (1x1x1 for blocks). Returns the
## node or null if unwired/overlapping/unknown. Emits blueprint_placed.
func spawn_blueprint(target_def: BuildableDef, anchor: Vector3i, yaw_quarters: int) -> Blueprint:
	if _container == null or target_def == null:
		return null
	var dims := FurnitureLayer.dimensions_of(target_def)
	for off in FurnitureLayer.footprint_cells(dims, yaw_quarters):
		if _anchor_by_cell.has(anchor + off):
			return null   # overlaps an existing blueprint
	var node := _create_blueprint_node(target_def, dims, yaw_quarters)
	if node == null:
		return null
	node.name = "Blueprint_%s" % target_def.id
	node.layer = self
	node.target_def_id = target_def.id
	node.target_rotation_step = yaw_quarters
	node.anchor_cell = anchor
	_container.add_child(node)
	# Position convention matches the target kind: blocks use the voxel-corner
	# convention (node at the cell corner; an authored mesh spans (0,0,0)->(1,1,1)),
	# furniture centers its footprint (FurnitureLayer.world_origin). Mixing these
	# up is what offsets a block blueprint by half a cell.
	node.global_position = Vector3(anchor) if target_def is BlockDef \
		else FurnitureLayer.world_origin(anchor, dims, yaw_quarters)
	_node_by_anchor[anchor] = node
	for off in FurnitureLayer.footprint_cells(dims, yaw_quarters):
		_anchor_by_cell[anchor + off] = anchor
	EventBus.blueprint_placed.emit(target_def.id, anchor)
	return node


func _create_blueprint_node(target_def: BuildableDef, dims: Vector3i, yaw_quarters: int) -> Blueprint:
	var root: Blueprint = _blueprint_template.instantiate()
	# The blueprint's own def is the TARGET's def (what it becomes), so the
	# interaction UI label and future reads resolve to the real buildable.
	root.def = target_def
	root.def_id = target_def.id

	var is_block := target_def is BlockDef
	var mesh_node: MeshInstance3D = root.find_child("Mesh")
	# Show the target's shape. Authored def meshes use the voxel-corner convention
	# (span (0,0,0)->(1,1,1)) and are used as-is. A plain BoxMesh is centered, so
	# for a block (whose node sits at the cell corner) offset it +0.5 to cover the
	# cell — mirrors GhostPreview.show_remove_at. (All current defs carry a mesh.)
	if target_def.mesh != null:
		mesh_node.mesh = target_def.mesh
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mesh_node.mesh = box
		if is_block:
			mesh_node.position = Vector3(0.5, 0.5, 0.5)
	# Hologram look (translucent, unshaded, double-sided). material_override so a
	# source mesh's embedded material is replaced for the blueprint form only.
	mesh_node.material_override = _hologram_material()

	# Non-physical (GDD §7.6: blueprints don't collide or block pathing until
	# construction starts). Deliberately NO trimesh on World (layer 1) — that's
	# the only layer the player physically collides with (its mask defaults to
	# World), so a trimesh there would make the blueprint solid. Rays still
	# target the footprint box below: the interaction ray and the build/
	# deconstruct ray both query all layers and hit it; the player passes through.

	# Footprint-sized box on layer 3 so the build/deconstruct ray stops on a
	# cell-aligned volume (reliable for removal), matching FurnitureLayer.
	var build_shape := root.get_node_or_null("BuildBody/BuildCollider") as CollisionShape3D
	if build_shape != null:
		var box := BoxShape3D.new()
		box.size = Vector3(dims.x, dims.y, dims.z)
		build_shape.shape = box
		# Center the box on the target's cell-box. A block's node sits at the cell
		# corner, so the box center is dims/2; furniture already centers XZ via
		# world_origin, so only Y needs +dims.y/2.
		build_shape.position = Vector3(dims.x * 0.5, dims.y * 0.5, dims.z * 0.5) if is_block \
			else Vector3(0, dims.y * 0.5, 0)
		var build_body := root.get_node_or_null("BuildBody") as StaticBody3D
		if build_body != null:
			build_body.set_collision_layer_value(3, true)

	# Rotate root so mesh and collision rotate together.
	if yaw_quarters != 0:
		root.rotate_y(float(yaw_quarters) * PI * 0.5)

	# Interactable: the child MUST be named exactly "InteractionComponent"
	# (Player._find_interaction_component). A blueprint with a material_cost
	# starts on "Add materials" and swaps to "Build" once materials are complete
	# (see Blueprint.deposit_from); a costless blueprint starts on "Build".
	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	var opts: Array[ActionOption]
	if target_def.material_cost.is_empty():
		opts = [_ensure_build_option()]
	else:
		opts = [_ensure_add_materials_option()]
		root._build_option = _ensure_build_option()
	interaction.action_options = opts
	root.add_child(interaction)
	return root


func _ensure_build_option() -> ActionOption:
	# Lazy-load (not a const preload) to keep the parse-time resource chain short.
	if _build_option == null:
		_build_option = load(_build_option_path)
	return _build_option


func _ensure_add_materials_option() -> ActionOption:
	if _add_materials_option == null:
		_add_materials_option = load(_add_materials_option_path)
	return _add_materials_option


static func _hologram_material() -> StandardMaterial3D:
	if _hologram_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.75, 1.0, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_hologram_mat = m
	return _hologram_mat


## Remove the blueprint covering `cell` (any covered cell resolves to its
## anchor) WITHOUT building the target. Returns true if something was removed.
## Emits blueprint_removed.
func remove_blueprint_at(cell: Vector3i) -> bool:
	var anchor: Variant = _anchor_by_cell.get(cell)
	if anchor == null:
		return false
	var bp: Blueprint = _node_by_anchor.get(anchor)
	_free_blueprint(bp, anchor)
	return true


## Materialize the blueprint's target into the world, then remove the blueprint.
## The single completion entry point: the player's Build action calls it now; a
## future colonist work-tick / JobBoard.complete calls it later. `builder` is the
## player now (unused) — passed through for future skill/stamina attribution.
func complete_blueprint(bp: Blueprint, _builder: Node = null) -> bool:
	if bp == null:
		return false
	var target_def := BuildLibrary.get_def(bp.target_def_id)
	if target_def == null:
		return false
	var anchor: Vector3i = bp.anchor_cell
	if target_def is BlockDef:
		if _grid != null:
			_grid.set_block_at(anchor, bp.target_def_id)
	elif _furniture_layer != null:
		_furniture_layer.spawn(target_def, anchor, bp.target_rotation_step)
	# Free the blueprint + clear its cells. blueprint_removed is emitted here too
	# (not only on cancel) so a future JobBoard sees the blueprint is gone even
	# when completion raced a pending job.
	_free_blueprint(bp, anchor)
	return true


func _free_blueprint(bp: Blueprint, anchor: Variant) -> void:
	var target_def_id := bp.target_def_id if bp != null else ""
	if bp != null:
		bp.queue_free()
	# Clear every cell this anchor covered (we don't track dims here, so sweep).
	var cells_to_clear: Array = []
	for c in _anchor_by_cell.keys():
		if _anchor_by_cell[c] == anchor:
			cells_to_clear.append(c)
	for c in cells_to_clear:
		_anchor_by_cell.erase(c)
	_node_by_anchor.erase(anchor)
	EventBus.blueprint_removed.emit(target_def_id, anchor)


# --- SaveSystem contract -----------------------------------------------------
# One record per in-progress blueprint, delegated to Blueprint.serialize
# (target_def_id + anchor + yaw + material progress). deserialize rebuilds the
# layer from such a list — clears first, so it is a true inverse of serialize.

## Snapshot every in-progress blueprint as a list of records.
func serialize() -> Dictionary:
	var items: Array = []
	for anchor in _node_by_anchor:
		var bp: Blueprint = _node_by_anchor[anchor]
		if bp != null:
			items.append(bp.serialize())
	return {"items": items}


## Clear the layer, then respawn every blueprint from a serialize() dict.
## Unknown target def ids are skipped with a warning. Each respawned blueprint's
## material progress + interaction UI is restored via Blueprint.deserialize.
func deserialize(data: Dictionary) -> void:
	_clear()
	for rec in data.get("items", []):
		var def := BuildLibrary.get_def(rec.get("target_def_id", ""))
		if def == null:
			push_warning("BlueprintLayer: unknown target_def_id '%s' in save data" % rec.get("target_def_id", ""))
			continue
		var a: Array = rec.get("anchor", [0, 0, 0])
		var anchor := Vector3i(int(a[0]), int(a[1]), int(a[2]))
		var bp := spawn_blueprint(def, anchor, int(rec.get("yaw", 0)))
		if bp != null:
			bp.deserialize(rec)


## Free every spawned blueprint and reset both registries. Used by deserialize
## so a restore fully replaces current contents.
func _clear() -> void:
	for anchor in _node_by_anchor.keys():
		var bp = _node_by_anchor[anchor]
		if bp != null and is_instance_valid(bp):
			bp.queue_free()
	_node_by_anchor.clear()
	_anchor_by_cell.clear()
