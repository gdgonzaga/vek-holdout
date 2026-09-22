extends GdUnitTestSuite

## Unit tests for Area data model and AreaManager CRUD / membership / persistence.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	if Colony.area_manager != null:
		Colony.area_manager.reset_for_new_game()
	Colony.colonists.clear()


func after_test() -> void:
	if Colony.area_manager != null:
		Colony.area_manager.reset_for_new_game()
	Colony.colonists.clear()
	_sandbox.restore()


func _make_test_colonist() -> Colonist:
	var c := _sandbox.make_colonist()
	Colony.add_colonist(c)
	return c


# ── Area Creation & Normalization ─────────────────────────────────────────────

func test_create_area_default_name_and_custom_name() -> void:
	var area1 := Colony.area_manager.create_area(Vector3i(0, 0, 0), Vector3i(2, 1, 2))
	assert_object(area1).is_not_null()
	assert_str(area1.display_name).is_equal("Area 1")
	assert_str(area1.id).is_not_empty()

	var area2 := Colony.area_manager.create_area(Vector3i(5, 0, 5), Vector3i(8, 2, 8), "Barracks")
	assert_object(area2).is_not_null()
	assert_str(area2.display_name).is_equal("Barracks")


func test_create_area_coordinate_normalization() -> void:
	# Pass reversed corners (max before min)
	var area := Colony.area_manager.create_area(Vector3i(10, 5, 20), Vector3i(2, 1, 4))
	assert_int(area.boxes.size()).is_equal(1)
	assert_vector(area.boxes[0]["min"]).is_equal(Vector3i(2, 1, 4))
	assert_vector(area.boxes[0]["max"]).is_equal(Vector3i(10, 5, 20))


func test_paint_and_erase_area() -> void:
	var area := Colony.area_manager.create_area(Vector3i(0, 0, 0), Vector3i(5, 5, 5), "MultiZone")
	var area_id := area.id

	# Paint an adjacent disjoint box
	Colony.area_manager.paint_area(area_id, Vector3i(10, 0, 10), Vector3i(15, 5, 15))
	assert_int(area.boxes.size()).is_equal(2)
	assert_bool(area.contains_cell(Vector3i(2, 2, 2))).is_true()
	assert_bool(area.contains_cell(Vector3i(12, 2, 12))).is_true()
	assert_bool(area.contains_cell(Vector3i(7, 2, 7))).is_false()

	# Erase partial volume of first box (carving center)
	Colony.area_manager.erase_area(area_id, Vector3i(2, 0, 2), Vector3i(3, 5, 3))
	assert_bool(area.contains_cell(Vector3i(2, 2, 2))).is_false()
	assert_bool(area.contains_cell(Vector3i(0, 0, 0))).is_true()
	assert_bool(area.contains_cell(Vector3i(5, 5, 5))).is_true()

	# Erase all remaining volume
	Colony.area_manager.erase_area(area_id, Vector3i(-50, -50, -50), Vector3i(50, 50, 50))
	# Automatically deleted when empty!
	assert_object(Colony.area_manager.get_area(area_id)).is_null()


## R13 candidate (Step 5): every other outer-bounds check in this suite paints a
## single box, so Area._calculate_outer_bounds's min/max-merge loop over boxes[1:]
## never ran (confirmed with a mutant that skips it entirely during this phase —
## every test here still passed). Three disjoint boxes in three different
## quadrants force the merge to actually widen on every axis.
func test_get_outer_bounds_spans_disjoint_boxes_in_mixed_quadrants() -> void:
	var area := Colony.area_manager.create_area(Vector3i(-10, 0, -10), Vector3i(-5, 2, -5), "Scattered")
	var area_id := area.id

	Colony.area_manager.paint_area(area_id, Vector3i(3, 5, -8), Vector3i(6, 9, -1))
	Colony.area_manager.paint_area(area_id, Vector3i(-2, -4, 4), Vector3i(1, -1, 8))
	assert_int(area.boxes.size()).is_equal(3)

	var bounds: Dictionary = area.get_outer_bounds()
	assert_vector(bounds["min"]).is_equal(Vector3i(-10, -4, -10))
	assert_vector(bounds["max"]).is_equal(Vector3i(6, 9, 8))


# ── Spatial Queries & Containment ─────────────────────────────────────────────

func test_area_contains_cell() -> void:
	var area := Colony.area_manager.create_area(Vector3i(0, 2, 0), Vector3i(10, 4, 10))

	# Inside
	assert_bool(area.contains_cell(Vector3i(5, 3, 5))).is_true()
	# Exact boundaries
	assert_bool(area.contains_cell(Vector3i(0, 2, 0))).is_true()
	assert_bool(area.contains_cell(Vector3i(10, 4, 10))).is_true()
	# Outside
	assert_bool(area.contains_cell(Vector3i(-1, 3, 5))).is_false()
	assert_bool(area.contains_cell(Vector3i(5, 1, 5))).is_false()
	assert_bool(area.contains_cell(Vector3i(5, 5, 5))).is_false()
	assert_bool(area.contains_cell(Vector3i(5, 3, 11))).is_false()


func test_manager_spatial_queries() -> void:
	var a1 := Colony.area_manager.create_area(Vector3i(0, 0, 0), Vector3i(5, 1, 5), "A1")
	var a2 := Colony.area_manager.create_area(Vector3i(3, 0, 3), Vector3i(8, 1, 8), "A2")

	# Overlapping point
	var overlapping: Array[Area] = Colony.area_manager.get_areas_at(Vector3i(4, 0, 4))
	assert_int(overlapping.size()).is_equal(2)
	assert_bool(Colony.area_manager.is_point_in_any_area(Vector3i(4, 0, 4))).is_true()

	# Point only in A1
	var only_a1: Array[Area] = Colony.area_manager.get_areas_at(Vector3i(1, 0, 1))
	assert_int(only_a1.size()).is_equal(1)
	assert_str(only_a1[0].id).is_equal(a1.id)

	# Point in neither
	var outside: Array[Area] = Colony.area_manager.get_areas_at(Vector3i(20, 0, 20))
	assert_array(outside).is_empty()
	assert_bool(Colony.area_manager.is_point_in_any_area(Vector3i(20, 0, 20))).is_false()


# ── CRUD Operations ───────────────────────────────────────────────────────────

func test_rename_and_delete_area() -> void:
	var area := Colony.area_manager.create_area(Vector3i(0, 0, 0), Vector3i(2, 1, 2), "Old Name")
	var area_id := area.id

	Colony.area_manager.rename_area(area_id, "New Name")
	assert_str(Colony.area_manager.get_area(area_id).display_name).is_equal("New Name")

	Colony.area_manager.delete_area(area_id)
	assert_object(Colony.area_manager.get_area(area_id)).is_null()
	assert_int(Colony.area_manager.get_all_areas().size()).is_equal(0)


# ── Membership Management & Colonist Removal Hygiene ──────────────────────────

func test_member_assignment_and_removal() -> void:
	var area := Colony.area_manager.create_area(Vector3i(0, 0, 0), Vector3i(2, 1, 2))
	var c1 := _make_test_colonist()
	var c2 := _make_test_colonist()

	Colony.area_manager.add_member(area.id, c1.colonist_id)
	Colony.area_manager.add_member(area.id, c2.colonist_id)
	# Deduplication check
	Colony.area_manager.add_member(area.id, c1.colonist_id)

	var members := Colony.area_manager.get_members(area.id)
	assert_int(members.size()).is_equal(2)
	assert_bool(members.has(c1.colonist_id)).is_true()
	assert_bool(members.has(c2.colonist_id)).is_true()

	Colony.area_manager.remove_member(area.id, c1.colonist_id)
	assert_int(Colony.area_manager.get_members(area.id).size()).is_equal(1)
	assert_bool(Colony.area_manager.get_members(area.id).has(c1.colonist_id)).is_false()


func test_colonist_removal_cleans_up_all_areas() -> void:
	var a1 := Colony.area_manager.create_area(Vector3i(0, 0, 0), Vector3i(2, 1, 2), "Zone 1")
	var a2 := Colony.area_manager.create_area(Vector3i(5, 0, 5), Vector3i(7, 1, 7), "Zone 2")
	var c := _make_test_colonist()

	Colony.area_manager.add_member(a1.id, c.colonist_id)
	Colony.area_manager.add_member(a2.id, c.colonist_id)

	assert_int(Colony.area_manager.get_members(a1.id).size()).is_equal(1)
	assert_int(Colony.area_manager.get_members(a2.id).size()).is_equal(1)

	# Remove colonist through Colony autoload lifecycle
	Colony.remove_colonist(c.colonist_id)

	assert_array(Colony.area_manager.get_members(a1.id)).is_empty()
	assert_array(Colony.area_manager.get_members(a2.id)).is_empty()


# ── Persistence & Round-Trip ──────────────────────────────────────────────────

func test_area_manager_serialization_round_trip() -> void:
	var a1 := Colony.area_manager.create_area(Vector3i(1, 2, 3), Vector3i(4, 5, 6), "Fortress")
	var a2 := Colony.area_manager.create_area(Vector3i(7, 8, 9), Vector3i(10, 11, 12))
	var c := _make_test_colonist()
	Colony.area_manager.add_member(a1.id, c.colonist_id)

	var snapshot: Dictionary = Colony.serialize()
	assert_bool(snapshot.has("areas")).is_true()

	# Clear manager
	Colony.area_manager.reset_for_new_game()
	assert_int(Colony.area_manager.get_all_areas().size()).is_equal(0)

	# Restore
	Colony.deserialize(snapshot)
	var restored_a1: Area = Colony.area_manager.get_area(a1.id)
	assert_object(restored_a1).is_not_null()
	assert_str(restored_a1.display_name).is_equal("Fortress")
	var bounds_a1: Dictionary = restored_a1.get_outer_bounds()
	assert_vector(bounds_a1["min"]).is_equal(Vector3i(1, 2, 3))
	assert_vector(bounds_a1["max"]).is_equal(Vector3i(4, 5, 6))
	assert_int(restored_a1.member_colonist_ids.size()).is_equal(1)
	assert_str(restored_a1.member_colonist_ids[0]).is_equal(c.colonist_id)

	var restored_a2: Area = Colony.area_manager.get_area(a2.id)
	assert_object(restored_a2).is_not_null()
	assert_str(restored_a2.display_name).is_equal(a2.display_name)
