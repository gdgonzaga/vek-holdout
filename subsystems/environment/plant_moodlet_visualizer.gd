## Subsystem: Environment / Visuals
## In-world 3D billboard visualizer for displaying active moodlet icons over plants and harvestables (ARCH §6, GDD §6.10).
class_name PlantMoodletVisualizer
extends Node3D

const DEFAULT_ORDER_MOODLET_PATH := "res://data/moodlets/plant_order_moodlet.tres"

@export var enabled: bool = true
@export var height_offset: float = 0.4
@export var line_spacing: float = 0.35
@export var update_interval: float = 0.5
@export var visibility_range_end: float = 35.0
@export var pixel_size: float = 0.002
@export var icon_spacing: float = 0.4
@export var max_icons: int = 4
@export var frame_fps: float = 6.0
@export var moodlet_defs: Array[MoodletDef] = []

var _furniture: Furniture
var _sprites: Array[Sprite3D] = []
var _timer: float = 0.0
var _anim_timer: float = 0.0
var _has_visible_sprites: bool = false
var _active_moodlets: Array[Dictionary] = []


# =================
# Primary Functions
# =================

func _ready() -> void:
	# 1. Parent Entity Resolution: Identify parent Furniture node.
	_furniture = _resolve_parent_furniture()

	# 2. Moodlet Definitions Initialization: Assign default plant order moodlet if unassigned.
	_initialize_default_moodlet_defs()

	# 3. Position Configuration: Position billboard above the flora/furniture bounding height.
	_apply_height_offset()

	# 4. Event Subscription: Listen for harvest mark toggles to trigger immediate visual refresh.
	_connect_event_bus_signals()

	# 5. Pool Allocation: Prepare initial sprite pool instance.
	_ensure_sprite_capacity(1)

	# 6. Display Refresh: Initial evaluation of active moodlet icons.
	refresh()


func _process(delta: float) -> void:
	if not enabled or not _has_visible_sprites:
		return

	# 1. Camera Alignment: Orient icon plane to face active camera horizontally.
	_align_to_camera()

	# 2. Animation Tick: Advance spritesheet frames for animated icons.
	_tick_spritesheet_animation(delta)

	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		# 3. Periodic Evaluation: Query and synchronize active moodlet state.
		refresh()


func _exit_tree() -> void:
	# 1. Event Cleanup: Disconnect event bus listeners to prevent stale references.
	_disconnect_event_bus_signals()


## Evaluates active moodlets and refreshes in-world sprite billboards immediately.
func refresh() -> void:
	if not enabled or not is_inside_tree():
		return

	# 1. Moodlet Query: Collect all currently active moodlet records.
	_active_moodlets = _collect_valid_moodlets()

	# 2. Sprite Pool Synchronization: Update sprite billboards to reflect active moodlets.
	_sync_sprites(_active_moodlets)

	# 3. State Tracking: Cache whether any sprites are currently visible.
	_has_visible_sprites = not _active_moodlets.is_empty()

	if _has_visible_sprites:
		# 4. Camera Alignment: Align immediately upon becoming visible.
		_align_to_camera()


## Returns the cached active moodlets currently displayed on the billboard.
func get_active_moodlets() -> Array[Dictionary]:
	return _active_moodlets


## Returns whether any billboard sprite is currently visible.
func is_showing_moodlet() -> bool:
	return _has_visible_sprites


## Returns the internal pool of billboard sprites.
func get_sprites() -> Array[Sprite3D]:
	return _sprites


# ===================
# Auxiliary Functions
# ===================

func _resolve_parent_furniture() -> Furniture:
	## Auxiliary: Resolves parent node to Furniture instance if available.
	var parent := get_parent()
	if parent is Furniture:
		return parent as Furniture
	return null


func _initialize_default_moodlet_defs() -> void:
	## Auxiliary: Loads the default plant order moodlet resource if defs are unconfigured.
	if moodlet_defs.is_empty() and ResourceLoader.exists(DEFAULT_ORDER_MOODLET_PATH):
		var default_res := load(DEFAULT_ORDER_MOODLET_PATH) as MoodletDef
		if default_res != null:
			moodlet_defs.append(default_res)


func _apply_height_offset() -> void:
	## Auxiliary: Adjusts local Y-position based on furniture dimensions.
	var base_y: float = 1.0
	if _furniture != null:
		var dims: Vector3i = _furniture.dimensions if "dimensions" in _furniture else Vector3i(1, 1, 1)
		base_y = float(dims.y)
	position = Vector3(0.0, base_y + height_offset, 0.0)


func _connect_event_bus_signals() -> void:
	## Auxiliary: Subscribes to harvest_mark_toggled for reactive refresh.
	if EventBus != null and not EventBus.harvest_mark_toggled.is_connected(_on_harvest_mark_toggled):
		EventBus.harvest_mark_toggled.connect(_on_harvest_mark_toggled)


func _disconnect_event_bus_signals() -> void:
	## Auxiliary: Unsubscribes from EventBus signals upon tree exit.
	if EventBus != null and EventBus.harvest_mark_toggled.is_connected(_on_harvest_mark_toggled):
		EventBus.harvest_mark_toggled.disconnect(_on_harvest_mark_toggled)


func _on_harvest_mark_toggled(furniture: Node, _anchor: Vector3i, _marked: bool) -> void:
	## Auxiliary: Reacts to harvest toggle events matching this furniture instance.
	if furniture == _furniture or furniture == self or furniture == get_parent():
		refresh()


func _align_to_camera() -> void:
	## Auxiliary: Rotates node to align with active camera's horizontal view vector.
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	global_rotation.y = cam.global_rotation.y


func _tick_spritesheet_animation(delta: float) -> void:
	## Auxiliary: Updates frame property of multi-frame spritesheet icons.
	_anim_timer += delta
	for sprite in _sprites:
		if sprite != null and sprite.visible and sprite.hframes > 1:
			var fps: float = float(sprite.get_meta("fps", frame_fps))
			var total_frames: int = sprite.hframes
			var current_frame: int = int(_anim_timer * fps) % total_frames
			sprite.frame = current_frame


func _collect_valid_moodlets() -> Array[Dictionary]:
	## Auxiliary: Queries active moodlets from parent furniture or local moodlet_defs without duplicates.
	var results: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	var target_node: Node = _furniture if _furniture != null else get_parent()
	if target_node == null:
		return results

	# 1. Query entity's own get_active_moodlets if implemented
	if target_node.has_method("get_active_moodlets"):
		var entity_moodlets: Array[Dictionary] = target_node.call("get_active_moodlets")
		for m in entity_moodlets:
			var m_def: MoodletDef = m.get("def", null)
			var m_id: StringName = m_def.id if m_def != null else &""
			if m.get("texture", null) != null:
				results.append(m)
				if m_id != &"":
					seen_ids[m_id] = true

	# 2. Query local moodlet_defs on target_node
	for m_def in moodlet_defs:
		if m_def == null or seen_ids.has(m_def.id):
			continue
		var idx: int = m_def.evaluate_icon_index(target_node)
		if idx >= 0:
			var tex: Texture2D = m_def.get_active_texture(target_node)
			if tex != null:
				results.append({
					"def": m_def,
					"index": idx,
					"texture": tex,
					"name": m_def.display_name,
				})
				if m_def.id != &"":
					seen_ids[m_def.id] = true

	return results


func _sync_sprites(valid_moodlets: Array[Dictionary]) -> void:
	## Auxiliary: Updates positions, textures, and visibility for all sprite billboard instances.
	# 1. Line Grouping: Group active moodlets into rows by line_number property.
	var grouped_lines: Dictionary = _group_moodlets_by_line(valid_moodlets, max_icons)
	
	# 2. Line Ordering: Sort line keys ascending to stack rows vertically.
	var active_lines: Array[int] = _get_sorted_active_lines(grouped_lines)
	
	# 3. Sprite Count Calculation: Calculate total required active sprites.
	var count: int = _count_grouped_sprites(grouped_lines, active_lines)

	# 4. Capacity Assurance: Ensure sufficient Sprite3D instances exist in the pool.
	_ensure_sprite_capacity(count)

	# 5. Active Layout: Position and assign textures to active sprites grouped by line number.
	_position_grouped_sprites(grouped_lines, active_lines)

	# 6. Inactive Cleanup: Hide surplus sprite instances beyond the active count.
	_hide_surplus_sprites(count)


func _group_moodlets_by_line(valid_moodlets: Array[Dictionary], per_line_cap: int) -> Dictionary:
	## Auxiliary: Buckets active moodlet records by line_number, capping each row independently.
	var grouped: Dictionary = {}
	for moodlet_data: Dictionary in valid_moodlets:
		var m_def: MoodletDef = moodlet_data.get("def", null) as MoodletDef
		var line_num: int = m_def.line_number if m_def != null else 0
		if not grouped.has(line_num):
			grouped[line_num] = []
		var line_list: Array = grouped[line_num]
		if line_list.size() < per_line_cap:
			line_list.append(moodlet_data)
	return grouped


func _get_sorted_active_lines(grouped_lines: Dictionary) -> Array[int]:
	## Auxiliary: Extracts sorted ascending line numbers from grouped dictionary.
	var keys: Array[int] = []
	for k in grouped_lines.keys():
		keys.append(int(k))
	keys.sort()
	return keys


func _count_grouped_sprites(grouped_lines: Dictionary, active_lines: Array[int]) -> int:
	## Auxiliary: Sums sprite counts across all active lines after per-line capping.
	var total := 0
	for line_num in active_lines:
		total += (grouped_lines[line_num] as Array).size()
	return total


func _position_grouped_sprites(grouped_lines: Dictionary, active_lines: Array[int]) -> void:
	## Auxiliary: Places billboard sprites row-by-row skipping empty lines.
	var sprite_index: int = 0
	for row_index in range(active_lines.size()):
		var line_num: int = active_lines[row_index]
		var line_moodlets: Array = grouped_lines[line_num]
		var line_count: int = line_moodlets.size()
		var row_y: float = float(row_index) * line_spacing

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

	var target_node: Node = _furniture if _furniture != null else get_parent()
	var hframes: int = 1
	var fps: float = frame_fps
	if m_def != null and target_node != null:
		hframes = m_def.get_hframes(target_node)
		fps = m_def.get_fps(target_node)

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


func _ensure_sprite_capacity(required: int) -> void:
	## Auxiliary: Expands the Sprite3D instance pool up to required capacity.
	while _sprites.size() < required:
		var sprite := Sprite3D.new()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.pixel_size = pixel_size
		sprite.no_depth_test = true
		sprite.render_priority = 10
		sprite.visibility_range_end = visibility_range_end
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
