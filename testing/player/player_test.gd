extends Node3D
## Player controller feel-test: walk over the voxel terrain + mouse-look.
##
## Instances world.tscn (the terrain) and player.tscn, adds a VoxelViewer so the
## terrain streams collision around the player (player.tscn must stay
## voxel-agnostic per ARCH line 138, so the viewer lives here in the test).
## Also scatters colored beacon landmarks so movement/speed is visible against an
## otherwise flat, single-color terrain.
##
## WASD move, mouse look, Esc release / click to recapture.

# Beacon colors per ring (innermost first). Terrain top surface sits at y=0, so
# beacons stand on y=0 and rise from there.
const _RING_RADIUS := [4, 8, 14, 22, 32]
const _RING_COLORS := [
	Color(0.20, 0.80, 0.20), # ring 1 — green (closest)
	Color(0.95, 0.85, 0.10), # ring 2 — yellow
	Color(0.95, 0.45, 0.10), # ring 3 — orange
	Color(0.90, 0.20, 0.20), # ring 4 — red
	Color(0.55, 0.30, 0.90), # ring 5 — purple (farthest)
]
const _BEACON_HEIGHT := 4.0
const _BEACON_SIZE := 0.6

func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)

	var world: Node3D = preload("res://voxel/world.tscn").instantiate()
	add_child(world)

	# Player drops in a couple meters above the terrain so it settles onto it.
	var player: Node3D = preload("res://player/player.tscn").instantiate()
	player.global_position = Vector3(0, 5, 0)
	world.add_child(player)

	# VoxelViewer parented to the player so terrain streams + generates collision
	# wherever the player is. (The camera is a child of the player via the rig, so
	# streaming follows movement automatically.)
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	player.add_child(viewer)

	_spawn_landmarks(world)

## Scatter colored beacon rings around spawn so walking has visible reference
## points (terrain is otherwise one flat color to the horizon). These are plain
## MeshInstance3D markers, not voxel blocks — they're test scaffolding, not game
## content, so they don't go through VoxelGrid or the block data.
func _spawn_landmarks(world: Node) -> void:
	# A tall marker at spawn so the origin is unmistakable from anywhere.
	_add_beacon(world, Vector3.ZERO, Color(1, 1, 1), _BEACON_HEIGHT * 1.5, _BEACON_SIZE * 1.2)
	for ring_i in _RING_RADIUS.size():
		var r: float = _RING_RADIUS[ring_i]
		var color: Color = _RING_COLORS[ring_i]
		# 8 beacons per ring at fixed angles; same angles across rings so the
		# radial lines read as distance lanes.
		for i in 8:
			var angle := TAU * i / 8.0
			var pos := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
			_add_beacon(world, pos, color, _BEACON_HEIGHT, _BEACON_SIZE)

func _add_beacon(parent: Node, pos: Vector3, color: Color, height: float, size: float) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size, height, size)
	mi.mesh = box
	mi.position = pos + Vector3(0, height * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	parent.add_child(mi)
