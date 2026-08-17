# Subsystem: Loot

Loot tables + container-roll logic for scavenge missions. GDD §17 "Loot tables" + "Key Item Table". Consumed by Expeditions (containers in POI scenes); output flows to Inventory on pickup. Cross-references: Expeditions subsystem (containers live in POI scenes), Inventory subsystem (pickup flow), SaveSystem (Key Item pool persists).

> **Implementation status: planned, not yet built.** `subsystems/loot/` and `data/loot/` are both empty — there is no `loot_container.gd`, `loot_roller.gd`, `KeyItemPool`, or any `LootTable`/`LootEntry` class, and Colony carries no key-item state. The Inventory pickup path this subsystem feeds (`Player.inventory.add(item_id, count)`) does exist. Treat this page as the spec to implement against, not a description of current code.

**Design notes:**
- **LootTable + LootEntry** are data (`.tres` Resources); the **roller** is a script. Matches the data-driven convention.
- **KeyItemPool lives on the Colony autoload** — run-state that must persist across scene swaps and saves (Key Items are once-per-playthrough). Same pattern as Memorial. See [Tech Debt & Unimplemented](tech-debt.md) on Colony bloat.
- Containers roll **on interaction** (not mission start), per GDD §17. A single container's contents are computed when the player loots it; the result then flows through the standard Inventory pickup.

## Files

| File | Type | Responsibility |
|---|---|---|
| `loot_container.gd` | Script | A lootable object in a POI scene. Holds a `LootTable` reference; on interact, rolls and offers results to the player's Inventory. Does NOT own the table data or the Key Item pool. |
| `loot_roller.gd` | Script (static) | Pure roll math: given a `LootTable`, returns a `Dictionary[item_id, count]`. No state, no signals. |
| `../autoloads/colony.gd` (`KeyItemPool`) | Subsystem on Colony | Tracks which Key Items have dropped this run; `roll_key_item()` returns one or null. Once-per-playthrough enforcement. |
| `../data/loot/standard.tres` | Data | Standard Container table (Zones A/B). See [Data Schemas](data-schemas.md). |
| `../data/loot/deep.tres` | Data | Deep Loot Container table (Zone C). See [Data Schemas](data-schemas.md). |
| `../data/loot/key_items.tres` | Data | Key Item pool (7 MVP items + their T2 upgrade targets). See [Data Schemas](data-schemas.md). |

## Signals

Loot is local to the POI scene + Inventory — no cross-scene signals. The Key Item pool emits nothing (Inventory queries it via `LootContainer` on a successful Key Item roll).

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| *(none — Loot uses direct refs and the Inventory pickup flow)* | — | — | — | Loot a Container |

## Flow Trace: Loot a container

**Trigger:** Player interacts (E) with a LootContainer in a POI scene.

1. `LootContainer.on_interact()` calls `LootRoller.roll(table)` with its assigned `LootTable` (standard or deep).
2. `LootRoller` iterates the table's entries: for each, roll the % chance; on success, pick a count in [min, max].
3. If a Key Item entry succeeds: `LootContainer` calls `Colony.key_item_pool.roll_key_item()` — returns a Key Item ID (and marks it as dropped) or null (all already found this run).
4. `LootContainer` aggregates results into a list of `{item_id, count}` and offers them to `Player.inventory.add(item_id, count)` via the standard Inventory pickup flow (stacking, partial-accept, remainder rules per Inventory subsystem).
5. On full accept: container marked looted (despawned / opened visual). On partial (inventory full): remainder stays in the world per Inventory rules; container stays interactable.

**End state:** Looted items in player inventory; container state updated; any Key Item marked as found for the run.

## Flow Trace: Key Item drop is once-per-playthrough

**Trigger:** A loot roll succeeds on a Key Item entry (5% standard / 20% deep).

1. `LootRoller` returns a "key_item_pending" result to `LootContainer`.
2. `LootContainer` calls `Colony.key_item_pool.roll_key_item()`.
3. `KeyItemPool` checks its `found: Array[String]` list:
   - If unfound items remain → picks one at random, adds its ID to `found`, returns the ID.
   - If all have been found → returns null (no drop this time).
4. `LootContainer` proceeds with the returned ID (or skips if null).
5. On save: `KeyItemPool.found` is serialized as part of Colony state (see SaveSystem tracked-state list).

**End state:** Each Key Item drops at most once per playthrough; progression gated by exploration, not luck.

## Class Reference

### Class: LootContainer

**Extends:** Node3D (or Area3D for proximity prompt)
**Script:** `loot_container.gd` (in `loot/`)
**Description:** A lootable object placed in a POI scene. Holds a `LootTable` reference; rolls on interact; offers results to Inventory. Does NOT own table data or the Key Item pool.
**Used by:** Expeditions (containers placed in per-map POI scenes), Inventory (pickup flow).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `loot_table` | `LootTable` | [export] The table to roll from (standard or deep). |
| `looted` | `bool` | True after a successful full loot; gates re-interaction. |

**Functions:**

| Function | Description |
|---|---|
| `on_interact(player: Node) -> void` | Rolls the table, resolves Key Item via Colony, offers results to `player.inventory`. |

### Class: LootRoller

**Extends:** RefCounted (static class)
**Script:** `loot_roller.gd` (in `loot/`)
**Description:** Pure roll math. No state, no signals. Reads a `LootTable`, returns item/count results.
**Used by:** LootContainer.

**Functions:**

| Function | Description |
|---|---|
| `static roll(table: LootTable) -> Array[Dictionary]` | Returns `[{item_id, count}, ...]`. Per-entry % chance roll; count in [min, max]. Key Item entries return `{item_id: "key_item_pending"}` for the caller to resolve via KeyItemPool. |

### Class: KeyItemPool

**Extends:** Node (child of Colony autoload)
**Script:** `key_item_pool.gd` (in `loot/`, or `autoloads/` if you prefer all Colony children there)
**Description:** Once-per-playthrough enforcement for Key Items. Tracks found items; `roll_key_item()` returns one or null. State is saved with Colony.
**Used by:** LootContainer (on a Key Item roll success).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `pool` | `KeyItemPoolDef` | Loaded from `data/loot/key_items.tres` — the full list of possible Key Items. |
| `found` | `Array[String]` | Key Item IDs already dropped this run. Saved with Colony state. |

**Functions:**

| Function | Description |
|---|---|
| `roll_key_item() -> String` | Returns a random unfound Key Item ID (and adds it to `found`), or empty string if all found. |
