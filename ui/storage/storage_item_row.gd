class_name StorageItemRow
extends ItemRow
## One stack in the transfer panel: the shared ItemRow line plus 1 / 10 / All move
## buttons. When nothing can move (the destination rejects the item or is full) the
## row is dimmed, its buttons are disabled and the tooltip says why. Emits intent
## only; the panel owns the transfer. Call setup_transfer() after add_child.

signal move_requested(count: int)

const _TEN: int = 10
const _DIMMED_ALPHA: float = 0.5

@onready var _move_one_button: Button = %MoveOneButton
@onready var _move_ten_button: Button = %MoveTenButton
@onready var _move_all_button: Button = %MoveAllButton

var _count: int = 0


func _ready() -> void:
	_move_one_button.pressed.connect(func() -> void: move_requested.emit(1))
	_move_ten_button.pressed.connect(func() -> void: move_requested.emit(_TEN))
	_move_all_button.pressed.connect(func() -> void: move_requested.emit(_count))


## `movable` is how many of the stack the destination would take right now; when it
## is 0, `block_reason` is shown instead of the item details.
func setup_transfer(def: ItemDef, count: int, movable: int, block_reason: String) -> void:
	# 1. Shared Line: Compact icon, name, count and stack weight.
	setup(def, count)
	set_compact(true)
	_count = count
	# 2. Buttons: 10 duplicates All for a small stack, so it is disabled rather than hidden (stable layout).
	var can_move: bool = movable > 0
	_move_one_button.disabled = not can_move
	_move_ten_button.disabled = not can_move or count <= _TEN
	_move_all_button.disabled = not can_move
	# 3. Explanation: Dim a blocked row and put the reason where the mouse will be.
	modulate.a = 1.0 if can_move else _DIMMED_ALPHA
	tooltip_text = _details_text(def) if can_move else block_reason
	for button: Button in [_move_one_button, _move_ten_button, _move_all_button]:
		button.tooltip_text = "" if can_move else block_reason


func _details_text(def: ItemDef) -> String:
	## Auxiliary: Name, per-unit weight and tags for the hover tooltip.
	var text: String = "%s\n%.1f kg each" % [def.get_display_name(), def.weight]
	if not def.tags.is_empty():
		text += "\nTags: %s" % ", ".join(def.tags)
	return text
