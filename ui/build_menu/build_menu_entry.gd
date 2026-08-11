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

@onready var _icon: TextureRect = $HBox/Icon
@onready var _label: Label = $HBox/Label


## Fill the entry from a def. Hides the icon node when the def has no icon so
## the label still aligns cleanly without a blank gap.
func setup(def: BuildableDef) -> void:
	setup_tool(def.id, def.display_name, def.icon)


## Fill the entry from primitive fields. Used for non-buildable tool entries
## (e.g. the Deconstruct tool, which has no BuildableDef). Same icon-null rule
## as setup() — hides the icon node so the label aligns without a blank gap.
func setup_tool(id: String, label: String, icon: Texture2D = null) -> void:
	_id = id
	# Defer the node setup to _ready if this entry hasn't entered the tree yet
	# (populate() sets up before add_child triggers _ready).
	if not is_node_ready():
		await ready
	_label.text = label
	if icon == null:
		_icon.visible = false
	else:
		_icon.texture = icon
		_icon.visible = true


func _pressed() -> void:
	pressed_id.emit(_id)
