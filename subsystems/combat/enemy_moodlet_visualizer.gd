## Subsystem: Combat / Visuals
## In-world 3D billboard visualizer for displaying active moodlet icons over an enemy's head (ARCH combat.md).
class_name EnemyMoodletVisualizer
extends Node3D

@export var enabled: bool = true
@export var height_offset: float = 2.0
@export var line_spacing: float = 0.35
@export var update_interval: float = 0.25
@export var visibility_range_end: float = 35.0
@export var pixel_size: float = 0.001
@export var icon_spacing: float = 0.35
@export var max_icons: int = 4
@export var frame_fps: float = 6.0

var _enemy: EnemyBase
var _sprites: Array[Sprite3D] = []
var _timer: float = 0.0
var _anim_timer: float = 0.0


# =================
# Primary Functions
# =================

func _ready() -> void:
	# 1. Parent Resolution: Resolve the parent EnemyBase entity node.
	_enemy = get_parent() as EnemyBase
	if _enemy == null:
		push_warning("EnemyMoodletVisualizer must be a child of an EnemyBase entity.")
		set_process(false)
		return
	
	# 2. Initial Setup: Allocate initial billboard sprite in the pool.
	_ensure_sprite_capacity(1)
	
	# 3. Camera Alignment: Orient the visualizer node to the active camera.
	_align_to_camera()
	
	# 4. Initial Evaluation: Immediately refresh active moodlets display.
	_update_moodlet_display()


func _process(delta: float) -> void:
	if not enabled or _enemy == null:
		return
	
	# 1. Camera Alignment: Orient the visualizer node so the icon row always aligns with the camera view plane.
	_align_to_camera()
	
	# 2. Animation Tick: Advance spritesheet frame timers for animated sprites.
	_tick_spritesheet_animation(delta)
	
	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		# 3. Periodic Tick: Refresh active moodlet display.
		_update_moodlet_display()


# ===================
# Auxiliary Functions
# ===================

func _align_to_camera() -> void:
	## Auxiliary: Rotates the visualizer to align its local X-axis with the active camera's horizontal view vector.
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	
	global_rotation.y = cam.global_rotation.y


func _tick_spritesheet_animation(delta: float) -> void:
	## Auxiliary: Advances the animation timer and updates frame indices for animated spritesheet icons.
	_anim_timer += delta
	for sprite in _sprites:
		if sprite != null and sprite.visible and sprite.hframes > 1:
			var fps: float = float(sprite.get_meta("fps", frame_fps))
			var total_frames: int = sprite.hframes
			var current_frame: int = int(_anim_timer * fps) % total_frames
			sprite.frame = current_frame


func _update_moodlet_display() -> void:
	## Auxiliary: Queries active moodlets from the enemy and positions billboard sprites in a row.
	if _enemy == null:
		return
	
	# 1. Active Moodlet Query: Collect all valid moodlets with non-null textures.
	var valid_moodlets: Array[Dictionary] = _collect_valid_moodlets()
	
	# 2. Sprite Synchronization: Synchronize billboard Sprite3D instances to match the active count.
	_sync_sprites(valid_moodlets)


func _collect_valid_moodlets() -> Array[Dictionary]:
	## Auxiliary: Retrieves active moodlets from enemy and filters for those with non-null textures.
	var result: Array[Dictionary] = []
	if not _enemy.has_method("get_active_moodlets"):
		return result
	var active_moodlets: Array[Dictionary] = _enemy.get_active_moodlets()
	for moodlet in active_moodlets:
		var tex: Texture2D = moodlet.get("texture", null)
		if tex != null:
			result.append(moodlet)
	return result


func _sync_sprites(valid_moodlets: Array[Dictionary]) -> void:
	## Auxiliary: Updates positions, textures, and visibility for all sprite billboard instances.
	var count: int = mini(valid_moodlets.size(), max_icons)
	
	# 1. Capacity Assurance: Ensure sufficient Sprite3D instances exist in the pool.
	_ensure_sprite_capacity(count)
	
	# 2. Active Layout: Position and assign textures to active sprites grouped by line number.
	_layout_active_sprites(valid_moodlets, count)
	
	# 3. Inactive Cleanup: Hide surplus sprite instances beyond the active count.
	_hide_surplus_sprites(count)


func _ensure_sprite_capacity(required_count: int) -> void:
	## Auxiliary: Instantiates additional Sprite3D instances if pool capacity is below required count.
	while _sprites.size() < required_count:
		var sprite := Sprite3D.new()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.pixel_size = pixel_size
		sprite.no_depth_test = false
		sprite.visibility_range_end = visibility_range_end
		sprite.position = Vector3(0.0, height_offset, 0.0)
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)


func _layout_active_sprites(valid_moodlets: Array[Dictionary], count: int) -> void:
	## Auxiliary: Configures billboard textures, hframes, and positions sprites across active lines.
	# 1. Line Grouping: Group the capped active moodlets by line number.
	var grouped_lines: Dictionary = _group_moodlets_by_line(valid_moodlets, count)
	
	# 2. Active Line Sorting: Extract unique active line numbers in ascending order.
	var active_lines: Array[int] = _get_sorted_active_lines(grouped_lines)
	
	# 3. Grid Positioning: Layout sprites in compacted rows above the entity.
	_position_grouped_sprites(grouped_lines, active_lines)


func _group_moodlets_by_line(valid_moodlets: Array[Dictionary], count: int) -> Dictionary:
	## Auxiliary: Buckets active moodlet records by their line_number property.
	var grouped: Dictionary = {}
	for i in range(count):
		var moodlet_data: Dictionary = valid_moodlets[i]
		var m_def: MoodletDef = moodlet_data.get("def", null) as MoodletDef
		var line_num: int = m_def.line_number if m_def != null else 0
		if not grouped.has(line_num):
			grouped[line_num] = []
		var line_list: Array = grouped[line_num]
		line_list.append(moodlet_data)
	return grouped


func _get_sorted_active_lines(grouped_lines: Dictionary) -> Array[int]:
	## Auxiliary: Extracts sorted ascending line numbers from grouped dictionary.
	var keys: Array[int] = []
	for k in grouped_lines.keys():
		keys.append(int(k))
	keys.sort()
	return keys


func _position_grouped_sprites(grouped_lines: Dictionary, active_lines: Array[int]) -> void:
	## Auxiliary: Places billboard sprites row-by-row skipping empty lines.
	var sprite_index: int = 0
	for row_index in range(active_lines.size()):
		var line_num: int = active_lines[row_index]
		var line_moodlets: Array = grouped_lines[line_num]
		var line_count: int = line_moodlets.size()
		var row_y: float = height_offset + float(row_index) * line_spacing
		
		for col_index in range(line_count):
			var sprite: Sprite3D = _sprites[sprite_index]
			var moodlet_data: Dictionary = line_moodlets[col_index]
			# 1. Sprite Setup: Apply texture and animation metadata to billboard sprite.
			_apply_sprite_moodlet_data(sprite, moodlet_data, col_index, line_count, row_y)
			sprite_index += 1


func _apply_sprite_moodlet_data(sprite: Sprite3D, moodlet_data: Dictionary, col_index: int, line_count: int, row_y: float) -> void:
	## Auxiliary: Sets sprite texture, frame properties, and centered position.
	var tex: Texture2D = moodlet_data["texture"]
	var m_def: MoodletDef = moodlet_data.get("def", null) as MoodletDef
	
	var hframes: int = 1
	var fps: float = frame_fps
	if m_def != null:
		hframes = m_def.get_hframes(_enemy)
		fps = m_def.get_fps(_enemy)
		
	var offset_x: float = (float(col_index) - float(line_count - 1) * 0.5) * icon_spacing
	sprite.position = Vector3(offset_x, row_y, 0.0)
	sprite.pixel_size = pixel_size
	sprite.visibility_range_end = visibility_range_end
	sprite.texture = tex
	sprite.hframes = hframes
	sprite.set_meta("fps", fps)
	if hframes > 1:
		sprite.frame = int(_anim_timer * fps) % hframes
	else:
		sprite.frame = 0
	sprite.visible = true


func _hide_surplus_sprites(start_index: int) -> void:
	## Auxiliary: Hides and clears unused Sprite3D nodes from start_index onward.
	for i in range(start_index, _sprites.size()):
		var sprite: Sprite3D = _sprites[i]
		sprite.visible = false
		sprite.texture = null
		sprite.hframes = 1
		sprite.frame = 0
