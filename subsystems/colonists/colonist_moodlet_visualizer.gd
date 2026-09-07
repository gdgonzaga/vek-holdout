## Subsystem: Colonists / Visuals
## In-world 3D billboard visualizer for displaying active moodlet icons over a colonist's head (ARCH §6).
class_name ColonistMoodletVisualizer
extends Node3D

@export var enabled: bool = true
@export var height_offset: float = 2.0
@export var update_interval: float = 0.25
@export var visibility_range_end: float = 35.0
@export var pixel_size: float = 0.0005

var _colonist: Colonist99
var _sprite: Sprite3D
var _timer: float = 0.0


# =================
# Primary Functions
# =================

func _ready() -> void:
	# 1. Parent Resolution: Resolve the parent Colonist entity node.
	_colonist = get_parent() as Colonist
	if _colonist == null:
		push_warning("ColonistMoodletVisualizer must be a child of a Colonist entity.")
		set_process(false)
		return
	
	# 2. Sprite Setup: Create and configure the billboarded Sprite3D component.
	_setup_sprite()
	
	# 3. Initial Evaluation: Immediately refresh moodlet display state.
	_update_moodlet_display()


func _process(delta: float) -> void:
	if not enabled or _colonist == null or _sprite == null:
		return
	
	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		# 1. Periodic Tick: Refresh active moodlet display.
		_update_moodlet_display()


# ===================
# Auxiliary Functions
# ===================

func _setup_sprite() -> void:
	## Auxiliary: Instantiates and attaches the configured 3D billboard sprite.
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.pixel_size = pixel_size
	_sprite.no_depth_test = false
	_sprite.visibility_range_end = visibility_range_end
	_sprite.position = Vector3(0, height_offset, 0)
	_sprite.visible = false
	add_child(_sprite)


func _update_moodlet_display() -> void:
	## Auxiliary: Queries active moodlets from the colonist and updates billboard texture visibility.
	if _colonist == null or _sprite == null:
		return
	
	var active_moodlets: Array[Dictionary] = _colonist.get_active_moodlets()
	if active_moodlets.is_empty():
		_sprite.visible = false
		_sprite.texture = null
		return
	
	# Display primary (most urgent/highest-order) active moodlet icon
	var primary: Dictionary = active_moodlets[0]
	var tex: Texture2D = primary.get("texture", null)
	if tex != null:
		_sprite.texture = tex
		_sprite.visible = true
	else:
		_sprite.visible = false
