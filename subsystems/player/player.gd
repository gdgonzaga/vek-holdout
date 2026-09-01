class_name Player
extends CharacterBody3D
## Minimal third-person controller (ARCH "Subsystem: Player").
##
## This build covers only walk + gravity + mouse-look. The Mode/State enums and
## the full state set are defined now so later features (sprint, attack, build
## mode...) fill in without restructuring. Movement references no stat components
## yet — Breath/Stamina/Health attach later as child nodes the code can opt into.
##
## TODO when CharacterDef lands: source move_speed/gravity from
## data/characters/player.tres instead of these exports (ARCH: no hardcoded
## content values). Exported for now so they're editor-tunable.

enum Mode {NORMAL, BUILD_MENU, BUILD_PLACEMENT, DIG_BOX_DESIGNATION}
enum State {IDLE, WALK, SPRINT, ATTACK, INTERACT, SLEEP, DEAD}

@export var walk_speed := 3.5
@export var sprint_speed := 7
@export var gravity := 9.8
@export var jump_force := 5.0
@export var jump_move_speed := 0.5
@export var interact_distance := 8.0

var mode := Mode.NORMAL
var state := State.IDLE

## True while a timed action (e.g. a BuildAction with a build_time) holds the
## player. While busy, movement, jump, and discrete actions (interact, build
## menu) are ignored — see the _busy guards in _handle_move_keys, _handle_jump,
## execute_default_action, open_interaction_menu, _on_build_key_pressed.
var _busy := false

## The InteractionComponent currently under the crosshair (or null).
var _current_interactable: InteractionComponent = null

## The currently open BuildMenu (null when no menu is open). Tracked so B can
## close it and so we know whether B means "open" or "close".
var _build_menu: BuildMenu = null

## Emitted when _current_interactable changes (target gained or lost).
signal interactable_changed(component: InteractionComponent)

@onready var _input: InputComponent = $InputComponent
@onready var _rig: CameraRig = $CameraRig
@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _camera: Camera3D = _rig.get_camera()
@onready var inventory: CharacterInventory = $Inventory

## The item currently equipped by the player (null if empty).
var equipped_item: ItemDef = null
var _equipped_action_cooldown: float = 0.0

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
## Returns the created WorldItem entity (or null if item wasn't carried).
func drop_item(item_id: String, count: int = 1) -> WorldItem:
	if inventory == null or not inventory.has_item(item_id, count):
		return null
	var removed := inventory.remove(item_id, count)
	var dropped_count := count - removed
	if dropped_count <= 0:
		return null

	if equipped_item != null and equipped_item.id == item_id and not inventory.has_item(item_id, 1):
		unequip_item()

	var forward := -global_transform.basis.z
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


# --- SaveSystem contract -----------------------------------------------------
# Transform + camera orientation + carried inventory. Movement mode/state and
# the transient interactable target are NOT persisted. Assumes the player (and
# its CameraRig) is ready — set_orientation touches the rig's spring arm.

## Snapshot position, camera yaw/pitch, and inventory stacks.
func serialize() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"cam_yaw": _rig.get_yaw(),
		"cam_pitch": _rig.get_pitch(),
		"inventory": inventory.serialize(),
	}


## Restore position, camera orientation, and inventory from a serialize() dict.
func deserialize(data: Dictionary) -> void:
	velocity = Vector3.ZERO
	_velocity_on_jump = Vector3.ZERO
	_speed_on_jump = 0.0
	_was_on_floor = true
	var p: Array = data.get("pos", [global_position.x, global_position.y, global_position.z])
	global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_rig.set_orientation(float(data.get("cam_yaw", 0.0)), float(data.get("cam_pitch", -0.25)))
	_rig.snap_to_target()
	if data.has("inventory"):
		inventory.deserialize(data["inventory"])
	var guard := get_node_or_null("GroundSafetyGuard") as GroundSafetyGuard
	if guard != null:
		guard.rearm()


var _velocity_on_jump := Vector3.ZERO # horizontal world-velocity frozen at jump (y=0)
var _speed_on_jump := 0.0 # walk_speed or sprint_speed, frozen at takeoff
var _is_sprinting_on_jump := false
var _was_on_floor := true

func _ready() -> void:
	add_to_group("player")
	GameState.set_local_player(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_max_angle = deg_to_rad(60.0)
	# SkillSet child (skill catalog loads in its own _ready; unseeded = all L1).
	var skills := SkillSet.new()
	skills.name = "SkillSet"
	add_child(skills)
	skill_set = skills
	# React to a buildable selection (emitted by the build menu) by entering
	# Blueprint mode + recapturing the mouse. The selected id itself goes straight
	# to BuildController via the same signal — Player doesn't carry it.
	EventBus.buildable_selected.connect(_on_buildable_selected)
	# Wire discrete input actions from the InputComponent child.
	_input.build_toggle_pressed.connect(_on_build_key_pressed)
	_input.primary_action_pressed.connect(_on_primary_action)
	_input.recapture_requested.connect(_recapture_mouse)
	_input.ui_cancel_pressed.connect(_on_ui_cancel)
	_input.dig_box_toggle_pressed.connect(_on_dig_box_toggle_pressed)

func _exit_tree() -> void:
	if GameState.get_local_player() == self:
		GameState.set_local_player(null)



## Blueprint key routing (GDD §4 controls table):
##   - B in Normal    -> open the build menu
##   - B in Placement -> back to the build menu (quick item swap)
## The menu itself consumes B and Esc while it's open (it registers with UiGate,
## which gates InputComponent), and Esc exits placement straight to Normal.
func _on_build_key_pressed() -> void:
	if _busy:
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
	var menu: BuildMenu = preload("res://ui/build_menu/build_menu.tscn").instantiate()
	# Mount on a UI CanvasLayer. Prefer the one Main owns; fall back to creating one
	# under the world root so this works in test scenes without Main.
	var layer := get_tree().get_first_node_in_group("ui_layer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "UILayer"
		# Add high enough to render above the world but below the HUD overlay.
		layer.layer = 20
		get_tree().current_scene.add_child(layer)
	layer.add_child(menu)
	menu.populate()
	# The menu registers with UiGate on _ready, which shows the cursor so the
	# player can click entries. Selection is broadcast via EventBus (menu emits
	# directly); only the no-selection dismissal is handled locally.
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
	mode = Mode.BUILD_PLACEMENT
	EventBus.build_placement_toggled.emit(true)


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
	if mode == Mode.BUILD_PLACEMENT:
		get_viewport().set_input_as_handled()
		mode = Mode.NORMAL
		EventBus.build_placement_toggled.emit(false)
	elif mode == Mode.DIG_BOX_DESIGNATION:
		get_viewport().set_input_as_handled()
		mode = Mode.NORMAL
		EventBus.dig_box_toggled.emit(false)


## Leave placement and reopen the build menu (B in placement — quick item swap).
## Esc exits placement straight to Normal instead (see _on_ui_cancel).
func _exit_build_placement_mode() -> void:
	mode = Mode.BUILD_MENU
	EventBus.build_placement_toggled.emit(false)


## Execute the first action option immediately (quick-tap E).
func execute_default_action() -> void:
	if _busy:
		return
	if _current_interactable and not _current_interactable.action_options.is_empty():
		var option: ActionOption = _current_interactable.action_options[0]
		if option.action != null:
			option.action.execute(self, _current_interactable.get_parent())
			interactable_changed.emit(_current_interactable)


## Open the full interaction menu for the targeted interactable (long-press E).
func open_interaction_menu() -> void:
	if _busy:
		return
	if _current_interactable and not _current_interactable.action_options.is_empty():
		_current_interactable.interact(self)


## Screen-center physics raycast for interaction. Returns the raw hit dict
## (empty if nothing struck). Shared by _update_interaction_target.
func _interaction_raycast() -> Dictionary:
	if _camera == null:
		return {}
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * interact_distance)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	return space.intersect_ray(query)


## Every-frame crosshair check. Updates _current_interactable so the HUD can
## display what the player is looking at, and E press can act on it.
func _update_interaction_target() -> void:
	if mode != Mode.NORMAL or UiGate.is_input_blocked():
		if _current_interactable != null:
			_current_interactable = null
			interactable_changed.emit(null)
		return
	var hit := _interaction_raycast()
	if hit.is_empty():
		if _current_interactable != null:
			_current_interactable = null
			interactable_changed.emit(null)
		return
	var component := _find_interaction_component(hit.collider)
	if component != _current_interactable:
		_current_interactable = component
		interactable_changed.emit(component)


## Clear the current interactable target and notify listeners (e.g. the HUD's
## InteractLabel) so they hide. Called by SceneManager.unload_current_map
## before the map (and its InteractionComponent children) is freed — otherwise
## the HUD keeps showing the last label over the title screen.
func clear_interactable() -> void:
	if _current_interactable != null:
		_current_interactable = null
		interactable_changed.emit(null)


## Walk up from the hit collider looking for a sibling InteractionComponent.
## Handles any nesting depth (RigidBody3D > MeshInstance3D > CollisionShape, etc.).
func _find_interaction_component(node: Node) -> InteractionComponent:
	var current: Node = node
	while current != null:
		var component := current.get_node_or_null("InteractionComponent") as InteractionComponent
		if component:
			return component
		current = current.get_parent()
	return null


func _physics_process(delta: float) -> void:
	if _equipped_action_cooldown > 0.0:
		_equipped_action_cooldown -= delta
	_update_interaction_target()
	_handle_move_keys(delta)
	_handle_jump()

func _handle_move_keys(delta: float) -> void:
	var grounded := is_on_floor()
	if not grounded:
		velocity.y -= gravity * delta
		if _was_on_floor and not _input.wants_jump():
			# Leaving ground without jumping (e.g. walking down stairs / stepping off a ledge):
			# Capture horizontal ground momentum so walking down ledges preserves walking speed.
			_velocity_on_jump = _camera_relative_wish(_input.get_movement_input())
			_speed_on_jump = sprint_speed if _input.wants_sprint() else walk_speed
			_is_sprinting_on_jump = _input.wants_sprint()
	_was_on_floor = grounded

	# Horizontal wish-velocity in WORLD space.
	# Ground: fresh each frame from camera-relative WASD.
	# Mid-air: starts from the frozen jump velocity; keys only BRAKE it (remove the
	# component opposing the held direction) — they never re-project the stored
	# vector, so rotating the camera mid-air can't curve movement. Keys are still
	# read relative to the live camera (W still means "away from where I look"),
	# but only to decide which component of the world-velocity to kill.
	var wish := Vector3.ZERO

	# A busy player can't drive movement — wish stays zero so velocity is wiped
	# below (gravity still applies so they stay planted on the ground).
	if not _busy:
		if is_on_floor():
			# Ground: camera-relative WASD, normalized, projected to world.
			var input := _input.get_movement_input()
			wish = _camera_relative_wish(input)
		else:
			# Mid-air: the two cardinal axes (forward/back, strafe) are resolved
			# INDEPENDENTLY, each against the captured world-momentum projected onto
			# the live camera directions. Keys are read relative to the live camera
			# (W = away from where you look now); momentum stays world-locked, so
			# rotating the camera mid-air can't curve movement.
			var basis := _rig.global_transform.basis
			var cam_fwd := (-basis.z)
			cam_fwd.y = 0.0
			cam_fwd = cam_fwd.normalized()
			var cam_right := basis.x
			cam_right.y = 0.0
			cam_right = cam_right.normalized()

			var air_input := _input.get_movement_input()

			# Resolve each axis to a signed scalar (positive = cam_fwd / cam_right).
			var fwd := _resolve_air_axis(
				air_input.y > 0.0, # backward component
				air_input.y < 0.0, # forward component
				_velocity_on_jump.dot(cam_fwd)
			)
			var strafe := _resolve_air_axis(
				air_input.x < 0.0, # left component
				air_input.x > 0.0, # right component
				_velocity_on_jump.dot(cam_right)
			)
			wish = cam_fwd * fwd + cam_right * strafe

	# Speed scalar: ground uses the live sprint key; air uses the speed frozen at
	# takeoff so holding/releasing Shift mid-air can't rescale preserved momentum.
	var speed: float
	if is_on_floor():
		speed = sprint_speed if _input.wants_sprint() else walk_speed
	else:
		speed = _speed_on_jump
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed

	move_and_slide()

	# Movement state + visual facing (CharacterBody3D itself never rotates, so the
	# camera rig's orbit is decoupled from where the avatar looks).
	if wish.length_squared() > 0.001:
		# SPRINT only while grounded + sprinting; mid-air carries momentum but
		# isn't "sprinting" (state reflects what the avatar is doing, not what it
		# did at takeoff).
		var sprinting := is_on_floor() and _input.wants_sprint()
		state = State.SPRINT if sprinting else State.WALK
		_mesh.look_at(_mesh.global_position + wish, Vector3.UP)
	else:
		state = State.IDLE


func _handle_jump() -> void:
	if _busy:
		return
	if not is_on_floor():
		return

	if _input.wants_jump():
		velocity.y = jump_force

		# Capture horizontal wish-velocity in WORLD space at the jump instant. This
		# is frozen for the whole jump — mid-air keys only brake it, never
		# re-project it, so rotating the camera mid-air can't curve movement.
		_velocity_on_jump = _camera_relative_wish(_input.get_movement_input())
		# Freeze the takeoff speed so a sprint-jump carries sprint-scale momentum
		# for the whole jump (mid-air Shift can't change it).
		_speed_on_jump = sprint_speed if _input.wants_sprint() else walk_speed
		
		_is_sprinting_on_jump = _input.wants_sprint()


## Project a camera-relative input Vector2 to a horizontal WORLD wish-vector.
## Used by both ground movement and the jump-momentum capture so they share one
## source of truth for the camera basis math.
## Sign convention (from the Vector2 gathering above):
##   input.y < 0 = forward, input.y > 0 = backward, input.x = strafe (right +).
func _camera_relative_wish(input: Vector2) -> Vector3:
	var basis := _rig.global_transform.basis
	var forward := (-basis.z)
	forward.y = 0.0
	forward = forward.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	return forward * -input.y + right * input.x


## Resolve ONE mid-air cardinal axis to a signed scalar.
## - `neg_held`: is the key driving this axis negative held? (backward / left)
## - `pos_held`: is the key driving this axis positive held? (forward / right)
## - `momentum`: this axis's captured world-momentum component (sign = direction)
## Returns a positive value toward the positive key, negative toward the negative.
##
## Per-axis rule (axes are independent):
##   both keys held            -> 0      (cancel)
##   pos held, momentum > 0    -> momentum (preserve — you jumped that way)
##   pos held, momentum <= 0   -> +jump_move_speed (nudge / brake toward pos)
##   neg held, momentum < 0    -> momentum (preserve)
##   neg held, momentum >= 0   -> -jump_move_speed (nudge / brake toward neg)
##   neither held              -> 0      (snap stop on this axis, no coasting)
func _resolve_air_axis(neg_held: bool, pos_held: bool, momentum: float) -> float:
	if neg_held and pos_held:
		return 0.0 # conflicting input cancels the axis
	if pos_held:
		return momentum if momentum > 0.0 else jump_move_speed
	if neg_held:
		return momentum if momentum < 0.0 else -jump_move_speed
	return 0.0 # released -> axis stops dead

## Equip an item to the player.
func equip_item(item: ItemDef) -> void:
	equipped_item = item


## Unequip the player's current item.
func unequip_item() -> void:
	equipped_item = null


## Execute the equipped item's primary action.
func _execute_equipped_primary_action() -> void:
	if equipped_item == null or not equipped_item.is_equippable():
		return
	var equip_params: EquippableParams = equipped_item.equippable
	if equip_params == null or equip_params.primary_action == null:
		return
	if _equipped_action_cooldown > 0.0:
		return

	var action: EquipActionParams = equip_params.primary_action
	_equipped_action_cooldown = action.cooldown_seconds
	action.execute(self)


func _on_primary_action() -> void:
	if _busy or mode != Mode.NORMAL or UiGate.is_input_blocked():
		return

	if equipped_item != null and equipped_item.is_equippable():
		_execute_equipped_primary_action()
		return

	if _current_interactable != null:
		var target := _current_interactable.get_parent()
		if target != null:
			var growable := target.get_node_or_null("Growable") as Growable
			if growable != null:
				var farm_action := FarmManualAction.new()
				farm_action.execute(self, target)
				return
			var harvestable := target.get_node_or_null("Harvestable") as Harvestable
			if harvestable != null:
				var action := HarvestAction.new()
				action.execute(self, target)
				return

	# Direct terrain / block mining with LMB from crosshair
	var hit := _interaction_raycast()
	if hit.is_empty():
		return

	var collider: Node = hit.collider as Node
	var hit_normal: Vector3 = hit.normal
	var hit_in: Vector3 = hit.position - hit_normal * 0.1
	var target_cell := Vector3i(int(floor(hit_in.x)), int(floor(hit_in.y)), int(floor(hit_in.z)))

	var smooth := _find_smooth_grid(collider)
	if smooth != null:
		smooth.apply_damage_at(target_cell, 50, self, hit_normal)
		return

	var blocky := _find_blocky_grid(collider)
	if blocky != null and blocky.has_block_at(target_cell):
		blocky.apply_damage(target_cell, 50)
		return


func _find_smooth_grid(node: Node) -> SmoothGrid:
	var cur: Node = node
	while cur != null:
		if cur is SmoothGrid:
			return cur
		if cur is Map:
			return (cur as Map).get_smooth_grid()
		cur = cur.get_parent()
	if SceneManager != null:
		var current_map := SceneManager.get_current_map()
		if current_map != null:
			return current_map.get_smooth_grid()
	return null


func _find_blocky_grid(node: Node) -> BlockyGrid:
	var cur: Node = node
	while cur != null:
		if cur is BlockyGrid:
			return cur
		if cur is Map:
			return (cur as Map).get_blocky_grid()
		cur = cur.get_parent()
	if SceneManager != null:
		var current_map := SceneManager.get_current_map()
		if current_map != null:
			return current_map.get_blocky_grid()
	return null


func _on_dig_box_toggle_pressed() -> void:
	if _busy:
		return
	if mode == Mode.DIG_BOX_DESIGNATION:
		mode = Mode.NORMAL
		EventBus.dig_box_toggled.emit(false)
	elif mode == Mode.NORMAL:
		mode = Mode.DIG_BOX_DESIGNATION
		EventBus.dig_box_toggled.emit(true)
