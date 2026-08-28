extends GdUnitTestSuite

## The walkability seam (MapWiring.blocky_ground_probe / compose_walkability):
## ground rules come from an injectable probe; occupancy layers AND on top.
## Stubbed get_block_at keeps this a pure-logic suite — no terrain or build
## layers needed. Production behavior is unchanged by the seam refactor
## (dual-voxel conversion Phase 1, docs/TODO.md D4); these tests pin it.

func _probe_from(cells: Dictionary) -> Callable:
	return MapWiring.blocky_ground_probe(func(cell: Vector3i) -> String: return cells.get(cell, ""))


func test_blocky_probe_ground_rules() -> void:
	var cells := {
		Vector3i(0, 0, 0): "wood",    # floor
		Vector3i(5, 0, 0): "",         # no floor under the stand cell
		Vector3i(9, 0, 0): "wood",
		Vector3i(9, 1, 0): "wood",    # solid stand cell
		Vector3i(20, 0, 0): "wood",
		Vector3i(20, 2, 0): "stone",   # no head clearance above the stand cell
	}
	var probe := _probe_from(cells)
	var ok: bool = probe.call(Vector3i(0, 1, 0))       # air over floor, clear head
	assert_bool(ok).is_true()
	ok = probe.call(Vector3i(5, 1, 0))                 # nothing below
	assert_bool(ok).is_false()
	ok = probe.call(Vector3i(9, 1, 0))                 # cell itself solid
	assert_bool(ok).is_false()
	ok = probe.call(Vector3i(20, 1, 0))                # ceiling one above
	assert_bool(ok).is_false()


func test_compose_ands_probe_with_occupancy() -> void:
	# No build layers on a map → the predicate is exactly the probe.
	var always := MapWiring.compose_walkability(
		func(_cell: Vector3i) -> bool: return true, null, null)
	var ok: bool = always.call(Vector3i(3, 1, 3))
	assert_bool(ok).is_true()
	var never := MapWiring.compose_walkability(
		func(_cell: Vector3i) -> bool: return false, null, null)
	ok = never.call(Vector3i(3, 1, 3))
	assert_bool(ok).is_false()


func test_wire_enemies_instantiates_swarmer() -> void:
	var map := preload("res://subsystems/maps/map_template.tscn").instantiate() as Map
	add_child(map)
	auto_free(map)

	var spawn_points := map.find_child("SpawnPoints") as Node3D
	var marker := Marker3D.new()
	marker.name = "EnemySpawn_1"
	marker.position = Vector3(10, 5, 10)
	spawn_points.add_child(marker)

	var container := MapWiring.wire_enemies(map)
	assert_that(container).is_not_null()
	assert_int(container.get_child_count()).is_equal(1)
	var enemy := container.get_child(0) as Node3D
	assert_that(enemy).is_not_null()
	assert_str(enemy.name).contains("EnemySwarmer")
