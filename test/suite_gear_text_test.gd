extends GdUnitTestSuite
## Tests for GearText, the pure naming helpers shared by the Gear sub-tab.
## Content-agnostic: ItemDefs are built in-memory and no ItemDB lookups happen.


func _make_item(id_val: String, display: String = "") -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = id_val
	def.resource_name = display
	return def


# ==============================
# item_display_name
# ==============================

func test_item_display_name_prefers_resource_name() -> void:
	var def: ItemDef = _make_item("some_id", "Fancy Name")
	assert_str(GearText.item_display_name(def)).is_equal("Fancy Name")


func test_item_display_name_falls_back_to_id() -> void:
	var def: ItemDef = _make_item("some_id")
	assert_str(GearText.item_display_name(def)).is_equal("some_id")


func test_item_display_name_null_def_is_empty() -> void:
	assert_str(GearText.item_display_name(null)).is_equal("")


# ==============================
# slot_display_name
# ==============================

func test_slot_display_name_title_cases_slot_id() -> void:
	assert_str(GearText.slot_display_name(Equipment.SLOT_MAIN_HAND)).is_equal("Main Hand")


func test_slot_display_name_applies_holster_alias() -> void:
	assert_str(GearText.slot_display_name(Equipment.SLOT_HOLSTER)).is_equal("Sidearm")


# ==============================
# group_label
# ==============================

func test_group_label_strips_equip_prefix() -> void:
	assert_str(GearText.group_label("equip_head")).is_equal("Head")


func test_group_label_capitalises_plain_tag() -> void:
	assert_str(GearText.group_label("weapon")).is_equal("Weapon")


# ==============================
# first_glyph
# ==============================

func test_first_glyph_is_uppercased_first_letter() -> void:
	assert_str(GearText.first_glyph("stone axe")).is_equal("S")


func test_first_glyph_of_empty_name_is_question_mark() -> void:
	assert_str(GearText.first_glyph("")).is_equal("?")
