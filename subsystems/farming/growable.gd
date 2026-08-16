class_name Growable
extends Node
## Capability component for farm plot furniture (GDD §6 / Farming, ARCH "Farming").
## Attached under a Furniture node by FurnitureLayer when its def declares farm_plot_params.
##
## Manages crop growth, hydration decay, milestone & decay tending, stage visuals,
## dynamic yield calculation, and seamless integration with Harvestable.

const STATE_KEY := "growable"

enum CropState {
	EMPTY = 0,
	GROWING = 1,
	MATURE = 2,
	WITHERED = 3,
}

var _furniture: Furniture:
	get: return get_parent() as Furniture

var _harvestable: Harvestable:
	get: return _furniture.get_node_or_null("Harvestable") as Harvestable if _furniture != null else null

var _crop_mesh_instance: MeshInstance3D = null
var _current_visual_stage: int = -1


func _ready() -> void:
	_sync_from_state()
	_update_visuals()
	_update_info_text()
	if get_crop_state() == CropState.EMPTY and get_selected_crop_id() != "":
		EventBus.plot_needs_sowing.emit(self, anchor_cell(), get_selected_crop_id(), true)


func _exit_tree() -> void:
	# Clean up any active EventBus job requests for this plot
	if is_sow_job_active():
		EventBus.plot_needs_sowing.emit(self, anchor_cell(), get_selected_crop_id(), false)
	if is_water_job_active():
		EventBus.plot_needs_water.emit(self, anchor_cell(), false)
	if is_tend_job_active():
		EventBus.plot_needs_tending.emit(self, anchor_cell(), false)


## Back-ref to definition's FarmPlotParams.
func params() -> FarmPlotParams:
	if _furniture == null or _furniture.def == null:
		return null
	var fdef := _furniture.def as FurnitureDef
	return fdef.farm_plot_params if fdef != null else null


func anchor_cell() -> Vector3i:
	if _furniture == null:
		return Vector3i.ZERO
	var cells := _furniture.get_footprint_cells()
	return cells[0] if not cells.is_empty() else Vector3i.ZERO


# --- State Getters / Setters ---

func get_crop_state() -> CropState:
	return _state().get("state", CropState.EMPTY) as CropState


func set_crop_state(s: CropState) -> void:
	var st := _state()
	st["state"] = int(s)
	_save_state(st)
	_update_visuals()
	_update_info_text()


func get_current_crop_id() -> String:
	return _state().get("current_crop_id", "")


func get_selected_crop_id() -> String:
	return _state().get("selected_crop_id", "")


func set_selected_crop(crop_id: String) -> void:
	var st := _state()
	st["selected_crop_id"] = crop_id
	_save_state(st)
	if get_crop_state() == CropState.EMPTY:
		if crop_id != "":
			st["sow_job_active"] = true
			_save_state(st)
			EventBus.plot_needs_sowing.emit(self, anchor_cell(), crop_id, true)
		else:
			if is_sow_job_active():
				st["sow_job_active"] = false
				_save_state(st)
				EventBus.plot_needs_sowing.emit(self, anchor_cell(), "", false)
	_update_info_text()


func get_growth_progress() -> float:
	return _state().get("growth_progress", 0.0)


func set_growth_progress(val: float) -> void:
	var st := _state()
	st["growth_progress"] = clampf(val, 0.0, 1.0)
	_save_state(st)
	_update_visuals()
	_update_info_text()


func get_water_level() -> float:
	return _state().get("water_level", 100.0)


func set_water_level(val: float) -> void:
	var st := _state()
	var def := get_crop_def()
	var max_w := def.max_water if def != null else 100.0
	st["water_level"] = clampf(val, 0.0, max_w)
	_save_state(st)
	_update_info_text()


func is_tended() -> bool:
	return _state().get("is_tended", true)


func set_is_tended(val: bool) -> void:
	var st := _state()
	st["is_tended"] = val
	_save_state(st)
	_update_info_text()


func is_water_job_active() -> bool:
	return _state().get("water_job_active", false)


func is_tend_job_active() -> bool:
	return _state().get("tend_job_active", false)


func is_sow_job_active() -> bool:
	return _state().get("sow_job_active", false)


func get_neglect_time() -> float:
	return _state().get("neglect_time", 0.0)


func get_crop_def() -> CropDef:
	var cid := get_current_crop_id()
	if cid == "":
		cid = get_selected_crop_id()
	return CropLibrary.get_crop(cid)


# --- Core Actions ---

## Plant a seed into the plot.
func plant(crop_id: String) -> bool:
	var def := CropLibrary.get_crop(crop_id)
	if def == null:
		return false
	var st := _state()
	st["state"] = int(CropState.GROWING)
	st["current_crop_id"] = crop_id
	st["selected_crop_id"] = crop_id
	st["growth_progress"] = 0.0
	st["water_level"] = def.max_water
	st["is_tended"] = true
	st["tended_timer"] = def.tending_decay_hours
	st["next_milestone_index"] = 0
	st["neglect_time"] = 0.0
	st["mature_time"] = 0.0
	st["water_job_active"] = false
	st["tend_job_active"] = false
	var was_sow_active: bool = st.get("sow_job_active", false)
	st["sow_job_active"] = false
	_save_state(st)

	if was_sow_active:
		EventBus.plot_needs_sowing.emit(self, anchor_cell(), crop_id, false)

	if _furniture != null:
		GameLog.info("Planted %s in %s" % [def.display_name, _furniture.label])

	_update_visuals()
	_update_info_text()
	return true


## Water the crop. Restores water level to max and clears water job.
func water(actor: Node = null) -> void:
	var def := get_crop_def()
	var max_w := def.max_water if def != null else 100.0
	set_water_level(max_w)
	var st := _state()
	if st.get("water_job_active", false):
		st["water_job_active"] = false
		_save_state(st)
		EventBus.plot_needs_water.emit(self, anchor_cell(), false)

	if actor != null:
		var colonist := actor as Colonist
		if colonist != null and colonist.skill_set != null:
			colonist.skill_set.record_use_for_labor("farming")
		var player := actor as Player
		if player != null and player.skill_set != null:
			player.skill_set.record_use_for_labor("farming")
	_update_info_text()


## Tend the crop. Clears tending requirement and updates timers/milestones.
func tend(actor: Node = null) -> void:
	var def := get_crop_def()
	var st := _state()
	st["is_tended"] = true
	if def != null and def.tending_mode == CropDef.TendingMode.DECAY:
		st["tended_timer"] = def.tending_decay_hours
	elif def != null and def.tending_mode == CropDef.TendingMode.MILESTONE:
		st["next_milestone_index"] = int(st.get("next_milestone_index", 0)) + 1

	if st.get("tend_job_active", false):
		st["tend_job_active"] = false
		EventBus.plot_needs_tending.emit(self, anchor_cell(), false)
	_save_state(st)

	if actor != null:
		var colonist := actor as Colonist
		if colonist != null and colonist.skill_set != null:
			colonist.skill_set.record_use_for_labor("farming")
		var player := actor as Player
		if player != null and player.skill_set != null:
			player.skill_set.record_use_for_labor("farming")
	_update_info_text()


func needs_water() -> bool:
	if get_crop_state() != CropState.GROWING:
		return false
	var def := get_crop_def()
	var threshold := def.thirsty_threshold if def != null else 30.0
	return get_water_level() <= threshold


func needs_tending() -> bool:
	if get_crop_state() != CropState.GROWING:
		return false
	return not is_tended()


func can_be_harvested() -> bool:
	var s := get_crop_state()
	if s == CropState.MATURE:
		return true
	if s == CropState.GROWING:
		return not get_harvest_yields().is_empty()
	return false


## Compute dynamic yields based on current growth progress against yield tiers,
## with neglect penalties applied.
func get_harvest_yields() -> Array[ItemAmount]:
	var def := get_crop_def()
	if def == null:
		return []
	var progress := get_growth_progress()
	var best_tier: CropYieldTier = null

	for tier in def.yield_tiers:
		if tier == null:
			continue
		if progress >= tier.min_growth_progress:
			if best_tier == null or tier.min_growth_progress > best_tier.min_growth_progress:
				best_tier = tier

	if best_tier == null:
		return []

	# Apply neglect yield penalty if applicable
	var penalty_mult := 1.0
	if def.neglect_hours > 0.0 and def.neglect_yield_penalty > 0.0:
		var neglect := get_neglect_time()
		if neglect > def.neglect_hours:
			var periods := (neglect - def.neglect_hours) / def.neglect_hours
			penalty_mult = maxf(0.0, 1.0 - periods * def.neglect_yield_penalty)

	var result: Array[ItemAmount] = []
	for entry in best_tier.yields:
		if entry == null or entry.item_def == null:
			continue
		var amount := ItemAmount.new()
		amount.item_def = entry.item_def
		amount.count = maxi(0, int(round(float(entry.count) * penalty_mult)))
		if amount.count > 0:
			result.append(amount)
	return result


## Invoked when Harvestable completes. Resets plot state to EMPTY and triggers sowing if selected.
func on_harvested(_actor: Node) -> void:
	var st := _state()
	var prev_crop := get_current_crop_id()
	st["state"] = int(CropState.EMPTY)
	st["current_crop_id"] = ""
	st["growth_progress"] = 0.0
	st["water_level"] = 100.0
	st["is_tended"] = true
	st["tended_timer"] = 0.0
	st["next_milestone_index"] = 0
	st["neglect_time"] = 0.0
	st["mature_time"] = 0.0
	st["water_job_active"] = false
	st["tend_job_active"] = false
	_save_state(st)

	var h := _harvestable
	if h != null:
		h.set_work_done(0.0)
		h.set_marked(false)

	_update_visuals()
	_update_info_text()

	var selected := get_selected_crop_id()
	if selected != "":
		st["sow_job_active"] = true
		_save_state(st)
		EventBus.plot_needs_sowing.emit(self, anchor_cell(), selected, true)


# --- Simulation Loop ---

func _process(delta: float) -> void:
	if GameState.paused:
		return

	var s := get_crop_state()
	if s != CropState.GROWING and s != CropState.MATURE:
		return

	var def := get_crop_def()
	if def == null:
		return

	# In-game hours calculation
	var day_seconds := 1800.0
	if TimeSystem != null and TimeSystem.get("_loop_length_seconds") != null:
		day_seconds = float(TimeSystem.get("_loop_length_seconds"))
	var hours_delta := (delta / day_seconds) * 24.0

	var st := _state()

	if s == CropState.GROWING:
		# 1. Hydration decay
		var current_w := get_water_level()
		var new_w := maxf(0.0, current_w - def.water_decay_per_hour * hours_delta)
		st["water_level"] = new_w

		if new_w <= def.thirsty_threshold:
			if not st.get("water_job_active", false):
				st["water_job_active"] = true
				EventBus.plot_needs_water.emit(self, anchor_cell(), true)
		else:
			if st.get("water_job_active", false):
				st["water_job_active"] = false
				EventBus.plot_needs_water.emit(self, anchor_cell(), false)

		# 2. Tending mechanics
		var tended: bool = st.get("is_tended", true)
		var prog: float = st.get("growth_progress", 0.0)

		if def.tending_mode == CropDef.TendingMode.MILESTONE:
			var m_idx: int = int(st.get("next_milestone_index", 0))
			if m_idx < def.tending_milestones.size():
				if prog >= def.tending_milestones[m_idx]:
					tended = false
					st["is_tended"] = false
		elif def.tending_mode == CropDef.TendingMode.DECAY:
			var timer: float = float(st.get("tended_timer", 0.0)) - hours_delta
			st["tended_timer"] = maxf(0.0, timer)
			if timer <= 0.0:
				tended = false
				st["is_tended"] = false

		if not tended:
			if not st.get("tend_job_active", false):
				st["tend_job_active"] = true
				EventBus.plot_needs_tending.emit(self, anchor_cell(), true)
			st["neglect_time"] = float(st.get("neglect_time", 0.0)) + hours_delta
		else:
			if st.get("tend_job_active", false):
				st["tend_job_active"] = false
				EventBus.plot_needs_tending.emit(self, anchor_cell(), false)

		# 3. Growth rate & advance
		var growth_mult := 1.0
		if new_w <= 0.0:
			growth_mult = 0.0 # frozen when dried out
		elif not tended:
			growth_mult = def.untended_growth_mult

		if def.growth_time_hours > 0.0 and growth_mult > 0.0:
			prog = minf(1.0, prog + (hours_delta / def.growth_time_hours) * growth_mult)
			st["growth_progress"] = prog

		_save_state(st)
		_update_visuals()
		_update_info_text()

		# 4. Check Maturity
		if prog >= 1.0:
			st["state"] = int(CropState.MATURE)
			if st.get("water_job_active", false):
				st["water_job_active"] = false
				EventBus.plot_needs_water.emit(self, anchor_cell(), false)
			if st.get("tend_job_active", false):
				st["tend_job_active"] = false
				EventBus.plot_needs_tending.emit(self, anchor_cell(), false)
			_save_state(st)
			if _harvestable != null:
				_harvestable.set_marked(true)
			_update_visuals()
			_update_info_text()

	elif s == CropState.MATURE:
		if def.wither_hours > 0.0:
			var m_time: float = float(st.get("mature_time", 0.0)) + hours_delta
			st["mature_time"] = m_time
			if m_time >= def.wither_hours:
				st["state"] = int(CropState.WITHERED)
				_save_state(st)
				_update_visuals()
				_update_info_text()


# --- Visuals & Info Text ---

func _update_visuals() -> void:
	if _furniture == null:
		return
	var s := get_crop_state()
	if s == CropState.EMPTY:
		if _crop_mesh_instance != null:
			_crop_mesh_instance.queue_free()
			_crop_mesh_instance = null
		_current_visual_stage = -1
		return

	var def := get_crop_def()
	var stage_idx := 0
	if s == CropState.GROWING:
		var prog := get_growth_progress()
		if prog < 0.4:
			stage_idx = 0 # Sprout
		else:
			stage_idx = 1 # Growing
	elif s == CropState.MATURE:
		stage_idx = 2 # Mature
	elif s == CropState.WITHERED:
		stage_idx = 3 # Withered

	if stage_idx == _current_visual_stage and _crop_mesh_instance != null:
		return

	_current_visual_stage = stage_idx

	if _crop_mesh_instance == null:
		_crop_mesh_instance = MeshInstance3D.new()
		_crop_mesh_instance.name = "CropMesh"
		_crop_mesh_instance.position = Vector3(0, 0.35, 0)
		_furniture.add_child(_crop_mesh_instance)

	_apply_stage_mesh(_crop_mesh_instance, def, stage_idx)


func _apply_stage_mesh(mesh_node: MeshInstance3D, def: CropDef, stage_idx: int) -> void:
	if def != null and stage_idx < def.stage_meshes.size() and def.stage_meshes[stage_idx] != null:
		mesh_node.mesh = def.stage_meshes[stage_idx]
		mesh_node.material_override = null
		return

	# Procedural fallback meshes
	var mat := StandardMaterial3D.new()
	if stage_idx == 0: # Sprout
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.06
		cyl.height = 0.2
		mesh_node.mesh = cyl
		mat.albedo_color = Color("#4caf50")
	elif stage_idx == 1: # Growing
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.15
		cyl.height = 0.45
		mesh_node.mesh = cyl
		mat.albedo_color = Color("#2e7d32")
	elif stage_idx == 2: # Mature
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.2
		cyl.height = 0.65
		mesh_node.mesh = cyl
		mat.albedo_color = Color("#fbc02d")
	else: # Withered
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.1
		cyl.bottom_radius = 0.15
		cyl.height = 0.25
		mesh_node.mesh = cyl
		mat.albedo_color = Color("#5d4037")

	mesh_node.material_override = mat


func _update_info_text() -> void:
	if _furniture == null:
		return
	var interaction := _furniture.get_node_or_null("InteractionComponent") as InteractionComponent
	if interaction == null:
		return

	var s := get_crop_state()
	var def := get_crop_def()
	if s == CropState.EMPTY:
		var sel := get_selected_crop_id()
		if sel != "":
			var sel_def := CropLibrary.get_crop(sel)
			var sel_name := sel_def.display_name if sel_def != null else sel
			interaction.info_text = "Empty (Selected: %s)" % sel_name
		else:
			interaction.info_text = "Empty (No Crop Selected)"
	elif s == CropState.GROWING:
		var crop_name := def.display_name if def != null else get_current_crop_id()
		var pct := int(get_growth_progress() * 100.0)
		var w_pct := int(get_water_level())
		var status_str := ""
		if not is_tended():
			status_str = " · [Needs Tending]"
		elif w_pct <= (def.thirsty_threshold if def != null else 30.0):
			status_str = " · [Thirsty]"
		interaction.info_text = "%s %d%% (Water: %d%%%s)" % [crop_name, pct, w_pct, status_str]
	elif s == CropState.MATURE:
		var crop_name := def.display_name if def != null else get_current_crop_id()
		interaction.info_text = "%s (Mature - Ready to Harvest)" % crop_name
	elif s == CropState.WITHERED:
		var crop_name := def.display_name if def != null else get_current_crop_id()
		interaction.info_text = "%s (Withered)" % crop_name


# --- Persistence Helper ---

func _state() -> Dictionary:
	if _furniture == null:
		return {}
	if not _furniture.state.has(STATE_KEY):
		_furniture.state[STATE_KEY] = {
			"state": int(CropState.EMPTY),
			"selected_crop_id": "",
			"current_crop_id": "",
			"growth_progress": 0.0,
			"water_level": 100.0,
			"is_tended": true,
			"tended_timer": 0.0,
			"next_milestone_index": 0,
			"neglect_time": 0.0,
			"mature_time": 0.0,
			"water_job_active": false,
			"tend_job_active": false,
			"sow_job_active": false,
		}
	return _furniture.state[STATE_KEY]


func _save_state(st: Dictionary) -> void:
	if _furniture != null:
		_furniture.state[STATE_KEY] = st


func _sync_from_state() -> void:
	_state()
