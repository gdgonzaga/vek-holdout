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


func test_labors_tab_empty_roster() -> void:
	Colony.colonists.clear()
	_scene.call("_refresh_labors_matrix")

	var no_col: Label = _scene.get_node("%NoColonistsLabel") as Label
	var grid: GridContainer = _scene.get_node("%LaborsGrid") as GridContainer
	assert_object(no_col).is_not_null()
	assert_bool(no_col.visible).is_true()
	assert_bool(grid.visible).is_false()


func test_labors_tab_populates_matrix() -> void:
	Colony.colonists.clear()
	var col_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(col_scene.instantiate() as Colonist)
	colonist.display_name = "Worker Alpha"
	Colony.colonists.append(colonist)

	_scene.call("_refresh_labors_matrix")

	var no_col: Label = _scene.get_node("%NoColonistsLabel") as Label
	var grid: GridContainer = _scene.get_node("%LaborsGrid") as GridContainer
	assert_bool(no_col.visible).is_false()
	assert_bool(grid.visible).is_true()

	# 7 labors (construction, crafting, farming, harvesting, hauling, mechanics, smelting) + 1 colonist column = 8 columns
	assert_int(grid.columns).is_equal(8)
	# 8 header cells + 8 row cells (1 name + 7 labor cells) = 16 children
	assert_int(grid.get_child_count()).is_equal(16)


func test_labor_cell_left_right_click_and_clamping() -> void:
	var col_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(col_scene.instantiate() as Colonist)
	colonist.display_name = "Matrix Worker"
	colonist.set_labor_priority("construction", 1)

	var cell_scene: PackedScene = load("res://ui/colony_management/labor_cell.tscn")
	var cell: LaborCell = auto_free(cell_scene.instantiate() as LaborCell)
	add_child(cell)
	cell.setup(colonist, "construction", "Construction")

	assert_str(cell.text).is_equal("1")

	# Increment to max (5) and clamp
	cell.call("_change_priority", 1) # 2
	assert_str(cell.text).is_equal("2")
	cell.call("_change_priority", 1) # 3
	assert_str(cell.text).is_equal("3")
	cell.call("_change_priority", 1) # 4
	assert_str(cell.text).is_equal("4")
	cell.call("_change_priority", 1) # 5
	assert_str(cell.text).is_equal("5")
	cell.call("_change_priority", 1) # Clamp at 5
	assert_str(cell.text).is_equal("5")
	assert_int(colonist.labor_priorities["construction"]).is_equal(5)

	# Decrement to min (0) and clamp
	cell.call("_change_priority", -1) # 4
	cell.call("_change_priority", -1) # 3
	cell.call("_change_priority", -1) # 2
	cell.call("_change_priority", -1) # 1
	cell.call("_change_priority", -1) # 0
	assert_str(cell.text).is_equal("0")
	cell.call("_change_priority", -1) # Clamp at 0
	assert_str(cell.text).is_equal("0")
	assert_int(colonist.labor_priorities["construction"]).is_equal(0)


func test_storage_tab_empty() -> void:
	_scene.call("_refresh_storage")
	var no_storage: Label = _scene.get_node("%NoStorageLabel") as Label
	var list: VBoxContainer = _scene.get_node("%StorageList") as VBoxContainer
	assert_object(no_storage).is_not_null()
	assert_bool(no_storage.visible).is_true()
	assert_bool(list.visible).is_false()


func test_storage_tab_with_container() -> void:
	var map_container: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(map_container)

	var furniture: Furniture = auto_free(Furniture.new()) as Furniture
	furniture.def_id = "storage_crate"

	var inv: StorageInventory = StorageInventory.new()
	inv.name = "StorageInventory"
	inv.capacity = 100.0
	furniture.add_child(inv)

	map_container.add_child(furniture)
	furniture.global_position = Vector3(10.0, 0.0, -5.0)
	Colony.storage_registry.on_map_wired(map_container)

	inv.items["wood_block"] = 15

	_scene.call("_refresh_storage")

	var no_storage: Label = _scene.get_node("%NoStorageLabel") as Label
	var list: VBoxContainer = _scene.get_node("%StorageList") as VBoxContainer
	assert_bool(no_storage.visible).is_false()
	assert_bool(list.visible).is_true()
	assert_int(list.get_child_count()).is_equal(1)

	var row: PanelContainer = list.get_child(0) as PanelContainer
	assert_object(row).is_not_null()

	var name_lbl: Label = row.get_node("%ContainerNameLabel") as Label
	assert_str(name_lbl.text).contains("@ (10, 0, -5)")

	var weight_lbl: Label = row.get_node("%WeightLabel") as Label
	assert_str(weight_lbl.text).contains("Stored Weight:")


func test_time_system_realtime_and_decimal_days() -> void:
	# Store initial time state
	var initial_day: int = GameState.current_day
	var initial_elapsed_in_day: float = TimeSystem._elapsed_in_day
	var initial_realtime: float = TimeSystem._realtime_play_time

	GameState.current_day = 3
	TimeSystem._elapsed_in_day = 450.0 # 450s out of 1800s (30m) = 0.25 day
	TimeSystem._realtime_play_time = 3665.0 # 1h 01m 05s

	# Assert decimal elapsed days: (Day 3 - 1) + 0.25 = 2.25 days
	assert_float(TimeSystem.get_elapsed_days()).is_equal_approx(2.25, 0.01)

	# Assert realtime play time
	assert_float(TimeSystem.get_realtime_play_time()).is_equal(3665.0)
	assert_str(TimeSystem.get_realtime_play_time_formatted()).is_equal("01:01:05")

	# Test serialization & deserialization
	var ser := TimeSystem.serialize()
	assert_float(float(ser.get("realtime_play_time", 0.0))).is_equal(3665.0)

	TimeSystem._realtime_play_time = 0.0
	TimeSystem.deserialize(ser)
	assert_float(TimeSystem.get_realtime_play_time()).is_equal(3665.0)

	# Restore state
	GameState.current_day = initial_day
	TimeSystem._elapsed_in_day = initial_elapsed_in_day
	TimeSystem._realtime_play_time = initial_realtime


func test_colony_info_tab_populates_metrics() -> void:
	Colony.colonists.clear()
	var col_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(col_scene.instantiate() as Colonist)
	colonist.display_name = "Info Test Colonist"
	Colony.colonists.append(colonist)

	_scene.call("_refresh_colony_info")

	var count_lbl: Label = _scene.get_node("%InfoColonistCountLabel") as Label
	var elapsed_lbl: Label = _scene.get_node("%InfoElapsedDaysLabel") as Label
	var play_time_lbl: Label = _scene.get_node("%InfoPlayTimeLabel") as Label

	assert_object(count_lbl).is_not_null()
	assert_object(elapsed_lbl).is_not_null()
	assert_object(play_time_lbl).is_not_null()

	assert_str(count_lbl.text).contains("Colonists: 1 / 5")
	assert_str(elapsed_lbl.text).contains("Elapsed In-Game Days:")
	assert_str(play_time_lbl.text).contains("Realtime Play Time:")


func test_spawn_colonist_success() -> void:
	Colony.colonists.clear()
	var dummy_container: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])

	var spawned: Colonist = Colony.spawn_colonist(null, Vector3(10, 0, 5))
	assert_object(spawned).is_not_null()
	assert_object(spawned.get_parent()).is_equal(dummy_container)
	assert_vector(spawned.global_position).is_equal(Vector3(10, 0, 5))
	assert_int(Colony.colonists.size()).is_equal(1)
	assert_object(Colony.colonists[0]).is_equal(spawned)

	# Clean up
	Colony.colonists.clear()


func test_spawn_colonist_cap_reached() -> void:
	Colony.colonists.clear()
	var dummy_container: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])

	for i in range(Colony.MVP_CAP):
		var c: Colonist = Colony.spawn_colonist(null, Vector3.ZERO)
		assert_object(c).is_not_null()

	var excess: Colonist = Colony.spawn_colonist(null, Vector3.ZERO)
	assert_object(excess).is_null()

	# Clean up
	Colony.colonists.clear()
