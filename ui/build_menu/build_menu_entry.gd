class_name BuildMenuEntry
extends Button
## One row in the build menu. Instances of build_menu_entry.tscn, populated by
## BuildMenu.populate() from a BuildableDef. The whole button is the click
## target; the icon + label layout is authored in the .tscn so it can be
## restyled without touching code.
##
## Emits pressed_id(id) on click (buildable id string). The opener wires that to
## EventBus.buildable_selected.

signal pressed_id(id: String)

var _id: String = ""
var _display_name: String = ""

var entry_id: String:
	get: return _id

var display_name: String:
	get: return _display_name

@onready var _icon: TextureRect = $HBox/Icon
@onready var _label: Label = $HBox/Label

const DEFAULT_ICON = preload("res://assets/item_icons/_default_.png")


## Fill the entry from a def. Defs without an icon fall back to DEFAULT_ICON.
func setup(def: BuildableDef) -> void:
	setup_tool(def.id, def.display_name, def.icon)


## Fill the entry from primitive fields. Used for non-buildable tool entries
## (e.g. the Deconstruct tool, which has no BuildableDef). A null icon (omitted
## OR passed explicitly, as setup() does for iconless defs) falls back to
## DEFAULT_ICON — resolved here rather than via a default param value, since
## default params only apply on argument *omission*, not on an explicit null.
func setup_tool(id: String, label: String, icon: Texture2D = null) -> void:
	_id = id
	_display_name = label
	# Defer the node setup to _ready if this entry hasn't entered the tree yet
	# (populate() sets up before add_child triggers _ready).
	if not is_node_ready():
		await ready
	_label.text = label
	_icon.texture = icon if icon != null else DEFAULT_ICON
	_icon.visible = true


func _pressed() -> void:
	pressed_id.emit(_id)
