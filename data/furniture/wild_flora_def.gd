extends BuildableDef
class_name WildFloraDef
## Definition resource for wild trees, plants, and fruit-bearing flora.
## Subclasses BuildableDef directly to present a focused inspector interface
## free from domestic furniture capability parameters and action options.

## Footprint dimensions in voxel cells (default 1x1x1).
@export var dimensions: Vector3i = Vector3i.ONE

## Default visual scene used across stages when stage.scene is null.
@export var default_scene: PackedScene = null

## Whether this flora physically blocks character capsules (Player, Colonists, Enemies).
## Set to false for shrubs, bushes, flowers, and small plants so entities walk through them.
## Set to true for solid tree trunks. Layer 5 (Interactable/Weapons) remains active in both cases.
@export var blocks_movement: bool = true

## In-game hours to grow from 0.0 to 1.0 (e.g. 24.0 = 1 in-game day).
## Set to 0.0 for static flora that never changes.
@export var growth_time_hours: float = 24.0

## If true, harvesting fruit destroys the entire plant (e.g. wild carrots/mushrooms).
## If false, harvesting only picks the fruit and leaves the plant alive (e.g. berry bush, apple tree).
@export var destroy_on_fruit_harvest: bool = false

## When harvested (and destroy_on_fruit_harvest is false), which stage index does the plant revert to?
## e.g. 0 = revert to sprout/sapling; 1 = revert to mature defruited bush.
@export var regrowth_stage_index: int = 0

## Initial growth variance when spawned on fresh map load.
@export_range(0.0, 1.0) var initial_growth_min: float = 0.3
@export_range(0.0, 1.0) var initial_growth_max: float = 1.0

## Audio event triggered on weapon impact (e.g. "wood_chop", "foliage_rustle").
@export var impact_audio_event: String = "wood_chop"

## Tint color for weapon hit sparks/splinters.
@export var hit_particles_color: Color = Color(0.65, 0.45, 0.25)

## Ordered list of growth stages. If empty, get_effective_stages() automatically synthesizes a mature stage.
@export var stages: Array[WildFloraStage] = []


## Returns the active stages list, synthesizing a default mature stage if stages is empty.
func get_effective_stages() -> Array[WildFloraStage]:
	if not stages.is_empty():
		return stages
	
	# 1. Fallback Stage Synthesis: Generates a single mature stage from base def properties.
	return [_create_default_fallback_stage()]


## Returns the stage corresponding to the specified growth progress (0.0 to 1.0).
func get_stage_for_progress(progress: float) -> WildFloraStage:
	var eff_stages: Array[WildFloraStage] = get_effective_stages()
	if eff_stages.is_empty():
		return null
	
	var active_stage: WildFloraStage = eff_stages[0]
	var clamped_progress := clampf(progress, 0.0, 1.0)
	for stage in eff_stages:
		if stage != null and clamped_progress >= stage.min_progress:
			active_stage = stage
	return active_stage


## Returns the stage index for the specified growth progress (0.0 to 1.0).
func get_stage_index_for_progress(progress: float) -> int:
	var eff_stages: Array[WildFloraStage] = get_effective_stages()
	if eff_stages.is_empty():
		return -1
	
	var active_index: int = 0
	var clamped_progress := clampf(progress, 0.0, 1.0)
	for i in range(eff_stages.size()):
		var stage: WildFloraStage = eff_stages[i]
		if stage != null and clamped_progress >= stage.min_progress:
			active_index = i
	return active_index


# ===================
# Auxiliary Functions
# ===================

func _create_default_fallback_stage() -> WildFloraStage:
	## Auxiliary: Creates a synthetic stage when no explicit stages are authored.
	var fallback := WildFloraStage.new()
	fallback.min_progress = 0.0
	fallback.max_hp = hp if hp > 0 else 200
	fallback.scene = default_scene if default_scene != null else scene
	fallback.visual_scale = Vector3.ONE
	fallback.can_harvest_fruit = false
	return fallback
