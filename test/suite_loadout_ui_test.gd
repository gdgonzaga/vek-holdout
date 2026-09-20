extends GdUnitTestSuite
## Tests for the loadout UI: LoadoutUi (shared text/dropdown helper), LoadoutStrip (Gear
## sub-tab header) and the Apply-loadout row on SquadCard.
## Content-agnostic: items are synthetic and registered in ItemDB only for each test's
## duration (swap-and-restore); Colony's loadout book, squads and roster are swapped too.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const STRIP_SCENE: PackedScene = preload("res://ui/colony_management/loadout_strip.tscn")
const PANEL_SCENE: PackedScene = preload("res://ui/colony_management/colonist_equipment_panel.tscn")
const SQUAD_CARD_SCENE: PackedScene = preload("res://ui/colony_management/squad_card.tscn")

const TOOL_ID: String = "loadout_ui_tool"
const HELM_ID: String = "loadout_ui_helm"
const GHOST_ID: String = "loadout_ui_ghost"

var _sandbox: ColonySandbox
var _real_loadouts: LoadoutBook
var _previous_item_defs: Dictionary = {}


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	_real_loadouts = Colony.loadouts
	Colony.loadouts = LoadoutBook.new()
	Colony.squads.clear()
	Colony.colonists.clear()
	_make_item(TOOL_ID, ["tool"])
	_make_item(HELM_ID, ["equip_head"])


func after_test() -> void:
	for id_val: String in _previous_item_defs:
		if _previous_item_defs[id_val] != null:
			ItemDB._defs_by_id[id_val] = _previous_item_defs[id_val]
		else:
			ItemDB._defs_by_id.erase(id_val)
	_previous_item_defs.clear()
	Colony.loadouts = _real_loadouts
	Colony.squads.clear()
	Colony.colonists.clear()
	_sandbox.restore()


# ==============================
# Helpers
# ==============================

func _make_item(id_val: String, item_tags: Array[String]) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = id_val
	def.tags = item_tags
	if not _previous_item_defs.has(id_val):
		_previous_item_defs[id_val] = ItemDB._defs_by_id.get(id_val, null)
	ItemDB._defs_by_id[id_val] = def
	return def


func _make_strip(colonist: Colonist) -> LoadoutStrip:
	var strip: LoadoutStrip = auto_free(STRIP_SCENE.instantiate() as LoadoutStrip)
	add_child(strip)
	strip.set_colonist(colonist)
	return strip


func _make_loadout(loadout_name: String, slots: Dictionary) -> String:
	var id: String = Colony.loadouts.create(loadout_name)
	for slot_id: String in slots:
		Colony.loadouts.set_slot(id, slot_id, slots[slot_id])
	return id


func _button(strip: Node, node_name: String) -> Button:
	return strip.get_node("%" + node_name) as Button


func _label(strip: Node, node_name: String) -> Label:
	return strip.get_node("%" + node_name) as Label


func _option(strip: Node) -> OptionButton:
	return strip.get_node("%LoadoutOption") as OptionButton


func _name_input(strip: Node) -> LineEdit:
	return strip.get_node("%SaveNameInput") as LineEdit


func _escape_key() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


## A node that counts ui_cancel presses reaching _unhandled_input, i.e. presses no control consumed.
func _make_unhandled_cancel_probe() -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar cancels_seen: int = 0\nfunc _unhandled_input(event: InputEvent) -> void:\n\tif event.is_action_pressed(\"ui_cancel\"):\n\t\tcancels_seen += 1\n"
	script.reload()
	var probe: Node = auto_free(Node.new())
	probe.set_script(script)
	add_child(probe)
	return probe


# ==============================
# LoadoutUi helpers
# ==============================

func test_apply_summary_lists_what_changed_and_what_was_skipped() -> void:
	assert_str(LoadoutUi.apply_summary("Miner", {"changed": 3, "skipped": 1})) \
		.is_equal("Applied Miner: 3 changed, 1 skipped (item unavailable)")


func test_apply_summary_omits_zero_counts() -> void:
	assert_str(LoadoutUi.apply_summary("Miner", {"changed": 2, "skipped": 0})).is_equal("Applied Miner: 2 changed")
	assert_str(LoadoutUi.apply_summary("Miner", {"changed": 0, "skipped": 2})) \
		.is_equal("Applied Miner: 2 skipped (item unavailable)")


func test_apply_summary_says_so_when_nothing_needed_doing() -> void:
	assert_str(LoadoutUi.apply_summary("Miner", {"changed": 0, "skipped": 0})) \
		.is_equal("Applied Miner: already up to date")


func test_squad_apply_summary_counts_colonists_with_singular_and_plural() -> void:
	assert_str(LoadoutUi.squad_apply_summary("Miner", 3, {"changed": 9, "skipped": 0})) \
		.is_equal("Applied Miner to 3 colonists: 9 changed")
	assert_str(LoadoutUi.squad_apply_summary("Miner", 1, {"changed": 2, "skipped": 1})) \
		.is_equal("Applied Miner to 1 colonist: 2 changed, 1 skipped (item unavailable)")


func test_save_summary_distinguishes_new_from_updated_and_pluralizes_slots() -> void:
	assert_str(LoadoutUi.save_summary("Miner", 5, false)).is_equal("Saved Miner (5 slots)")
	assert_str(LoadoutUi.save_summary("Miner", 1, true)).is_equal("Updated Miner (1 slot)")


func test_match_text_has_a_message_for_each_state() -> void:
	var none: Array[String] = []
	var names: Array[String] = ["Miner", "Guard"]

	assert_str(LoadoutUi.match_text(none, false)).is_equal("No targets set")
	assert_str(LoadoutUi.match_text(none, true)).is_equal("Custom targets")
	assert_str(LoadoutUi.match_text(names, true)).is_equal("Matches: Miner, Guard")


func test_fill_options_lists_loadouts_by_name_and_returns_ids_as_selection() -> void:
	var option: OptionButton = auto_free(OptionButton.new())
	_make_loadout("Miner", {})
	var b: String = _make_loadout("Guard", {})

	LoadoutUi.fill_options(option, Colony.loadouts, b)

	assert_int(option.item_count).is_equal(2)
	assert_str(option.get_item_text(0)).is_equal("Miner")
	assert_str(LoadoutUi.selected_id(option)).is_equal(b)
	assert_bool(option.disabled).is_false()


func test_fill_options_falls_back_to_the_first_loadout_when_the_kept_one_is_gone() -> void:
	var option: OptionButton = auto_free(OptionButton.new())
	var a: String = _make_loadout("Miner", {})

	LoadoutUi.fill_options(option, Colony.loadouts, "loadout_gone")

	assert_str(LoadoutUi.selected_id(option)).is_equal(a)


func test_fill_options_shows_a_disabled_placeholder_when_there_are_no_loadouts() -> void:
	var option: OptionButton = auto_free(OptionButton.new())

	LoadoutUi.fill_options(option, Colony.loadouts, "")

	assert_int(option.item_count).is_equal(1)
	assert_str(option.get_item_text(0)).is_equal(LoadoutUi.NO_LOADOUTS_TEXT)
	assert_bool(option.disabled).is_true()
	assert_str(LoadoutUi.selected_id(option)).is_equal("")


func test_item_resolver_finds_registered_items_and_returns_null_for_unknown_ones() -> void:
	var resolve: Callable = LoadoutUi.item_resolver()

	assert_object(resolve.call(TOOL_ID)).is_not_null()
	assert_object(resolve.call(GHOST_ID)).is_null()


# ==============================
# LoadoutStrip
# ==============================

func test_strip_without_loadouts_disables_apply() -> void:
	var strip: LoadoutStrip = _make_strip(_sandbox.make_colonist())

	assert_bool(_button(strip, "ApplyButton").disabled).is_true()
	assert_bool(_option(strip).disabled).is_true()


func test_strip_lists_the_colonys_loadouts() -> void:
	_make_loadout("Miner", {})
	_make_loadout("Guard", {})

	var strip: LoadoutStrip = _make_strip(_sandbox.make_colonist())

	assert_int(_option(strip).item_count).is_equal(2)
	assert_bool(_button(strip, "ApplyButton").disabled).is_false()


func test_apply_stamps_the_selected_loadout_onto_the_colonist() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_loadout("Miner", {Equipment.SLOT_MAIN_HAND: TOOL_ID, Equipment.SLOT_HEAD: HELM_ID})
	var strip: LoadoutStrip = _make_strip(colonist)

	_button(strip, "ApplyButton").pressed.emit()

	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal(TOOL_ID)
	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_HEAD)).is_equal(HELM_ID)
	assert_str(_label(strip, "ResultLabel").text).is_equal("Applied Miner: 2 changed")


func test_apply_reports_items_it_had_to_skip() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_loadout("Miner", {Equipment.SLOT_MAIN_HAND: TOOL_ID, Equipment.SLOT_HEAD: GHOST_ID})
	var strip: LoadoutStrip = _make_strip(colonist)

	_button(strip, "ApplyButton").pressed.emit()

	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_HEAD)).is_equal("")
	assert_str(_label(strip, "ResultLabel").text).is_equal("Applied Miner: 1 changed, 1 skipped (item unavailable)")


func test_apply_uses_the_loadout_chosen_in_the_dropdown() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_loadout("Miner", {Equipment.SLOT_MAIN_HAND: TOOL_ID})
	_make_loadout("Guard", {Equipment.SLOT_HEAD: HELM_ID})
	var strip: LoadoutStrip = _make_strip(colonist)
	_option(strip).select(1)

	_button(strip, "ApplyButton").pressed.emit()

	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_HEAD)).is_equal(HELM_ID)
	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("")


func test_match_label_follows_the_colonists_targets_without_a_manual_refresh() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_loadout("Miner", {Equipment.SLOT_MAIN_HAND: TOOL_ID})
	var strip: LoadoutStrip = _make_strip(colonist)
	assert_str(_label(strip, "MatchLabel").text).is_equal("No targets set")

	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)
	assert_str(_label(strip, "MatchLabel").text).is_equal("Custom targets")

	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, TOOL_ID)
	assert_str(_label(strip, "MatchLabel").text).is_equal("Matches: Miner")


func test_set_colonist_moves_the_target_listener_to_the_new_colonist() -> void:
	var first: Colonist = _sandbox.make_colonist()
	var second: Colonist = _sandbox.make_colonist()
	var strip: LoadoutStrip = _make_strip(first)
	assert_int(first.equipment.desired_slot_changed.get_connections().size()).is_equal(1)

	strip.set_colonist(second)

	assert_int(first.equipment.desired_slot_changed.get_connections().size()).is_equal(0)
	assert_int(second.equipment.desired_slot_changed.get_connections().size()).is_equal(1)


func test_set_colonist_clears_the_previous_result_and_closes_the_save_row() -> void:
	var first: Colonist = _sandbox.make_colonist()
	_make_loadout("Miner", {Equipment.SLOT_MAIN_HAND: TOOL_ID})
	var strip: LoadoutStrip = _make_strip(first)
	_button(strip, "ApplyButton").pressed.emit()
	_button(strip, "SaveAsButton").pressed.emit()

	strip.set_colonist(_sandbox.make_colonist())

	assert_str(_label(strip, "ResultLabel").text).is_equal("")
	assert_bool((strip.get_node("%SaveRow") as Control).visible).is_false()


func test_the_dropdown_refreshes_when_the_book_changes() -> void:
	var strip: LoadoutStrip = _make_strip(_sandbox.make_colonist())
	assert_int(_option(strip).item_count).is_equal(1)

	var id: String = _make_loadout("Miner", {})
	assert_str(LoadoutUi.selected_id(_option(strip))).is_equal(id)

	Colony.loadouts.delete(id)
	assert_bool(_option(strip).disabled).is_true()


func test_save_as_is_disabled_until_the_colonist_has_a_target() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var strip: LoadoutStrip = _make_strip(colonist)
	assert_bool(_button(strip, "SaveAsButton").disabled).is_true()

	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)

	assert_bool(_button(strip, "SaveAsButton").disabled).is_false()


func test_save_as_opens_the_name_row() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)
	var strip: LoadoutStrip = _make_strip(colonist)

	_button(strip, "SaveAsButton").pressed.emit()

	assert_bool((strip.get_node("%SaveRow") as Control).visible).is_true()


func test_saving_a_new_name_captures_the_targets_and_selects_the_loadout() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, TOOL_ID)
	var strip: LoadoutStrip = _make_strip(colonist)
	_button(strip, "SaveAsButton").pressed.emit()
	_name_input(strip).text = "Miner"

	_button(strip, "ConfirmSaveButton").pressed.emit()

	var id: String = Colony.loadouts.find_id_by_name("Miner")
	assert_dict(Colony.loadouts.get_slots(id)).is_equal({
		Equipment.SLOT_HEAD: HELM_ID,
		Equipment.SLOT_MAIN_HAND: TOOL_ID,
	})
	assert_str(LoadoutUi.selected_id(_option(strip))).is_equal(id)
	assert_str(_label(strip, "ResultLabel").text).is_equal("Saved Miner (2 slots)")
	assert_bool((strip.get_node("%SaveRow") as Control).visible).is_false()
	assert_str(_label(strip, "MatchLabel").text).is_equal("Matches: Miner")


func test_saving_an_existing_name_overwrites_that_loadout() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var id: String = _make_loadout("Miner", {Equipment.SLOT_FEET: HELM_ID})
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, TOOL_ID)
	var strip: LoadoutStrip = _make_strip(colonist)
	_button(strip, "SaveAsButton").pressed.emit()
	_name_input(strip).text = "miner"

	_button(strip, "ConfirmSaveButton").pressed.emit()

	assert_int(Colony.loadouts.list_ids().size()).is_equal(1)
	assert_dict(Colony.loadouts.get_slots(id)).is_equal({Equipment.SLOT_MAIN_HAND: TOOL_ID})
	assert_str(_label(strip, "ResultLabel").text).is_equal("Updated Miner (1 slot)")


func test_the_name_row_is_prefilled_with_the_selected_loadouts_name() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)
	_make_loadout("Miner", {})
	var strip: LoadoutStrip = _make_strip(colonist)

	_button(strip, "SaveAsButton").pressed.emit()

	assert_str(_name_input(strip).text).is_equal("Miner")


func test_the_confirm_button_reads_overwrite_when_the_name_is_taken() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)
	_make_loadout("Miner", {})
	var strip: LoadoutStrip = _make_strip(colonist)
	_button(strip, "SaveAsButton").pressed.emit()

	_name_input(strip).text = "MINER"
	_name_input(strip).text_changed.emit("MINER")
	assert_str(_button(strip, "ConfirmSaveButton").text).is_equal("Overwrite")

	_name_input(strip).text = "Guard"
	_name_input(strip).text_changed.emit("Guard")
	assert_str(_button(strip, "ConfirmSaveButton").text).is_equal("Save")


func test_saving_a_blank_name_creates_nothing_and_keeps_the_row_open() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)
	var strip: LoadoutStrip = _make_strip(colonist)
	_button(strip, "SaveAsButton").pressed.emit()
	_name_input(strip).text = "   "

	_button(strip, "ConfirmSaveButton").pressed.emit()

	assert_int(Colony.loadouts.list_ids().size()).is_equal(0)
	assert_bool((strip.get_node("%SaveRow") as Control).visible).is_true()
	assert_str(_label(strip, "ResultLabel").text).is_equal("Enter a name for the loadout")


func test_cancel_closes_the_name_row_without_saving() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)
	var strip: LoadoutStrip = _make_strip(colonist)
	_button(strip, "SaveAsButton").pressed.emit()
	_name_input(strip).text = "Miner"

	_button(strip, "CancelSaveButton").pressed.emit()

	assert_int(Colony.loadouts.list_ids().size()).is_equal(0)
	assert_bool((strip.get_node("%SaveRow") as Control).visible).is_false()


func test_escape_in_the_name_field_closes_the_row_and_never_reaches_unhandled_input() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)
	var strip: LoadoutStrip = _make_strip(colonist)
	var probe: Node = _make_unhandled_cancel_probe()
	_button(strip, "SaveAsButton").pressed.emit()

	strip.get_viewport().push_input(_escape_key())

	assert_bool((strip.get_node("%SaveRow") as Control).visible).is_false()
	assert_int(probe.get("cancels_seen")).is_equal(0)


func test_escape_with_the_name_row_closed_is_left_for_the_screen() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var strip: LoadoutStrip = _make_strip(colonist)
	var probe: Node = _make_unhandled_cancel_probe()

	strip.get_viewport().push_input(_escape_key())

	assert_int(probe.get("cancels_seen")).is_equal(1)


func test_pressing_enter_in_the_name_field_saves() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, HELM_ID)
	var strip: LoadoutStrip = _make_strip(colonist)
	_button(strip, "SaveAsButton").pressed.emit()
	_name_input(strip).text = "Miner"

	_name_input(strip).text_submitted.emit("Miner")

	assert_int(Colony.loadouts.list_ids().size()).is_equal(1)


func test_the_gear_panel_hosts_a_strip_bound_to_its_colonist() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_loadout("Miner", {Equipment.SLOT_MAIN_HAND: TOOL_ID})
	var panel: ColonistEquipmentPanel = auto_free(PANEL_SCENE.instantiate() as ColonistEquipmentPanel)
	add_child(panel)

	panel.set_colonist(colonist)
	var strip: LoadoutStrip = panel.get_node("%LoadoutStrip") as LoadoutStrip
	_button(strip, "ApplyButton").pressed.emit()

	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal(TOOL_ID)


# ==============================
# SquadCard
# ==============================

func _make_squad_card(squad_id: String) -> SquadCard:
	Colony.create_squad(squad_id)
	var card: SquadCard = auto_free(SQUAD_CARD_SCENE.instantiate() as SquadCard)
	add_child(card)
	card.setup(squad_id)
	return card


func _add_squad_member(squad_id: String) -> Colonist:
	var colonist: Colonist = _sandbox.make_colonist()
	Colony.colonists.append(colonist)
	Colony.assign_to_squad(colonist.colonist_id, squad_id)
	return colonist


func test_squad_card_apply_stamps_the_loadout_onto_every_member() -> void:
	var first: Colonist = _add_squad_member("alpha")
	var second: Colonist = _add_squad_member("alpha")
	_make_loadout("Miner", {Equipment.SLOT_MAIN_HAND: TOOL_ID})
	var card: SquadCard = _make_squad_card("alpha")

	(card.get_node("%ApplyLoadoutButton") as Button).pressed.emit()

	assert_str(first.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal(TOOL_ID)
	assert_str(second.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal(TOOL_ID)
	assert_str((card.get_node("%LoadoutResultLabel") as Label).text) \
		.is_equal("Applied Miner to 2 colonists: 2 changed")


func test_squad_card_apply_leaves_colonists_outside_the_squad_alone() -> void:
	_add_squad_member("alpha")
	var outsider: Colonist = _sandbox.make_colonist()
	Colony.colonists.append(outsider)
	_make_loadout("Miner", {Equipment.SLOT_MAIN_HAND: TOOL_ID})
	var card: SquadCard = _make_squad_card("alpha")

	(card.get_node("%ApplyLoadoutButton") as Button).pressed.emit()

	assert_str(outsider.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("")


func test_squad_card_apply_is_disabled_without_loadouts_or_members() -> void:
	var empty_card: SquadCard = _make_squad_card("alpha")
	assert_bool((empty_card.get_node("%ApplyLoadoutButton") as Button).disabled).is_true()

	_make_loadout("Miner", {})
	empty_card.refresh()
	assert_bool((empty_card.get_node("%ApplyLoadoutButton") as Button).disabled).is_true()

	_add_squad_member("alpha")
	empty_card.refresh()
	assert_bool((empty_card.get_node("%ApplyLoadoutButton") as Button).disabled).is_false()


func test_squad_card_keeps_the_chosen_loadout_across_refreshes() -> void:
	_add_squad_member("alpha")
	_make_loadout("Miner", {})
	var guard: String = _make_loadout("Guard", {})
	var card: SquadCard = _make_squad_card("alpha")
	(card.get_node("%LoadoutOption") as OptionButton).select(1)

	card.refresh()

	assert_str(LoadoutUi.selected_id(card.get_node("%LoadoutOption") as OptionButton)).is_equal(guard)
