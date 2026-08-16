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
## haulable-to exactly like a blueprint. One active order per station; a
## station with no order reports no needs and reads as satisfied, which closes
## any bound haul job through HaulingJobDef's normal lifecycle.
##
## Dual-mode (one order, two possible workers — the blueprint pattern, where
## the player's BuildAction and ConstructionJobDef share a target):
##   worker "colony" — the standard chain: queue → haul → crafting_materials_
##     ready → Colony spawns the craft job → a colonist works it.
##   worker "player" — RESERVED for the player: the crossing does NOT emit
##     (no colonist craft job ever spawns); the order waits ready until the
##     player works it personally (CraftAction + the ActionProgress gauge).
## The materials ledger is communal either way — haulers fill player orders
## too, and the player may "Craft now" any ready order unless a colonist is
## mid-WORK (the `claimed` lock arbitrates; claimed is runtime-only, never
## saved — a loaded order is never left locked by a dead job).
##
## Maintain orders ("craft until storage has N", colony worker only): on
## completion, if StorageRegistry.colony_stock is still short of the target
## the station requeues the same recipe through queue_recipe (so the haul
## producer fires again); material shortages mid-goal drought-wait as usual.
## One-shot, not a standing bill: once the target is reached the order ends —
## stock falling later doesn't auto-resume.
##
## Persistence: the order lives in the parent Furniture's `state` bag under
## ORDER_KEY, so Furniture.serialize round-trips it with no per-component
## branch (the documented capability-state seam; Core Change 6).

## state-bag key: {"recipe_id": String, "given": {item_id: count},
## "worker": "colony"|"player", "maintain": {item_id, count}|{} (absent ok),
## "work_done": float (player gauge resume)}. Older saves lacking the new keys
## read as worker "colony", no maintain, 0.0.
const ORDER_KEY := "craft_order"

const WORKER_COLONY := "colony"
const WORKER_PLAYER := "player"

## Recipes offered here — copied from def.crafting_params at _ready.
var recipes: Array[RecipeDef] = []

## Claim lock: which worker is mid-WORK on this order ("" = none, "player",
## or a colonist_id). Arbitrates the dual-mode race in BOTH directions — the
## player's Craft now checks it, and the craft job's leg/begin/complete check
## it — with double-start protection via idempotent owner matching. Runtime-
## only (never saved): a loaded order is never left locked by a dead job.
var _claim_owner := ""


## Acquire the work claim for `owner`. Idempotent for the current owner;
## returns false (and changes nothing) when someone else holds it.
func claim(owner: String) -> bool:
	if _claim_owner != "" and _claim_owner != owner:
		return false
	_claim_owner = owner
	return true


## Release the claim. Pass the owner to release only your own claim (a
## mismatched release is a no-op — a colonist's abort must not unlock the
## player's gauge); pass nothing to release unconditionally (the order
## resolved — nobody is working it anymore).
func release_claim(owner: String = "") -> void:
	if owner == "" or _claim_owner == owner:
		_claim_owner = ""


func is_claimed() -> bool:
	return _claim_owner != ""


func claim_owner() -> String:
	return _claim_owner


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
## already active (one at a time) or the recipe isn't offered here.
## `worker` reserves the order (WORKER_PLAYER → colonists never claim it) and
## `maintain` ({item_id, count}) makes the order self-requeue until colony
## storage holds `count` (colony worker only — the player variant is one-shot).
## Never rejects for missing materials — the haul job drought-waits on the
## board until storage can satisfy the order. Emits crafting_order_queued,
## Colony's trigger to spawn the haul job (fires for requeues too).
func queue_recipe(recipe_id: String, worker := WORKER_COLONY, maintain := {}) -> bool:
	if has_active_order():
		return false
	var recipe := recipe_by_id(recipe_id)
	if recipe == null:
		return false
	var furniture := get_parent() as Furniture
	if furniture == null:
		return false
	furniture.state[ORDER_KEY] = {
		"recipe_id": recipe_id,
		"given": {},
		"worker": worker,
		"maintain": maintain.duplicate(true),
	}
	if worker == WORKER_PLAYER:
		GameLog.craft("Queued %s (for you)" % recipe.label())
	elif not maintain.is_empty():
		GameLog.craft("Queued %s (until %d %s in storage)" % [
			recipe.label(), int(maintain.get("count", 0)),
			str(maintain.get("item_id", "")),
		])
	else:
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


## Who the order is reserved for: WORKER_COLONY (the default, including
## legacy orders without the key) or WORKER_PLAYER.
func worker() -> String:
	return _order().get("worker", WORKER_COLONY)


## The order's maintain goal ({item_id, count}) or {} when it's a plain order.
func maintain_goal() -> Dictionary:
	var m = _order().get("maintain", {})
	return m if m is Dictionary else {}


## An order is ready when its inputs are fully deposited — workable by whoever
## it's reserved for (a colonist via the craft job, the player via CraftAction).
func is_ready() -> bool:
	return has_active_order() and has_complete_materials()


## Whether the player may start crafting this order personally: it must be
## ready and unclaimed — either by a colonist mid-WORK or by the player's own
## running gauge (a double-start would double-produce).
func can_player_work() -> bool:
	return is_ready() and not is_claimed()


## Resolve the order after a craft applied its effects (CraftingJobDef.complete
## and CraftAction both end here). A maintain order short of its stock target
## requeues itself — through queue_recipe, so the haul producer fires again and
## the loop rides the existing chain (drought persistence makes a mid-goal
## material shortage safe). Everything else (plain orders, player orders,
## targets reached) just clears: the inputs "consumption" IS the clear
## (deposits were virtual: counted in `given`, never physically stored here).
## Releases the claim either way — the order resolved, nobody is working it.
func complete_order() -> void:
	var maintain := maintain_goal()
	if not maintain.is_empty():
		var item_id: String = maintain.get("item_id", "")
		var target: int = int(maintain.get("count", 0))
		if item_id != "" and Colony.storage_registry.colony_stock(item_id) < target:
			var recipe_id: String = _order().get("recipe_id", "")
			release_claim()
			clear_order()
			queue_recipe(recipe_id, WORKER_COLONY, maintain)
			return
	release_claim()
	clear_order()


## Player-abandon path: refund the deposit ledger to the nearest crate (the
## deposits conceptually came from storage or the player's pocket — either way
## a crate is their return address), then clear. Bound jobs self-clean through
## the normal lifecycle: a no-order station reads satisfied to hauling and
## order-gone to the craft def.
func cancel_order() -> void:
	var order := _order()
	if order.is_empty():
		return
	var given: Dictionary = order.get("given", {})
	if not given.is_empty():
		var origin := Vector3.ZERO
		var furniture := get_parent() as Node3D
		if furniture != null:
			origin = furniture.global_position
		var crate_inv := Colony.storage_registry.inventory_of(
			Colony.storage_registry.nearest_crate(origin))
		if crate_inv != null:
			for item_id in given:
				crate_inv.add(item_id, int(given[item_id]))
	release_claim()
	clear_order()
	GameLog.craft("Order cancelled — deposits returned to storage")


## Drop the order and its deposit ledger (the raw form; the craft paths use
## complete_order/cancel_order around it).
func clear_order() -> void:
	var furniture := get_parent() as Furniture
	if furniture != null:
		furniture.state.erase(ORDER_KEY)


## Seconds of player gauge time already spent on this order (ActionProgress
## resume — Esc-cancel persists, restart continues; the BuildAction work_done
## pattern). Resets with each new order.
func work_done() -> float:
	return float(_order().get("work_done", 0.0))


func set_work_done(value: float) -> void:
	var order := _order()
	if not order.is_empty():
		order["work_done"] = value


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
## that crosses has_complete_materials completes the order's materials:
## colony orders emit crafting_materials_ready (Colony's trigger to spawn the
## craft job); PLAYER orders skip the emit — the order is reserved and waits
## for the player to work it. Single-fire per order either way: `given` never
## decreases within an order and the branch requires total > 0, so a satisfied
## order can't re-cross (the Blueprint.deposit_from pattern).
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
		if worker() == WORKER_COLONY:
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

