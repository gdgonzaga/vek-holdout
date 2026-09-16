extends GdUnitTestSuite

## Player look behavior: body facing follows camera yaw.

const PlayerScene = preload("res://subsystems/player/player.tscn")


## Regression: visual body-facing must track the camera's look direction, not
## a frozen last-walked direction -- the source of the "back button turns the
## player around" bug (facing used to be re-derived from movement velocity).
func test_look_direction_tracks_camera_yaw() -> void:
	var player := _spawn_player()

	var yaw := deg_to_rad(37.0)
	player._rig.set_orientation(yaw, 0.0)

	var reference: Node3D = auto_free(Node3D.new())
	add_child(reference)
	reference.rotation.y = yaw
	var expected_dir := -reference.global_transform.basis.z

	var look_dir := player.get_look_direction()
	assert_float(look_dir.x).is_equal_approx(expected_dir.x, 0.001)
	assert_float(look_dir.y).is_equal_approx(0.0, 0.001)
	assert_float(look_dir.z).is_equal_approx(expected_dir.z, 0.001)


## Auxiliary: Instantiates player.tscn into the test tree
func _spawn_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)
	return player
