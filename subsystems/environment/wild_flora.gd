class_name WildFlora
extends Furniture
## Runtime instance for wild flora (trees, bushes, and harvestable wild plants).
## Manages stage-based visual progression, HealthComponent durability,
## real-time axe damage resolution, and perennial fruit foraging cycles.

const STATE_KEY_GROWTH := "growth_progress"
const _VisualizerScript = preload("res://subsystems/environment/wild_flora_moodlet_visualizer.gd")

@export var growth_progress: float = 0.0: set = set_growth_progress

var harvestable: Harvestable

var _active_stage_index: int = -1
var _stage_visual_instance: Node3D = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# HealthComponent Setup: super._ready() (Furniture) calls _setup_health_component(),
	# which virtual-dispatches to this class's own override below.
	super._ready()
	_rng.randomize()

	# 1. Initial Progress Resolution: Restore from state or randomize initial growth.
	_initialize_growth_progress()

	# 2. Collision Layer Configuration: Set blocking or pass-through character collision.
	_apply_movement_collision_policy()

	# 3. Stage State Synchronization: Instantiate visual representation and configure HP.
	_sync_to_current_stage(true)

	# 4. Moodlet Visualizer Setup: Self-heal a missing billboard visualizer node
	# (declared in new_wild_flora_template.tscn; a future alternate template
	# that omits it still gets one, mirroring EnemyBase._setup_moodlet_visualizer).
	_setup_moodlet_visualizer()


func _process(delta: float) -> void:
	if GameState.paused:
		return
	
	var flora_def := _get_flora_def()
	if flora_def == null or flora_def.growth_time_hours <= 0.0:
		return
	
	if growth_progress >= 1.0:
		return
	
	# 1. Delta Calculation: Convert real-time delta to in-game hours.
	var hours_delta: float = _calculate_hours_delta(delta)
	
	# 2. Progress Advance: Add fractional progress towards full maturity.
	var new_prog: float = minf(1.0, growth_progress + (hours_delta / flora_def.growth_time_hours))
	set_growth_progress(new_prog)


## Sets the current growth progress (0.0 to 1.0) and updates stage visuals if changed.
func set_growth_progress(val: float) -> void:
	var clamped := clampf(val, 0.0, 1.0)
	print("[FLORA_DEBUG] set_growth_progress: def_id=%s old=%s new=%s" % [def_id, growth_progress, clamped])
	growth_progress = clamped
	state[STATE_KEY_GROWTH] = growth_progress
	
	var flora_def := _get_flora_def()
	if flora_def != null:
		var target_stage_idx: int = flora_def.get_stage_index_for_progress(growth_progress)
		if target_stage_idx != _active_stage_index:
			# 1. Stage Refresh: Reconfigure visuals, HP, and interaction for new stage.
			_sync_to_current_stage(false)


## Returns whether this flora currently bears mature fruit ready for foraging.
func can_forage() -> bool:
	var stage := get_current_stage()
	return stage != null and stage.can_harvest_fruit and not stage.harvest_yields.is_empty()


## Gathers mature fruit/produce from the flora.
## Resets growth to regrowth_stage_index, or destroys plant if destroy_on_fruit_harvest is true.
func forage(actor: Node) -> bool:
	if not can_forage():
		return false
	
	var stage := get_current_stage()
	var flora_def := _get_flora_def()
	
	# 1. Yield Spawning: Spawn fruit item drops scattered clear of trunk mesh.
	_spawn_harvest_yields(stage.harvest_yields, actor)
	
	if flora_def != null and flora_def.destroy_on_fruit_harvest:
		# 2. Plant Removal: Uproot single-harvest wild plants.
		_destroy_flora()
		return true
	
	# 3. Perennial Regrowth: Reset progress to configured post-harvest stage.
	var reset_progress: float = 0.0
	if flora_def != null and flora_def.stages.size() > flora_def.regrowth_stage_index and flora_def.regrowth_stage_index >= 0:
		reset_progress = flora_def.stages[flora_def.regrowth_stage_index].min_progress
	
	set_growth_progress(reset_progress)
	if GameLog != null:
		GameLog.info("Harvested %s" % label)
	return true


## Physical damage entry point (weapons, tools, raid attacks, explosions).
func take_damage(raw_amount: int, source: Node = null) -> void:
	if health_component == null or health_component.is_dead or raw_amount <= 0:
		return
	
	# 1. Damage Scaling: Calculate weapon-type effectiveness on wood/foliage.
	var effective_damage: int = _calculate_effective_damage(raw_amount, source)
	
	# 2. Damage Application: Apply scaled damage to health component.
	health_component.take_damage(effective_damage, source)


## Returns the active growth stage definition.
func get_current_stage() -> WildFloraStage:
	var flora_def := _get_flora_def()
	if flora_def == null:
		return null
	return flora_def.get_stage_for_progress(growth_progress)


## Implements the IStatProvider contract (subsystems/core/i_stat_provider.gd).
## Returns the normalized (0.0 to 1.0) ratio for a given stat, or -1.0 if unknown.
func get_stat_ratio(stat_name: StringName) -> float:
	return _resolve_stat_ratio(stat_name)


## Returns the raw scalar value for a given stat, or -1.0 if unknown.
func get_stat_value(stat_name: StringName) -> float:
	return _resolve_stat_value(stat_name)


## Returns the current interaction-state identifier — &"marked_for_harvest",
## &"forageable", &"depleted", or &"choppable" (first match wins) — or &""
## if none apply. Consumed by ActivityMoodletDef the same way a colonist's
## current labor is.
func get_current_activity() -> StringName:
	return _resolve_current_activity()


## Returns all currently active moodlets evaluated from the flora def's
## moodlet_defs in order. Same Dictionary shape as Colonist/EnemyBase:
## { "def": MoodletDef, "index": int, "texture": Texture2D, "name": String }.
func get_active_moodlets() -> Array[Dictionary]:
	var flora_def := _get_flora_def()
	if flora_def == null or flora_def.moodlet_defs.is_empty():
		return []
	return MoodletLayoutResolver.evaluate_active_moodlets(self, flora_def.moodlet_defs)


# =============================================================================
# Auxiliary Functions (Step-down narrative order)
# =============================================================================

func _setup_health_component() -> void:
	## Auxiliary: Resolves or instantiates HealthComponent child node.
	health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null:
		health_component = HealthComponent.new()
		health_component.name = "HealthComponent"
		health_component.show_damage_particles = false
		add_child(health_component)
	else:
		health_component.show_damage_particles = false
	
	if not health_component.entity_died.is_connected(_on_health_entity_died):
		health_component.entity_died.connect(_on_health_entity_died)
	if not health_component.damaged.is_connected(_on_health_damaged):
		health_component.damaged.connect(_on_health_damaged)


func _initialize_growth_progress() -> void:
	## Auxiliary: Restores growth progress from saved state or randomizes initial range.
	if state.has(STATE_KEY_GROWTH):
		growth_progress = float(state[STATE_KEY_GROWTH])
		print("[FLORA_DEBUG] _initialize_growth_progress: def_id=%s restored_from_state=%s" % [def_id, growth_progress])
	else:
		var flora_def := _get_flora_def()
		if flora_def != null:
			var min_g := flora_def.initial_growth_min
			var max_g := flora_def.initial_growth_max
			growth_progress = _rng.randf_range(min_g, max_g)
		else:
			growth_progress = 1.0
		state[STATE_KEY_GROWTH] = growth_progress
		print("[FLORA_DEBUG] _initialize_growth_progress: def_id=%s randomized=%s" % [def_id, growth_progress])


func _apply_movement_collision_policy() -> void:
	## Auxiliary: Configures Layer 1 physical collision based on blocks_movement.
	var flora_def := _get_flora_def()
	var should_block: bool = flora_def.blocks_movement if flora_def != null else true
	
	var mesh_node := find_child("Mesh", true, false)
	if mesh_node != null:
		for child in mesh_node.get_children():
			if child is StaticBody3D:
				(child as StaticBody3D).set_collision_layer_value(1, should_block)


func _setup_moodlet_visualizer() -> void:
	## Auxiliary: Instantiates and binds WildFloraMoodletVisualizer if not already attached.
	var visualizer := get_node_or_null("WildFloraMoodletVisualizer") as WildFloraMoodletVisualizer
	if not visualizer:
		visualizer = _VisualizerScript.new() as WildFloraMoodletVisualizer
		visualizer.name = "WildFloraMoodletVisualizer"
		add_child(visualizer)


func _sync_to_current_stage(is_first_sync: bool) -> void:
	## Auxiliary: Updates visual instance, HealthComponent max HP, and collision extents.
	var flora_def := _get_flora_def()
	if flora_def == null:
		return
	
	_active_stage_index = flora_def.get_stage_index_for_progress(growth_progress)
	var stage := flora_def.get_stage_for_progress(growth_progress)
	if stage == null:
		return
	
	# 1. HP Synchronization: Reconfigure HealthComponent with stage max HP.
	if health_component != null:
		if is_first_sync:
			health_component.setup(stage.max_hp)
		else:
			var prev_max := health_component.max_hp
			var ratio: float = float(health_component.current_hp) / float(maxi(1, prev_max))
			health_component.max_hp = stage.max_hp
			health_component.current_hp = maxi(1, int(round(float(stage.max_hp) * ratio)))
	
	# 2. Visual Instance Update: Instantiate stage scene or scale fallback.
	_update_stage_visuals(stage, flora_def)
	
	# 3. Collision Scaling: Scale BuildCollider based on stage visual scale.
	_scale_interaction_collider(stage.visual_scale)


func _update_stage_visuals(stage: WildFloraStage, flora_def: WildFloraDef) -> void:
	## Auxiliary: Swaps or scales child scene instance for active growth stage.
	var scene_to_use: PackedScene = stage.scene if stage.scene != null else flora_def.default_scene
	if scene_to_use == null and flora_def.scene != null:
		scene_to_use = flora_def.scene
	
	var mesh_placeholder := find_child("Mesh", true, false) as MeshInstance3D
	if mesh_placeholder != null:
		mesh_placeholder.visible = (scene_to_use == null)
	
	if scene_to_use != null:
		if _stage_visual_instance != null and is_instance_valid(_stage_visual_instance):
			_stage_visual_instance.queue_free()
			_stage_visual_instance = null
		
		var inst := scene_to_use.instantiate() as Node3D
		if inst != null:
			_stage_visual_instance = inst
			add_child(_stage_visual_instance)
			_stage_visual_instance.scale = stage.visual_scale
	elif _stage_visual_instance != null and is_instance_valid(_stage_visual_instance):
		_stage_visual_instance.scale = stage.visual_scale


func _scale_interaction_collider(v_scale: Vector3) -> void:
	## Auxiliary: Scales BuildCollider and adjusts position so the base remains grounded across stage growth.
	var build_shape := get_node_or_null("BuildBody/BuildCollider") as CollisionShape3D
	if build_shape != null:
		var flora_def := _get_flora_def()
		var height: float = float(flora_def.dimensions.y) if flora_def != null else 1.0
		build_shape.scale = v_scale
		build_shape.position = Vector3(0.0, height * v_scale.y * 0.5, 0.0)


func _calculate_hours_delta(delta: float) -> float:
	## Auxiliary: Converts frame delta into in-game hours via TimeSystem day length.
	var day_seconds: float = 1800.0
	if TimeSystem != null and TimeSystem.get("_loop_length_seconds") != null:
		day_seconds = float(TimeSystem.get("_loop_length_seconds"))
	return (delta / maxf(1.0, day_seconds)) * 24.0


func _calculate_effective_damage(raw_amount: int, source: Node) -> int:
	## Auxiliary: Evaluates tool and weapon tags to modulate damage on wood/flora.
	var flora_def := _get_flora_def()
	if flora_def == null or source == null:
		return raw_amount
	
	var is_tree := has_tag("tree") or has_tag("timber") or has_tag("wood")
	if not is_tree:
		return raw_amount
	
	var weapon: ItemDef = _resolve_source_weapon(source)
	if weapon == null:
		# Bare hands / unarmed strikes deal 20% damage to solid timber
		return maxi(1, int(float(raw_amount) * 0.2))
	
	if weapon.has_tag("axe") or weapon.has_tag("tool_axe"):
		return raw_amount
	elif weapon.has_tag("sword") or weapon.has_tag("dagger") or weapon.has_tag("blade"):
		return maxi(1, int(float(raw_amount) * 0.25))
	elif weapon.has_tag("pickaxe") or weapon.has_tag("pick"):
		return maxi(1, int(float(raw_amount) * 0.15))
	
	return raw_amount


func _resolve_source_weapon(source: Node) -> ItemDef:
	## Auxiliary: Retrieves the active main-hand weapon from player or actor.
	if source is Player:
		var player := source as Player
		if player.equipment != null:
			return player.equipment.get_item(Equipment.SLOT_MAIN_HAND)
	return null


func _on_health_damaged(amount: int, source: Node) -> void:
	## Auxiliary: Handles hit feedback particles and audio upon taking damage.
	var flora_def := _get_flora_def()
	var p_color := flora_def.hit_particles_color if flora_def != null else Color(0.65, 0.45, 0.25)
	var impact_pos := global_position + Vector3(0.0, 1.0, 0.0)
	
	# 1. Visual Feedback: Spawn splinter/leaf particles at hit location.
	_spawn_splinter_particles(impact_pos, p_color)


func _on_health_entity_died(_entity: Node) -> void:
	## Auxiliary: Triggers felling and drops when HealthComponent reaches 0 HP.
	_on_felled()


func _on_felled() -> void:
	## Auxiliary: Spawns active stage fell yields + ripe fruit yields and destroys plant.
	var stage := get_current_stage()
	
	if stage != null:
		var combined_yields: Array[ItemAmount] = []
		combined_yields.append_array(stage.fell_yields)
		if stage.can_harvest_fruit:
			combined_yields.append_array(stage.harvest_yields)
		
		# 1. Yield Scattering: Spawn logs, branches, and fruits distributed radially around trunk base.
		_spawn_radial_yields(combined_yields)
	
	if GameLog != null:
		GameLog.info("Felled %s" % label)
	
	# 2. Plant Destruction: Remove tree node from furniture layer.
	_destroy_flora()


func _spawn_harvest_yields(amounts: Array[ItemAmount], actor: Node) -> void:
	## Auxiliary: Spawns harvested fruit drops directed towards the actor or scattered clear of trunk.
	var tree := get_tree()
	if tree == null:
		return
	
	var actor_3d := actor as Node3D
	var has_actor := actor_3d != null and actor_3d.is_inside_tree()
	var to_actor: Vector3 = (actor_3d.global_position - global_position) if has_actor else Vector3.ZERO
	to_actor.y = 0.0
	
	var base_dir: Vector3 = to_actor.normalized() if to_actor.length_squared() > 0.01 else Vector3.FORWARD
	var total_entries := amounts.size()
	
	for i in range(total_entries):
		var entry := amounts[i]
		if entry == null or entry.item_def == null or entry.count <= 0:
			continue
		
		# Angle offset across multiple yields
		var spread_angle := (float(i) - float(total_entries - 1) * 0.5) * 0.35 if has_actor else (float(i) * TAU / float(maxi(1, total_entries)))
		var dir := base_dir.rotated(Vector3.UP, spread_angle)
		var spawn_pos := global_position + dir * 0.8 + Vector3(0.0, 0.5, 0.0)
		var impulse_dir := (dir + Vector3(0.0, 0.8, 0.0)).normalized()
		
		WorldItem.spawn_at(tree, entry.item_def.id, entry.count, spawn_pos, impulse_dir, 2.0)


func _spawn_radial_yields(amounts: Array[ItemAmount]) -> void:
	## Auxiliary: Spawns felling yields scattered evenly in a circle around trunk base.
	var tree := get_tree()
	if tree == null:
		return
	
	var total_entries := amounts.size()
	for i in range(total_entries):
		var entry := amounts[i]
		if entry == null or entry.item_def == null or entry.count <= 0:
			continue
		
		var angle := float(i) * TAU / float(maxi(1, total_entries)) + randf_range(-0.2, 0.2)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var spawn_pos := global_position + dir * 0.85 + Vector3(0.0, 0.5, 0.0)
		var impulse_dir := (dir + Vector3(0.0, 0.9, 0.0)).normalized()
		
		WorldItem.spawn_at(tree, entry.item_def.id, entry.count, spawn_pos, impulse_dir, 2.2)


func _spawn_item_amounts(amounts: Array[ItemAmount], origin: Vector3) -> void:
	## Auxiliary: Instantiates WorldItem drops for an array of ItemAmount entries.
	var tree := get_tree()
	if tree == null:
		return
	
	for entry in amounts:
		if entry != null and entry.item_def != null and entry.count > 0:
			WorldItem.spawn_at(tree, entry.item_def.id, entry.count, origin)


func _destroy_flora() -> void:
	## Auxiliary: Cleans up and removes the node from FurnitureLayer.
	destroy()


func _spawn_splinter_particles(pos: Vector3, color: Color) -> void:
	## Auxiliary: Spawns quick directional wood/leaf particle burst.
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	
	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 45.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.5
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.04
	mat.scale_max = 0.09
	mat.color = color
	
	var draw_mesh := BoxMesh.new()
	draw_mesh.size = Vector3(0.05, 0.05, 0.05)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = color
	draw_mesh.material = draw_mat
	
	particles.process_material = mat
	particles.draw_pass_1 = draw_mesh
	particles.amount = 8
	particles.lifetime = 0.25
	particles.one_shot = true
	particles.explosiveness = 1.0
	
	tree.current_scene.add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	
	var timer := tree.create_timer(0.35)
	timer.timeout.connect(particles.queue_free)


func _resolve_stat_ratio(stat_name: StringName) -> float:
	## Auxiliary: Resolves normalized 0.0 to 1.0 ratio for HP, or delegates
	## &"work_progress" to the sibling Harvestable capability component.
	match stat_name:
		&"hp", &"health":
			if health_component != null and health_component.max_hp > 0:
				return float(health_component.current_hp) / float(health_component.max_hp)
			return 0.0
		&"work_progress":
			var h := _get_harvestable()
			return h.get_stat_ratio(stat_name) if h != null else -1.0
		_:
			return -1.0


func _resolve_stat_value(stat_name: StringName) -> float:
	## Auxiliary: Resolves raw value for HP, or delegates &"work_progress" to
	## the sibling Harvestable capability component.
	match stat_name:
		&"hp", &"health":
			return float(health_component.current_hp) if health_component != null else -1.0
		&"work_progress":
			var h := _get_harvestable()
			return h.get_stat_value(stat_name) if h != null else -1.0
		_:
			return -1.0


func _resolve_current_activity() -> StringName:
	## Auxiliary: Walks the interaction-state priority chain — marked for
	## colonist harvest, ripe for foraging, recently depleted, or choppable
	## timber — first match wins. marked_for_harvest is currently inert (no
	## content sets harvest_params on WildFloraDef yet, so nothing can toggle
	## it) — forward-looking scaffolding for the tree-chop job flow described
	## in job-extensions.md, not a bug.
	var h := _get_harvestable()
	if h != null and h.is_marked_for_harvest():
		return &"marked_for_harvest"
	if can_forage():
		return &"forageable"
	if _is_depleted_fruit_stage():
		return &"depleted"
	if _is_choppable():
		return &"choppable"
	return &""


func _is_depleted_fruit_stage() -> bool:
	## Auxiliary: True when the flora sits exactly at its configured
	## regrowth_stage_index — the "mature, defruited" stage forage() resets
	## to — and that stage isn't currently ripe. Anchoring on the regrowth
	## stage index (rather than "bears fruit at some stage") avoids
	## misclassifying a young sapling still growing toward its first harvest
	## as depleted.
	var flora_def := _get_flora_def()
	if flora_def == null:
		return false
	var eff_stages := flora_def.get_effective_stages()
	var idx := flora_def.regrowth_stage_index
	if idx < 0 or idx >= eff_stages.size():
		return false
	return _active_stage_index == idx and not can_forage()


func _is_choppable() -> bool:
	## Auxiliary: True for solid timber that can still be felled — the same
	## tags _calculate_effective_damage() already checks for axe scaling.
	if health_component != null and health_component.is_dead:
		return false
	return has_tag("tree") or has_tag("timber") or has_tag("wood")


func _get_harvestable() -> Harvestable:
	## Auxiliary: Resolves and caches the sibling Harvestable capability
	## component, self-healing if queried before _ready() has run —
	## WildFloraMoodletVisualizer (a child) evaluates moodlets in its own
	## _ready(), which Godot runs before this node's own _ready() (mirrors
	## Colonist.get_max_hp()'s health_component guard).
	if harvestable == null:
		harvestable = get_node_or_null("Harvestable") as Harvestable
	return harvestable


func _get_flora_def() -> WildFloraDef:
	## Auxiliary: Casts BuildableDef back-reference to WildFloraDef.
	return def as WildFloraDef
