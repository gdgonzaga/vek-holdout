extends RefCounted
## A small real Map holding BOTH grids as recording doubles, plus wall fixtures and player
## spawners, for tests of what the player's LMB and wading do to the world.
##
## The grids are doubles (no voxel streaming) and the "terrain" is a StaticBody3D wall placed
## under whichever node owns it, so a crosshair ray hits a collider with the same ancestry a
## streamed VoxelTerrain block has: VoxelTerrain -> grid -> Map. The Map owns BOTH grids, which
## is what makes ancestry-only lookups claim every hit. A plain script, never a suite (the
## runner would scan it), used as `MiningRig.new(self)` from a suite.

const PlayerScene = preload("res://subsystems/player/player.tscn")


## SmoothGrid double: records damage instead of touching voxel_tool. Skips the real _ready
## (terrain generation setup); the @onready terrain ref is null-safe.
class RecordingSmoothGrid extends SmoothGrid:
	var damage_calls: int = 0
	var damage_amounts: Array[int] = []

	func _ready() -> void:
		pass

	func apply_damage_at(_pos: Vector3i, amount: int, _actor: Node = null, _normal: Vector3 = Vector3.UP) -> Dictionary:
		damage_calls += 1
		damage_amounts.append(amount)
		return {}


## BlockyGrid double: every cell holds a block, damage is recorded, and the fluid drag every cell
## reports is settable.
## Skips the real _ready (block library, generator); needs a VoxelTerrain child only so the
## @onready terrain_path resolves.
class RecordingBlockyGrid extends BlockyGrid:
	var damage_calls: int = 0
	var damage_amounts: Array[int] = []
	var wading_mult: float = 1.0
	var last_wading_query := Vector3i.ZERO

	func _ready() -> void:
		pass

	func has_block_at(_pos: Vector3i) -> bool:
		return true

	func apply_damage(_pos: Vector3i, amount: int) -> void:
		damage_calls += 1
		damage_amounts.append(amount)

	func get_wading_speed_mult_at(pos: Vector3i) -> float:
		last_wading_query = pos
		return wading_mult


var map: Map
var blocky: RecordingBlockyGrid
var smooth: RecordingSmoothGrid
var furniture_container: Node3D

var _suite: GdUnitTestSuite


## Builds the Map (children attached before it enters the tree so its @onready refs resolve)
## and adds it to the suite's tree.
func _init(suite: GdUnitTestSuite) -> void:
	_suite = suite
	map = suite.auto_free(Map.new())
	blocky = _add_grid("BlockyGrid", RecordingBlockyGrid.new())
	smooth = _add_grid("SmoothGrid", RecordingSmoothGrid.new())
	for slot: String in ["ColonistContainer", "EnemyContainer", "FurnitureContainer"]:
		var container := Node3D.new()
		container.name = slot
		map.add_child(container)
		if slot == "FurnitureContainer":
			furniture_container = container
	suite.add_child(map)


## A wide wall just ahead of the origin, facing the player, on the default layer, parented
## under `parent` (the node whose grid, or lack of one, should own the struck collider).
## `depth` is its z position (more negative = farther ahead). Returns the wall so a test can
## attach components to it.
func add_wall(parent: Node, depth: float = -1.5) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 20.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 0.0, depth)
	parent.add_child(wall)
	return wall


## A player in the suite's tree, outside the Map.
func spawn_player() -> Player:
	var player: Player = _suite.auto_free(PlayerScene.instantiate())
	_suite.add_child(player)
	return player


## A player looking level along -Z at the wall, with the camera settled first.
func spawn_aimed_player() -> Player:
	var player := spawn_player()
	player._rig.set_orientation(0.0, 0.0)
	for _i in range(3):
		await _suite.get_tree().physics_frame
	player._rig.snap_to_target()
	return player


## Names a grid double, gives it the bare VoxelTerrain child its terrain_path expects, and
## parents it under the map.
func _add_grid(grid_name: String, grid: Node) -> Node:
	grid.name = grid_name
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	grid.add_child(terrain)
	map.add_child(grid)
	return grid
