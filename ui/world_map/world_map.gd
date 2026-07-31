extends PanelContainer
## Full-screen world map overlay. Lists available POIs from ExpeditionManager
## and allows the player to depart on an expedition or return to base.
##
## Opened via SceneManager.open_screen("world_map") and closed via the Close
## button or SceneManager.close_screen().

@onready var _poi_list: VBoxContainer = %POIList
@onready var _return_btn: Button = %ReturnButton
@onready var _close_btn: Button = %CloseButton
@onready var _no_pois_label: Label = %NoPoisLabel

var _poi_entries: Array[Node] = []


func _ready() -> void:
	_populate_pois()
	_update_return_visibility()
	EventBus.map_loaded.connect(_on_map_loaded)


func _populate_pois() -> void:
	# Clear existing entries.
	for entry in _poi_entries:
		entry.queue_free()
	_poi_entries.clear()

	var pois: Array[MapDef] = ExpeditionManager.get_available_pois()
	_no_pois_label.visible = pois.is_empty()

	for def in pois:
		var scene: PackedScene = preload("res://ui/world_map/poi_entry.tscn")
		var entry: Node = scene.instantiate()
		entry.setup(def)
		entry.depart_requested.connect(_on_depart_requested)
		_poi_list.add_child(entry)
		_poi_entries.append(entry)


func _update_return_visibility() -> void:
	_return_btn.visible = ExpeditionManager.is_on_expedition()


func _on_depart_requested(poi_id: String) -> void:
	ExpeditionManager.start_expedition(poi_id)


func _on_return_pressed() -> void:
	ExpeditionManager.end_expedition()


func _on_close_pressed() -> void:
	SceneManager.close_screen()


func _on_map_loaded(_map_id: String) -> void:
	_populate_pois()
	_update_return_visibility()
