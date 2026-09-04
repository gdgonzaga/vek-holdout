class_name DebugItemRow
extends PanelContainer
## One row in the Debug Item Spawner screen. Displays item icon, ID, display name,
## weight, tags, and buttons to spawn 1 or 10 units at the player location.

signal spawn_requested(item_id: String, count: int)

const DEFAULT_ICON = preload("res://assets/item_icons/_default_.png")

var item_id: String = ""
var display_name: String = ""
var tags: Array[String] = []

@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _details_label: Label = %DetailsLabel
@onready var _spawn_1_btn: Button = %Spawn1Button
@onready var _spawn_10_btn: Button = %Spawn10Button


func _ready() -> void:
	_spawn_1_btn.pressed.connect(_on_spawn_1_pressed)
	_spawn_10_btn.pressed.connect(_on_spawn_10_pressed)


func setup(def: ItemDef) -> void:
	if def == null:
		return
	item_id = def.id
	display_name = def.id.capitalize()
	tags = def.tags.duplicate()

	if not is_node_ready():
		await ready

	_icon.texture = def.icon if def.icon != null else DEFAULT_ICON
	_name_label.text = display_name

	var tag_str := ""
	if not tags.is_empty():
		tag_str = " | tags: [" + ", ".join(tags) + "]"
	_details_label.text = "id: %s | weight: %.1fkg%s" % [item_id, def.weight, tag_str]


func _on_spawn_1_pressed() -> void:
	spawn_requested.emit(item_id, 1)


func _on_spawn_10_pressed() -> void:
	spawn_requested.emit(item_id, 10)
