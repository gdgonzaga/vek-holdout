# Subsystem: Inventory

Weight-based inventory model. Items stored as `{item_id: count}` dictionaries; capacity enforced by total weight. GDD §4.5, §7.3.

## Files

| File | Type | Responsibility |
|---|---|---|
| `inventory.gd` | Script (`class_name Inventory`, extends Node) | Base inventory: weight capacity, add/remove/has_item/get_item_count/current_weight/transfer_to. Looks up `ItemDef` via `_get_def()` (delegates to `ItemDB` by default). Emits `inventory_changed` on mutation. |
| `character_inventory.gd` | Script (`class_name CharacterInventory`, extends Inventory) | Character-specific inventory with `base_capacity` (export, default 50.0) + `bonus_capacity` (set by bag equipment). Recalculates `capacity` on ready and on bag equipment change. |
| `item_db.gd` | Autoload (`ItemDB`) | Read-only catalog of item definitions. Scans `data/items/*.tres` at startup; keyed by `ItemDef.id` (the canonical item identity, e.g. `"wood_block"`). Read-only after `_ready`. |
| `../data/items/item_def.gd` | Resource (`class_name ItemDef`, extends Resource) | Item definition schema. Fields: `id: String` (canonical item identity — what `ItemDB` keys by and inventories store), `weight: float`, `icon: Texture2D`. |
| `../data/items/` | Data | Item definition `.tres` files (one per item type). |

## Autoloads

| Name | Script | Responsibility |
|---|---|---|
| **ItemDB** | `item_db.gd` | Global catalog of `ItemDef` resources loaded from `data/items/`. Read-only after `_ready`. `get_def(item_id) -> ItemDef`, `has_def(item_id) -> bool`. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `inventory_changed()` | `Inventory` | Inventory screen, HUD hotbar | No (direct ref or scene-scoped) | Any item add/remove/transfer |
| `item_picked_up(item_id, count)` | inventory subsystem | HUD (refresh) | Yes (for HUD when Player screen closed) | Pickup Item |

## Class Reference

### Class: Inventory

**Extends:** Node
**Script:** `inventory.gd`
**Description:** Base weight-based inventory. Items stored as `{item_id: count}`; `capacity` (float, kg) enforced by `current_weight()`. Looks up `ItemDef.weight` via `_get_def(item_id)`. Child classes override `_get_def` for test mocking or extend capacity logic.
**Used by:** `CharacterInventory`, `StorageInventory` (crates/chests; reads capacity from its furniture def), UI (Inventory screen, HUD hotbar, storage panel), Combat (ammo consumption), Crafting (material consumption).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `capacity` | `float` | Max carry weight (kg). Set by child classes. |
| `items` | `Dictionary` | `{item_id: String -> count: int}`. |

**Signals:**

| Signal | Description |
|---|---|
| `inventory_changed()` | Emitted after any successful add/remove/transfer mutation. |

**Functions:**

| Function | Returns | Description |
|---|---|---|
| `add(item_id, count)` | `int` | Adds items; returns overflow (items that didn't fit). Handles unknown items (returns all as overflow) and negative/zero counts (noop). |
| `remove(item_id, count)` | `int` | Removes items; returns items NOT removed (excess request). Erases key when count hits zero. |
| `can_add(item_id, count)` | `bool` | True if the items would fit by weight. False for unknown items. |
| `has_item(item_id, count)` | `bool` | True if `items[item_id] >= count`. |
| `get_item_count(item_id)` | `int` | Current count of the item (0 if absent). |
| `current_weight()` | `float` | Sum of `count × weight` for all stored items. |
| `transfer_to(target, item_id, count)` | `int` | Moves items to another `Inventory`. Removes from self first, adds to target, returns overflow to self. Returns items that did NOT end up in the target. |
| `_get_def(item_id)` | `ItemDef` | Virtual. Default: `ItemDB.get_def(item_id)`. Override in tests or subclasses. |

### Class: CharacterInventory

**Extends:** Inventory
**Script:** `character_inventory.gd`
**Description:** Character inventory with equipment-driven capacity. `capacity = base_capacity + bonus_capacity`. Bag equipment changes trigger `_recalc_capacity()`.
**Used by:** Player, Colonist (as a component node).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `base_capacity` | `float` | [export] Default 50.0 kg. Base carry weight. |
| `bonus_capacity` | `float` | Additional capacity from equipped bag items. |

## Design Notes

- **Weight-based, not slot-based.** No `ItemStack` or fixed slot array. Items accumulate freely; the only constraint is total weight.
- **transfer_to() uses remove-first-then-add.** Prevents item duplication. If the target is full, overflow items are returned to the source.
- **transfer_to() return value:** Returns the number of items that did **not** end up in the target. This covers both "target was full" (partial transfer) and "source didn't have enough" (requested 10, source had 3 → returns 7).
- **`_get_def()` is the test seam.** Unit tests subclass `Inventory` and override `_get_def()` with a mock dictionary; no `.tres` files needed in the test suite.
- **ItemDB autoload** follows the same pattern as `BuildLibrary` and `MapLibrary`: scan a `data/` directory at startup into an `id → def` map, read-only after `_ready`. ItemDB keys by the `ItemDef.id` field (e.g. `wood_block`); the `.tres` filename is just the file location, not the identity.
