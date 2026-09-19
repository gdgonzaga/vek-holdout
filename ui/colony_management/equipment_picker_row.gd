class_name EquipmentPickerRow
extends Button
## One item row in the Gear sub-tab's picker: icon (letter fallback when the item has no
## authored icon), name, target/equipped mark and crate stock. Pure display plus one signal;
## the panel owns what choosing an item means. Call setup() after add_child.

signal chosen(item_id: String)

const COLOR_IN_STOCK: Color = Color(0.85, 0.95, 0.85, 1.0)
const COLOR_OUT_OF_STOCK: Color = Color(0.6, 0.6, 0.6, 1.0)

var _entry: GearPickerModel.Entry = null

@onready var _icon_texture: TextureRect = %IconTexture
@onready var _icon_fallback_label: Label = %IconFallbackLabel
@onready var _name_label: Label = %NameLabel
@onready var _mark_label: Label = %MarkLabel
@onready var _stock_label: Label = %StockLabel

# =================
# Primary Functions
# =================

func _ready() -> void:
	pressed.connect(_on_pressed)


## Binds the row to a picker entry and renders it.
func setup(entry: GearPickerModel.Entry) -> void:
	_entry = entry

	# 1. Static Content: name, icon, mark and tooltip only change when the entry is rebuilt.
	_render_static_content()

	# 2. Stock Label: shown separately because the panel refreshes it in place on a slow tick.
	_update_stock_label()


## Updates the crate stock shown on this row without rebuilding the list.
func refresh_stock(stock: int) -> void:
	if _entry == null:
		return
	_entry.stock = stock
	_update_stock_label()


func get_item_id() -> String:
	return _entry.def.id if _entry != null and _entry.def != null else ""

# ===================
# Auxiliary Functions
# ===================

func _render_static_content() -> void:
	## Auxiliary: Fills name, icon/fallback glyph, target/equipped mark and tooltip from the entry.
	var display_name: String = GearText.item_display_name(_entry.def)
	_name_label.text = display_name
	_mark_label.text = _mark_text(_entry)
	tooltip_text = _tooltip_text(_entry.def)

	# 1. Icon Cell: authored icons render as-is; art-less items get a letter so rows stay aligned.
	_apply_icon(_entry.def, display_name)


func _apply_icon(def: ItemDef, display_name: String) -> void:
	## Auxiliary: Shows def.icon when present, otherwise the first-letter fallback.
	_icon_texture.texture = def.icon
	_icon_texture.visible = def.icon != null
	_icon_fallback_label.visible = def.icon == null
	_icon_fallback_label.text = GearText.first_glyph(display_name)


func _update_stock_label() -> void:
	## Auxiliary: "xN" when crates hold the item, otherwise a muted "none".
	var stocked: bool = _entry.stock > 0
	_stock_label.text = "x%d" % _entry.stock if stocked else "none"
	_stock_label.add_theme_color_override("font_color", COLOR_IN_STOCK if stocked else COLOR_OUT_OF_STOCK)


func _mark_text(entry: GearPickerModel.Entry) -> String:
	## Auxiliary: "✓ target", "equipped", both joined, or "" when the row is neither.
	var marks: Array[String] = []
	if entry.is_target:
		marks.append("✓ target")
	if entry.is_equipped:
		marks.append("equipped")
	return " · ".join(marks)


func _tooltip_text(def: ItemDef) -> String:
	## Auxiliary: Weight and tags, since the row itself only has room for the name.
	var tag_text: String = ", ".join(def.tags) if not def.tags.is_empty() else "none"
	return "Weight: %.1f kg\nTags: %s" % [def.weight, tag_text]


func _on_pressed() -> void:
	if _entry != null and _entry.def != null:
		chosen.emit(_entry.def.id)
