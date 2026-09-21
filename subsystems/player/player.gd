class_name Player
extends CharacterBody3D
## Third-person controller (ARCH "Subsystem: Player").
##
## Owns the Mode state machine that routes the build and designation menus, the
## equipped item's LMB action, the movement state, and the SaveSystem contract.
## Locomotion (walk, sprint, jump, frozen air momentum) lives in the PlayerMotor child
## and everything the player does to the world under the crosshair (interaction target,
## E-key paths, manual LMB interactions, mining) in the PlayerInteractor child; the
## Player only feeds them the input lock, the needs/wading speed penalty and its gates.
## Needs, equipment, skills, health, the motor and the interactor attach as child components.
## Mode/State members no code sets yet (ATTACK, INTERACT, SLEEP) are reserved so
## later features fill in without restructuring.

enum Mode {NORMAL, BUILD_MENU, BUILD_PLACEMENT, DIG_BOX_DESIGNATION, AREA_DESIGNATION, DESIGNATION_MENU, HARVEST_BOX_DESIGNATION}
enum State {IDLE, WALK, SPRINT, ATTACK, INTERACT, SLEEP, DEAD}

## Height above the player's origin (its feet) of the voxel cell sampled for wading: the lower torso.
const _WADING_SAMPLE_HEIGHT := 0.2

var mode := Mode.NORMAL
var state := State.IDLE

## True while a timed action (e.g. a BuildAction with a build_time) holds the
## player. While busy (or dead), movement, jump, and discrete actions (interact,
## menus, hotkeys) are ignored — every input handler gates on is_input_locked().
var _busy := false

## The currently open BuildMenu (null when no menu is open). Tracked so B can
## close it and so we know whether B means "open" or "close".
var _build_menu: BuildMenu = null
var _designation_menu: DesignationMenu = null

@onready var _input: InputComponent = $InputComponent
@onready var _rig: CameraRig = $CameraRig
@onready var motor: PlayerMotor = $Motor
@onready var interactor: PlayerInteractor = $Interactor
@onready var _camera: Camera3D = _rig.get_camera()
@onready var inventory: CharacterInventory = $Inventory
@onready var command_controller: CommandController = get_node_or_null("CommandController") as CommandController
@onready var anim_controller: PlayerAnimationController = get_node_or_null("AnimationController") as PlayerAnimationController

## Equipment component — 8 slots. Code-created in _ready alongside skill_set.
var equipment: Equipment
var _equipped_action_cooldown: float = 0.0

## Needs and physiological state (hunger, etc.)
var needs: ColonistNeeds
@onready var health_component: HealthComponent = $HealthComponent

## True once health_component has reached 0 HP (ARCH combat.md — mirrors the
## is_dead flag EnemyBase/Colonist expose so threat-scanning tasks can skip
## dead targets uniformly across actor types).
var is_dead: bool:
	get:
		return health_component.is_dead if health_component != null else false

## Player skill progression (the same SkillSet colonists use — GDD §6.3).
## Code-created (the Colonist's code-created-inventory precedent; script-only,
## no scene edit) and unseeded: every skill reads L1 until trained by use
## (personal crafting today). Wiring it means recipe conditions evaluate the
## player naturally — MinSkillCondition reads actor.get("skill_set")
## reflectively, so it already knew what to do.
var skill_set: SkillSet


## The player's active Camera3D (via the rig). Used by BuildController for its
## screen-center raycast (ARCH line 335).
func get_camera() -> Camera3D:
	return _rig.get_camera()


## Horizontal direction the camera is looking, independent of movement state.
## Drives visual body-facing (PlayerAnimationController) so the avatar always
## faces where the player looks instead of where they last walked.
func get_look_direction() -> Vector3:
	return _rig.get_forward_horizontal()


## Camera pitch (radians, look-up positive per CameraRig's convention). Drives
## the torso/head look lean in PlayerAnimationController.
func get_look_pitch() -> float:
	return _rig.get_pitch()


## Whether the player is currently locked by a timed action (e.g. a build).
func is_busy() -> bool:
	return _busy


## Lock or release the player. Taken by BuildAction before showing its progress
## gauge and released on that gauge's completed / cancelled signals.
func set_busy(value: bool) -> void:
	_busy = value


## Add items to the player's inventory. Returns the overflow (items that didn't fit).
func add_item(item_id: String, count: int) -> int:
	return inventory.add(item_id, count)


## Remove items from the player's inventory. Returns the shortfall (items that
## weren't there to remove).
func remove_item(item_id: String, count: int) -> int:
	return inventory.remove(item_id, count)


## Drops `count` of `item_id` from the player's inventory into the world in front of the player.
## "In front" is where the camera looks: the body itself never rotates, so its basis
## can't say which way the player faces.
## Returns the created WorldItem entity (or null if item wasn't carried).
func drop_item(item_id: String, count: int = 1) -> WorldItem:
	if not inventory.has_item(item_id, count):
		return null
	var removed := inventory.remove(item_id, count)
	var dropped_count := count - removed
	if dropped_count <= 0:
		return null

	# 1. Look Direction: Horizontal camera forward, so the drop lands where the crosshair points instead of along world -Z.
	var forward := get_look_direction()
	var spawn_pos := global_position + Vector3(0.0, 1.2, 0.0) + forward * 0.8
	var impulse_dir := forward + Vector3(0.0, 0.3, 0.0)
	var tree := get_tree() if is_inside_tree() else null
	var dropped_item := WorldItem.spawn_at(tree, item_id, dropped_count, spawn_pos, impulse_dir, 2.5)
	return dropped_item


## Check whether the player is carrying at least `count` of the given item.
func has_item(item_id: String, count: int) -> bool:
	return inventory.has_item(item_id, count)


## Check whether the player's inventory can fit `count` of the given item.
func can_carry(item_id: String, count: int) -> bool:
	return inventory.can_add(item_id, count)


## Consumes 1 unit of food from player inventory, restoring hunger and HP.
func consume_food_item(item_id: String) -> bool:
	if inventory.get_item_count(item_id) <= 0:
		return false
	var def: ItemDef = ItemDB.get_def(item_id)
	if def == null or def.food == null:
		return false

	inventory.remove(item_id, 1)
	if needs != null:
		needs.restore_need(&"hunger", def.food.nutrition_value)
	if def.food.health_restore > 0:
		heal(def.food.health_restore)
	return true


func take_damage(amount: int, source: Node = null) -> void:
	health_component.take_damage(amount, source)


func heal(amount: int) -> void:
	health_component.heal(amount)


func _on_health_component_died(_entity: Node) -> void:
	state = State.DEAD
	EventBus.player_died.emit("combat")


# --- SaveSystem contract -----------------------------------------------------
# Transform + camera orientation + carried inventory + equipment, needs, skills and
# health. Movement mode/state and the transient interactable target are NOT
# persisted. Assumes the player (and its CameraRig) is ready — set_orientation
# touches the rig's spring arm.

## Snapshot position, camera yaw/pitch, inventory stacks, and component state.
func serialize() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"cam_yaw": _rig.get_yaw(),
		"cam_pitch": _rig.get_pitch(),
		"inventory": inventory.serialize(),
		"equipment": equipment.serialize() if equipment != null else {},
		"needs": needs.serialize() if needs != null else {},
		"skills": skill_set.serialize(),
		"health": health_component.serialize(),
	}


## Restore position, camera orientation, and inventory from a serialize() dict.
func deserialize(data: Dictionary) -> void:
	motor.reset()
	var p: Array = data.get("pos", [global_position.x, global_position.y, global_position.z])
	global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_rig.set_orientation(float(data.get("cam_yaw", 0.0)), float(data.get("cam_pitch", -0.25)))
	_rig.snap_to_target()
	if data.has("inventory"):
		inventory.deserialize(data["inventory"])
	if data.has("equipment") and equipment != null:
		equipment.deserialize(data["equipment"])
	if data.has("needs") and needs != null:
		needs.deserialize(data["needs"])
	if data.has("skills"):
		skill_set.deserialize(data["skills"])
	if data.has("health"):
		health_component.deserialize(data["health"])
	var guard := get_node_or_null("GroundSafetyGuard") as GroundSafetyGuard
	if guard != null:
		guard.rearm()


func _ready() -> void:
	add_to_group("player")
	GameState.set_local_player(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_max_angle = deg_to_rad(60.0)

	# Needs component for physiological needs (hunger, etc.) and depletion penalties
	needs = get_node_or_null("ColonistNeeds") as ColonistNeeds
	if not needs:
		needs = ColonistNeeds.new()
		needs.name = "ColonistNeeds"
		add_child(needs)

	# SkillSet child (skill catalog loads in its own _ready; unseeded = all L1).
	var skills := SkillSet.new()
	skills.name = "SkillSet"
	add_child(skills)
	skill_set = skills

	# Equipment component: 8-slot gear state. Added before EquipmentVisualizer
	# so the sibling node exists when the visualizer wires slot_changed in _ready.
	_ensure_equipment()

	health_component.entity_died.connect(_on_health_component_died)
	motor.setup(_input, _rig)
	interactor.setup(self, _camera)

	# React to a buildable selection (emitted by the build menu) by entering
	# Blueprint mode + recapturing the mouse. The selected id itself goes straight
	# to BuildController via the same signal — Player doesn't carry it.
	EventBus.buildable_selected.connect(_on_buildable_selected)
	# Wire discrete input actions from the InputComponent child.
	_input.build_toggle_pressed.connect(_on_build_key_pressed)
	_input.primary_action_pressed.connect(_on_primary_action)
	_input.recapture_requested.connect(_recapture_mouse)
	if command_controller != null and _camera != null:
		command_controller.set_camera(_camera)
	_input.ui_cancel_pressed.connect(_on_ui_cancel)
	_input.dig_box_toggle_pressed.connect(_on_dig_box_toggle_pressed)
	_input.area_designation_toggle_pressed.connect(_on_area_designation_toggle_pressed)
	EventBus.area_designation_tool_selected.connect(_on_area_designation_tool_selected)
	_input.harvest_box_toggle_pressed.connect(_on_harvest_box_toggle_pressed)

func _exit_tree() -> void:
	if GameState.get_local_player() == self:
		GameState.set_local_player(null)



## Blueprint key routing (GDD §4 controls table):
##   - B in Normal    -> open the build menu
##   - B in Placement -> back to the build menu (quick item swap)
## The menu itself consumes B and Esc while it's open (it registers with UiGate,
## which gates InputComponent), and Esc exits placement straight to Normal.
func _on_build_key_pressed() -> void:
	if is_input_locked():
		return
	if mode == Mode.BUILD_PLACEMENT:
		# Placement -> menu. Drop the selected buildable and reopen the menu.
		_exit_build_placement_mode()
		open_build_menu()
	else:
		open_build_menu()


## Open the build menu. Selecting a buildable closes it and enters Blueprint mode
## with that buildable selected (ARCH Player flow, line 388 — now driven by menu
## selection rather than a direct B-toggle). Movement still applies in Blueprint.
func open_build_menu() -> void:
	if _build_menu != null:
		return
	# 1. Menu Layer Resolution: Find the hud_layer (else ui_layer) CanvasLayer, or create a fallback for scenes without one.
	var layer: CanvasLayer = _resolve_menu_layer()
	# 2. Build Menu Instantiation: Instantiate and mount build menu modal onto resolved UI layer.
	_mount_build_menu(layer)


func _resolve_menu_layer() -> CanvasLayer:
	## Auxiliary: The CanvasLayer modal menus mount on: the "hud_layer" group first (AGENTS.md: ad-hoc
	## panels live there; the UILayer is SceneManager's full-screen slot), then "ui_layer" like every other
	## panel-mounting call site. Scenes with neither (headless tests, playtest scenes without Main) get one
	## fallback layer that joins "hud_layer", so the next call reuses it instead of stacking another per
	## menu open. It mounts on the running scene, or on the tree root when no scene is set.
	var tree := get_tree()
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "HUDLayer"
		layer.layer = 10
		layer.add_to_group("hud_layer")
		var mount: Node = tree.current_scene if tree.current_scene != null else tree.root
		mount.add_child(layer)
	return layer


func _mount_build_menu(layer: CanvasLayer) -> void:
	## Auxiliary: Mounts, populates, and wires signals for the build menu modal.
	var menu: BuildMenu = preload("res://ui/build_menu/build_menu.tscn").instantiate()
	layer.add_child(menu)
	menu.populate()
	menu.closed.connect(_on_build_menu_closed)
	_build_menu = menu
	mode = Mode.BUILD_MENU
	EventBus.build_menu_toggled.emit(true)


func _on_buildable_selected(_id: String) -> void:
	# The selected id flows menu -> EventBus -> BuildController directly; Player
	# only reacts to the event to flip its own mode. The menu frees itself on
	# selection without emitting closed(), so clear the tracked ref here; its
	# unregistration re-captures the mouse for placement.
	_build_menu = null
	EventBus.build_menu_toggled.emit(false)
	# 1. Mode Entry: Switches to placement and announces it so BuildController starts previewing.
	_enter_tool_mode(Mode.BUILD_PLACEMENT)


func _on_build_menu_closed() -> void:
	# Menu closed without a selection (Esc/B/Close button). Clear the tracked
	# ref; the menu's unregistration re-captures the mouse.
	_build_menu = null
	EventBus.build_menu_toggled.emit(false)
	mode = Mode.NORMAL


func _recapture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_ui_cancel() -> void:
	# Esc exits Blueprint placement straight back to Normal (the build menu
	# handles its own Esc). This runs synchronously inside InputComponent's
	# _unhandled_input, so marking the event handled here also stops Main from
	# treating the same press as "open pause menu".
	# 1. Tool Mode Check: Only tool modes announce a toggled signal; Normal and the menus own their Esc, so the press isn't ours.
	if not _is_tool_mode(mode):
		return
	get_viewport().set_input_as_handled()
	# 2. Mode Exit: Returns to Normal and announces toggled(false) so the mode's controller disarms.
	_exit_tool_mode(mode)


func _is_tool_mode(tool_mode: Mode) -> bool:
	## Auxiliary: True for the modes that toggle on/off via an EventBus signal (placement and the box/area tools).
	return not _get_mode_toggled_signal(tool_mode).is_null()


func _enter_tool_mode(tool_mode: Mode) -> void:
	## Auxiliary: Switches to `tool_mode` and announces toggled(true) to its controller and the HUD.
	mode = tool_mode
	_get_mode_toggled_signal(tool_mode).emit(true)


func _exit_tool_mode(tool_mode: Mode) -> void:
	## Auxiliary: Returns to Normal and announces toggled(false) on the signal of the mode being left.
	mode = Mode.NORMAL
	_get_mode_toggled_signal(tool_mode).emit(false)


func _get_mode_toggled_signal(tool_mode: Mode) -> Signal:
	## Auxiliary: The EventBus signal announcing entry to / exit from `tool_mode`; a null Signal for modes that aren't tool modes.
	match tool_mode:
		Mode.BUILD_PLACEMENT:
			return EventBus.build_placement_toggled
		Mode.DIG_BOX_DESIGNATION:
			return EventBus.dig_box_toggled
		Mode.AREA_DESIGNATION:
			return EventBus.area_designation_toggled
		Mode.HARVEST_BOX_DESIGNATION:
			return EventBus.harvest_box_toggled
		_:
			return Signal()


## Leave placement and reopen the build menu (B in placement — quick item swap).
## Esc exits placement straight to Normal instead (see _on_ui_cancel).
func _exit_build_placement_mode() -> void:
	mode = Mode.BUILD_MENU
	EventBus.build_placement_toggled.emit(false)


## Plays a tool or interaction action animation on the child animation controller (a no-op
## when the player has none). Shared by the equipped-item action and the interactor.
func trigger_animation_action(action_name: StringName) -> void:
	if anim_controller:
		anim_controller.trigger_action(action_name)


func _physics_process(delta: float) -> void:
	if _equipped_action_cooldown > 0.0:
		_equipped_action_cooldown -= delta
	# 1. Interaction Target: Re-aims the crosshair target so the HUD label and the E press act on what is in view.
	interactor.update_target()
	# 2. Locomotion: One motor tick with the input lock and the speed penalty; returns the wish vector so the movement state can follow it.
	var wish := motor.tick(delta, is_input_locked(), _movement_speed_multiplier())
	# 3. Movement State: CharacterBody3D itself never rotates (the camera rig's orbit is decoupled from where the avatar looks; visual facing comes from PlayerAnimationController via get_look_direction()), so state follows the wish alone.
	state = _resolve_move_state(wish)


func _movement_speed_multiplier() -> float:
	## Auxiliary: The penalties scaling ground speed, and the speed frozen into a jump or ledge exit: the
	## depleted-need slowdown and the drag of the fluid the body is wading through. One value per tick,
	## so airborne momentum can't shed a penalty that walking would keep.
	var multiplier := 1.0
	if needs != null:
		multiplier *= needs.get_speed_multiplier()
	# 1. Wading Drag: The multiplier of the fluid block at the lower torso (BlockDef.wading_speed_mult; 1.0 when dry or between maps).
	multiplier *= _get_wading_speed_multiplier()
	return multiplier


func _resolve_move_state(wish: Vector3) -> State:
	## Auxiliary: Movement state for this tick. DEAD is terminal so a tick can't overwrite it.
	if is_dead:
		return State.DEAD
	if wish.length_squared() <= 0.001:
		return State.IDLE
	# SPRINT only while grounded + sprinting; mid-air carries momentum but
	# isn't "sprinting" (state reflects what the avatar is doing, not what it
	# did at takeoff).
	var sprinting := is_on_floor() and _input.wants_sprint()
	return State.SPRINT if sprinting else State.WALK


## True while the player can't act: held by a timed action or dead. Every input-driven
## handler gates on it, and the interactor reads it for the E key. is_busy() stays the
## timed-action flag alone (BuildController reads it).
func is_input_locked() -> bool:
	return _busy or is_dead


## Equips a carried item: MOVES one from the inventory into the slot it belongs
## in (main_hand for tools/weapons, the tagged slot for apparel), stowing whatever
## it displaces. Returns Equipment.EquipResult.OK, or why nothing changed. Visual
## update is handled automatically by EquipmentVisualizer via Equipment.slot_changed.
func equip_item(item: ItemDef) -> Equipment.EquipResult:
	_ensure_equipment()
	return equipment.equip_from_inventory(item, inventory)


## Takes the item out of `slot_id` and puts it back in the inventory. Returns
## false (item stays equipped) when the slot is empty or the pack has no room.
func unequip_slot(slot_id: String) -> bool:
	_ensure_equipment()
	return equipment.unequip_to_inventory(slot_id, inventory)


## Convenience accessor — returns the item currently in main_hand, or null.
func get_equipped_item() -> ItemDef:
	if equipment == null:
		return null
	return equipment.get_item(Equipment.SLOT_MAIN_HAND)


func _ensure_equipment() -> void:
	## Auxiliary: Ensures Equipment and EquipmentVisualizer children exist and are wired.
	equipment = Equipment.ensure_on(self, equipment)


## Runs the equipped item's primary action unless it is still in its lockout. Only plays the
## animation once the action actually fires -- triggering on every input event restarted the
## one-shot mid-swing whenever the player clicked faster than the weapon's own lockout duration.
func _fire_equipped_action(equip_params: EquippableParams) -> void:
	if _equipped_action_cooldown > 0.0:
		return

	var action: EquipActionParams = equip_params.primary_action
	_equipped_action_cooldown = action.get_lockout_duration()

	# 1. Action Animation Trigger: Plays the item's use animation (or the generic interact) now that the action fires.
	var anim: StringName = equip_params.use_animation if equip_params.use_animation != &"" else &"Interact"
	trigger_animation_action(anim)

	action.execute(self)


func _on_primary_action() -> void:
	if is_input_locked() or mode != Mode.NORMAL or UiGate.is_input_blocked():
		return

	# 1. Equipped Item Action: Check and trigger main-hand tool or weapon primary action.
	if _try_execute_equipped_action():
		return

	# 2. World Interaction: A manual interaction on the crosshair target (foraging, farming, harvesting), else mining the terrain or block under it.
	interactor.primary_interact()


func _try_execute_equipped_action() -> bool:
	## Auxiliary: Runs the main-hand item's primary action. True when the item owns LMB (it has a
	## primary action, whether it fired or is still in its lockout, so a press inside the lockout is
	## swallowed rather than mining what is under the crosshair). False when nothing usable is held,
	## so LMB falls through to interaction and mining.
	var equip_params := _get_equipped_params()
	if equip_params == null or equip_params.primary_action == null:
		return false
	# 1. Action Fire: Cooldown-gated execution of the primary action with its animation.
	_fire_equipped_action(equip_params)
	return true


func _get_equipped_params() -> EquippableParams:
	## Auxiliary: The EquippableParams of the main-hand item, or null when the hand is empty or the item isn't equippable.
	var active_item: ItemDef = equipment.get_item(Equipment.SLOT_MAIN_HAND) if equipment != null else null
	return active_item.equippable if active_item != null else null


func _on_dig_box_toggle_pressed() -> void:
	# 1. Mode Toggle: Enters or leaves dig-box designation; the press is ignored in any other mode.
	_toggle_tool_mode(Mode.DIG_BOX_DESIGNATION)


func _on_area_designation_toggle_pressed() -> void:
	if is_input_locked():
		return
	if mode == Mode.AREA_DESIGNATION:
		# 1. Mode Exit: Leaves area designation and announces it, then reopens the menu for a quick tool swap.
		_exit_tool_mode(Mode.AREA_DESIGNATION)
		open_designation_menu()
	elif mode == Mode.NORMAL:
		open_designation_menu()


## Open the designation/orders menu (hotkey T). Selecting a tool closes it and enters
## Area/Designation 3D placement mode.
func open_designation_menu() -> void:
	if _designation_menu != null:
		return
	# 1. Menu Layer Resolution: Find the hud_layer (else ui_layer) CanvasLayer, or create a fallback for scenes without one.
	var layer: CanvasLayer = _resolve_menu_layer()
	# 2. Designation Menu Instantiation: Mount and wire signals for designation menu modal.
	_mount_designation_menu(layer)


func _mount_designation_menu(layer: CanvasLayer) -> void:
	## Auxiliary: Mounts and wires signals for the designation orders menu modal.
	var menu: DesignationMenu = preload("res://ui/designation_menu/designation_menu.tscn").instantiate()
	layer.add_child(menu)
	menu.closed.connect(_on_designation_menu_closed)
	_designation_menu = menu
	mode = Mode.DESIGNATION_MENU


func _on_area_designation_tool_selected(_tool_id: String, _target_area_id: String) -> void:
	# 1. Listener Teardown: Disconnects closed callback to ensure dismissal does not override active mode.
	_disconnect_designation_menu_closed()
	_designation_menu = null
	# 2. Mode Entry: Switches to area designation and announces it so its controller arms.
	_enter_tool_mode(Mode.AREA_DESIGNATION)


func _on_designation_menu_closed() -> void:
	_designation_menu = null
	mode = Mode.NORMAL


func _disconnect_designation_menu_closed() -> void:
	## Auxiliary: Disconnects the designation menu closed listener if currently wired.
	if _designation_menu != null and _designation_menu.closed.is_connected(_on_designation_menu_closed):
		_designation_menu.closed.disconnect(_on_designation_menu_closed)


func _on_harvest_box_toggle_pressed() -> void:
	# 1. Mode Toggle: Enters or leaves harvest-box designation; the press is ignored in any other mode.
	_toggle_tool_mode(Mode.HARVEST_BOX_DESIGNATION)


func _toggle_tool_mode(tool_mode: Mode) -> void:
	## Auxiliary: Hotkey toggle for a tool mode. Enters it from Normal, leaves it when already in it,
	## and ignores the press in every other mode so tool modes never stack.
	if is_input_locked():
		return
	if mode == tool_mode:
		_exit_tool_mode(tool_mode)
	elif mode == Mode.NORMAL:
		_enter_tool_mode(tool_mode)


func _get_wading_speed_multiplier() -> float:
	## Auxiliary: The drag of the fluid at the player's lower torso, from the running map's blocky
	## grid; 1.0 with no map (between maps there is nothing to wade in) or in a cell with no fluid.
	var grid := _get_current_blocky_grid()
	if grid == null:
		return 1.0
	# 1. Position Resolution: Resolves the voxel coordinates at the player's lower torso.
	var cell: Vector3i = _get_wading_cell()
	return grid.get_wading_speed_mult_at(cell)


func _get_current_blocky_grid() -> BlockyGrid:
	## Auxiliary: The blocky grid of the map SceneManager is running, or null between maps.
	var current_map := SceneManager.get_current_map() as Map
	return current_map.get_blocky_grid() if current_map != null else null


func _get_wading_cell() -> Vector3i:
	## Auxiliary: Resolves the voxel cell at the player's lower torso.
	return Vector3i(
		int(floor(global_position.x)),
		int(floor(global_position.y + _WADING_SAMPLE_HEIGHT)),
		int(floor(global_position.z))
	)
