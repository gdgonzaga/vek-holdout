extends GdUnitTestSuite
## Tests for Colony Management main UI window and tab layout.

var _scene: Control


func before_test() -> void:
	var packed: PackedScene = load("res://ui/colony_management/colony_management.tscn")
	_scene = auto_free(packed.instantiate() as Control)
	add_child(_scene)


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
