class_name SpawnHelpers
extends RefCounted
## Reads spawn positions and furniture records from a Map's SpawnPoints container.
##
## Scene markers override MapDef values when present (non-zero): an authored POI
## scene can place PlayerSpawn / EnemySpawn_* Marker3Ds to control exactly where
## actors enter, and SceneManager consults SpawnHelpers before falling back to
## map_def.player_spawn.
##
## Furniture markers (Furniture_<def_id>_<n>) are scanned for authored furniture
## placement data (def_id, anchor, yaw_quarters). The caller (SceneManager) replays
## these records through FurnitureLayer.spawn() at runtime.

static func read_spawns(map: Map) -> Dictionary:
	var result := { "player": Vector3.ZERO, "enemies": [], "furniture": [] }
	var root := map.find_child("SpawnPoints") as Node3D
	if root == null:
		return result
	for child in root.get_children():
		if child.name == "PlayerSpawn":
			result.player = child.global_position
		elif child.name.begins_with("EnemySpawn"):
			result.enemies.append(child.global_position)
		elif child.name.begins_with("Furniture_"):
			var def_id: String = child.get_meta("def_id", "")
			var anchor: Vector3i = child.get_meta("anchor", Vector3i())
			var yaw: int = child.get_meta("yaw_quarters", 0)
			if def_id.is_empty() or anchor == Vector3i.ZERO:
				push_warning("SpawnHelpers: Furniture marker '%s' missing metadata" % child.name)
				continue
			result.furniture.append({"def_id": def_id, "anchor": anchor, "yaw": yaw})
	return result


## Free the authored `Furniture_*` markers after their placement metadata has been
## replayed into the live FurnitureLayer. The markers exist only to carry
## def_id/anchor/yaw into runtime; each also has an editor `PreviewMesh` child
## that would otherwise duplicate the spawned furniture's mesh and survive
## deconstruct (which only frees the spawned copy under FurnitureContainer).
## No-op if the map has no SpawnPoints.
static func clear_furniture_markers(map: Map) -> void:
	var root := map.find_child("SpawnPoints") as Node3D
	if root == null:
		return
	for child in root.get_children():
		if child.name.begins_with("Furniture_"):
			child.queue_free()
