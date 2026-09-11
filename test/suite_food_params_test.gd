extends GdUnitTestSuite

## Unit tests for FoodParams capability parameters and ItemDef integration.

const FoodParamsScript = preload("res://data/capability_params/food_params.gd")
const ItemDefScript = preload("res://data/items/item_def.gd")


# =================
# Primary Tests
# =================

func test_food_params_defaults_and_properties() -> void:
	var food: FoodParams = auto_free(FoodParamsScript.new()) as FoodParams
	
	assert_float(food.nutrition_value).is_equal_approx(0.4, 0.001)
	assert_int(food.health_restore).is_equal(0)
	assert_float(food.eat_duration).is_equal_approx(2.0, 0.001)
	assert_str(String(food.eating_animation)).is_equal("eat")
	assert_float(food.spoilage_hours).is_equal_approx(0.0, 0.001)


func test_food_params_nutrition_calculation() -> void:
	var food: FoodParams = auto_free(FoodParamsScript.new()) as FoodParams
	food.nutrition_value = 0.5

	# Clamps to current deficit when deficit is smaller than nutrition
	var partial_restore: float = food.calculate_effective_nutrition(0.3)
	assert_float(partial_restore).is_equal_approx(0.3, 0.001)

	# Caps at nutrition value when deficit is greater
	var full_restore: float = food.calculate_effective_nutrition(0.8)
	assert_float(full_restore).is_equal_approx(0.5, 0.001)

	# Zero restore when deficit is zero or negative
	var zero_restore: float = food.calculate_effective_nutrition(0.0)
	assert_float(zero_restore).is_equal_approx(0.0, 0.001)


func test_item_def_food_capability_integration() -> void:
	var item: ItemDef = auto_free(ItemDefScript.new()) as ItemDef
	item.id = "test_ration"
	
	# Initially non-food
	assert_bool(item.is_food()).is_false()
	assert_object(item.food).is_null()

	# Attach food params
	var food: FoodParams = auto_free(FoodParamsScript.new()) as FoodParams
	food.nutrition_value = 0.65
	food.health_restore = 10
	item.food = food

	assert_bool(item.is_food()).is_true()
	assert_float(item.food.nutrition_value).is_equal_approx(0.65, 0.001)
	assert_int(item.food.health_restore).is_equal(10)
