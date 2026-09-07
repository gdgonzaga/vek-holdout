## Data Schema: MoodletDef
## Base Resource definition for colonist moodlets (ARCH §6).
## Defines moodlet metadata and provides virtual state/icon evaluation.
extends Resource
class_name MoodletDef

@export var id: StringName = &""
@export var display_name: String = ""
@export var icons: Array[Texture2D] = []
## Optional array of horizontal spritesheet frame counts corresponding 1-to-1 with the icons array.
## Defaults to 1 (single static frame) if unconfigured or out-of-bounds.
@export var icon_hframes: Array[int] = []
## Default animation playback speed in frames per second (FPS) for animated icons.
@export var frame_fps: float = 6.0
## Optional per-icon tier FPS overrides corresponding 1-to-1 with the icons array.
@export var icon_fps: Array[float] = []


# =================
# Primary Functions
# =================

## Virtual: Evaluates the entity state and returns the icon index to display.
## Returns < 0 (e.g. -1) if the moodlet is inactive/hidden, or >= 0 for the active icon index.
func evaluate_icon_index(entity: Node) -> int:
	return -1


## Safe getter: Resolves the active texture based on entity state.
## Returns null if inactive or icons is empty. Clamps to the highest available icon if out-of-bounds.
func get_active_texture(entity: Node) -> Texture2D:
	# 1. State Evaluation: Query the active icon index for the given entity.
	var index: int = evaluate_icon_index(entity)
	if index < 0 or icons.is_empty():
		return null
	
	# 2. Texture Resolution: Safely clamp and retrieve the texture asset from the icons array.
	return _resolve_texture_at_index(index)


## Resolves the horizontal spritesheet frame count for the entity's currently active icon tier.
func get_hframes(entity: Node) -> int:
	# 1. State Evaluation: Query the active icon index for the given entity.
	var index: int = evaluate_icon_index(entity)
	if index < 0 or icon_hframes.is_empty():
		return 1
	
	# 2. Frame Count Resolution: Look up horizontal frame count for the active index tier.
	return _resolve_hframes_at_index(index)


## Resolves the animation playback speed (FPS) for the entity's currently active icon tier.
func get_fps(entity: Node) -> float:
	# 1. State Evaluation: Query the active icon index for the given entity.
	var index: int = evaluate_icon_index(entity)
	if index >= 0 and index < icon_fps.size() and icon_fps[index] > 0.0:
		return icon_fps[index]
	return frame_fps if frame_fps > 0.0 else 6.0


# ===================
# Auxiliary Functions
# ===================

func _resolve_texture_at_index(index: int) -> Texture2D:
	## Auxiliary: Retrieves texture at index with defensive clamping and developer warnings on out-of-bounds.
	if index >= icons.size():
		push_warning("MoodletDef '%s': evaluate_icon_index returned %d, exceeding icons array size (%d). Clamping to highest available icon." % [
			id if id != &"" else resource_path,
			index,
			icons.size()
		])
		return icons.back()
	return icons[index]


func _resolve_hframes_at_index(index: int) -> int:
	## Auxiliary: Resolves horizontal frame count at specified index tier, returning 1 for unconfigured tiers.
	if index < icon_hframes.size():
		return maxi(1, icon_hframes[index])
	return 1
