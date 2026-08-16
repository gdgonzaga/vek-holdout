extends GdUnitTestSuite
## Tests for Colony Management main UI window, tab layout, and colonist roster.

var _scene: Control


func before_test() -> void:
	var packed: PackedScene = load("res://ui/colony_management/colony_management.tscn")
	_scene = auto_free(packed.instantiate() as Control)
	add_child(_scene)


func after_test() -> void:
	Colony.colonists.clear()


func test_colony_management_scene_loads() -> void:
	assert_object(_scene).is_not_null()


func test_colony_management_has_all_five_tabs() -> void:
	var tab_container: TabContainer = _scene.get_node("%TabContainer") as TabContainer
	assert_object(tab_container).is_not_null()
	assert_int(tab_container.get_tab_count()).is_equal(5)
	
	assert_str(tab_container.get_tab_title(0)).is_equal("Colony Info")
	assert_str(tab_container.get_tab_title(1)).is_equal("Colonists")
	assert_str(tab_container.get_tab_title(2)).is_equal("Labors")
	assert_str(tab_container.get_tab_title(3)).is_equal("Crafting")
	assert_str(tab_container.get_tab_title(4)).is_equal("Storage")


func test_colonist_tab_empty_roster() -> void:
	Colony.colonists.clear()
	_scene.call("_refresh_colonist_roster")
	
	var no_sel: Label = _scene.get_node("%NoSelectionLabel") as Label
	var details: VBoxContainer = _scene.get_node("%DetailsContent") as VBoxContainer
	assert_object(no_sel).is_not_null()
	assert_bool(no_sel.visible).is_true()
	assert_bool(details.visible).is_false()


func test_colonist_tab_roster_and_details() -> void:
	Colony.colonists.clear()
	var col_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(col_scene.instantiate() as Colonist)
	colonist.display_name = "Test Colonist Alpha"
	Colony.colonists.append(colonist)
	
	_scene.call("_refresh_colonist_roster")
	
	var list: VBoxContainer = _scene.get_node("%ColonistList") as VBoxContainer
	assert_int(list.get_child_count()).is_equal(1)
	
	var no_sel: Label = _scene.get_node("%NoSelectionLabel") as Label
	var details: VBoxContainer = _scene.get_node("%DetailsContent") as VBoxContainer
	assert_bool(no_sel.visible).is_false()
	assert_bool(details.visible).is_true()
	
	var name_lbl: Label = _scene.get_node("%DetailNameLabel") as Label
	assert_str(name_lbl.text).is_equal("Test Colonist Alpha")
	
	var hp_lbl: Label = _scene.get_node("%DetailHpLabel") as Label
	assert_str(hp_lbl.text).contains("Health:")
	
	var stam_lbl: Label = _scene.get_node("%DetailStaminaLabel") as Label
	assert_str(stam_lbl.text).contains("Stamina:")
	
	var mood_lbl: Label = _scene.get_node("%DetailMoodLabel") as Label
	assert_str(mood_lbl.text).contains("Mood:")
	
	var act_lbl: Label = _scene.get_node("%DetailActivityLabel") as Label
	assert_str(act_lbl.text).contains("Current Activity:")
