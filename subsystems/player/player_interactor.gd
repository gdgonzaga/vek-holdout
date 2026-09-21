class_name PlayerInteractor
extends Node
## What the player does to the world under the crosshair (ARCH "Subsystem: Player"): tracks
## which InteractionComponent is being looked at, runs the E-key tap/hold paths on it, and
## resolves the world half of an LMB press (a manual interaction on the target, else mining
## the terrain or block under it). A child of the Player that the Player ticks explicitly
## (update_target every physics tick, before the motor moves the body), so it has no
## _physics_process of its own.
##
## What it does NOT own: the equipped item's primary action (Player owns equipment and its
## lockout, and runs that before handing LMB here), the input lock and mode gates for LMB
## (Player checks them once), and the animation controller (reached through the Player).
##
## Interactable ownership: the component only tracks and acts; the HUD owns the E tap-vs-hold
## timer and the label, and learns about target changes through interactable_changed.

## Emitted when the crosshair target changes (target gained or lost). The HUD's InteractLabel
## listens; execute_default_action also re-emits it after every tap so a status line re-reads.
signal interactable_changed(component: InteractionComponent)

## Max range for the crosshair raycast.
@export var interact_distance := 8.0

## The tool the bare hands mine with; per-swing damage lives on it (hard rule 1). An equipped
## pickaxe supplies its own DigToolParams here once equipped-tool mining lands (see DigToolParams).
@export var mining_tool: DigToolParams

## The coarse interaction box furniture and flora carry (a StaticBody3D on collision layer 5). The
## crosshair ray looks through it to reach the discrete items and colonists inside.
const _BUILD_BODY_NAME := "BuildBody"
const _BUILD_BODY_LAYER := 5

## How many bodies the crosshair ray may look through before it gives up.
const _MAX_RAY_STEPS := 6

var _player: Player
var _camera: Camera3D

## The InteractionComponent currently under the crosshair (or null).
var _current_interactable: InteractionComponent = null

## True from the moment a target is announced until it is cleared. Needed because a freed
## component compares equal to null in GDScript, so `_current_interactable != null` cannot tell
## "no target" from "the target was freed since it was announced".
var _has_target := false

## Cached raycast query and exclusion buffer to eliminate per-frame allocations during interaction scanning.
var _ray_query: PhysicsRayQueryParameters3D = null
var _ray_excluded_rids: Array[RID] = []


func _ready() -> void:
	set_physics_process(false)
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_bodies = true
	_ray_query.collide_with_areas = false


## Wires the collaborators the Player owns. Called by Player._ready.
func setup(player: Player, camera: Camera3D) -> void:
	_player = player
	_camera = camera


# =================
# Primary Functions
# =================

## Every-frame crosshair check. Updates the current target so the HUD can display what the
## player is looking at, and the E press can act on it.
func update_target() -> void:
	# 1. Dead Target Flush: A target freed since the last tick is announced lost before anything is compared against it.
	_has_live_target()
	if _player.mode != Player.Mode.NORMAL or UiGate.is_input_blocked():
		# 2. Target Reset: No crosshair target while a mode or modal owns the cursor, so the HUD label hides.
		clear_interactable()
		return
	# 3. Crosshair Raycast: What the screen-center ray strikes, with coarse build boxes seen through.
	var hit := _interaction_raycast()
	if hit.is_empty():
		# 4. Target Reset: Nothing under the crosshair, so drop the previous target and notify listeners.
		clear_interactable()
		return
	# 5. Component Lookup: The InteractionComponent owning the struck collider, if any.
	var component := _find_interaction_component(hit.collider)
	# 6. Options Refresh: Rebuilds the target's options so the HUD hint reflects its current state.
	_refresh_options(component)
	if component != _current_interactable:
		_current_interactable = component
		_has_target = component != null
		interactable_changed.emit(component)


## Clear the current interactable target and notify listeners (e.g. the HUD's
## InteractLabel) so they hide. Called by SceneManager.unload_current_map
## before the map (and its InteractionComponent children) is freed — otherwise
## the HUD keeps showing the last label over the title screen.
func clear_interactable() -> void:
	if _has_target:
		_current_interactable = null
		_has_target = false
		interactable_changed.emit(null)


## Execute the first action option immediately (quick-tap E).
func execute_default_action() -> void:
	if _player.is_input_locked() or not _has_live_target():
		return
	# 1. Options Refresh: Rebuilds the target's options so the first one reflects its current state.
	var target := _refresh_options(_current_interactable)
	if _current_interactable.action_options.is_empty():
		return
	var option: ActionOption = _current_interactable.action_options[0]
	if option.action == null:
		return
	# 2. Action Animation Trigger: Trigger interaction animation for default action.
	_player.trigger_animation_action(&"Interact")
	option.action.execute(_player, target)
	# 3. Target Validity: An action may consume its target (freeing the component with it), which is announced as a loss instead of handing listeners a dead object.
	if _has_live_target():
		interactable_changed.emit(_current_interactable)


## Open the full interaction menu for the targeted interactable (long-press E).
func open_interaction_menu() -> void:
	if _player.is_input_locked() or not _has_live_target():
		return
	# 1. Options Refresh: Rebuilds the target's options so the menu lists what is possible now.
	_refresh_options(_current_interactable)
	if _current_interactable.action_options.is_empty():
		return
	# 2. Action Animation Trigger: Trigger interaction animation for menu selection.
	_player.trigger_animation_action(&"Interact")
	_current_interactable.interact(_player)


## The world half of an LMB press: a manual interaction on the crosshair target if it supports
## one (foraging, farming, harvesting), otherwise mining the terrain or block under it. The
## Player has already checked its gates and given an equipped item first refusal.
func primary_interact() -> void:
	# 1. Focused Interactable Action: Check if crosshair target supports direct actions like foraging or farming.
	if _try_interact_current_target():
		return
	# 2. Terrain Mining Action: Raycast forward to mine voxel terrain or placed blocks under crosshair.
	_try_mine_terrain()


# ===================
# Auxiliary Functions
# ===================

func _has_live_target() -> bool:
	## Auxiliary: True when there is a current target that still exists. A freed one (its owner was
	## removed since the last tick, or by the action just run) is dropped and announced lost through
	## clear_interactable, so listeners never see a dead component.
	if not _has_target:
		return false
	if is_instance_valid(_current_interactable):
		return true
	clear_interactable()
	return false


func _refresh_options(component: InteractionComponent) -> Node:
	## Auxiliary: Asks the component's owner to rebuild its interaction options (owners that have
	## dynamic ones, like a blueprint's remaining cost, expose refresh_interaction_options) and
	## returns that owner, or null with no component.
	if component == null:
		return null
	var target := component.get_parent()
	if target != null and target.has_method("refresh_interaction_options"):
		target.refresh_interaction_options()
	return target


## Screen-center physics raycast for interaction. Returns the raw hit dict
## (empty if nothing struck). Shared by update_target and mining.
func _interaction_raycast() -> Dictionary:
	if _camera == null:
		return {}
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	var space := _player.get_world_3d().direct_space_state
	_ray_query.from = origin
	_ray_query.to = origin + dir * interact_distance

	# 1. Multi-Hit Resolution: Resolve discrete WorldItems or Colonists prioritized through coarse BuildBody bounding boxes.
	return _resolve_best_interaction_hit(space, _ray_query)


func _resolve_best_interaction_hit(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	## Auxiliary: Performs sequential raycasts to detect discrete items or colonists occluded by coarse BuildBody boxes.
	_ray_excluded_rids.clear()
	_ray_excluded_rids.append(_player.get_rid())
	query.exclude = _ray_excluded_rids

	var first_hit: Dictionary = {}
	for _i in range(_MAX_RAY_STEPS):
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break

		var collider: Node = hit.collider as Node
		if collider == null:
			break

		# Record the initial hit as baseline fallback
		if first_hit.is_empty():
			first_hit = hit

		# Direct hit on discrete interactable entity (WorldItem or Colonist)
		if collider is WorldItem or collider.get_parent() is WorldItem or collider is Colonist:
			return hit

		# If colliding with a coarse interaction bounding box (BuildBody on Layer 5), exclude and continue
		if collider is CollisionObject3D:
			var col_obj := collider as CollisionObject3D
			if col_obj.name == _BUILD_BODY_NAME or col_obj.get_collision_layer_value(_BUILD_BODY_LAYER):
				_ray_excluded_rids.append(col_obj.get_rid())
				query.exclude = _ray_excluded_rids
				continue

		# Hit opaque physical geometry (terrain or solid structure), cannot see through
		break

	return first_hit


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


func _try_interact_current_target() -> bool:
	## Auxiliary: Dispatches manual action to currently focused interactable entity.
	if not _has_live_target():
		return false
	var target := _current_interactable.get_parent()
	if target == null:
		return false

	# 1. Wild Flora Interaction: Check if target is forageable wild flora.
	if _try_forage_flora(target):
		return true

	# 2. Farming Plot Interaction: Check if target is a tendable growable plot.
	if _try_tend_farm(target):
		return true

	# 3. Harvest Interaction: Check if target has a ready harvestable component.
	return _try_harvest_crop(target)


func _try_forage_flora(target: Node) -> bool:
	## Auxiliary: Triggers foraging on wild flora targets.
	var flora := target as WildFlora
	if flora != null and flora.can_forage():
		# 1. Manual Action: Plays the interaction animation and runs the forage action.
		_run_manual_action(ForageAction.new(), target)
		return true
	return false


func _try_tend_farm(target: Node) -> bool:
	## Auxiliary: Triggers manual tending on farm plots with Growable component.
	var growable := target.get_node_or_null("Growable") as Growable
	if growable != null:
		# 1. Manual Action: Plays the interaction animation and runs the tending action.
		_run_manual_action(FarmManualAction.new(), target)
		return true
	return false


func _try_harvest_crop(target: Node) -> bool:
	## Auxiliary: Triggers manual crop harvest on targets with Harvestable component.
	var harvestable := target.get_node_or_null("Harvestable") as Harvestable
	if harvestable != null:
		# 1. Manual Action: Plays the interaction animation and runs the harvest action.
		_run_manual_action(HarvestAction.new(), target)
		return true
	return false


func _run_manual_action(action: GameAction, target: Node) -> void:
	## Auxiliary: Plays the interaction animation, then runs `action` on `target` as the player.
	_player.trigger_animation_action(&"Interact")
	action.execute(_player, target)


func _try_mine_terrain() -> void:
	## Auxiliary: Performs interaction raycast and damages the grid that owns the struck collider.
	var hit := _interaction_raycast()
	if hit.is_empty():
		return

	var collider: Node = hit.collider as Node
	var hit_normal: Vector3 = hit.normal
	var hit_in: Vector3 = hit.position - hit_normal * 0.1
	var target_cell := Vector3i(int(floor(hit_in.x)), int(floor(hit_in.y)), int(floor(hit_in.z)))

	# 1. Grid Ownership: The grid the struck collider belongs to; null for bodies no grid owns (furniture, colonists), which mining must ignore.
	var grid := _find_struck_grid(collider)

	# 2. Smooth Voxel Mining: Damage smooth voxel terrain if the struck collider belongs to the SmoothGrid.
	if _try_damage_smooth_grid(grid, target_cell, hit_normal):
		return

	# 3. Blocky Grid Mining: Damage the blocky cell if the struck collider belongs to the BlockyGrid and a block exists there.
	_try_damage_blocky_grid(grid, target_cell)


func _try_damage_smooth_grid(grid: Node, target_cell: Vector3i, hit_normal: Vector3) -> bool:
	## Auxiliary: Applies mining damage to smooth terrain if `grid` is a SmoothGrid.
	var smooth := grid as SmoothGrid
	if smooth != null:
		_player.trigger_animation_action(&"Digging")
		smooth.apply_damage_at(target_cell, mining_tool.swing_damage, _player, hit_normal)
		return true
	return false


func _try_damage_blocky_grid(grid: Node, target_cell: Vector3i) -> bool:
	## Auxiliary: Applies mining damage to the blocky grid if `grid` is a BlockyGrid holding a block at the cell.
	var blocky := grid as BlockyGrid
	if blocky != null and blocky.has_block_at(target_cell):
		_player.trigger_animation_action(&"Digging")
		blocky.apply_damage(target_cell, mining_tool.swing_damage)
		return true
	return false


func _find_struck_grid(collider: Node) -> Node:
	## Auxiliary: The nearest SmoothGrid or BlockyGrid ancestor of `collider`. Stops at the first
	## grid instead of continuing up to the Map, which owns both grids and would claim every body under it.
	var current := collider
	while current != null:
		if current is SmoothGrid or current is BlockyGrid:
			return current
		current = current.get_parent()
	return null
