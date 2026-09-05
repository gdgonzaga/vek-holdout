extends GdUnitTestSuite
## Tests for Colony Management main UI window, tab layout, and colonist roster.

var _scene: Control

# Swap-and-restore (AGENTS.md): the real registry must never be wired to test
# fixtures, and Colony's container must survive the spawn tests' on_map_wired.
var _real_registry: StorageRegistry
var _real_container: Node3D
var _test_registry: StorageRegistry


func before_test() -> void:
	var packed: PackedScene = load("res://ui/colony_management/colony_management.tscn")
	_scene = auto_free(packed.instantiate() as Control)
	add_child(_scene)
	_real_registry = Colony.storage_registry
	_real_container = Colony._container
	_test_registry = StorageRegistry.new()
	auto_free(_test_registry)
	Colony.storage_registry = _test_registry


func after_test() -> void:
	Colony.storage_registry = _real_registry
	Colony._container = _real_container
	Colony.colonists.clear()


func test_colony_management_scene_loads() -> void:
	assert_object(_scene).is_not_null()


func test_colony_management_has_all_seven_tabs() -> void:
	var tab_container: TabContainer = _scene.get_node("%TabContainer") as TabContainer
	assert_object(tab_container).is_not_null()
	assert_int(tab_container.get_tab_count()).is_equal(7)
	
	assert_str(tab_container.get_tab_title(0)).is_equal("Colony Info")
	assert_str(tab_container.get_tab_title(1)).is_equal("Colonists")
	assert_str(tab_container.get_tab_title(2)).is_equal("Labors")
	assert_str(tab_container.get_tab_title(3)).is_equal("Jobs")
	assert_str(tab_container.get_tab_title(4)).is_equal("Crafting")
	assert_str(tab_container.get_tab_title(5)).is_equal("Storage")
	assert_str(tab_container.get_tab_title(6)).is_equal("Squads")


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

	# 8 labors (construction, crafting, farming, harvesting, hauling, mechanics,
	# mining, smelting) + 1 colonist column = 9 columns
	assert_int(grid.columns).is_equal(9)
	# 9 header cells + 9 row cells (1 name + 8 labor cells) = 18 children
	assert_int(grid.get_child_count()).is_equal(18)


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
	var dummy_container: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])

	var spawned: Colonist = Colony.spawn_colonist(null, Vector3(10, 0, 5))
	assert_object(spawned).is_not_null()
	assert_object(spawned.get_parent()).is_equal(dummy_container)
	assert_vector(spawned.global_position).is_equal(Vector3(10, 1, 5))
	assert_int(Colony.colonists.size()).is_equal(1)
	assert_object(Colony.colonists[0]).is_equal(spawned)


## Marker Y is a hint: with a ground query wired (dual-voxel Phase 3), the
## spawn snaps XZ-preserving onto surface + epsilon; NAN keeps authored Y.
## Swap-and-restore — the query is autoload state.
func test_spawn_colonist_snaps_to_ground_query() -> void:
	var dummy_container: Node3D = auto_free(Node3D.new())
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])
	Colony.set_ground_query(func(_x: float, _z: float) -> float: return 5.0)
	var spawned: Colonist = Colony.spawn_colonist(null, Vector3(10, 0, 5))
	assert_object(spawned).is_not_null()
	assert_vector(spawned.global_position).is_equal(Vector3(10, 6.0, 5))
	Colony.set_ground_query(func(_x: float, _z: float) -> float: return NAN)
	var kept: Colonist = Colony.spawn_colonist(null, Vector3(0, 3, 0))
	assert_object(kept).is_not_null()
	assert_vector(kept.global_position).is_equal(Vector3(0, 4.0, 0))
	Colony.set_ground_query(Callable())


func test_spawn_colonist_cap_reached() -> void:
	var dummy_container: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])

	for i in range(Colony.MVP_CAP):
		var c: Colonist = Colony.spawn_colonist(null, Vector3.ZERO)
		assert_object(c).is_not_null()

	var excess: Colonist = Colony.spawn_colonist(null, Vector3.ZERO)
	assert_object(excess).is_null()


func test_colony_serialize_deserialize_round_trip() -> void:
	var dummy_container: Node3D = auto_free(Node3D.new())
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])

	var spawned: Colonist = Colony.spawn_colonist(null, Vector3(5, 2, 8))
	assert_object(spawned).is_not_null()
	spawned.display_name = "Test Colonist"

	var serialized := Colony.serialize()
	assert_dict(serialized).contains_keys(["colonists"])
	var col_list: Array = serialized.get("colonists", [])
	assert_int(col_list.size()).is_equal(1)
	assert_str(col_list[0].get("display_name", "")).is_equal("Test Colonist")

	# Test reset_for_new_game
	Colony.reset_for_new_game()
	assert_int(Colony.colonists.size()).is_equal(0)

	# Test deserialize and map wiring
	Colony.deserialize(serialized)
	var new_container: Node3D = auto_free(Node3D.new())
	add_child(new_container)
	Colony.on_map_wired(new_container, [])

	assert_int(Colony.colonists.size()).is_equal(1)
	var restored: Colonist = Colony.colonists[0]
	assert_object(restored).is_not_null()
	assert_str(restored.display_name).is_equal("Test Colonist")
	assert_object(restored.get_parent()).is_equal(new_container)


func test_squads_tab_empty() -> void:
	Colony.squads.clear()
	_scene.call("_refresh_squads")

	var no_squads: Label = _scene.get_node("%NoSquadsLabel") as Label
	var list: VBoxContainer = _scene.get_node("%SquadList") as VBoxContainer
	assert_object(no_squads).is_not_null()
	assert_bool(no_squads.visible).is_true()
	assert_bool(list.visible).is_false()


func test_squads_tab_create_squad_ui() -> void:
	Colony.squads.clear()
	var line_edit: LineEdit = _scene.get_node("%NewSquadLineEdit") as LineEdit
	line_edit.text = "recon_unit"
	_scene.call("_on_create_squad_pressed")

	assert_bool(Colony.squads.has("recon_unit")).is_true()
	assert_str(line_edit.text).is_equal("")

	var list: VBoxContainer = _scene.get_node("%SquadList") as VBoxContainer
	assert_bool(list.visible).is_true()
	assert_int(list.get_child_count()).is_equal(1)


func test_squad_card_display_and_dismiss_controls() -> void:
	Colony.colonists.clear()
	Colony.squads.clear()

	var col_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(col_scene.instantiate() as Colonist)
	colonist.display_name = "Squad Fighter"
	Colony.colonists.append(colonist)

	Colony.assign_to_squad(colonist.colonist_id, "alpha_fireteam")
	Colony.deploy_colonist(colonist.colonist_id, Vector3(10, 0, 10))

	_scene.call("_refresh_squads")

	var list: VBoxContainer = _scene.get_node("%SquadList") as VBoxContainer
	assert_int(list.get_child_count()).is_equal(1)

	var card: SquadCard = list.get_child(0) as SquadCard
	assert_object(card).is_not_null()

	var dismiss_btn: Button = card.get_node("%DismissSquadButton") as Button
	assert_bool(dismiss_btn.visible).is_true()

	# Press Dismiss Squad
	dismiss_btn.emit_signal("pressed")
	assert_bool(Colony.has_active_deployment(colonist.colonist_id)).is_false()


func test_colonist_details_displays_ai_behavior_and_telemetry() -> void:
	Colony.colonists.clear()
	var col_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(col_scene.instantiate() as Colonist)
	colonist.display_name = "AI Telemetry Tester"
	Colony.colonists.append(colonist)

	if colonist.bt_player != null and colonist.bt_player.blackboard != null:
		colonist.bt_player.blackboard.set_var(&"current_goal", &"work")
		var job := Job.new()
		job.title = "Haul Scrap"
		job.anchor_cell = Vector3i(15, 2, -10)
		job.completed_units = 1
		job.total_units = 3
		colonist.bt_player.blackboard.set_var(&"active_job", job)

	_scene.call("_refresh_colonist_roster")

	var goal_lbl: Label = _scene.get_node("%DetailGoalLabel") as Label
	var act_lbl: Label = _scene.get_node("%DetailActivityLabel") as Label
	var target_lbl: Label = _scene.get_node("%DetailJobTargetLabel") as Label
	var nav_lbl: Label = _scene.get_node("%DetailNavigationLabel") as Label
	var bl_lbl: Label = _scene.get_node("%DetailBlacklistLabel") as Label
	var needs_lbl: Label = _scene.get_node("%DetailNeedsLabel") as Label

	assert_object(goal_lbl).is_not_null()
	assert_object(act_lbl).is_not_null()
	assert_object(target_lbl).is_not_null()
	assert_object(nav_lbl).is_not_null()
	assert_object(bl_lbl).is_not_null()
	assert_object(needs_lbl).is_not_null()

	assert_str(goal_lbl.text).contains("Brain Goal:")
	assert_str(act_lbl.text).contains("Current Activity:")
	assert_str(target_lbl.text).contains("Job Target:")
	assert_str(nav_lbl.text).contains("Navigation:")
	assert_str(bl_lbl.text).contains("Job Cooldowns:")
	assert_str(needs_lbl.text).contains("Needs:")


func test_jobs_tab_empty() -> void:
	if Colony.job_board != null:
		Colony.job_board.clear()
	_scene.call("_refresh_jobs")

	var no_jobs: Label = _scene.get_node("%NoJobsLabel") as Label
	var list: VBoxContainer = _scene.get_node("%JobList") as VBoxContainer
	assert_object(no_jobs).is_not_null()
	assert_bool(no_jobs.visible).is_true()
	assert_bool(list.visible).is_false()


func test_jobs_tab_populates_hauling_and_construction_jobs() -> void:
	if Colony.job_board != null:
		Colony.job_board.clear()

	var haul_job := Job.new()
	haul_job.id = "test_haul_1"
	haul_job.labor_id = "hauling"
	haul_job.title = "Haul Scrap to Crate"
	haul_job.location = Vector3(5, 0, 5)
	haul_job.anchor_cell = Vector3i(5, 0, 5)
	Colony.job_board.add_job(haul_job)

	var construct_job := Job.new()
	construct_job.id = "test_construct_1"
	construct_job.labor_id = "construction"
	construct_job.title = "Construct Turret"
	construct_job.location = Vector3(12, 1, -4)
	construct_job.anchor_cell = Vector3i(12, 1, -4)
	Colony.job_board.add_job(construct_job)

	_scene.call("_refresh_jobs")

	var no_jobs: Label = _scene.get_node("%NoJobsLabel") as Label
	var list: VBoxContainer = _scene.get_node("%JobList") as VBoxContainer
	var summary: Label = _scene.get_node("%JobsSummaryLabel") as Label

	assert_bool(no_jobs.visible).is_false()
	assert_bool(list.visible).is_true()
	assert_int(list.get_child_count()).is_equal(2)
	assert_str(summary.text).contains("Total Jobs: 2")

	var row0: PanelContainer = list.get_child(0) as PanelContainer
	var row1: PanelContainer = list.get_child(1) as PanelContainer
	assert_object(row0).is_not_null()
	assert_object(row1).is_not_null()

	# Verify Hauling row contains hauling section
	var haul_sec: VBoxContainer = row0.get_node("%HaulingSection") as VBoxContainer
	assert_bool(haul_sec.visible).is_true()

	# Verify Construction row contains construction section
	var const_sec: VBoxContainer = row1.get_node("%ConstructionSection") as VBoxContainer
	assert_bool(const_sec.visible).is_true()

	# Clean up
	Colony.job_board.clear()
