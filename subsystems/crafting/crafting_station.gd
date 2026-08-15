class_name CraftingStation
extends Node
## Crafting capability component (GDD §7.9), attached under a Furniture by
## FurnitureLayer when its def declares crafting_params — the StorageInventory
## pattern (a code-created child named "CraftingStation"; StorageRegistry-style
## discovery is by that exact name). The furniture itself stays generic; this
## node is the whole crafting surface.
##
## Implements MaterialSink from the ACTIVE ORDER's inputs (material_sink.gd):
## hauling needs zero station knowledge — a queued order makes the station
## haulable-to exactly like a blueprint. One active order per station in v1
## (queue_recipe no-ops while one runs); a station with no order reports no
## needs and reads as satisfied, which closes any bound haul job through
## HaulingJobDef's normal lifecycle.
##
## Order lifecycle (job-extensions.md "Crafting"): queue_recipe →
## crafting_order_queued → Colony spawns a haul job bound to this station →
## haul DELIVERs cross has_complete_materials → crafting_materials_ready →
## Colony spawns the craft job → CraftingJobDef.complete consumes the inputs
## (clears the order) and produces the outputs. The station never crafts
## anything itself — it is the order + deposit ledger; the job def does the
## work (skills/stamina stay in the job layer).
##
## Persistence: the order lives in the parent Furniture's `state` bag under
## ORDER_KEY, so Furniture.serialize round-trips it with no per-component
## branch (the documented capability-state seam; Core Change 6).

## state-bag key: {"recipe_id": String, "given": {item_id (String): count (int)}}.
const ORDER_KEY := "craft_order"

## Recipes offered here — copied from def.crafting_params at _ready.
var recipes: Array[RecipeDef] = []


func _ready() -> void:
	_apply_crafting_params()


## Reads the recipe list from the parent furniture's def.crafting_params.
## Extracted from _ready so tests can invoke it directly without a scene tree
## (a child only runs _ready once it enters the tree; the StorageInventory
## `_apply_storage_params` precedent).
func _apply_crafting_params() -> void:
	var furniture := get_parent() as Furniture
	if furniture == null or furniture.def == null:
		return
	var params := furniture.def.crafting_params as CraftingParams
	if params != null:
		recipes = params.recipes


## Queue `recipe_id` at this station. Returns false (no-op) when an order is
## already active (one at a time in v1) or the recipe isn't offered here.
## Never rejects for missing materials — the haul job drought-waits on the
## board until storage can satisfy the order. Emits crafting_order_queued,
## Colony's trigger to spawn the haul job.
func queue_recipe(recipe_id: String) -> bool:
	if has_active_order():
		return false
	var recipe := recipe_by_id(recipe_id)
	if recipe == null:
		return false
	var furniture := get_parent() as Furniture
	if furniture == null:
		return false
	furniture.state[ORDER_KEY] = {"recipe_id": recipe_id, "given": {}}
	GameLog.craft("Queued %s" % recipe.label())
	EventBus.crafting_order_queued.emit(self, anchor_cell())
	return true


## The order's RecipeDef, resolved from `recipes` by its id. Null when no
## order is active or the recipe no longer exists on the def (edited .tres) —
## callers treat null as "nothing owed" (see has_complete_materials).
func active_recipe() -> RecipeDef:
	var order := _order()
	if order.is_empty():
		return null
	return recipe_by_id(order.get("recipe_id", ""))


func has_active_order() -> bool:
	return not _order().is_empty()


## Drop the order and its deposit ledger. CraftingJobDef.complete calls this
## once the craft applied — the inputs "consumption" IS this clear (deposits
## were virtual: counted in `given`, never physically stored here).
func clear_order() -> void:
	var furniture := get_parent() as Furniture
	if furniture != null:
		furniture.state.erase(ORDER_KEY)


## This station's anchor cell (the footprint corner; Colony's job dedupe key).
## Derived from the furniture's footprint — get_footprint_cells reverses
## FurnitureLayer.world_origin, so cell [0] is the anchor. Vector3i.ZERO when
## there is no furniture/footprint (a safe inert key for tests).
func anchor_cell() -> Vector3i:
	var furniture := get_parent() as Furniture
	if furniture == null:
		return Vector3i.ZERO
	var cells := furniture.get_footprint_cells()
	return cells[0] if not cells.is_empty() else Vector3i.ZERO


# --- MaterialSink contract (see material_sink.gd) ------------------------------
# Read from the active order: an entry is owed when `given` counts less than
# the recipe input. No order → nothing owed → vacuously satisfied (the same
# reading Blueprint gives a costless blueprint), which makes hauling close any
# job bound here once the order is crafted or cleared.

func needed_item_ids() -> Array[String]:
	var recipe := active_recipe()
	if recipe == null:
		return []
	var out: Array[String] = []
	for entry in recipe.inputs:
		if given_count(entry.item_def.id) < entry.count:
			out.append(entry.item_def.id)
	return out


func remaining_need(item_id: String) -> int:
	var recipe := active_recipe()
	if recipe == null:
		return 0
	for entry in recipe.inputs:
		if entry.item_def.id == item_id:
			return maxi(0, entry.count - given_count(item_id))
	return 0


func has_complete_materials() -> bool:
	return needed_item_ids().is_empty()


## Move as much as `actor` carries toward the order's still-unsatisfied inputs.
## Partial fulfillment allowed; returns the count deposited. The first deposit
## that crosses has_complete_materials emits crafting_materials_ready —
## Colony's trigger to spawn the craft job. Single-fire per order: `given`
## never decreases within an order and the branch requires total > 0, so a
## satisfied order can't re-cross (the Blueprint.deposit_from pattern).
func deposit_from(actor: Node) -> int:
	var recipe := active_recipe()
	if recipe == null:
		return 0
	var total := 0
	for entry in recipe.inputs:
		var id := entry.item_def.id
		var need: int = entry.count - given_count(id)
		if need <= 0:
			continue
		# remove_item returns the shortfall and clamps to what's held, so this
		# takes "everything available" when the actor can't cover `need`.
		var shortfall: int = actor.remove_item(id, need)
		var deposited: int = need - shortfall
		if deposited > 0:
			_given()[id] = given_count(id) + deposited
			total += deposited
	if total > 0 and has_complete_materials():
		GameLog.craft("Materials ready for %s" % recipe.label())
		EventBus.crafting_materials_ready.emit(self, anchor_cell())
	return total


## Units of `item_id` deposited toward the active order so far (0 when the
## recipe doesn't use it). The craft panel's progress read.
func given_count(item_id: String) -> int:
	return int(_order().get("given", {}).get(item_id, 0))


func recipe_by_id(recipe_id: String) -> RecipeDef:
	for recipe in recipes:
		if recipe.id == recipe_id:
			return recipe
	return null


func _order() -> Dictionary:
	var furniture := get_parent() as Furniture
	if furniture == null:
		return {}
	return furniture.state.get(ORDER_KEY, {})


## Live reference into the state bag — writes go straight to the furniture's
## serialized state (never a stale copy).
func _given() -> Dictionary:
	var order := _order()
	if order.is_empty():
		return {}
	return order.get("given")

