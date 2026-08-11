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
	_id = def.id
	# Defer the node setup to _ready if this entry hasn't entered the tree yet
	# (populate() sets up before add_child triggers _ready).
	if not is_node_ready():
		await ready
	_label.text = def.display_name
	if def.icon == null:
		_icon.visible = false
	else:
		_icon.texture = def.icon
		_icon.visible = true


func _pressed() -> void:
	pressed_id.emit(_id)
