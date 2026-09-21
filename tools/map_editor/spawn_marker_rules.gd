class_name SpawnMarkerRules
extends RefCounted
## Naming contract for authored spawn markers under a map's SpawnPoints node
## (read back at runtime by SpawnHelpers.read_spawns). Furniture_* markers live
## under the same node and are not spawn markers.

enum Kind { NONE, PLAYER, COLONIST, ENEMY }

const PLAYER_NAME: String = "PlayerSpawn"
const COLONIST_PREFIX: String = "ColonistSpawn"
const ENEMY_PREFIX: String = "EnemySpawn"


static func kind_of(marker_name: String) -> Kind:
	if marker_name == PLAYER_NAME:
		return Kind.PLAYER
	if marker_name.begins_with(COLONIST_PREFIX):
		return Kind.COLONIST
	if marker_name.begins_with(ENEMY_PREFIX):
		return Kind.ENEMY
	return Kind.NONE


## One past the highest numeric suffix among names starting with prefix. A name
## with no numeric suffix counts as index 1, matching the old placement logic.
static func next_index(names: Array[String], prefix: String) -> int:
	var next := 1
	for marker_name: String in names:
		if not marker_name.begins_with(prefix):
			continue
		var suffix := marker_name.trim_prefix(prefix + "_").trim_prefix(prefix)
		next = maxi(next, int(suffix) + 1 if suffix.is_valid_int() else 2)
	return next
