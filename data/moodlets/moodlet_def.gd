## Data Schema: MoodletDef
## Base Resource definition for colonist moodlets (ARCH §6).
## Defines moodlet metadata and provides virtual state/icon evaluation.
extends Resource
class_name MoodletDef

@export var id: StringName = &""
@export var display_name: String = ""
@export var icons: Array[Texture2D] = []


# =================
# Primary Functions
# =================

## Virtual: Evaluates the colonist state and returns the icon index to display.
## Returns < 0 (e.g. -1) if the moodlet is inactive/hidden, or >= 0 for the active icon index.
func evaluate_icon_index(colonist: Colonist) -> int:
	return -1


## Safe getter: Resolves the active texture based on colonist state.
## Returns null if inactive or icons is empty. Clamps to the highest available icon if out-of-bounds.
func get_active_texture(colonist: Colonist) -> Texture2D:
	# 1. State Evaluation: Query the active icon index for the given colonist.
	var index: int = evaluate_icon_index(colonist)
	if index < 0 or icons.is_empty():
		return null
	
	# 2. Texture Resolution: Safely clamp and retrieve the texture asset from the icons array.
	return _resolve_texture_at_index(index)


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
