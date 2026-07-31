class_name SpawnHelpers
extends RefCounted
## Reads spawn positions from a World's SpawnPoints container.
##
## Scene markers override MapDef values when present (non-zero): an authored POI
## scene can place PlayerSpawn / EnemySpawn_* Marker3Ds to control exactly where
## actors enter, and SceneManager consults SpawnHelpers before falling back to
## map_def.player_spawn.

static func read_spawns(world: World) -> Dictionary:
	var result := { "player": Vector3.ZERO, "enemies": [] }
	var root := world.find_child("SpawnPoints") as Node3D
	if root == null:
		return result
	for child in root.get_children():
		if child.name == "PlayerSpawn":
			result.player = child.global_position
		elif child.name.begins_with("EnemySpawn"):
			result.enemies.append(child.global_position)
	return result
