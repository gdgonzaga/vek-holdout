# Subsystem: Loot

Loot tables + roll logic. Enemy drops are built; container rolls for scavenge missions (GDD §17 "Loot tables" + "Key Item Table") are still planned. Consumed by Combat (`EnemyBase` rolls on death) and, once built, Expeditions (containers in POI scenes); container output flows to Inventory on pickup. Cross-references: Combat subsystem (enemy drops), Expeditions subsystem (containers live in POI scenes), Inventory subsystem (pickup flow, `WorldItem`), SaveSystem (Key Item pool persists).

> **Implementation status: partially implemented.** Built: `LootTable` and `LootEntry` (`data/loot/`), the pure `LootRoller` (`subsystems/loot/loot_roller.gd`), the `EnemyDef.loot_table` field, and drop-on-death in `EnemyBase`. No enemy `.tres` references a table yet, so no shipped enemy drops anything until one is authored. Still planned and not built: `loot_container.gd`, `KeyItemPool` (Colony carries no key-item state), the `data/loot/standard.tres` / `deep.tres` / `key_items.tres` tables, and mutually exclusive weighted pools ("exactly one of these"). The container sections below are the spec to implement against, not a description of current code.

**Design notes:**
- **LootTable + LootEntry** are data (`.tres` Resources); the **roller** is a script. Matches the data-driven convention.
- **Independent entries, no cap.** Each `LootEntry` rolls its own `chance`, then a uniform count in `[min_count, max_count]`; every entry that passes drops. Caps and pick-one behavior, if needed later, belong in a separate pool structure, not in `LootEntry`. `LootTable.guaranteed` reuses `ItemAmount` for always-dropped items.
- **One stack per item id.** The roller merges guaranteed amounts and every passing entry into one `item_id -> count` stack, so an item listed several times spawns one `WorldItem` body, not several.
- **The RNG is injected.** `LootRoller.roll` takes a `RandomNumberGenerator`, so tests seed it and callers own their randomness.
- **KeyItemPool lives on the Colony autoload** — run-state that must persist across scene swaps and saves (Key Items are once-per-playthrough). Same pattern as Memorial. See [Tech Debt & Unimplemented](tech-debt.md) on Colony bloat.
- Containers roll **on interaction** (not mission start), per GDD §17. A single container's contents are computed when the player loots it; the result then flows through the standard Inventory pickup.

## Files

| File | Type | Responsibility |
|---|---|---|
| `../data/loot/loot_table.gd` | Resource | `LootTable`: `guaranteed` amounts plus independently rolled `entries`. Schema: [Data Schemas](data-schemas.md). *(built)* |
| `../data/loot/loot_entry.gd` | Resource | `LootEntry`: item, `chance`, `min_count`, `max_count`. Schema: [Data Schemas](data-schemas.md). *(built)* |
| `loot_roller.gd` | Script (static) | Pure roll math: given a `LootTable` and a `RandomNumberGenerator`, returns a `Dictionary[String, int]` of `item_id -> count`. No state, no signals. *(built)* |
| `loot_container.gd` | Script | *(planned)* A lootable object in a POI scene. Holds a `LootTable` reference; on interact, rolls and offers results to the player's Inventory. Does NOT own the table data or the Key Item pool. |
| `../autoloads/colony.gd` (`KeyItemPool`) | Subsystem on Colony | Tracks which Key Items have dropped this run; `roll_key_item()` returns one or null. Once-per-playthrough enforcement. |
| `../data/loot/standard.tres` | Data | Standard Container table (Zones A/B). See [Data Schemas](data-schemas.md). |
| `../data/loot/deep.tres` | Data | Deep Loot Container table (Zone C). See [Data Schemas](data-schemas.md). |
| `../data/loot/key_items.tres` | Data | Key Item pool (7 MVP items + their T2 upgrade targets). See [Data Schemas](data-schemas.md). |

## Signals

Loot is local to the POI scene + Inventory — no cross-scene signals. The Key Item pool emits nothing (Inventory queries it via `LootContainer` on a successful Key Item roll).

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| *(none — Loot uses direct refs and the Inventory pickup flow)* | — | — | — | Loot a Container |

## Flow Trace: Enemy drops loot on death

**Trigger:** An `EnemyBase`'s `HealthComponent` emits `entity_died`.

1. `EnemyBase._on_entity_died()` calls `_drop_loot()` before `queue_free()`, while `global_position` is still valid. Direct refs only; nothing goes through EventBus.
2. `_drop_loot()` returns early when `enemy_def` or `enemy_def.loot_table` is null, or the enemy is not in the tree.
3. Otherwise it calls `LootRoller.roll(table, rng)`. The roller adds every valid `guaranteed` amount, then rolls each entry (chance, then count) and merges the results into one stack per item id.
4. Each stack is spawned with `WorldItem.spawn_at`, on its own slice of a circle around the death position (`_LOOT_SCATTER_RADIUS`, an outward and upward impulse), so drops never share a spawn point.
5. `WorldItem`s are parented to the scene (or its `ItemsLayer`), not the enemy, so they outlive it. Colonists haul them and the player picks them up through the normal `WorldItem` paths.

**End state:** The enemy is freed and its drops lie scattered where it fell. Enemies freed directly (for example raid cleanup) never emit `entity_died` and so never drop.

## Flow Trace: Loot a container *(planned)*

**Trigger:** Player interacts (E) with a LootContainer in a POI scene.

1. `LootContainer.on_interact()` calls `LootRoller.roll(table)` with its assigned `LootTable` (standard or deep).
2. `LootRoller` iterates the table's entries: for each, roll the % chance; on success, pick a count in [min, max].
3. If a Key Item entry succeeds: `LootContainer` calls `Colony.key_item_pool.roll_key_item()` — returns a Key Item ID (and marks it as dropped) or null (all already found this run).
4. `LootContainer` aggregates results into a list of `{item_id, count}` and offers them to `Player.inventory.add(item_id, count)` via the standard Inventory pickup flow (stacking, partial-accept, remainder rules per Inventory subsystem).
5. On full accept: container marked looted (despawned / opened visual). On partial (inventory full): remainder stays in the world per Inventory rules; container stays interactable.

**End state:** Looted items in player inventory; container state updated; any Key Item marked as found for the run.

## Flow Trace: Key Item drop is once-per-playthrough *(planned)*

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

### Class: LootContainer *(planned)*

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
**Description:** Pure roll math. No state, no signals, no scene tree. Reads a `LootTable`, returns merged item/count stacks.
**Used by:** `EnemyBase` (drop on death); LootContainer once built.

**Functions:**

| Function | Description |
|---|---|
| `static roll(table: LootTable, rng: RandomNumberGenerator) -> Dictionary[String, int]` | Returns `item_id -> count`, empty for a null or empty table. Adds valid `guaranteed` amounts, then rolls each entry: `chance` (`>= 1.0` always, `<= 0.0` never, else `rng.randf() < chance`), then a uniform inclusive count in `[max(min_count, 1), max(max_count, min_count)]`. Entries with a null `item_def` are skipped. Key Item entries are not handled yet: when `LootContainer` and `KeyItemPool` are built, the roller will return a `key_item_pending` marker for the caller to resolve. |

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
