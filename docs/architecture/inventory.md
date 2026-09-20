# Subsystem: Inventory

Weight-based inventory model. Items stored as `{item_id: count}` dictionaries; capacity enforced by total weight. GDD §4.5, §7.3.

## Files

| File | Type | Responsibility |
|---|---|---|
| `inventory.gd` | Script (`class_name Inventory`, extends Node) | Base inventory: weight capacity, add/remove/has_item/get_item_count/current_weight/transfer_to. Looks up `ItemDef` via `_get_def()` (delegates to `ItemDB` by default). Emits `inventory_changed` on mutation. |
| `character_inventory.gd` | Script (`class_name CharacterInventory`, extends Inventory) | Character-specific inventory with `base_capacity` (export, default 50.0) + `bonus_capacity` (set by bag equipment). Recalculates `capacity` on ready and on bag equipment change. Used by Player (scene-placed) and Colonist (code-created in `_ready`, so the colonist can carry hauled materials and stand in for `actor` in `Blueprint.deposit_from`). |
| `storage_inventory.gd` | Script (`class_name StorageInventory`, extends Inventory) | Per-instance contents of a storage container (crates, shelves). Attached as a child of a `Furniture` (named `"StorageInventory"`) when its `FurnitureDef` has `storage_params`; reads `capacity` and item/tag filter restrictions from those params at `_ready`. Player<->crate transfers use the inherited `transfer_to`. |
| `storage_registry.gd` | Script (`class_name StorageRegistry`, on Colony) | Live index of storage crates, so hauling jobs can find a source for a blueprint's still-needed materials. Scans the current map's `FurnitureContainer` each call — no registration. See class reference. |
| `world_item.gd` | Script (`class_name WorldItem`, extends RigidBody3D) | Physical item drop in the 3D world (Layer 5 interaction). Visual mesh from `ItemDef.mesh`, pickup via interaction, forbidden state (`is_forbidden`), and impulse toss on drop. |
| `item_db.gd` | Autoload (`ItemDB`) | Read-only catalog of item definitions. Recursively scans `data/items/` at startup via `ContentDirLoader` (see [Overview](overview.md#content-directory-loading)); keyed by `ItemDef.id` (the canonical item identity, e.g. `"wood_block"`). Read-only after `_ready`. |
| `../data/items/item_def.gd` | Resource (`class_name ItemDef`, extends Resource) | Item definition schema. Fields: `id: String` (canonical item identity — what `ItemDB` keys by and inventories store), `weight: float`, `icon: Texture2D`, `mesh: Mesh` (world item visual shape — authoring guide: [`docs/HOWTO-author-worlditems.md`](../HOWTO-author-worlditems.md)), `material: Material` (optional material override), `visual_scale: Vector3` (world item scale), `get_display_name()` (the authored `resource_name`, else `id`: the single player-facing naming rule every UI uses), `tags: Array[String]` (categorization — the `"tool"` tag protects carried tools from dirt-floor drops during in-field job transitions while allowing crate storage during hygiene), `equippable: EquippableParams` (nullable capability). |
| `../data/items/` | Data | Item definition `.tres` files (one per item type), grouped into `materials/`, `weapons/`, `ammo/`, `tools/`, `apparel/`, `food/` subfolders by category. |

## UI Consumers

The inventory model has no UI of its own; these read it. Behavior is documented in [UI](ui.md).

| File | Reads | Notes |
|---|---|---|
| `../../ui/inventory/inventory_panel.tscn` | Player `CharacterInventory` + `Equipment` | Carried list and Equipped strip; Equip / Eat / Drop actions call `Player`. |
| `../../ui/storage/storage_panel.tscn` | Player inventory and a `StorageInventory` | Moves 1 / 10 / All through `transfer_to`; dims rows using `max_addable` and `is_item_allowed`. |
| `../../ui/colony_management/storage_container_row.tscn` | A crate's `StorageInventory` | Read-only crate card in Colony Management. |
| `../../ui/shared/item_row.tscn`, `item_stack_order.gd`, `row_focus.gd` | (none) | Shared row layout, list ordering and focus keeping. |

## Autoloads

| Name | Script | Responsibility |
|---|---|---|
| **ItemDB** | `item_db.gd` | Global catalog of `ItemDef` resources loaded from `data/items/`. Read-only after `_ready`. `get_def(item_id) -> ItemDef`, `has_def(item_id) -> bool`, `get_display_name(item_id) -> String` (the def's display name, or the raw id when the def is gone, never ""). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `inventory_changed()` | `Inventory` | `InventoryPanel`, `StoragePanel`, `StorageContainerRow` (each coalesces to one rebuild per frame) | No (direct ref) | An add that took units or a remove that removed units. `transfer_to` emits once per inventory. |
| `item_picked_up(item_id, count)` | *(nothing emits it)* | *(nothing listens)* | Declared on `EventBus` but unwired | *(none yet, see [Tech Debt](tech-debt.md))* |

## Class Reference

### Class: Inventory

**Extends:** Node
**Script:** `inventory.gd`
**Description:** Base weight-based inventory. Items stored as `{item_id: count}`; `capacity` (float, kg) enforced by `current_weight()`. Looks up `ItemDef.weight` via `_get_def(item_id)`. Child classes override `_get_def` for test mocking or extend capacity logic.
**Used by:** `CharacterInventory`, `StorageInventory` (crates/chests; reads capacity from its furniture def), UI (`InventoryPanel`, `StoragePanel`, `StorageContainerRow`; see [UI](ui.md)), Combat (ammo consumption), Crafting (material consumption).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `capacity` | `float` | Max carry weight (kg). Set by child classes. |
| `items` | `Dictionary` | `{item_id: String -> count: int}`. Insertion order is not display order (removing and re-adding a stack moves its key): lists use `ItemStackOrder.sorted_item_ids`. |
| `UNLIMITED_COUNT` | `int` (const) | What `max_addable` returns for a weightless item (`1 << 30`), larger than any real stack. |

**Signals:**

| Signal | Description |
|---|---|
| `inventory_changed()` | Emitted after a mutation that changed the contents: an `add` that took at least one unit, or a `remove` that removed at least one. A rejected or empty call emits nothing, so open panels do not rebuild for no change. |

**Functions:**

| Function | Returns | Description |
|---|---|---|
| `add(item_id, count)` | `int` | Adds as many as `max_addable` allows; returns overflow (items that didn't fit). Handles unknown or filtered-out items (returns all as overflow) and negative/zero counts (noop). Emits `inventory_changed` only if something was added. |
| `max_addable(item_id)` | `int` | Largest count that would be accepted right now: 0 for an unknown or filtered-out item or when no weight room is left (never negative, even if capacity dropped below the current load), `UNLIMITED_COUNT` for a weightless item. The single "does it fit" rule behind `add`, `can_add` and `transfer_to`; UIs use it to dim or disable a transfer. |
| `remove(item_id, count)` | `int` | Removes items; returns items NOT removed (excess request). Erases key when count hits zero. |
| `is_item_allowed(item_id)` | `bool` | Virtual check whether this inventory accepts `item_id`. Base class returns true; overridden by subclasses (e.g. `StorageInventory`). |
| `can_add(item_id, count)` | `bool` | `count <= max_addable(item_id)`: true if the item is allowed and fits by weight. False for unknown or disallowed items. |
| `has_item(item_id, count)` | `bool` | True if `items[item_id] >= count`. |
| `has_item_tag(tag, count = 1)` | `bool` | `count_items_with_tag(tag) >= count`: true if items whose `ItemDef.tags` carry `tag` total at least `count` across stacks (e.g. any carried `"tool"`). Unknown items never match. |
| `count_items_with_tag(tag)` | `int` | Total units, across stacks, of items whose `ItemDef.tags` carry `tag`. Equipped items are not included (they live in `Equipment`). |
| `get_item_count(item_id)` | `int` | Current count of the item (0 if absent). |
| `current_weight()` | `float` | Sum of `count × weight` for all stored items. |
| `transfer_to(target, item_id, count)` | `int` | Moves items to another `Inventory`. Caps the move at what self holds and `target.max_addable` accepts before touching either side, then removes from self and adds to target. A rejected or full-target transfer changes nothing and emits nothing; a partial one emits once per inventory and leaves the source's other stacks in place. Anything the target still refuses goes back to self as a safety net. Returns items that did NOT end up in the target. |
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
**Description:** Per-instance contents of a storage container (crates, shelves). Attached as a child Node of a `Furniture` (named `"StorageInventory"`) by `FurnitureLayer` only when the `FurnitureDef` has `storage_params`; reads `capacity`, `priority` (1-5), and item/tag filter restrictions from those `StorageParams` at `_ready`. Exposes runtime `allowed_item_ids` (the item whitelist, edited per crate in the Storage Options panel through `set_item_allowed` / `clear_allowed_items`) and `allowed_tags` (the tag rule, copied from `StorageParams` and restored on load; the panel shows it read-only). `is_item_allowed()` admits an item that matches EITHER one, and a container with both empty accepts anything. `priority` (1-5) changes through `set_priority`; whitelist and priority changes emit `inventory_changed`, so open panels and crate cards update live. Player↔crate transfers use the inherited `transfer_to`, which interoperates between any two `Inventory` instances (used by both the storage UI and colonist hauling).
**Used by:** storage UI (`StoragePanel` transfer and header via `StorageSummary`), the Storage Options panel (`StorageFilterPanel`), crate cards (`StorageContainerRow`), `StorageRegistry` (indexing), `HaulingJobDef` (crate↔colonist transfers).

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
| `find_storage_for(item_id: String, near: Vector3, count: int = 1) -> Furniture` | Best crate for deposit: evaluates highest `priority` (1-5) first, breaking ties with shortest distance to `near`. Null if no storage crate has capacity. |
| `has_source_for(item_ids: Array[String]) -> bool` | Any crate holds any of `item_ids`. |
| `nearest_crate(near: Vector3) -> Furniture` | Nearest crate regardless of contents (for surplus return). |
| `find_closest_item_matching(item_id, tags, near) -> String` | Nearest item_id (by tag or exact id) across crates, for tool/tag-driven fetch. |
| `find_best_food_source(near, blacklisted_sources = []) -> Dictionary` | Nearest edible item across crates and ground `WorldItem`s, skipping blacklisted sources. Used by `BTActionFindFood` ([Hunger](hunger.md)). |
| `colony_food_count() -> int` | Total edible item count across crates and ground. |
| `crate_stock(item_id) -> int` | Total held across all crates only (ignores ground items and pockets, unlike `colony_stock`). This is what a `FetchEquipmentJob` can actually withdraw; the Gear picker shows it next to each item. |
| `colony_stock(item_id, near_pos = null, radius = 50.0, include_reserved = false) -> int` | Colony-wide stock of one item: storage crates + unforbidden WorldItems (filtered within `radius` of `near_pos`) + carried items on colonists and player. Reserved WorldItems are excluded unless `include_reserved` is true. |
| `inventory_of(crate: Furniture) -> StorageInventory` | The crate's `StorageInventory` (or null if the crate is null/freed or has no such child). Shared resolution path so haul legs don't each re-fetch the child node. |
| `get_all_crates() -> Array[Furniture]` | All live crate `Furniture` nodes in the current map. |

## Design Notes

- **Weight-based, not slot-based.** No `ItemStack` or fixed slot array. Items accumulate freely; the only constraint is total weight.
- **Equipment is a separate store.** An item in an `Equipment` slot is not in `items`: it is not listed, weighed, dropped or deposited as cargo, and `has_item` / `count_items_with_tag` do not see it. The Player's Equip button moves ONE unit from `items` into a slot (`Equipment.equip_from_inventory`) and Unequip moves it back, refusing when the pack has no room. `HasItemCondition` therefore counts both. See [Equipment](equipment.md#inventory-vs-equipment).
- **Lists sort, they do not iterate the dictionary.** Every item list (inventory panel, transfer panel, crate card, colonist carry list) orders its stacks with `ItemStackOrder` (gear, food, other; then name), so a stack that is removed and re-added never jumps.
- **transfer_to() sizes the move first, then removes-first-then-adds.** It asks `target.max_addable` up front so a full or filtering target is a no-op rather than a remove/re-add round trip (which used to reorder the source's `items` dictionary, and so any UI list built from it, and fire `inventory_changed` several times). Remove-first still prevents item duplication; the add-back only runs if a target's `add` is stricter than its `max_addable`.
- **Weightless items are unbounded, not unaddable.** An `ItemDef` left at the default `weight = 0.0` used to be rejected in full, because `add` divided the free capacity by the item's weight. `max_addable` now treats it as taking no room.
- **transfer_to() return value:** Returns the number of items that did **not** end up in the target. This covers both "target was full" (partial transfer) and "source didn't have enough" (requested 10, source had 3 → returns 7).
- **Forbidden flag, not a cooldown.** `WorldItem.forbidden` (toggled by the player via `ToggleForbiddenAction`, or read by `StorageRegistry`/`HaulingJobDef`/`Colony`) excludes an item from hauling and stock counts. It is a persistent flag, not a timed cooldown — nothing currently auto-forbids items dropped by AI inventory hygiene (`AIUtils.drop_unneeded_items`, `Colonist.drop_held_item`).
- **`_get_def()` is the test seam.** Unit tests subclass `Inventory` and override `_get_def()` with a mock dictionary; no `.tres` files needed in the test suite.
- **ItemDB autoload** follows the same pattern as `BuildLibrary` and `MapLibrary`: scan a `data/` directory (recursively, via `ContentDirLoader`) at startup into an `id → def` map, read-only after `_ready`. ItemDB keys by the `ItemDef.id` field (e.g. `wood_block`); the `.tres` filename and its subfolder are just the file location, not the identity.
