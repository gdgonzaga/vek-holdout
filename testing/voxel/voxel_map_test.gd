extends Node3D
## Integration test for the Voxel / Map subsystem.
## Loads the real map.tscn, flies a camera through it, and exercises VoxelGrid:
##   - places one block of every buildable type (wood/scrap/stone/metal/reinforced)
##   - verifies get_block_at round-trips the block_id
##   - verifies raycast_to_voxel hits placed blocks
## Results print to console + an on-screen label.
##
## Controls: WASD move, Space/C up-down, Shift fast, click to grab, Esc release.

const BLOCK_TYPES := ["wood", "scrap", "stone", "metal", "reinforced"]

var _map: Map
var _camera: Camera3D
var _label: Label
var _diagnostics := PackedStringArray()

func _ready() -> void:
	# Lighting + sky so the map is visible.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)

	# The real MapRoot.
	_map = preload("res://subsystems/voxel/map.tscn").instantiate()
	add_child(_map)

	# Fly camera + viewer (drives terrain streaming + collision for raycasts).
	_camera = Camera3D.new()
	_camera.current = true
	_camera.global_position = Vector3(4, 8, 12)
	_camera.rotation_degrees = Vector3(-35, -20, 0)
	add_child(_camera)
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	_camera.add_child(viewer)

	# On-screen diagnostics.
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_label)

	_run_tests()

func _run_tests() -> void:
	# Let terrain stream in before we read/write.
	await get_tree().create_timer(0.5).timeout

	var grid: VoxelGrid = _map.get_grid()
	_diagnostics.append("=== Voxel/Map subsystem test ===")

	# 1) Place one of each buildable type in a row on top of the terrain (y=1).
	var y := 1
	var all_placed := true
	for i in BLOCK_TYPES.size():
		var pos := Vector3i(i * 2, y, 0)
		grid.set_block_at(pos, BLOCK_TYPES[i])
		var got := grid.get_block_at(pos)
		var ok: bool = got == BLOCK_TYPES[i]
		all_placed = all_placed and ok
		_diagnostics.append("place %-10s @ %-18s : %s" % [BLOCK_TYPES[i], str(pos), "PASS" if ok else "FAIL (got '%s')" % got])

	# 2) Empty cell reads as air ("").
	var air_ok := grid.get_block_at(Vector3i(50, 50, 50)) == ""
	_diagnostics.append("air readback @ (50,50,50)      : %s" % ("PASS" if air_ok else "FAIL"))

	# 3) HP tracking: placed block has full BlockDef HP.
	var stone_def: BlockDef = grid.get_library().get_def("stone")
	var hp_ok := grid.get_hp_at(Vector3i(0, y, 0)) == stone_def.hp
	_diagnostics.append("hp tracking (wood full=%d)     : %s" % [stone_def.hp, "PASS" if hp_ok else "FAIL"])

	# 4) Damage -> destroy emits block_destroyed and clears the cell.
	var target := Vector3i(0, y, 0)
	grid.apply_damage(target, 9999)
	var destroyed_ok := grid.get_block_at(target) == "" and not grid.has_block_at(target)
	_diagnostics.append("apply_damage destroys wood     : %s" % ("PASS" if destroyed_ok else "FAIL"))

	# 5) raycast_to_voxel hits a placed block after collision has streamed.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var block_top := Vector3(2, y, 0) + Vector3(0.5, 1.0, 0.5) # center of top face
	var rc := grid.raycast_to_voxel(block_top + Vector3(0, 5, 0), Vector3.DOWN, 20.0)
	var ray_ok: bool = rc.get("hit", false) and rc.get("position") == Vector3i(2, y, 0)
	_diagnostics.append("raycast_to_voxel @ (2,1,0)     : %s" % ("PASS" if ray_ok else "FAIL %s" % str(rc)))

	_diagnostics.append("")
	_diagnostics.append("ALL: %s" % ("PASS" if all_placed and air_ok and hp_ok and destroyed_ok and ray_ok else "FAIL"))
	_diagnostics.append("controls: WASD move, Space/C up-down, Shift fast")
	_diagnostics.append("click to grab mouse, Esc to release")
	_refresh()

func _refresh() -> void:
	if _label:
		_label.text = "\n".join(_diagnostics)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera.rotation_degrees.y -= event.relative.x * 0.2
		_camera.rotation_degrees.x -= event.relative.y * 0.2
		_camera.rotation_degrees.x = clamp(_camera.rotation_degrees.x, -89.0, 89.0)

func _process(delta: float) -> void:
	if _camera == null:
		return
	var speed := 12.0 if Input.is_key_pressed(KEY_SHIFT) else 5.0
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := _camera.global_transform.basis.x
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move += forward
	if Input.is_key_pressed(KEY_S): move -= forward
	if Input.is_key_pressed(KEY_D): move += right
	if Input.is_key_pressed(KEY_A): move -= right
	if Input.is_key_pressed(KEY_SPACE): move += Vector3.UP
	if Input.is_key_pressed(KEY_C): move += Vector3.DOWN
	if move != Vector3.ZERO:
		_camera.global_position += move.normalized() * speed * delta
