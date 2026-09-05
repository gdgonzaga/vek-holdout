@tool
class_name FurnitureAuthoring
extends RefCounted
## Editor-only helper for the voxel_paint Furniture mode. Owns Marker3D
## create/rotate/delete under the map's SpawnPoints. Does NOT touch voxel_tool,
## does NOT construct a FurnitureLayer (that's runtime-only). Pure scene-graph.
##
## Lifetime: one instance per plugin activation (created in _activate, freed in
## _deactivate). Holds the SpawnPoints reference so individual ops don't re-find it.

var _spawn_points: Node3D = null        # set by bind(); Marker3D parent
var _scene_root: Node = null            # owner for authored markers (scene save)
var _counter: int = 0                   # monotonic name uniquifier
var _index_by_cell: Dictionary = {}    # Vector3i cell → Marker3D


## Resolve the SpawnPoints container for a freshly-activated map. Returns true if
## the map has the expected structure (Map root + SpawnPoints child); false (with
## a push_warning) otherwise — the panel uses this to disable Furniture mode.
func bind(map_root: Node) -> bool:
    _spawn_points = map_root.get_node("SpawnPoints")
    if _spawn_points == null:
        push_warning("FurnitureAuthoring.bind: SpawnPoints not found in map root")
        return false

    # The edited scene root is the correct owner for authored markers:
    # it's an ancestor of SpawnPoints (so the ancestor check passes) AND
    # save_scene persists nodes owned by it. map_root is resolved by the
    # plugin via get_edited_scene_root(), so it's exactly that node.
    _scene_root = map_root

    # Rebuild the cell->marker index AND the counter from existing markers.
    # Without this, furniture loaded from the scene has no index entries, so
    # remove_at() can't find them (place() only adds entries it creates itself).
    _index_by_cell = {}
    _counter = 0
    for child in _spawn_points.get_children():
        if child is Marker3D and child.name.begins_with("Furniture_"):
            # Seed counter from the trailing index in the name.
            var name_parts = child.name.split("_")
            if name_parts.size() >= 3:
                var n = int(name_parts[name_parts.size() - 1])
                if n >= _counter:
                    _counter = n + 1
            # Re-index the marker's footprint cells from its metadata.
            var anchor: Vector3i = child.get_meta("anchor", Vector3i())
            var yaw: int = child.get_meta("yaw_quarters", 0)
            var def_id: String = child.get_meta("def_id", "")
            var def_res = load("res://data/furniture/%s.tres" % def_id)
            var dims := Vector3i.ONE
            if def_res is FurnitureDef:
                dims = (def_res as FurnitureDef).dimensions
            for off in FurnitureLayer.footprint_cells(dims, yaw):
                _index_by_cell[anchor + off] = child

    return true


## Release the reference (called on plugin deactivate). Does not free authored
## markers — they persist in the scene.
func unbind() -> void:
    _spawn_points = null
    _scene_root = null
    _index_by_cell = {}


## Place a furniture def at the given air anchor cell. Writes a Marker3D under
## SpawnPoints named "Furniture_<def_id>_<n>", world-positioned via
## FurnitureLayer.world_origin (reused for parity with runtime), rotated by yaw.
## Performs overlap validity against existing Furniture_* markers (anchor +
## footprint cells). Returns the created Marker3D, or null on overlap/invalid.
func place(def: BuildableDef, anchor: Vector3i, yaw_quarters: int) -> Marker3D:
    # Validate
    var dims = FurnitureLayer.dimensions_of(def)
    var offsets = FurnitureLayer.footprint_cells(dims, yaw_quarters)

    # Check overlap with existing furniture
    for off in offsets:
        var cell = anchor + off
        if _index_by_cell.has(cell):
            push_warning("Furniture placement overlaps at cell " + str(cell))
            return null

    # Create marker
    var marker = Marker3D.new()
    var marker_name = "Furniture_" + def.id + "_" + str(_counter)
    marker.name = marker_name
    _counter += 1

    # Set transform
    var origin = FurnitureLayer.world_origin(anchor, dims, yaw_quarters)
    marker.transform.origin = origin
    marker.transform.basis = Basis(Vector3.UP, deg_to_rad(yaw_quarters * 90))

    # Set metadata
    marker.set_meta("def_id", def.id)
    marker.set_meta("yaw_quarters", yaw_quarters)
    marker.set_meta("anchor", anchor)

    # Add preview mesh/scene so the author can see what they placed.
    if def.scene != null:
        var scn_inst := def.scene.instantiate() as Node3D
        if scn_inst != null:
            scn_inst.name = "PreviewScene"
            marker.add_child(scn_inst)
    elif def.get_mesh() != null:
        var mesh_inst := MeshInstance3D.new()
        mesh_inst.name = "PreviewMesh"
        mesh_inst.mesh = def.get_mesh()
        mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        if def.texture != null:
            var mat := StandardMaterial3D.new()
            mat.albedo_texture = def.texture
            mesh_inst.material_override = mat
        marker.add_child(mesh_inst)

    # Add to scene tree first, then set owner on the marker and its mesh
    # child. Owner can only be assigned once the node is in the tree AND the
    # owner is an ancestor — both true now that the marker is under SpawnPoints.
    _spawn_points.add_child(marker)
    marker.owner = _scene_root
    for child in marker.get_children():
        child.owner = _scene_root

    # Update index
    for off in offsets:
        _index_by_cell[anchor + off] = marker

    return marker


## Rotate the most-recently-placed (or selected) marker 90° on Y. Increments the
## metadata yaw_quarters mod 4 and re-derives origin from the stored anchor so the
## footprint pivot stays correct. Returns true if something rotated.
func rotate_selected(marker: Marker3D) -> bool:
    if marker == null:
        return false

    var current_yaw = marker.get_meta("yaw_quarters", 0)
    var new_yaw = (current_yaw + 1) % 4

    # Try to resolve def for dimensions — gracefully degrade if unavailable
    # (BuildLibrary autoload unreachable in @tool context).
    var def_id: String = marker.get_meta("def_id", "")
    var dims := Vector3i.ONE
    var def_res = load("res://data/furniture/%s.tres" % def_id)
    if def_res is FurnitureDef:
        dims = (def_res as FurnitureDef).dimensions

    var anchor: Vector3i = marker.get_meta("anchor", Vector3i())

    # Remove old cells from index
    var old_offsets = FurnitureLayer.footprint_cells(dims, current_yaw)
    for off in old_offsets:
        _index_by_cell.erase(anchor + off)

    # Update metadata and transform
    marker.set_meta("yaw_quarters", new_yaw)
    var origin = FurnitureLayer.world_origin(anchor, dims, new_yaw)
    marker.transform.origin = origin
    marker.transform.basis = Basis(Vector3.UP, deg_to_rad(new_yaw * 90))

    # Add new cells to index
    var new_offsets = FurnitureLayer.footprint_cells(dims, new_yaw)
    for off in new_offsets:
        _index_by_cell[anchor + off] = marker

    return true


## Remove the furniture marker covering `cell` (any covered footprint cell resolves
## to its anchor, mirroring FurnitureLayer.remove_at). Shift+LMB and Delete both
## route here. Returns true if a marker was removed.
func remove_at(cell: Vector3i) -> bool:
    if not _index_by_cell.has(cell):
        return false

    var marker = _index_by_cell[cell]

    # Remove from index — read anchor/yaw from metadata rather than re-resolving
    # the def (BuildLibrary autoload is unreachable in @tool context).
    var anchor: Vector3i = marker.get_meta("anchor", Vector3i())
    var yaw: int = marker.get_meta("yaw_quarters", 0)

    # Clear every cell that maps to this marker (safe even if dims unknown).
    var cells_to_clear: Array = []
    for c in _index_by_cell.keys():
        if _index_by_cell[c] == marker:
            cells_to_clear.append(c)
    for c in cells_to_clear:
        _index_by_cell.erase(c)

    # Remove from scene
    marker.queue_free()

    return true


## Snapshot all authored furniture as plain Dictionaries (for SpawnHelpers parity).
func export_records() -> Array[Dictionary]:
    var records = []
    for child in _spawn_points.get_children():
        if child is Marker3D and child.name.begins_with("Furniture_"):
            var record = {
                "def_id": child.get_meta("def_id", ""),
                "anchor": child.get_meta("anchor", Vector3i()),
                "yaw": child.get_meta("yaw_quarters", 0)
            }
            records.append(record)
    return records