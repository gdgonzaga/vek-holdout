class_name FarmManualAction
extends GameAction
## Context-sensitive manual farming action bound to Player LMB (GDD §6 / Farming, ARCH "Farming").
## Dynamically evaluates plot state (Sow -> Tend -> Water -> Harvest) and initiates
## the corresponding timed ActionProgress gauge.

const _progress_scene: PackedScene = preload("res://ui/action_progress/action_progress.tscn")


func execute(actor: Node, target: Node) -> void:
	var growable := _growable_of(target)
	if growable == null:
		return

	var s := growable.get_crop_state()
	var player := actor as Player
	var farming_mult := 1.0
	var harvesting_mult := 1.0
	if player != null and player.skill_set != null:
		farming_mult = player.skill_set.get_multiplier("farming")
		harvesting_mult = player.skill_set.get_multiplier("harvesting")

	if s == Growable.CropState.EMPTY:
		var sel := growable.get_selected_crop_id()
		if sel == "":
			GameLog.warning("Select a crop first in the [E] menu")
			return
		var def := CropLibrary.get_crop(sel)
		if def == null:
			return
		for c in def.plant_conditions:
			if not c.is_met(actor, target):
				GameLog.warning("Cannot plant %s: requirements not met" % def.display_name)
				return
		var duration := 2.0 / farming_mult
		_start_progress(actor, target, "Planting %s" % def.display_name, duration, func() -> void:
			if is_instance_valid(growable):
				growable.plant(sel)
				if player != null and player.skill_set != null:
					player.skill_set.record_use_for_labor("farming")
		)
		return

	var def := growable.get_crop_def()
	var crop_name := def.display_name if def != null else "Crop"

	# Priority: Tend -> Water -> Harvest
	if growable.needs_tending():
		if def != null:
			for c in def.tend_conditions:
				if not c.is_met(actor, target):
					GameLog.warning("Cannot tend %s: requirements not met" % crop_name)
					return
		var duration := 3.0 / farming_mult
		_start_progress(actor, target, "Tending %s" % crop_name, duration, func() -> void:
			if is_instance_valid(growable):
				growable.tend(actor)
				if player != null and player.skill_set != null:
					player.skill_set.record_use_for_labor("farming")
		)
		return

	if growable.needs_water():
		var duration := 2.0 / farming_mult
		_start_progress(actor, target, "Watering %s" % crop_name, duration, func() -> void:
			if is_instance_valid(growable):
				growable.water(actor)
				if player != null and player.skill_set != null:
					player.skill_set.record_use_for_labor("farming")
		)
		return

	var harvestable := _harvestable_of(target)
	if s == Growable.CropState.MATURE or (harvestable != null and harvestable.is_marked_for_harvest()) or growable.can_be_harvested():
		var base_time := def.base_harvest_time if def != null else 3.0
		var duration := base_time / harvesting_mult
		var work_done := harvestable.work_done() if harvestable != null else 0.0
		var remaining := maxf(0.0, duration - work_done)

		_start_timed_harvest(actor, target, harvestable, "Harvesting %s" % crop_name, duration, work_done)
		return

	# Crop is growing and satisfied
	GameLog.info("%s is healthy and growing (%d%%)" % [crop_name, int(growable.get_growth_progress() * 100.0)])


func _start_progress(actor: Node, target: Node, label: String, duration: float, on_complete: Callable) -> void:
	var player := actor as Player
	if player != null:
		player.set_busy(true)
	var ui: Control = _progress_scene.instantiate()
	ui.completed.connect(func() -> void:
		if player != null:
			player.set_busy(false)
		on_complete.call()
	)
	ui.cancelled.connect(func(_elapsed: float) -> void:
		if player != null:
			player.set_busy(false)
	)
	_mount(ui, target)
	ui.setup(label, duration, 0.0)


func _start_timed_harvest(actor: Node, target: Node, harvestable: Harvestable, label: String, total_duration: float, start_elapsed: float) -> void:
	var player := actor as Player
	if player != null:
		player.set_busy(true)
	var ui: Control = _progress_scene.instantiate()
	ui.completed.connect(func() -> void:
		if player != null:
			player.set_busy(false)
		if harvestable != null and is_instance_valid(harvestable):
			var completed := harvestable.complete(actor)
			if completed and player != null and player.skill_set != null:
				player.skill_set.record_use_for_labor("harvesting")
	)
	ui.cancelled.connect(func(elapsed: float) -> void:
		if player != null:
			player.set_busy(false)
		if harvestable != null and is_instance_valid(harvestable):
			harvestable.set_work_done(elapsed)
	)
	_mount(ui, target)
	ui.setup(label, total_duration, start_elapsed)


func _growable_of(target: Node) -> Growable:
	if target == null or not is_instance_valid(target):
		return null
	var g := target as Growable
	if g != null:
		return g
	return target.get_node_or_null("Growable") as Growable


func _harvestable_of(target: Node) -> Harvestable:
	if target == null or not is_instance_valid(target):
		return null
	var h := target as Harvestable
	if h != null:
		return h
	return target.get_node_or_null("Harvestable") as Harvestable


func _mount(ui: Control, target: Node) -> void:
	var tree := target.get_tree()
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	if layer == null:
		target.add_child(ui)
	else:
		layer.add_child(ui)
