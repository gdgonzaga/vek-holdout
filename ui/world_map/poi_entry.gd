extends HBoxContainer
## A single POI row in the world map list. Displays the POI's display name,
## difficulty, and description. Emits depart_requested when the Depart button
## is clicked.

signal depart_requested(poi_id: String)

@onready var _name_label: Label = $VBox/NameLabel
@onready var _desc_label: Label = $VBox/DescLabel
@onready var _difficulty_label: Label = $DifficultyLabel
@onready var _depart_btn: Button = $DepartButton

var _poi_id: String = ""


## Initialize the entry with a MapDef's data.
func setup(def: MapDef) -> void:
	_poi_id = def.id
	_name_label.text = def.display_name
	_desc_label.text = def.description
	_difficulty_label.text = "Difficulty: %d" % def.difficulty


func _on_depart_pressed() -> void:
	depart_requested.emit(_poi_id)
