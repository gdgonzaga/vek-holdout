# Subsystem: Equipment & Loadouts

Per-character equipped gear + named loadout templates that auto-equip on raid/expedition and auto-return to storage on return. GDD §17 Equipment + §12 Loadout Template editor.

**Design notes:**
- **`Equipment` is a component on each character** (8 slots: 6 armor + melee + ranged). Pairs with HealthComponent — HealthComponent's `max_durability` is the sum of equipped armor Durability values.
- **`LoadoutTemplate` = slot → item_def_id mapping** (abstract, not concrete instances). Equipping resolves the template to concrete items pulled from storage at equip time. Handles "discovered gear" + "nearest unclaimed" rules cleanly.
- **Templates live in `data/loadouts/`** (player-created, saved per run). The *catalog* of equippable item_defs lives in `data/items/` (already specced) + `data/weapons/` + `data/armor/` (C9 schemas pending).
- **"Discovered gear" lives on Colony** (run-state, persists + saves, like Memorial/KeyItemPool): tracks which item_def_ids the colony has possessed at least once. Gates the loadout-slot picker UI.
- **Auto-equip/unequip subscribes to existing EventBus signals** (`raid_started`, `expedition_started`, `raid_ended`, `expedition_ended`) — no new trigger signals.
- Player character's `Gear` tab in the Player screen uses the same Equipment component (manual equip, no loadout template needed for the player in MVP).

## Files

| File | Type | Responsibility |
|---|---|---|
| `equipment.gd` | Script (component) | Per-character equipped gear (8 slots). Holds concrete item references; exposes `get_total_durability()` for HealthComponent. Does NOT own loadout templates (those are data + Colony). |
| `loadout_manager.gd` | Script (on Colony autoload) | Holds player-created templates; resolves + executes auto-equip/unequip on raid/expedition signals. Owns the "nearest unclaimed item" resolution. |
| `discovered_gear.gd` | Script (on Colony autoload) | Tracks item_def_ids the colony has ever possessed (once per run). Gates the loadout-slot picker. Subscribes to Inventory `item_picked_up`. |
| `../data/loadouts/` | Data | Player-created templates, saved per run. See [Data Schemas](data-schemas.md). |
| `../data/armor/` | Data | Armor defs per slot per tier (Durability values from GDD §17). Schema pending (C9). |
| `../data/weapons/` | Data | Weapon defs (Knife, Pistol; Club/Bow post-MVP). Schema pending (C9). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `equip_completed(character, slot, item_id)` | `equipment.gd` | HealthComponent (recalc max_durability), HUD | No | Equip from Loadout |
| `unequip_completed(character, slot)` | `equipment.gd` | HealthComponent (recalc), HUD | No | Unequip on Return |

*(Auto-equip triggers come from existing `raid_started` / `expedition_started` / `raid_ended` / `expedition_ended` signals on EventBus — Equipment subscribes, doesn't emit new triggers.)*

## Flow Trace: Player creates a loadout template + assigns it

**Trigger:** Player opens Colony screen → Loadouts tab → clicks New.

1. UI creates a blank `LoadoutTemplate` (random default name, all slots empty).
2. Player names it; clicks each slot to assign:
   - Slot picker queries `Colony.discovered_gear.get_discovered_for_slot(slot)` → filters to item_defs valid for that slot + discovered this run.
   - Player picks one (or "auto-assign" → MVP: nearest unclaimed item for that slot in storage).
3. Player saves the template → written to `Colony.loadout_manager.templates` (and to `data/loadouts/` on save).
4. Player assigns the template to a colonist via the per-colonist dropdown.

**End state:** Named template exists with slot→item_def_id mappings; assigned to one or more colonists.

## Flow Trace: Colonist auto-equips loadout on raid start

**Trigger:** EventBus emits `raid_started(raid_data)`.

1. `LoadoutManager` (on Colony) listens → for each colonist with an assigned template:
2. For each slot in the template: resolve `item_def_id` to a concrete item from colony storage (nearest unclaimed of that type).
3. Move item: storage → `colonist.equipment.equip(slot, item)`.
4. `Equipment` emits `equip_completed` → HealthComponent recalculates `max_durability` (sum of equipped armor).
5. If no matching item in storage: slot stays empty (partial equip); Job Log notes the gap.

**End state:** Colonist equipped per template (best-effort); Durability updated; ready for raid.

## Flow Trace: Colonist returns equipment to storage on return

**Trigger:** EventBus emits `raid_ended(outcome)` or `expedition_ended(result)`.

1. `LoadoutManager` listens → for each returning colonist:
2. For each equipped slot: move item → `colonist.equipment.unequip(slot)` → back to colony storage (via Inventory add flow).
3. `Equipment` emits `unequip_completed` → HealthComponent recalculates `max_durability` (back to 0 if no permanent armor).
4. Items now available in storage for reassignment or repair.

**End state:** Colonist bare; equipment in storage; Durability reset.

## Class Reference

### Class: Equipment

**Extends:** Node (component on Player + each Colonist)
**Script:** `equipment.gd` (in `equipment/`)
**Description:** Per-character equipped gear (8 slots). Holds concrete item references; HealthComponent reads total Durability from it.
**Used by:** HealthComponent (max_durability calc), Combat (weapon damage/ammo), HUD (gear display), LoadoutManager (equip/unequip target).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `slots` | `Dictionary[String, Item]` | 8 entries keyed by slot id (`"armor_head"`, `"armor_body"`, ..., `"melee"`, `"ranged"`). Values are concrete `Item` refs or null. |

**Signals:**

| Signal | Description |
|---|---|
| `equip_completed(character, slot, item_id)` | For HealthComponent recalc + HUD refresh. |
| `unequip_completed(character, slot)` | For HealthComponent recalc + HUD refresh. |

**Functions:**

| Function | Description |
|---|---|
| `equip(slot: String, item: Item) -> void` | Places item in slot; emits `equip_completed`. |
| `unequip(slot: String) -> Item` | Removes + returns item; emits `unequip_completed`. |
| `get_total_durability() -> int` | Sum of equipped armor Durability values. Called by HealthComponent. |
| `get_weapon_damage() -> int` | Melee weapon's fixed damage (or 0 if none). |
| `get_active_ranged() -> Item` | The ranged-weapon Item (for ammo consumption). |

### Class: LoadoutManager

**Extends:** Node (child of Colony autoload)
**Script:** `loadout_manager.gd` (in `equipment/`)
**Description:** Holds player-created loadout templates; resolves + executes auto-equip/unequip on raid/expedition signals. Owns the "nearest unclaimed item" resolution.
**Used by:** UI (Loadouts tab — create/assign/delete), Colony (subscribes raid/expedition signals).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `templates` | `Array[LoadoutTemplate]` | Player-created templates (saved per run in `data/loadouts/`). |
| `assignments` | `Dictionary[String, String]` | colonist_id → template_id. |

**Functions:**

| Function | Description |
|---|---|
| `create_template(name: String) -> String` | Returns new template_id. |
| `delete_template(template_id: String) -> void` | Also clears any assignments referencing it. |
| `assign(colonist_id: String, template_id: String) -> void` | Per-colonist assignment. |
| `auto_equip_for_raid() -> void` | Called on `raid_started`; resolves + equips all assigned colonists. |
| `auto_unequip_on_return() -> void` | Called on `raid_ended`/`expedition_ended`; returns all equipped to storage. |

### Class: DiscoveredGear

**Extends:** Node (child of Colony autoload)
**Script:** `discovered_gear.gd` (in `equipment/`)
**Description:** Once-per-run tracking of item_def_ids the colony has possessed. Gates the loadout-slot picker. Subscribes to Inventory signals.
**Used by:** UI (Loadouts slot picker), LoadoutManager (auto-equip candidates).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `discovered` | `Array[String]` | item_def_ids ever possessed this run. Saved with Colony. |

**Functions:**

| Function | Description |
|---|---|
| `mark_discovered(item_def_id: String) -> void` | Called on item pickup; idempotent. |
| `get_discovered_for_slot(slot: String) -> Array[String]` | Filters discovered item_defs valid for the slot (for the picker UI). |
