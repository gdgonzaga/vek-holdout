extends GdUnitTestSuite

## Colonist persistence (serialize/deserialize round trip of the state a Colonist owns).
## Extended in R13; starts with the one test that used to live in suite_ai_tasks_test.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	_sandbox.restore()


func test_stateless_colonist_save_load() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.global_position = Vector3(12.0, 3.5, -8.0)
	colonist.inventory.items["wood_plank"] = 7
	colonist.needs.set_need(&"hunger", 0.42)
	colonist.needs.set_need(&"rest", 0.88)
	
	var data: Dictionary = colonist.serialize()
	assert_bool(data.has("needs")).is_true()
	assert_bool(data.has("inventory")).is_true()
	assert_bool(data.has("pos")).is_true()
	assert_int(data["inventory"]["items"]["wood_plank"]).is_equal(7)
	
	# Deserialize into another colonist
	var loaded_colonist: Colonist = _sandbox.make_colonist()
	loaded_colonist.deserialize(data)
	
	assert_vector(loaded_colonist.global_position).is_equal(Vector3(12.0, 3.5, -8.0))
	assert_int(loaded_colonist.inventory.get_item_count("wood_plank")).is_equal(7)
	assert_float(loaded_colonist.needs.get_need(&"hunger")).is_equal_approx(0.42, 0.001)
	assert_float(loaded_colonist.needs.get_need(&"rest")).is_equal_approx(0.88, 0.001)
