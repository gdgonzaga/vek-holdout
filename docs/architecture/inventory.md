# Subsystem: Inventory

Weight-based inventory model. Items stored as `{item_id: count}` dictionaries; capacity enforced by total weight. GDD §4.5, §7.3.

## Files

| File | Type | Responsibility |
|---|---|---|
| `inventory.gd` | Script (`class_name Inventory`, extends Node) | Base inventory: weight capacity, add/remove/has_item/get_item_count/current_weight/transfer_to. Looks up `ItemDef` via `_get_def()` (delegates to `ItemDB` by default). Emits `inventory_changed` on mutation. |
| `character_inventory.gd` | Script (`class_name CharacterInventory`, extends Inventory) | Character-specific inventory with `base_capacity` (export, default 50.0) + `bonus_capacity` (set by bag equipment). Recalculates `capacity` on ready and on bag equipment change. Used by Player (scene-placed) and Colonist (code-created in `_ready`, so the colonist can carry hauled materials and stand in for `actor` in `Blueprint.deposit_from`). |
| `storage_inventory.gd` | Script (`class_name StorageInventory`, extends Inventory) | Per-instance contents of a storage container (crates, shelves). Attached as a child of a `Furniture` (named `"StorageInventory"`) when its `FurnitureDef` has `storage_params`; reads `capacity` from those params at `_ready`. Player<->crate transfers use the inherited `transfer_to`. |
| `storage_registry.gd` | Script (`class_name StorageRegistry`, on Colony) | Live index of storage crates, so hauling jobs can find a source for a blueprint's still-needed materials. Scans the current map's `FurnitureContainer` each call — no registration. See class reference. |
| `item_db.gd` | Autoload (`ItemDB`) | Read-only catalog of item definitions. Scans `data/items/*.tres` at startup; keyed by `ItemDef.id` (the canonical item identity, e.g. `"wood_block"`). Read-only after `_ready`. |
| `../data/items/item_def.gd` | Resource (`class_name ItemDef`, extends Resource) | Item definition schema. Fields: `id: String` (canonical item identity — what `ItemDB` keys by and inventories store), `weight: float`, `icon: Texture2D`, `mesh: Mesh` (world item visual shape — authoring guide: [`docs/HOWTO-author-worlditems.md`](../HOWTO-author-worlditems.md)), `material: Material` (optional material override), `visual_scale: Vector3` (world item scale), `tags: Array[String]` (categorization — the `"tool"` tag exempts an item from hauling's surplus dump), `equippable: EquippableParams` (nullable capability). |
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
| `has_item_tag(tag, count = 1)` | `bool` | True if items whose `ItemDef.tags` carry `tag` total at least `count` across stacks (e.g. any carried `"tool"`). Unknown items never match. |
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

### Class: StorageInventory

**Extends:** Inventory
**Script:** `storage_inventory.gd`
**Description:** Per-instance contents of a storage container (crates, shelves). Attached as a child Node of a `Furniture` (named `"StorageInventory"`) by `FurnitureLayer` only when the `FurnitureDef` has `storage_params`; reads `capacity` from those `StorageParams` at `_ready`. Weight-only — the base `Inventory` enforces the budget, so this subclass does not override `add`/`can_add`. Player↔crate transfers use the inherited `transfer_to`, which interoperates between any two `Inventory` instances (used by both the storage UI and colonist hauling).
**Used by:** storage UI (player transfer), `StorageRegistry` (indexing), `HaulingJobDef` (crate↔colonist transfers).

### Class: StorageRegistry

**Extends:** Node
**Script:** `storage_registry.gd` (a child of the `Colony` autoload)
**Description:** Live index of the colony's storage crates, so hauling jobs can find "nearest crate that has the materials this blueprint still needs" without each call site re-scanning. No registration: `find_source` / `has_source_for` / `nearest_crate` scan the current map's `FurnitureContainer` children each call (filtering for `Furniture` nodes with a `"StorageInventory"` child). Crates are few and queries run at most once per haul FETCH leg, so the live scan is cheap and always correct — freed crates are simply absent from the container's child list (no stale refs, no unregister hook on `FurnitureLayer`).
**Used by:** `HaulingJobDef` (FETCH source via `find_source`; surplus return via `nearest_crate`; `is_available` gate via `has_source_for`; crate-inventory resolution via `inventory_of`). (The producer's haul-vs-construct decision in `Colony._on_blueprint_placed` no longer consults stock — any unmet `material_cost` hauls, regardless of current crate contents; see [Jobs](jobs.md).)
**Lifecycle:** `Colony._ready` creates it; `MapWiring.wire_colonists` calls `on_map_wired(furniture_container)` on every map load so base↔POI swaps rebind it to the new map's crates.

**Functions:**

| Function | Description |
|---|---|
| `on_map_wired(container: Node3D) -> void` | Bind to the current map's furniture container. |
| `find_source(item_ids: Array[String], near: Vector3) -> Furniture` | Nearest crate whose `StorageInventory` holds any of `item_ids` (straight-line; reachability verified later by the pathfinder). Null if none. |
| `has_source_for(item_ids: Array[String]) -> bool` | Any crate holds any of `item_ids`. |
| `nearest_crate(near: Vector3) -> Furniture` | Nearest crate regardless of contents (for surplus return). |
| `colony_stock(item_id, near_pos, radius)` | `-> int` | Colony-wide stock of one item: storage crates + unforbidden WorldItems (filtered within `radius` of `near_pos`, default 50 cells) + carried items on colonists and player. |
| `inventory_of(crate: Furniture) -> StorageInventory` | The crate's `StorageInventory` (or null if the crate is null/freed or has no such child). Shared resolution path so haul legs don't each re-fetch the child node. |
| `get_all_crates() -> Array[Furniture]` | All live crate `Furniture` nodes in the current map. |

## Design Notes

- **Weight-based, not slot-based.** No `ItemStack` or fixed slot array. Items accumulate freely; the only constraint is total weight.
- **transfer_to() uses remove-first-then-add.** Prevents item duplication. If the target is full, overflow items are returned to the source.
- **transfer_to() return value:** Returns the number of items that did **not** end up in the target. This covers both "target was full" (partial transfer) and "source didn't have enough" (requested 10, source had 3 → returns 7).
- **`_get_def()` is the test seam.** Unit tests subclass `Inventory` and override `_get_def()` with a mock dictionary; no `.tres` files needed in the test suite.
- **ItemDB autoload** follows the same pattern as `BuildLibrary` and `MapLibrary`: scan a `data/` directory at startup into an `id → def` map, read-only after `_ready`. ItemDB keys by the `ItemDef.id` field (e.g. `wood_block`); the `.tres` filename is just the file location, not the identity.
