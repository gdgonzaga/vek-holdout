extends GdUnitTestSuite

## Unit tests for Furniture's HealthComponent wiring and destroy() (ARCH combat.md,
## GDD §7.2/§7.7) — buildables becoming damageable via the same take_damage()
## contract player/colonist/enemy combat already uses.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const Doubles = preload("res://test/helpers/doubles.gd")
const FurnitureDefScript = preload("res://data/furniture/furniture_def.gd")
const FurnitureScript = preload("res://subsystems/furniture/furniture.gd")

var _sandbox: ColonySandbox
var _furniture_layer: FurnitureLayer


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	_furniture_layer = FurnitureLayer.new()
	_furniture_layer.set_container(_sandbox.container)


func after_test() -> void:
	_sandbox.restore()


func _make_test_def(p_id: String, p_hp: int) -> FurnitureDef:
	var def := FurnitureDefScript.new() as FurnitureDef
	def.id = p_id
	def.display_name = "Test Furniture"
	def.hp = p_hp
	def.mesh = BoxMesh.new()
	return def


func test_health_component_attaches_when_hp_positive() -> void:
	var def := _make_test_def("test_wall", 100)
	var node: Furniture = _furniture_layer.spawn(def, Vector3i.ZERO, 0)

	assert_that(node.health_component).is_not_null()
	assert_int(node.health_component.max_hp).is_equal(100)


func test_health_component_skipped_when_hp_zero() -> void:
	var def := _make_test_def("test_decor", 0)
	var node: Furniture = _furniture_layer.spawn(def, Vector3i.ZERO, 0)

	assert_that(node.health_component).is_null()


func test_take_damage_forwards_to_health_component() -> void:
	var def := _make_test_def("test_wall", 100)
	var node: Furniture = _furniture_layer.spawn(def, Vector3i.ZERO, 0)

	node.take_damage(30)
	assert_int(node.health_component.current_hp).is_equal(70)


func test_destroyed_at_zero_hp_removes_from_layer() -> void:
	var def := _make_test_def("test_wall", 50)
	var anchor := Vector3i(2, 0, 3)
	_furniture_layer.spawn(def, anchor, 0)
	assert_bool(_furniture_layer.has_at(anchor)).is_true()

	_furniture_layer.get_furniture_at(anchor).take_damage(50)

	assert_bool(_furniture_layer.has_at(anchor)).is_false()


func test_destroy_without_furniture_layer_emits_furniture_removed() -> void:
	var def := _make_test_def("test_wall", 20)
	var node := FurnitureScript.new() as Furniture
	auto_free(node)
	node.def = def
	node.def_id = def.id
	add_child(node)
	node._ready()

	var counter := Doubles.SignalCounter.new(EventBus.furniture_removed)

	node.take_damage(20)
	assert_int(counter.count).is_equal(1)
	assert_bool(node.is_queued_for_deletion()).is_true()
