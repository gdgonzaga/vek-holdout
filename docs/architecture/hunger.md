# Subsystem: Hunger & Nutrition

The Hunger and Nutrition subsystem governs physiological energy depletion, autonomous colonist sustenance seeking, starvation hazards, and player manual consumption (GDD §6.12). Satiety decays continuously, transitioning into starvation when depleted. Starving entities suffer movement speed debuffs and periodic health damage until food is consumed. Edible resources are defined declaratively via composition through the FoodParams capability schema on ItemDef.

**Design notes:**
- **Data-Driven Need Consolidation**: Hunger is defined as a standard `NeedDef` resource (`data/needs/need_hunger.tres`), managed alongside `rest` and `recreation` by `ColonistNeeds` on both `Colonist` and `Player`.
- **Unified Depletion Consequences**: Starvation penalties (periodic HP damage, movement speed penalty, and stamina recovery multiplier) are configured declaratively on `NeedDef` and executed generically by `ColonistNeeds`.
- **Data-Driven Composition**: Food properties (nutrition value, heal amount, consumption duration, animations, moodlets) are encapsulated in FoodParams (`ItemDef.food`), leaving ammunition, fuel, and materials decoupled.
- **Pocket Feeding Priority**: Colonists prioritize consuming food already carried in their personal inventory over travelling across the colony to storage crates, saving transit time and pathfinding overhead.
- **Thrash and Race Resilience**: If a food container is emptied before arrival or is physically unreachable, the target is blacklisted on ColonistBrain for 10 seconds to allow dynamic re-arbitration without 1.5-second pathing lockup loops.
- **Deferred Expansion Hooks**: FoodParams reserves metadata properties for future table-dining satisfaction, spoilage timers, and culinary recipe tiers without requiring schema overhauls.

## Files

| File | Type | Responsibility |
|---|---|---|
| `data/needs/need_hunger.tres` | Resource | Declarative need definition specifying decay rate, emergency threshold, and depletion penalties. |
| `subsystems/ai/colonist_needs.gd` | Script | Entity needs tracker managing hunger decay, depletion timers, damage ticks, and speed multipliers. |
| `data/capability_params/food_params.gd` | Script | Declarative capability parameter resource attached to edible `ItemDef.food`. |
| `subsystems/ai/tasks/actions/bt_action_find_food.gd` | Script | LimboAI task locating pocket food or nearest unblacklisted colony food source. |
| `subsystems/ai/tasks/actions/bt_action_fetch_food.gd` | Script | LimboAI task transferring 1 food unit from storage container to colonist pockets. |
| `subsystems/ai/tasks/actions/bt_action_eat_food.gd` | Script | LimboAI task executing timed eating animation, physiological replenishment, and goal clearance. |
| `subsystems/ai/colonist_brain.gd` | Script | Arbitrates eating desires, tracks unreachable food blacklist, and evaluates food targets. |
| `subsystems/inventory/storage_registry.gd` | Script | Spatial queries for edible items across registered crates and world drops. |
| `ui/hud/hud.gd` | Script | HUD inventory panel rendering "Eat" action for carried food items. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `need_changed(need_id: StringName, current: float, max_val: float)` | `colonist_needs.gd` | UI panels, telemetry | No | Need level updates |
| `need_depleted(need_id: StringName)` | `colonist_needs.gd` | Colonist, Player, GameLog | No | Depletion / starvation enter |
| `need_replenished(need_id: StringName)` | `colonist_needs.gd` | Colonist, Player, GameLog | No | Depletion / starvation exit |
| `depletion_tick_damage(need_id: StringName, amount: int)` | `colonist_needs.gd` | Parent entity `take_damage` | No | Periodic starvation / depletion damage |

## Flow Trace: Colonist Autonomous Feeding

**Trigger:** ColonistNeeds hunger deficit increases; ColonistBrain.evaluate_goals() scores `&"eat"` higher than work or recreation.

1. ColonistBrain sets `current_goal = &"eat"` and assigns target to LimboAI blackboard.
2. BTActionFindFood evaluates carried inventory pockets. If edible food exists, sets `food_source_type = &"inventory"` with zero navigation cost.
3. If pockets are empty, BTActionFindFood queries StorageRegistry.find_best_food_source (filtering blacklisted nodes) and writes the crate node to blackboard.
4. BTActionNavigateTo guides the colonist to the storage crate. On path failure, the target is blacklisted for 10 seconds.
5. BTActionFetchFood retrieves 1 food item into colonist inventory. If the container was depleted by another actor, the task fails cleanly.
6. BTActionEatFood locks movement, triggers the eating animation override, counts down eat_duration, applies nutrition restoration to ColonistNeeds, heals HP if specified, and resets current_goal to `&"none"`.

**End state:** Colonist hunger is replenished above emergency thresholds; carry inventory count is deducted; LimboAI returns to standard labor arbitration.

## Flow Trace: Player Food Consumption

**Trigger:** Player opens the HUD inventory list and activates the "Eat" button on an edible food stack.

1. HUD._on_inventory_eat_pressed dispatches item ID to Player.consume_food_item(item_id).
2. Player checks that the item exists in carry inventory and has `def.is_food() == true`.
3. Player.inventory.remove(item_id, 1) deducts 1 unit from carried weight and stacks.
4. Player.needs.restore_need(&"hunger", nutrition_value) increases current hunger and clears starvation state if applicable.
5. If `health_restore > 0`, Player.heal(health_restore) replenishes player hit points.
6. HUD updates inventory list and hunger progress telemetry.

**End state:** Player consumes food with instant replenishment and HP gain without entering behavior tree states.

## Class Reference

### Class: ColonistNeeds

**Extends:** `Node`  
**Script:** `subsystems/ai/colonist_needs.gd`  
**Description:** Core physiological component tracking all entity need levels (hunger, rest, recreation), applying game-hour decay, evaluating depletion transitions, accumulating damage ticks, and scaling locomotion speed / stamina recovery.  
**Used by:** `Colonist`, `Player`.  

**Properties:**

| Property | Type | Description |
|---|---|---|
| `needs` | `Dictionary` | Base need levels normalized between 0.0 (depleted) and 1.0 (satisfied). |

**Functions:**

| Function | Description |
|---|---|
| `get_need(need_id: StringName) -> float` | Returns current level for the specified need. |
| `set_need(need_id: StringName, value: float) -> void` | Sets need level clamped to [0.0, 1.0], triggering signals on change. |
| `restore_need(need_id: StringName, amount: float) -> void` | Restores specified need by amount clamped to 1.0. |
| `get_deficit(need_id: StringName) -> float` | Returns deficit (1.0 - current) on a 0.0 to 1.0 scale. |
| `is_depleted(need_id: StringName) -> bool` | Returns true if need is at or below 0.0. |
| `get_speed_multiplier() -> float` | Compound speed multiplier computed from all active depleted needs. |
| `get_stamina_recovery_multiplier() -> float` | Compound stamina recovery multiplier computed from all active depleted needs. |
| `serialize() -> Dictionary` | Serializes need states and depletion timers for save games. |
| `deserialize(data: Dictionary) -> void` | Restores need states and depletion timers from save data. |

### Class: FoodParams

**Extends:** `Resource`  
**Script:** `data/capability_params/food_params.gd`  
**Description:** Capability parameters resource attached to `ItemDef.food` for edible items.  
**Used by:** `ItemDef`, `BTActionEatFood`, `Player`.  

**Properties:**

| Property | Type | Description |
|---|---|---|
| `nutrition_value` | `float` | Satiety restored to HungerComponent (default `0.4`). |
| `health_restore` | `int` | Hit points healed upon ingestion (default `0`). |
| `eat_duration` | `float` | Time in seconds required to consume item (default `2.0`). |
| `eating_animation` | `StringName` | Mixamo animation override key (default `&"eat"`). |
| `mood_modifier` | `String` | Optional moodlet applied to colonist upon eating. |
| `spoilage_hours` | `float` | Reserved shelf-life hours for future perishability system. |
