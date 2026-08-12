extends Node
## Manages expeditions: discovering POIs, swapping maps. Scaffold.
##
## Tracks discovered POIs in an Array[String]. Emits existing expedition_started
## and expedition_ended signals via EventBus. Delegates all map loading to
## SceneManager.swap_map().
##
## Full hex-grid and crew logic is deferred.

var _discovered_pois: Array[String] = []
var _on_expedition: bool = false


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)


func _on_run_started() -> void:
	_discovered_pois.clear()
	_on_expedition = false


## Returns all discovered POIs as MapDef resources (map_type == POI only).
func get_available_pois() -> Array[MapDef]:
	var out: Array[MapDef] = []
	for id in _discovered_pois:
		var def: MapDef = MapLibrary.get_def(id)
		if def != null and def.map_type == MapDef.MapType.POI:
			out.append(def)
	return out


## Returns true if the player is currently on an expedition (away from base).
func is_on_expedition() -> bool:
	return _on_expedition


## Add a POI to the discovered list. No-op if already discovered.
func discover(poi_id: String) -> void:
	if not _discovered_pois.has(poi_id):
		_discovered_pois.append(poi_id)


## Travel to a POI. Emits expedition_started and calls SceneManager.swap_map().
## Does nothing if already on an expedition or if the POI is unknown.
func start_expedition(poi_id: String, crew: Array = []) -> void:
	if _on_expedition:
		push_warning("ExpeditionManager: already on an expedition")
		return
	if not MapLibrary.has_def(poi_id):
		push_error("ExpeditionManager: unknown POI '%s'" % poi_id)
		return
	_on_expedition = true
	EventBus.expedition_started.emit(crew, poi_id)
	SceneManager.swap_map(poi_id)


## Return to base colony. Emits expedition_ended and calls swap_map("base_colony").
## Does nothing if not on an expedition.
func end_expedition(result: Dictionary = {}) -> void:
	if not _on_expedition:
		return
	_on_expedition = false
	EventBus.expedition_ended.emit(result)
	SceneManager.swap_map("base_colony")


# --- SaveSystem contract -----------------------------------------------------
# Run-scoped discovery state: which POIs have been found and whether the player
# is currently away from base. (The orchestrator restores the right map via
# GameState.scene_id; this just tracks the flags.)

func serialize() -> Dictionary:
	return {
		"discovered_pois": _discovered_pois.duplicate(),
		"on_expedition": _on_expedition,
	}


func deserialize(data: Dictionary) -> void:
	_discovered_pois.clear()
	for poi_id in data.get("discovered_pois", []):
		_discovered_pois.append(String(poi_id))
	_on_expedition = bool(data.get("on_expedition", false))
