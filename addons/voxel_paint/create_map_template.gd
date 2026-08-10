@tool
extends EditorScript
## One-shot script: builds subsystems/maps/map_template.tscn — the blank authored
## map scene that VoxelPaint writes into.
##
## Run via editor File → Run (Ctrl+Shift+X) with any scene open. Produces:
##   MapTemplate (Node3D, map.gd, database_path exported)
##     VoxelGrid (Node, voxel_grid.gd)
##       VoxelTerrain (generator, mesher with library)
##     ColonistContainer, EnemyContainer, FurnitureContainer, EnvironmentContainer
##     BuildController (instanced from build.tscn)
##     SpawnPoints → PlayerSpawn (Marker3D)
##
## The baked mesher library (data/blocks/voxel_library.tres) is the decisive
## ingredient for in-editor rendering (Fact 5).
## The stream is wired by map.gd _ready() from the database_path export —
## no manual VoxelStreamSQLite sub-resource needed in the .tscn.

const OUTPUT_PATH := "res://subsystems/maps/map_template.tscn"
const LIBRARY_PATH := "res://data/blocks/voxel_library.tres"


func _run() -> void:
	var root := Node3D.new()
	root.name = "MapTemplate"
	root.set_script(load("res://subsystems/voxel/map.gd"))

	# -- VoxelGrid --
	var grid := Node.new()
	grid.name = "VoxelGrid"
	grid.set_script(load("res://subsystems/voxel/voxel_grid.gd"))
	root.add_child(grid)
	grid.owner = root

	# -- VoxelTerrain --
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"

	# Generator: flat ground (same as base map). voxel_type must be 1 (terrain's
	# library index) — VoxelGeneratorFlat defaults to 0 (air), which renders
	# nothing. See docs/VOXEL-TOOL-NOTES.md "Save the scene after setting voxel_type".
	# NOTE: setting it in memory is not enough — PackedScene.pack() drops this
	# GDExtension property on the programmatic save path (the editor's Ctrl+S path
	# preserves it, which is why the discrepancy goes unnoticed). We re-assert it
	# in the saved .tscn text below (_ensure_voxel_type) as the source of truth.
	var gen := VoxelGeneratorFlat.new()
	gen.channel = 0
	gen.voxel_type = 1
	terrain.generator = gen

	# Mesher: blocky with baked library.
	var mesher := VoxelMesherBlocky.new()
	var baked_lib: Resource = load(LIBRARY_PATH)
	if baked_lib != null:
		mesher.library = baked_lib
		print("MapTemplate: mesher library set from ", LIBRARY_PATH)
	else:
		push_warning("MapTemplate: could not load ", LIBRARY_PATH, " — editor rendering will be blank")
	terrain.mesher = mesher

	# No stream set here — map.gd _ready() creates it from database_path export.

	grid.add_child(terrain)
	terrain.owner = root

	# -- DirectionalLight3D (sun) --
	# Transform mirrors the light in the old hand-authored map scenes: a ~60°
	# sun angle with shadows on. Without a light the editor viewport and any
	# runtime scene stamped from this template render pitch black.
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.transform = Transform3D(
		Vector3(-0.8660254, -0.43301278, 0.25),
		Vector3(0, 0.49999997, 0.86602545),
		Vector3(-0.50000006, 0.75, -0.43301266),
		Vector3.ZERO
	)
	light.shadow_enabled = true
	root.add_child(light)
	light.owner = root

	# -- Containers (match map.tscn structure) --
	for container_name in ["ColonistContainer", "EnemyContainer", "FurnitureContainer", "EnvironmentContainer"]:
		var c := Node3D.new()
		c.name = container_name
		root.add_child(c)
		c.owner = root

	# -- BuildController (instance of build.tscn) --
	var build_scene: PackedScene = load("res://subsystems/build/build.tscn")
	if build_scene != null:
		var ctrl := build_scene.instantiate()
		ctrl.name = "BuildController"
		root.add_child(ctrl)
		ctrl.owner = root
	else:
		push_error("MapTemplate: could not load build.tscn")

	# -- SpawnPoints --
	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	root.add_child(spawns)
	spawns.owner = root

	var player_spawn := Marker3D.new()
	player_spawn.name = "PlayerSpawn"
	player_spawn.transform = Transform3D(
		Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
		Vector3(0, 5, 0)
	)
	spawns.add_child(player_spawn)
	player_spawn.owner = root

	# -- Save --
	var result := PackedScene.new()
	result.pack(root)
	var err := ResourceSaver.save(result, OUTPUT_PATH)
	if err == OK:
		# PackedScene.pack() drops VoxelGeneratorFlat.voxel_type on the programmatic
		# save path (it survives the editor's Ctrl+S path but not this one), leaving
		# the generator at its default 0 (air) — flat ground then generates as
		# all-air, so the paint tool's voxel march never hits a solid cell and
		# placement silently no-ops. Re-assert voxel_type = 1 in the saved text.
		# This is the authoritative fix; the in-memory gen.voxel_type above is kept
		# only for parity/inspection. See VOXEL-TOOL-NOTES.md "Save the scene after
		# setting voxel_type".
		_ensure_voxel_type(OUTPUT_PATH, TERRAIN_VOXEL_TYPE)
		print("MapTemplate: saved to ", OUTPUT_PATH)
		EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("MapTemplate: failed to save (error %d)" % err)

	root.queue_free()


# Library index written into VoxelGeneratorFlat.voxel_type. Must be 1 (terrain)
# so VoxelGeneratorFlat emits solid terrain instead of air (index 0).
const TERRAIN_VOXEL_TYPE := 1


## Patch every VoxelGeneratorFlat sub_resource in `path` so its voxel_type equals
## `value`. Idempotent: sets it if missing, corrects it if wrong, leaves it if
## already right. Operates on the .tscn text directly because pack()/save() drop
## this GDExtension property on the programmatic save path. Aborts (push_error)
## if no VoxelGeneratorFlat sub_resource is present — that would mean the terrain
## node itself failed to serialize, a different and more severe problem.
static func _ensure_voxel_type(path: String, value: int) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MapTemplate: could not re-open %s to patch voxel_type" % path)
		return
	var text := f.get_as_text()
	f.close()

	# Lines that start the VoxelGeneratorFlat sub_resource block, e.g.:
	#   [sub_resource type="VoxelGeneratorFlat" id="..."]
	var sub_re := RegEx.new()
	sub_re.compile(r'^\[sub_resource type="VoxelGeneratorFlat"[^\]]*\]$')

	# An existing voxel_type = <int> assignment line. .tscn sub_resource
	# properties have no leading whitespace, so anchor to start-of-line.
	var prop_re := RegEx.new()
	prop_re.compile(r'^voxel_type = ')
	var target_line := "voxel_type = %d" % value

	var lines := text.split("\n")
	var in_block := false
	var saw_prop_in_block := false  # did the current block already have voxel_type?
	var found_block := false
	var changed := false
	var out_lines: PackedStringArray = []
	for i in lines.size():
		var line: String = lines[i]
		# A [section] header ends the current sub_resource block (if any) BEFORE we
		# consider it as a new block. Order matters: if we matched sub_re first, a
		# second VoxelGeneratorFlat header would re-enter the header branch while
		# still inside the previous block, skipping its close-out injection.
		if in_block and line.begins_with("["):
			if not saw_prop_in_block:
				out_lines.append(target_line)
				changed = true
			in_block = false
		if sub_re.search(line) != null:
			in_block = true
			saw_prop_in_block = false
			found_block = true
			out_lines.append(line)
			continue
		if in_block:
			if prop_re.search(line) != null:
				saw_prop_in_block = true
				if line != target_line:
					out_lines.append(target_line)
					changed = true
				else:
					out_lines.append(line)
				continue
			out_lines.append(line)
			continue
		out_lines.append(line)

	# If the file ends while still inside the last block (no trailing section),
	# close it out the same way as above.
	if in_block and not saw_prop_in_block:
		out_lines.append(target_line)
		changed = true

	if not found_block:
		push_error("MapTemplate: no VoxelGeneratorFlat sub_resource in %s — "
				% path + "terrain node may not have serialized; check the .tscn")
		return

	if not changed:
		return  # already correct

	var written := FileAccess.open(path, FileAccess.WRITE)
	if written == null:
		push_error("MapTemplate: could not write patched %s" % path)
		return
	written.store_string("\n".join(out_lines))
	written.close()
	print("MapTemplate: asserted voxel_type = %d in %s" % [value, path])
