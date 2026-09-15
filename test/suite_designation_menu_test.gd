extends GdUnitTestSuite
## Unit tests for DesignationMenu modal and AreaDesignationController order dispatch.

const _DesignationMenuScene := preload("res://ui/designation_menu/designation_menu.tscn")
const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	if Colony.area_manager != null:
		Colony.area_manager.reset_for_new_game()


func after_test() -> void:
	if Colony.area_manager != null:
		Colony.area_manager.reset_for_new_game()
	_sandbox.restore()


# ── Designation Menu Interaction ──────────────────────────────────────────────

func test_menu_buttons_emit_tool_selected() -> void:
	var menu: DesignationMenu = auto_free(_DesignationMenuScene.instantiate()) as DesignationMenu
	add_child(menu)

	var recorded: Array[Dictionary] = []
	var signal_conn := func(tool_id: String, target_area_id: String) -> void:
		recorded.append({"tool": tool_id, "area": target_area_id})
	EventBus.area_designation_tool_selected.connect(signal_conn)

	var remove_btn: Button = menu.get_node("%RemovePlantsButton") as Button
	remove_btn.pressed.emit()
	assert_int(recorded.size()).is_equal(1)
	assert_str(recorded[0]["tool"]).is_equal("remove_plant")

	EventBus.area_designation_tool_selected.disconnect(signal_conn)


func test_menu_hotkeys_dispatch_orders() -> void:
	var menu: DesignationMenu = auto_free(_DesignationMenuScene.instantiate()) as DesignationMenu
	add_child(menu)

	var recorded: Array[String] = []
	var signal_conn := func(tool_id: String, _target_area_id: String) -> void:
		recorded.append(tool_id)
	EventBus.area_designation_tool_selected.connect(signal_conn)

	var ev_chop := InputEventKey.new()
	ev_chop.pressed = true
	ev_chop.keycode = KEY_2
	menu._unhandled_input(ev_chop)

	var ev_forage := InputEventKey.new()
	ev_forage.pressed = true
	ev_forage.keycode = KEY_3
	menu._unhandled_input(ev_forage)

	var ev_cancel := InputEventKey.new()
	ev_cancel.pressed = true
	ev_cancel.keycode = KEY_4
	menu._unhandled_input(ev_cancel)

	assert_int(recorded.size()).is_equal(3)
	assert_str(recorded[0]).is_equal("chop_tree")
	assert_str(recorded[1]).is_equal("forage")
	assert_str(recorded[2]).is_equal("cancel_orders")

	EventBus.area_designation_tool_selected.disconnect(signal_conn)


func test_menu_area_crud_buttons() -> void:
	var area := Colony.area_manager.create_area(Vector3i(0, 0, 0), Vector3i(2, 2, 2), "Test Zone")
	var area_id := area.id

	var recorded: Array[Dictionary] = []
	var signal_conn := func(tool_id: String, target_area_id: String) -> void:
		recorded.append({"tool": tool_id, "area": target_area_id})
	EventBus.area_designation_tool_selected.connect(signal_conn)

	# 1. New Area button
	var menu1: DesignationMenu = auto_free(_DesignationMenuScene.instantiate()) as DesignationMenu
	add_child(menu1)
	var new_area_btn: Button = menu1.get_node("%NewAreaButton") as Button
	new_area_btn.pressed.emit()
	assert_int(recorded.size()).is_equal(1)
	assert_str(recorded[0]["tool"]).is_equal("create_area")

	# 2. Paint Area button
	var menu2: DesignationMenu = auto_free(_DesignationMenuScene.instantiate()) as DesignationMenu
	add_child(menu2)
	var area_list2: VBoxContainer = menu2.get_node("%AreaList") as VBoxContainer
	var row2: HBoxContainer = null
	for child in area_list2.get_children():
		if child is HBoxContainer:
			row2 = child as HBoxContainer
			break
	assert_object(row2).is_not_null()
	var paint_btn := row2.get_child(1) as Button
	paint_btn.pressed.emit()
	assert_int(recorded.size()).is_equal(2)
	assert_str(recorded[1]["tool"]).is_equal("paint_area")
	assert_str(recorded[1]["area"]).is_equal(area_id)

	# 3. Erase Area button
	var menu3: DesignationMenu = auto_free(_DesignationMenuScene.instantiate()) as DesignationMenu
	add_child(menu3)
	var area_list3: VBoxContainer = menu3.get_node("%AreaList") as VBoxContainer
	var row3: HBoxContainer = null
	for child in area_list3.get_children():
		if child is HBoxContainer:
			row3 = child as HBoxContainer
			break
	assert_object(row3).is_not_null()
	var erase_btn := row3.get_child(2) as Button
	erase_btn.pressed.emit()
	assert_int(recorded.size()).is_equal(3)
	assert_str(recorded[2]["tool"]).is_equal("erase_area")
	assert_str(recorded[2]["area"]).is_equal(area_id)

	EventBus.area_designation_tool_selected.disconnect(signal_conn)


# ── Harvestable Visualizer ───────────────────────────────────────────────────

func test_harvestable_order_visualizer_lifecycle() -> void:
	var furniture := auto_free(Furniture.new()) as Furniture
	furniture.label = "Oak Tree"
	add_child(furniture)

	var harvestable := Harvestable.new()
	harvestable.name = "Harvestable"
	furniture.add_child(harvestable)

	# 1. Marked with Chop order -> shows PlantMoodletVisualizer with chop icon (index 0)
	harvestable.set_order_type("chop")
	harvestable.set_marked(true)
	var visualizer := furniture.get_node_or_null("PlantMoodletVisualizer") as PlantMoodletVisualizer
	assert_object(visualizer).is_not_null()
	assert_bool(visualizer.is_showing_moodlet()).is_true()
	var active_chop: Array[Dictionary] = visualizer.get_active_moodlets()
	assert_int(active_chop.size()).is_equal(1)
	assert_int(int(active_chop[0].get("index", -1))).is_equal(0)
	assert_object(active_chop[0].get("texture", null)).is_not_null()

	# 2. Update to Forage order -> index 1
	harvestable.set_order_type("forage")
	var active_forage: Array[Dictionary] = visualizer.get_active_moodlets()
	assert_int(active_forage.size()).is_equal(1)
	assert_int(int(active_forage[0].get("index", -1))).is_equal(1)

	# 3. Update to Remove order -> index 2
	harvestable.set_order_type("remove")
	var active_remove: Array[Dictionary] = visualizer.get_active_moodlets()
	assert_int(active_remove.size()).is_equal(1)
	assert_int(int(active_remove[0].get("index", -1))).is_equal(2)

	# 4. Update to Harvest order -> index 3
	harvestable.set_order_type("harvest")
	var active_harvest: Array[Dictionary] = visualizer.get_active_moodlets()
	assert_int(active_harvest.size()).is_equal(1)
	assert_int(int(active_harvest[0].get("index", -1))).is_equal(3)

	# 5. Unmarked hides billboard
	harvestable.set_marked(false)
	assert_bool(visualizer.is_showing_moodlet()).is_false()
	assert_int(visualizer.get_active_moodlets().size()).is_equal(0)


# ── Controller Tool Management ───────────────────────────────────────────────

func test_controller_tool_readouts() -> void:
	var ctrl: AreaDesignationController = auto_free(AreaDesignationController.new()) as AreaDesignationController
	add_child(ctrl)

	var recorded: Array[Dictionary] = []
	var signal_conn := func(tool_id: String, tool_label: String) -> void:
		recorded.append({"tool": tool_id, "label": tool_label})
	EventBus.area_designation_tool_changed.connect(signal_conn)

	ctrl.set_tool("chop_tree")
	ctrl.set_tool("forage")
	ctrl.set_tool("remove_plant")
	ctrl.set_tool("cancel_orders")

	assert_int(recorded.size()).is_equal(4)
	assert_str(recorded[0]["tool"]).is_equal("chop_tree")
	assert_str(recorded[0]["label"]).is_equal("Chop Trees")
	assert_str(recorded[1]["tool"]).is_equal("forage")
	assert_str(recorded[1]["label"]).is_equal("Forage")
	assert_str(recorded[2]["tool"]).is_equal("remove_plant")
	assert_str(recorded[2]["label"]).is_equal("Remove Plants")
	assert_str(recorded[3]["tool"]).is_equal("cancel_orders")
	assert_str(recorded[3]["label"]).is_equal("Cancel Orders")

	EventBus.area_designation_tool_changed.disconnect(signal_conn)


func test_menu_tool_selection_does_not_emit_closed() -> void:
	var menu: DesignationMenu = auto_free(_DesignationMenuScene.instantiate()) as DesignationMenu
	add_child(menu)

	var closed_emitted: Array[bool] = []
	menu.closed.connect(func() -> void: closed_emitted.append(true))

	var forage_btn: Button = menu.get_node("%ForageButton") as Button
	forage_btn.pressed.emit()

	assert_int(closed_emitted.size()).is_equal(0)


func test_menu_escape_emits_closed() -> void:
	var menu: DesignationMenu = auto_free(_DesignationMenuScene.instantiate()) as DesignationMenu
	add_child(menu)

	var closed_emitted: Array[bool] = []
	menu.closed.connect(func() -> void: closed_emitted.append(true))

	var ev_esc := InputEventAction.new()
	ev_esc.action = "ui_cancel"
	ev_esc.pressed = true
	menu._unhandled_input(ev_esc)

	assert_int(closed_emitted.size()).is_equal(1)


func test_controller_right_click_resets_corner_a() -> void:
	var ctrl: AreaDesignationController = auto_free(AreaDesignationController.new()) as AreaDesignationController
	add_child(ctrl)
	ctrl.set_active(true)

	ctrl._stage = AreaDesignationController.Stage.CORNER_A_PICKED
	var stages_emitted: Array[String] = []
	var cb := func(stage_name: String) -> void: stages_emitted.append(stage_name)
	EventBus.area_designation_stage_changed.connect(cb)

	var rmb_ev := InputEventMouseButton.new()
	rmb_ev.button_index = MOUSE_BUTTON_RIGHT
	rmb_ev.pressed = true
	ctrl._unhandled_input(rmb_ev)

	assert_int(ctrl._stage).is_equal(AreaDesignationController.Stage.IDLE)
	assert_int(stages_emitted.size()).is_equal(1)
	assert_str(stages_emitted[0]).is_equal("pick corner A")

	EventBus.area_designation_stage_changed.disconnect(cb)


func test_player_ui_cancel_exits_area_designation_mode() -> void:
	var player: Player = _sandbox.make_player()

	EventBus.area_designation_tool_selected.emit("forage", "")
	assert_int(player.mode).is_equal(Player.Mode.AREA_DESIGNATION)

	var toggle_events: Array[bool] = []
	var toggle_cb := func(active: bool) -> void: toggle_events.append(active)
	EventBus.area_designation_toggled.connect(toggle_cb)

	player._on_ui_cancel()

	assert_int(player.mode).is_equal(Player.Mode.NORMAL)
	assert_int(toggle_events.size()).is_equal(1)
	assert_bool(toggle_events[0]).is_false()

	EventBus.area_designation_toggled.disconnect(toggle_cb)
