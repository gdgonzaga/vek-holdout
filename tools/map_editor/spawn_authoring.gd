class_name SpawnAuthoring
extends RefCounted
## Manages authoring, lifecycle, and visualization of spawn markers (Player, Colonist, Enemy)
## under a map's SpawnPoints container node. Non-spawn markers (e.g. Furniture_*) are preserved.

const COLOR_PLAYER := Color(0.2, 1.0, 0.2, 0.5)
const COLOR_COLONIST := Color(0.2, 0.5, 1.0, 0.5)
const COLOR_ENEMY := Color(1.0, 0.2, 0.2, 0.5)

var _map_root: Node3D = null
var _markers: Dictionary = {
	"player": null,
	"colonists": [] as Array[Marker3D],
	"enemies": [] as Array[Marker3D],
}


# =================
# Primary Functions
# =================

## Reads the SpawnPoints children of map_root into the marker lists and tints them.
func bind(map_root: Node3D) -> void:
	_map_root = map_root
	# 1. Marker Cache: Scan SpawnPoints children and visualize existing markers.
	_cache_spawn_markers()


## Detaches from map root and resets cached marker references.
func unbind() -> void:
	_map_root = null
	_markers = {
		"player": null,
		"colonists": [] as Array[Marker3D],
		"enemies": [] as Array[Marker3D],
	}


## Creates or relocates the marker for kind at world_pos; returns it (null for Kind.NONE).
func place(kind: SpawnMarkerRules.Kind, world_pos: Vector3) -> Marker3D:
	if _map_root == null or kind == SpawnMarkerRules.Kind.NONE:
		return null
	# 1. Container Resolution: Ensure SpawnPoints container exists under map root.
	var spawn_points: Node3D = _ensure_spawn_points_container()
	match kind:
		SpawnMarkerRules.Kind.PLAYER:
			# 2. Player Placement: Reuse existing single player marker or create a new one.
			return _place_player_marker(spawn_points, world_pos)
		SpawnMarkerRules.Kind.COLONIST:
			# 2. Colonist Placement: Instantiate numbered colonist spawn marker.
			return _place_numbered_spawn(spawn_points, SpawnMarkerRules.COLONIST_PREFIX, COLOR_COLONIST, "colonists", world_pos)
		SpawnMarkerRules.Kind.ENEMY:
			# 2. Enemy Placement: Instantiate numbered enemy spawn marker.
			return _place_numbered_spawn(spawn_points, SpawnMarkerRules.ENEMY_PREFIX, COLOR_ENEMY, "enemies", world_pos)
	return null


## Frees the nearest spawn marker within max_distance; returns its Kind (NONE when nothing was removed).
func remove_nearest(world_pos: Vector3, max_distance: float) -> SpawnMarkerRules.Kind:
	if _map_root == null:
		return SpawnMarkerRules.Kind.NONE
	var spawn_points: Node3D = _map_root.find_child("SpawnPoints", true, false) as Node3D
	if spawn_points == null:
		return SpawnMarkerRules.Kind.NONE
	# 1. Candidate Selection: Locate nearest valid spawn marker within range.
	var marker: Marker3D = _nearest_spawn_marker(spawn_points, world_pos, max_distance)
	if marker == null:
		return SpawnMarkerRules.Kind.NONE
	var kind: SpawnMarkerRules.Kind = SpawnMarkerRules.kind_of(marker.name)
	# 2. Bookkeeping: Erase marker reference from cached marker dictionary.
	_forget_spawn_marker(marker)
	marker.queue_free()
	return kind


## Player spawn position if set, or null.
func player_position() -> Variant:
	var player: Marker3D = _markers.get("player") as Marker3D
	if player != null and is_instance_valid(player):
		# 1. Position Resolution: Read global or local position based on tree attachment.
		return _marker_pos(player)
	return null


## Array of enemy spawn definitions matching MapDef.enemy_spawns shape [{"pos": Vector3, "count": 1}].
func enemy_spawns() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var enemy_list: Array = _markers.get("enemies", []) as Array
	for marker_variant: Variant in enemy_list:
		var marker: Marker3D = marker_variant as Marker3D
		if marker != null and is_instance_valid(marker):
			# 1. Position Resolution: Read global or local position based on tree attachment.
			result.append({"pos": _marker_pos(marker), "count": 1})
	return result


## Summary counts of tracked spawn markers.
func counts() -> Dictionary:
	var player_set: bool = _markers.get("player") != null and is_instance_valid(_markers["player"])
	var col_count: int = (_markers.get("colonists", []) as Array).size()
	var enemy_count: int = (_markers.get("enemies", []) as Array).size()
	return {
		"player": player_set,
		"colonists": col_count,
		"enemies": enemy_count,
	}


## Returns the active Player Marker3D instance if valid, or null.
func player_marker() -> Marker3D:
	return _markers.get("player") as Marker3D


## Returns a duplicate array of tracked colonist Marker3D instances.
func colonist_markers() -> Array[Marker3D]:
	var list: Array[Marker3D] = []
	for m: Variant in _markers.get("colonists", []):
		if m != null and is_instance_valid(m):
			list.append(m as Marker3D)
	return list


## Returns a duplicate array of tracked enemy Marker3D instances.
func enemy_markers() -> Array[Marker3D]:
	var list: Array[Marker3D] = []
	for m: Variant in _markers.get("enemies", []):
		if m != null and is_instance_valid(m):
			list.append(m as Marker3D)
	return list


# ===================
# Auxiliary Functions
# ===================

func _ensure_spawn_points_container() -> Node3D:
	## Auxiliary: Resolves or creates the SpawnPoints Node3D container under map root.
	var spawn_points: Node3D = _map_root.find_child("SpawnPoints", true, false) as Node3D
	if spawn_points == null:
		spawn_points = Node3D.new()
		spawn_points.name = "SpawnPoints"
		_map_root.add_child(spawn_points)
		spawn_points.owner = _map_root
	return spawn_points


func _place_player_marker(spawn_points: Node3D, world_pos: Vector3) -> Marker3D:
	## Auxiliary: Resolves or instantiates the singleton PlayerSpawn marker and positions it.
	var player_node: Marker3D = _markers.get("player") as Marker3D
	if player_node == null or not is_instance_valid(player_node):
		player_node = spawn_points.find_child(SpawnMarkerRules.PLAYER_NAME, true, false) as Marker3D
		if player_node == null:
			player_node = Marker3D.new()
			player_node.name = SpawnMarkerRules.PLAYER_NAME
			spawn_points.add_child(player_node)
			player_node.owner = _map_root
		_markers["player"] = player_node
	# 1. Transform Assignment: Set marker coordinates appropriately whether in tree or detached.
	_set_marker_pos(player_node, world_pos)
	# 2. Visualization: Apply player tint capsule mesh to the marker.
	_visualize_spawn(player_node, COLOR_PLAYER)
	return player_node


func _place_numbered_spawn(spawn_points: Node3D, prefix: String, color: Color, list_key: String, world_pos: Vector3) -> Marker3D:
	## Auxiliary: Instantiates and tracks a numbered spawn marker with visualization.
	var names: Array[String] = []
	for child in spawn_points.get_children():
		names.append(String(child.name))
	var marker: Marker3D = Marker3D.new()
	marker.name = "%s_%d" % [prefix, SpawnMarkerRules.next_index(names, prefix)]
	spawn_points.add_child(marker)
	marker.owner = _map_root
	# 1. Transform Assignment: Set marker coordinates appropriately whether in tree or detached.
	_set_marker_pos(marker, world_pos)
	# 2. Visualization: Apply tinted capsule mesh to the new marker.
	_visualize_spawn(marker, color)
	(_markers[list_key] as Array).append(marker)
	return marker


func _nearest_spawn_marker(spawn_points: Node3D, target: Vector3, max_distance: float) -> Marker3D:
	## Auxiliary: Locates the nearest valid spawn marker within range.
	var best: Marker3D = null
	var best_dist: float = max_distance
	for child in spawn_points.get_children():
		if not (child is Marker3D) or SpawnMarkerRules.kind_of(child.name) == SpawnMarkerRules.Kind.NONE:
			continue
		# 1. Position Resolution: Read marker coordinates appropriately whether in tree or detached.
		var dist: float = _marker_pos(child as Marker3D).distance_to(target)
		if dist < best_dist:
			best_dist = dist
			best = child as Marker3D
	return best


func _forget_spawn_marker(marker: Marker3D) -> void:
	## Auxiliary: Removes a spawn marker from internal cache.
	match SpawnMarkerRules.kind_of(marker.name):
		SpawnMarkerRules.Kind.PLAYER:
			_markers["player"] = null
		SpawnMarkerRules.Kind.COLONIST:
			(_markers["colonists"] as Array).erase(marker)
		SpawnMarkerRules.Kind.ENEMY:
			(_markers["enemies"] as Array).erase(marker)


func _cache_spawn_markers() -> void:
	## Auxiliary: Scans SpawnPoints children and caches recognized spawn markers.
	_markers = {
		"player": null,
		"colonists": [] as Array[Marker3D],
		"enemies": [] as Array[Marker3D],
	}
	if _map_root == null:
		return
	var spawns: Node3D = _map_root.find_child("SpawnPoints", true, false) as Node3D
	if spawns == null:
		return
	for child in spawns.get_children():
		if child is Marker3D:
			match SpawnMarkerRules.kind_of(child.name):
				SpawnMarkerRules.Kind.PLAYER:
					_markers["player"] = child
					# 1. Visualization: Tint existing player marker.
					_visualize_spawn(child as Marker3D, COLOR_PLAYER)
				SpawnMarkerRules.Kind.COLONIST:
					(_markers["colonists"] as Array).append(child)
					# 1. Visualization: Tint existing colonist marker.
					_visualize_spawn(child as Marker3D, COLOR_COLONIST)
				SpawnMarkerRules.Kind.ENEMY:
					(_markers["enemies"] as Array).append(child)
					# 1. Visualization: Tint existing enemy marker.
					_visualize_spawn(child as Marker3D, COLOR_ENEMY)


func _visualize_spawn(marker: Marker3D, color: Color) -> void:
	## Auxiliary: Attaches or updates unshaded capsule preview on marker.
	var existing: MeshInstance3D = marker.get_node_or_null("SpawnVisualizer") as MeshInstance3D
	if existing != null:
		var mat: StandardMaterial3D = existing.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = color
		return
	var visualizer: MeshInstance3D = MeshInstance3D.new()
	visualizer.name = "SpawnVisualizer"
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	visualizer.mesh = capsule
	visualizer.position = Vector3(0, 0.9, 0)
	visualizer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visualizer.material_override = mat
	marker.add_child(visualizer)


func _marker_pos(marker: Marker3D) -> Vector3:
	## Auxiliary: Resolves marker position using global coordinates when attached to scene tree.
	return marker.global_position if marker.is_inside_tree() else marker.position


func _set_marker_pos(marker: Marker3D, pos: Vector3) -> void:
	## Auxiliary: Assigns marker position using global coordinates when attached to scene tree.
	if marker.is_inside_tree():
		marker.global_position = pos
	else:
		marker.position = pos

