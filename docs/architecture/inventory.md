# Subsystem: Inventory

Items, stacks, inventory model. GDD §4.5, §7.3.

## Files

| File | Type | Responsibility |
|---|---|---|
| `inventory.gd` | Script (on Player node) | Player's inventory: 30 slots (10 hotbar + 20 general). Owns stacking algorithm. Does NOT own UI (Inventory screen reads this). |
| `item_stack.gd` | Script | A stack of one item type; count up to cap. |
| `storage_crate.gd` | Script | Shared colony storage node; proximity access (2m); 32-stack cap per crate. |
| `../data/items/` | Data | Item definitions (id, name, icon, stack cap, usable flag). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `inventory_changed()` | `inventory.gd` | Inventory screen, HUD hotbar | No (same scene / direct ref) | Pickup Item |
| `item_picked_up(item_id, count)` | `inventory.gd` | HUD (refresh) | Yes (for HUD when Player screen closed) | Pickup Item |

## Flow Trace: Pickup item (no auto-pickup; interact or container)

**Trigger:** Player presses E on a world item, or takes from a container.

> **Implementation status: pickup interaction not yet built.** World-item pickup will resolve through the [Actions & Interaction](actions.md) chain (a `GameAction` that calls `inventory.add`), not a dedicated `interact_started` signal. The stacking algorithm below is the intended shape.

1. Player interacts with the world item / crate (E) → an `ActionOption`'s `GameAction.execute` offers `{item_id, count}` to `Player.inventory.add(item_id, count)`.
2. Inventory runs stacking algorithm:
   - Fill existing same-type stacks to cap.
   - Overflow → new non-hotbar slot (prefer non-hotbar).
   - If no slot: container subtracts transferred; world item re-drops remainder.
3. Inventory emits `inventory_changed()` (direct) + `item_picked_up` via EventBus.
4. Inventory screen / HUD hotbar refresh.

**End state:** Item in inventory (full or partial); source updated; UI refreshed.

## Class Reference

### Class: Inventory

**Extends:** Node
**Script:** `inventory.gd`
**Description:** Player's inventory model. 30 slots; stacking per GDD §4.5. Owned by Player; UI reads/writes via public methods.
**Used by:** UI (Inventory screen, HUD hotbar), Combat (weapon/ammo consumption).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `slots` | `Array[ItemStack]` | 30 slots; first 10 = hotbar. |
| `slot_count` | `int` | [export] 30. |

**Functions:**

| Function | Description |
|---|---|
| `add(item_id: String, count: int) -> int` | Stacks per algorithm; returns overflow not stored. |
| `remove(item_id: String, count: int) -> int` | Returns actually removed. |
| `get_hotbar() -> Array[ItemStack]` | First 10 slots. |
