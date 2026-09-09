
extends CharacterBody3D
class_name Colonist

@export var colonist_def: ColonistDef = preload("res://data/colonists/default_colonist.tres")
@export var gravity: float = 9.8
var colonist_id: String
var display_name: String
var labor_priorities: Dictionary
var raid_stance: int
var current_job: Variant = null
var squad_id: String = ""
var skill_set: SkillSet
var stamina_component: StaminaComponent
var pathfinder: VoxelPathfinder

## LimboAI / Utility AI components
var needs: ColonistNeeds
var brain: ColonistBrain
var bt_player: BTPlayer

## Carry inventory (materials hauled to blueprints, etc.). Created in _ready so
## Blueprint.deposit_from(self) works unchanged — it calls actor.remove_item,
## which the Player has via the same CharacterInventory pattern (player.gd).
var inventory: CharacterInventory

# Path-following locomotion. Waypoints are fed by VoxelPathfinder (Phase 3) /
# ColonistAI (Phase 4); until then set_path() can be driven manually to verify
# movement. Mirrors Player's gravity + move_and_slide kernel.
const _ARRIVAL_THRESHOLD: float = 0.2
const _STEP_ARRIVAL_THRESHOLD: float = 0.08
var _path: Array[Vector3] = []
var _path_index: int = 0

var _stuck_timer: float = 0.0
var _wiggle_timer: float = 0.0
var _wiggle_dir: Vector3 = Vector3.ZERO

var _current_hp: int = 100
var _is_dead: bool = false
var equipped_item: ItemDef = null
@onready var interaction: InteractionComponent = get_node_or_null("InteractionComponent") as InteractionComponent

func _ready() -> void:
	add_to_group("colonists")
	colonist_id = Tools.generate_uuid()
	if display_name == "" and colonist_def != null:
		display_name = colonist_def.display_name
	labor_priorities = colonist_def.default_labor_priorities
	raid_stance = colonist_def.default_raid_stance
	current_job = null
	skill_set = $SkillSet
	skill_set.seed(colonist_def.starting_skills)
	stamina_component = $StaminaComponent
	pathfinder = $VoxelPathfinder
	
	# Resolve or initialize AI components
	needs = get_node_or_null("ColonistNeeds") as ColonistNeeds
	if not needs:
		needs = ColonistNeeds.new()
		needs.name = "ColonistNeeds"
		add_child(needs)
		
	brain = get_node_or_null("ColonistBrain") as ColonistBrain
	if not brain:
		brain = ColonistBrain.new()
		brain.name = "ColonistBrain"
		add_child(brain)
		
	bt_player = get_node_or_null("BTPlayer") as BTPlayer
	if not bt_player:
		bt_player = BTPlayer.new()
		bt_player.name = "BTPlayer"
		var tree_res: BehaviorTree = load("res://data/ai/trees/colonist_root.tres") as BehaviorTree
		if tree_res:
			bt_player.behavior_tree = tree_res
		add_child(bt_player)
	brain.bt_player = bt_player
	
	# Carry inventory: code-created (mirrors Player's scene-placed CharacterInventory)
	# so this stays a script-only change. CharacterInventory._ready recalc's capacity
	# on enter-tree, so add_child before any hauler reads it.
	var inv := CharacterInventory.new()
	inv.name = "Inventory"
	add_child(inv)
	inventory = inv
	_current_hp = colonist_def.max_hp
	floor_max_angle = deg_to_rad(60.0)
	if interaction == null:
		interaction = get_node_or_null("InteractionComponent") as InteractionComponent
	if interaction == null:
		interaction = InteractionComponent.new()
		interaction.name = "InteractionComponent"
		add_child(interaction)
	refresh_interaction_options()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	_follow_path(delta)
	move_and_slide()


## Feed a world-space waypoint path (from VoxelPathfinder, Phase 3). Resets any
## in-progress path. An empty path leaves the colonist standing.
func set_path(path: Array) -> void:
	# assign() copies elements into the typed Array[Vector3] with per-element
	# checks; a bare duplicate() returns an untyped Array, which 4.7 won't assign
	# to a typed var.
	_path.assign(path)
	_path_index = 0
	_stuck_timer = 0.0
	_wiggle_timer = 0.0


## True when every waypoint has been consumed (or no path was set).
func has_arrived() -> bool:
	return _path_index >= _path.size()


func _follow_path(delta: float) -> void:
	if _path_index >= _path.size():
		velocity.x = 0.0
		velocity.z = 0.0
		_stuck_timer = 0.0
		_wiggle_timer = 0.0
		return
	var to_target: Vector3 = _path[_path_index] - global_position
	to_target.y = 0.0 # navigate on the horizontal plane

	# Enforce tight arrival threshold on vertical steps and ramp transitions
	# so the colonist capsule (radius 0.3m) reaches the cell center and fully
	# clears the opening/riser before turning toward subsequent waypoints.
	var threshold := _ARRIVAL_THRESHOLD
	var has_prev_step := _path_index > 0 and absf(_path[_path_index].y - _path[_path_index - 1].y) > 0.2
	var has_next_step := _path_index + 1 < _path.size() and absf(_path[_path_index + 1].y - _path[_path_index].y) > 0.2
	if has_prev_step or has_next_step:
		threshold = _STEP_ARRIVAL_THRESHOLD

	if to_target.length() <= threshold:
		_path_index += 1
		_stuck_timer = 0.0
		_wiggle_timer = 0.0
		if _path_index >= _path.size():
			velocity.x = 0.0
			velocity.z = 0.0
			return
		to_target = _path[_path_index] - global_position
		to_target.y = 0.0
	var dir: Vector3 = to_target.normalized()
	var speed: float = colonist_def.base_move_speed
	
	if _wiggle_timer > 0.0:
		_wiggle_timer -= delta
		dir = _wiggle_dir
	else:
		var horiz_vel := Vector2(velocity.x, velocity.z)
		if is_on_wall() and horiz_vel.length_squared() < (speed * 0.1) ** 2:
			_stuck_timer += delta
			if _stuck_timer > 0.3:
				_stuck_timer = 0.0
				_wiggle_timer = 0.4 + randf() * 0.2
				var wall_normal := get_wall_normal()
				wall_normal.y = 0.0
				if wall_normal.length_squared() > 0.01:
					wall_normal = wall_normal.normalized()
					var tangent := Vector3(wall_normal.z, 0, -wall_normal.x)
					if tangent.dot(dir) < 0:
						tangent = - tangent
					_wiggle_dir = (tangent + wall_normal * 0.5).normalized()
				else:
					var angle := randf() * TAU
					_wiggle_dir = Vector3(cos(angle), 0, sin(angle))
		else:
			_stuck_timer = maxf(0.0, _stuck_timer - delta)

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed


func take_damage(amount: int, source: Node) -> void:
	if _is_dead:
		return
	_current_hp -= amount

	# 1. Damage Visuals: Spawning big red impact particles on colonist damage.
	_spawn_big_red_hit_effect(false)

	if _current_hp <= 0:
		_current_hp = 0
		_die()


func heal(amount: int) -> void:
	if _is_dead:
		return
	_current_hp = clamp(_current_hp + amount, 0, colonist_def.max_hp)


func get_hp() -> int:
	return _current_hp


func get_max_hp() -> int:
	return colonist_def.max_hp if colonist_def != null else 100


func _die() -> void:
	_is_dead = true

	# 1. Death Visuals: Spawning big red death particle burst on colonist death.
	_spawn_big_red_hit_effect(true)

	EventBus.colonist_died.emit(colonist_id)


## Auxiliary: Spawns big red particle visual effect at colonist location on taking damage or dying
func _spawn_big_red_hit_effect(is_death: bool = false) -> void:
	if get_tree() == null or not is_inside_tree():
		return

	var tree := get_tree()
	var scene_root: Node = tree.current_scene if tree.current_scene != null else get_parent()
	if scene_root == null:
		return

	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0 if is_death else 60.0
	mat.initial_velocity_min = 4.0 if is_death else 2.5
	mat.initial_velocity_max = 8.0 if is_death else 5.5
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.15 if is_death else 0.12
	mat.scale_max = 0.35 if is_death else 0.25
	mat.color = Color(0.95, 0.05, 0.05)

	var draw_mesh := BoxMesh.new()
	var mesh_size: float = 0.18 if is_death else 0.12
	draw_mesh.size = Vector3(mesh_size, mesh_size, mesh_size)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(0.95, 0.05, 0.05)
	draw_mesh.material = draw_mat

	particles.process_material = mat
	particles.draw_pass_1 = draw_mesh
	particles.amount = 24 if is_death else 14
	particles.lifetime = 0.35
	particles.one_shot = true
	particles.explosiveness = 1.0

	scene_root.add_child(particles)
	var spawn_pos := global_position + Vector3(0, 1.0, 0)
	particles.global_position = spawn_pos
	particles.emitting = true

	var timer := tree.create_timer(0.4)
	timer.timeout.connect(particles.queue_free)



func set_labor_priority(labor_id: String, priority: int) -> void:
	labor_priorities[labor_id] = clampi(priority, 0, 5)


func set_raid_stance(stance: int) -> void:
	# TODO: Add a guard vs configured min/max values
	raid_stance = stance


# --- Stat & Moodlet queries --------------------------------------------------

## Returns the normalized (0.0 to 1.0) ratio for a given stat, or -1.0 if not found/uninitialized.
func get_stat_ratio(stat_name: StringName) -> float:
	# 1. Primary Resolution: Match against health, stamina, or dynamic need levels.
	return _resolve_stat_ratio(stat_name)


## Returns the raw scalar value for a given stat, or -1.0 if not found/uninitialized.
func get_stat_value(stat_name: StringName) -> float:
	# 1. Raw Resolution: Query raw numerical value for health, stamina points, or need levels.
	return _resolve_stat_value(stat_name)


## Returns the current active activity of the colonist (e.g. &"idle", &"mining", &"eat").
func get_current_activity() -> StringName:
	# 1. Activity Resolution: Inspect behavior tree goals and assigned job state to derive active activity.
	return _resolve_current_activity()


## Returns all currently active moodlets evaluated from colonist_def.moodlet_defs in order.
## Each element is a Dictionary: { "def": MoodletDef, "index": int, "texture": Texture2D, "name": String }
func get_active_moodlets() -> Array[Dictionary]:
	if colonist_def == null or colonist_def.moodlet_defs.is_empty():
		return []
	
	# 1. Moodlet Collection: Iterate and collect active moodlets from definitions.
	return _evaluate_all_moodlets()


func _resolve_stat_ratio(stat_name: StringName) -> float:
	## Auxiliary: Resolves normalized 0.0 to 1.0 ratio for health, stamina, or needs.
	match stat_name:
		&"hp", &"health":
			var max_health: int = get_max_hp()
			return float(_current_hp) / float(max_health) if max_health > 0 else 0.0
		&"stamina":
			if stamina_component != null and stamina_component.max_stamina > 0.0:
				return stamina_component.current_stamina / stamina_component.max_stamina
			return 1.0
		_:
			if needs != null and needs.needs.has(stat_name):
				return needs.get_need(stat_name)
	return -1.0


func _resolve_stat_value(stat_name: StringName) -> float:
	## Auxiliary: Resolves raw value for health, stamina, or needs.
	match stat_name:
		&"hp", &"health":
			return float(_current_hp)
		&"stamina":
			if stamina_component != null:
				return stamina_component.current_stamina
			return 100.0
		_:
			if needs != null and needs.needs.has(stat_name):
				return needs.get_need(stat_name)
	return -1.0


func _resolve_current_activity() -> StringName:
	## Auxiliary: Resolves current activity from bt_player blackboard goal or current job labor.
	if bt_player != null and bt_player.blackboard != null and bt_player.blackboard.has_var(&"current_goal"):
		var goal: Variant = bt_player.blackboard.get_var(&"current_goal")
		var goal_name := StringName(str(goal))
		if goal_name == &"work":
			# 1. Labor Extraction: Retrieve the active job's labor category when work goal is selected.
			return _resolve_work_activity()
		elif goal_name != &"none" and goal_name != &"":
			return goal_name
	
	if current_job != null:
		# 2. Direct Fallback: Check assigned current_job if blackboard goal was unset.
		return _resolve_work_activity()
		
	return &"idle"


func _resolve_work_activity() -> StringName:
	## Auxiliary: Extracts specific work/labor identifier from the current job or blackboard reference.
	var job: Variant = current_job
	if job == null and bt_player != null and bt_player.blackboard != null:
		if bt_player.blackboard.has_var(&"active_job"):
			job = bt_player.blackboard.get_var(&"active_job")
		elif bt_player.blackboard.has_var(&"active_claim"):
			job = bt_player.blackboard.get_var(&"active_claim")
	
	if job != null:
		if "labor_id" in job and str(job.labor_id) != "":
			return StringName(str(job.labor_id))
		if "title" in job and str(job.title) != "":
			return StringName(str(job.title))
	return &"idle"


func _evaluate_all_moodlets() -> Array[Dictionary]:
	## Auxiliary: Evaluates moodlets in colonist_def and constructs the active list.
	var active: Array[Dictionary] = []
	for m_def in colonist_def.moodlet_defs:
		if m_def == null:
			continue
		var idx: int = m_def.evaluate_icon_index(self)
		if idx >= 0:
			var tex: Texture2D = m_def.get_active_texture(self)
			active.append({
				"def": m_def,
				"index": idx,
				"texture": tex,
				"name": m_def.display_name,
			})
	return active



# --- Carry inventory wrappers ------------------------------------------------
# Mirror Player's inventory helpers so a colonist can stand in for `actor` in
# Blueprint.deposit_from (which calls actor.remove_item) and HaulingJobDef can
# move items between a crate's StorageInventory and the colonist via transfer_to.

func add_item(item_id: String, count: int) -> int:
	return inventory.add(item_id, count)


func remove_item(item_id: String, count: int) -> int:
	return inventory.remove(item_id, count)


func has_item(item_id: String, count: int) -> bool:
	return inventory.has_item(item_id, count)


func can_carry(item_id: String, count: int) -> bool:
	return inventory.can_add(item_id, count)


## Free weight left in the carry inventory (capacity − current_weight). Not
## exercised by the haul loop yet (transfer_to enforces capacity at fetch) —
## kept for future capacity-aware assignment.
func drop_held_item(item_id: String = "") -> String:
	if inventory == null:
		return ""
	if item_id != "":
		if inventory.has_item(item_id, 1):
			inventory.remove(item_id, 1)
			if is_inside_tree():
				WorldItem.spawn_at(self, item_id, 1, global_position + Vector3(0, 0.5, 0))
			return item_id
		return ""
	if not inventory.items.is_empty():
		var first_item: String = str(inventory.items.keys()[0])
		inventory.remove(first_item, 1)
		if is_inside_tree():
			WorldItem.spawn_at(self, first_item, 1, global_position + Vector3(0, 0.5, 0))
		return first_item
	return ""


func hands_full() -> bool:
	return inventory != null and not inventory.items.is_empty()


func remaining_capacity() -> float:
	return inventory.capacity - inventory.current_weight()


# --- SaveSystem contract -----------------------------------------------------
# Owned scalar/dict state + world position + skill state + needs state.

func serialize() -> Dictionary:
	return {
		"colonist_id": colonist_id,
		"display_name": display_name,
		"labor_priorities": labor_priorities.duplicate(true),
		"raid_stance": raid_stance,
		"squad_id": squad_id,
		"hp": _current_hp,
		"is_dead": _is_dead,
		"skills": skill_set.serialize() if skill_set != null else {},
		"needs": needs.serialize() if needs != null else {},
		"inventory": inventory.serialize() if inventory != null else {},
		"pos": [global_position.x, global_position.y, global_position.z],
	}


## Equip an item to the colonist.
func equip_item(item: ItemDef) -> void:
	equipped_item = item

	# 1. Visual Attachment: Update 3D equipped item visual mesh on skeleton attachment socket.
	_update_equipped_item_visual(item)


## Unequip the colonist's current item.
func unequip_item() -> void:
	equipped_item = null

	# 1. Visual Detachment: Clear 3D equipped item visual mesh from skeleton attachment socket.
	_update_equipped_item_visual(null)


## Auxiliary: Updates or clears the instantiated weapon/tool visual node attached to the character's skeleton
func _update_equipped_item_visual(item: ItemDef) -> void:
	# 1. Socket Resolution: Locate or create the right-hand BoneAttachment3D on the active Skeleton3D.
	var socket: BoneAttachment3D = _get_or_create_hand_socket(&"socket_hand_r")
	if socket == null:
		return

	# 2. Socket Cleanup: Remove and free any previously attached weapon visual nodes.
	_clear_socket_children(socket)

	if item == null:
		return

	# 3. Instance Visual: Instantiate weapon PackedScene or MeshInstance3D and attach to socket.
	_attach_item_visual_to_socket(item, socket)


## Auxiliary: Finds an existing BoneAttachment3D or creates and configures one on the Skeleton3D
func _get_or_create_hand_socket(preferred_socket_bone: StringName) -> BoneAttachment3D:
	var skeleton := find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton == null:
		return null

	var existing_socket := skeleton.get_node_or_null("RightHandAttachment") as BoneAttachment3D
	if existing_socket != null:
		return existing_socket

	# 1. Bone Resolution: Find the best matching bone name for hand attachment.
	var bone_name: String = _resolve_hand_bone_name(skeleton, preferred_socket_bone)
	if bone_name.is_empty():
		return null

	var new_socket := BoneAttachment3D.new()
	new_socket.name = "RightHandAttachment"
	new_socket.bone_name = bone_name
	skeleton.add_child(new_socket)
	return new_socket


## Auxiliary: Resolves the best available bone name in the skeleton for hand socket attachment
func _resolve_hand_bone_name(skeleton: Skeleton3D, preferred: StringName) -> String:
	if skeleton.find_bone(String(preferred)) != -1:
		return String(preferred)
	if skeleton.find_bone("RightHand") != -1:
		return "RightHand"
	if skeleton.find_bone("mixamorig:RightHand") != -1:
		return "mixamorig:RightHand"
	for i in range(skeleton.get_bone_count()):
		var b_name := skeleton.get_bone_name(i)
		if "righthand" in b_name.to_lower() or "hand_r" in b_name.to_lower() or "hand.r" in b_name.to_lower():
			return b_name
	return ""


## Auxiliary: Removes and frees all children nodes currently attached to a socket
func _clear_socket_children(socket: BoneAttachment3D) -> void:
	for child in socket.get_children():
		socket.remove_child(child)
		child.queue_free()


## Auxiliary: Instantiates and attaches the 3D visual representation of an ItemDef to a socket
func _attach_item_visual_to_socket(item: ItemDef, socket: BoneAttachment3D) -> void:
	if item.scene != null:
		var visual_node: Node = item.scene.instantiate()
		if visual_node is Node3D:
			(visual_node as Node3D).name = "EquippedVisual"
			# 1. Node Sanitization: Hide auxiliary collision/hitbox meshes inside imported weapon model.
			_sanitize_weapon_visual_nodes(visual_node)
			socket.add_child(visual_node)
	elif item.mesh != null:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "EquippedVisual"
		mesh_instance.mesh = item.mesh
		socket.add_child(mesh_instance)


## Auxiliary: Recursively hides collision, area, or hitbox mesh nodes inside an imported weapon scene
func _sanitize_weapon_visual_nodes(node: Node) -> void:
	for child in node.get_children():
		var child_name := child.name.to_lower()
		if child is MeshInstance3D:
			if "hitbox" in child_name or "hibox" in child_name or "area" in child_name or "col" in child_name:
				(child as MeshInstance3D).visible = false
		elif child is CollisionShape3D or child is CollisionObject3D or child is Area3D:
			if child is Node3D:
				(child as Node3D).visible = false
		_sanitize_weapon_visual_nodes(child)


func deserialize(data: Dictionary) -> void:
	colonist_id = data.get("colonist_id", colonist_id)
	display_name = data.get("display_name", display_name)
	labor_priorities = data.get("labor_priorities", {}).duplicate(true)
	raid_stance = int(data.get("raid_stance", raid_stance))
	squad_id = data.get("squad_id", "")
	_current_hp = int(data.get("hp", _current_hp))
	_is_dead = bool(data.get("is_dead", false))
	if skill_set != null and data.has("skills"):
		skill_set.deserialize(data["skills"])
	if needs != null and data.has("needs"):
		needs.deserialize(data["needs"])
	if inventory != null and data.has("inventory"):
		inventory.deserialize(data["inventory"])
	var p: Array = data.get("pos", [global_position.x, global_position.y, global_position.z])
	global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if bt_player != null:
		bt_player.restart()
	if brain != null:
		brain.evaluate_goals()


## Dynamically builds interaction options (Deploy / Dismiss single & squad).
func refresh_interaction_options() -> void:
	if interaction == null:
		interaction = get_node_or_null("InteractionComponent") as InteractionComponent
	if interaction == null:
		return

	var is_deployed := Colony.has_active_deployment(colonist_id) if Colony != null else false
	var options: Array[ActionOption] = []

	if not is_deployed:
		interaction.display_name = display_name
		interaction.info_text = "Squad: %s" % squad_id if squad_id != "" else ""

		var deploy_act := DeployColonistAction.new()
		deploy_act.label = "Deploy %s" % display_name
		var opt_deploy := ActionOption.new()
		opt_deploy.action = deploy_act
		options.append(opt_deploy)

		if squad_id != "":
			var squad_act := DeploySquadAction.new()
			squad_act.label = "Deploy Squad: %s" % squad_id.capitalize()
			var opt_squad := ActionOption.new()
			opt_squad.action = squad_act
			options.append(opt_squad)
	else:
		interaction.display_name = "%s [Stationed]" % display_name
		var pos = Colony.get_active_deployment_position(colonist_id) if Colony != null else null
		if pos is Vector3:
			interaction.info_text = "Stationed @ (%d, %d, %d)" % [int(pos.x), int(pos.y), int(pos.z)]
		else:
			interaction.info_text = "Stationed"

		var dismiss_act := DismissColonistAction.new()
		dismiss_act.label = "Dismiss %s" % display_name
		var opt_dismiss := ActionOption.new()
		opt_dismiss.action = dismiss_act
		options.append(opt_dismiss)

		if squad_id != "":
			var dismiss_squad_act := DismissSquadAction.new()
			dismiss_squad_act.label = "Dismiss Squad: %s" % squad_id.capitalize()
			var opt_dismiss_squad := ActionOption.new()
			opt_dismiss_squad.action = dismiss_squad_act
			options.append(opt_dismiss_squad)

	interaction.action_options = options
