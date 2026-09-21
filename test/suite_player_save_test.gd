extends GdUnitTestSuite

## Player save/load: state that lives on child components must round-trip through
## serialize()/deserialize(). Content-agnostic: skill state is written in-memory.

const PlayerScene = preload("res://subsystems/player/player.tscn")


func test_skill_progress_survives_save_and_load() -> void:
	# Break caught: serialize() omitted skill_set, so trained levels reset to L1 on load.
	var player := _spawn_player()
	player.skill_set.skills["test_skill"] = {"level": 3, "progress": 7}

	var saved := player.serialize()

	var restored := _spawn_player()
	restored.deserialize(saved)
	assert_int(restored.skill_set.get_level("test_skill")).is_equal(3)
	assert_int(int(restored.skill_set.skills.get("test_skill", {}).get("progress", -1))).is_equal(7)


func test_loading_a_save_clears_leftover_motion() -> void:
	# Break caught: a restored player keeping the velocity it had when the load happened, so it
	# slides off (or falls through) its restored position.
	var player := _spawn_player()
	var saved := player.serialize()
	player.velocity = Vector3(3.0, -5.0, 2.0)

	player.deserialize(saved)

	assert_vector(player.velocity).is_equal(Vector3.ZERO)


## Auxiliary: Instantiates player.tscn into the test tree.
func _spawn_player() -> Player:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	return player
