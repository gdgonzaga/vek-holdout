# Subsystem: Equipment

Per-character 8-slot gear system. `Equipment` (Node component) holds concrete `ItemDef` references keyed by slot ID. `EquipmentVisualizer` (sibling Node) owns all 3D visual attachment logic. Both live under `subsystems/equipment/`. GDD §17 Equipment.

> **Implementation status: implemented.** `equipment.gd` and `equipment_visualizer.gd` exist and are code-created on every `Colonist` and `Player` in `_ready`. Loadout fulfillment via `EquipmentAudit` and `FetchEquipmentJobDef` is active. Manual loadout templates (`LoadoutBook`, applied from the Gear sub-tab and squad cards) are implemented; raid auto-equip (`LoadoutManager`), `DiscoveredGear` and armor/shield data schemas are future scope.

---

## Slot Design

| Slot ID | Constant | Accepted Tags | Notes |
|---|---|---|---|
| `head` | `SLOT_HEAD` | `equip_head` | Armor |
| `torso` | `SLOT_TORSO` | `equip_torso` | Armor |
| `legs` | `SLOT_LEGS` | `equip_legs` | Armor |
| `feet` | `SLOT_FEET` | `equip_feet` | Armor |
| `main_hand` | `SLOT_MAIN_HAND` | `tool`, `weapon` | Active working/combat hand |
| `off_hand` | `SLOT_OFF_HAND` | `shield` | Placeholder — shield items not yet authored |
| `holster` | `SLOT_HOLSTER` | `tool`, `weapon` | Sidearm slot; swaps with main_hand |
| `back` | `SLOT_BACK` | `equip_back`, `shield` | Back carry; shield stow destination |

Slot routing is **tag-based**: items declare eligibility via `ItemDef.tags`. `EquippableParams` no longer has a `SlotType` enum — it owns only animation and action parameters.

In the Colony Management UI, `holster` is labeled as **"Sidearm"** via `GearText.SLOT_DISPLAY_NAMES` (see [Colony Management Gear UI](#colony-management-gear-ui)).

---

## Files

| File | Type | Responsibility |
|---|---|---|
| `equipment.gd` | Script (`class_name Equipment`, extends Node) | Per-character slot state and desired target assignments. No visual logic. Serializable. |
| `equipment_visualizer.gd` | Script (`class_name EquipmentVisualizer`, extends Node) | Visual attachment: listens to `Equipment.slot_changed`, instantiates GLB/mesh on per-slot skeleton sockets. |
| `equipment_audit.gd` | Script (`class_name EquipmentAudit`) | Static helper library executing desired equipment audits, swap-first resolution, and fetch job creation. |
| `fetch_equipment_job.gd` | Script (`class_name FetchEquipmentJob`, extends Job) | Targeted job carrying `target_slot` and `target_item_id`. |
| `fetch_equipment_job_def.gd` | Script (`class_name FetchEquipmentJobDef`, extends JobDef) | Work logic for equipment fetching: path to storage, direct equip in `complete()`, desire invalidation. |
| `data/jobs/fetch_equipment.tres` | Resource (`FetchEquipmentJobDef`) | Singleton job def resource for equipment retrieval. |

Both `Equipment` and `EquipmentVisualizer` are code-created as child nodes in `Colonist._ready` and `Player._ready`, via the shared `Equipment.ensure_on(actor, current)` static factory — it creates `Equipment` if `current` is null, then creates and wires `EquipmentVisualizer` so the sibling exists and listens to `slot_changed`. `equip_item()`'s main-hand-first-with-fallback policy is likewise shared via `Equipment.equip_preferring_main_hand(item_def)`.

---

## Signals

| Signal | Emitted by | Listeners | Via EventBus? |
|---|---|---|---|
| `slot_changed(slot_id, item)` | `Equipment` | `EquipmentVisualizer` (direct ref), HUD (direct ref), `ColonistEquipmentPanel` (direct ref) | No |
| `desired_slot_changed(slot_id, item_id)` | `Equipment` | `ColonistEquipmentPanel` (direct ref; it refreshes the slot rows) | No |

---

## Visual Socket Architecture

`EquipmentVisualizer` manages visual attachment across two pipelines depending on whether the equipped `ItemDef` carries a `WearableParams` capability (`item.is_wearable()`):

### 1. Traditional Held Items (Tools, Weapons)
For non-wearable items, `EquipmentVisualizer` resolves one `BoneAttachment3D` socket per slot from the parent's `Skeleton3D`:
1. **Scene-authored socket** — looks for a child named `EquipSocket_<slot_id>` on the skeleton (e.g. `EquipSocket_main_hand`). Author these in `colonist.tscn` / `player.tscn` for precise placement.
2. **Auto-created socket** — if not found, tries bone names from `SLOT_BONE_HINTS[slot_id]` (e.g. `["socket_hand_r", "RightHand", "mixamorig:RightHand"]` for `main_hand`). Creates a `BoneAttachment3D` named `EquipSocket_<slot_id>` on the first match.
3. **Skip** — if no bone hint matches (e.g. `holster` with no authored socket), the slot has no visual and is silently ignored.

### 2. Wearable Items (Armor, Clothing, Headgear, Footwear)
When `item.is_wearable()` is true, visuals mount dynamically across multi-bone attachments or skinned mesh bindings, tracked in `_slot_visuals[slot_id]` (`Array[Node]`):
- **Rigid Parts (`rigid_parts: Array[WearablePart]`)**: For helmets, pauldrons, boots, and primitive clothing shapes. For each part, resolves or creates a `BoneAttachment3D` named `WearBone_<bone>` on the character's `Skeleton3D` on first use (silently skipping if the bone does not exist in the rig). Mounts a `MeshInstance3D` with the part's mesh, material, and offset. Two slots sharing the same bone attach separate child meshes and do not delete each other's visuals on unequip.
- **Skinned Garments (`skinned_scene: PackedScene`)**: For deformable shirts and pants. Instantiates the garment scene, extracts all `MeshInstance3D` nodes carrying an active `skin`, reparents them directly under the character's `Skeleton3D` with `skeleton = NodePath("..")`, and frees the scene root remnant. Bone mapping binds through glTF `bind_names` matching the humanoid `SkeletonProfileHumanoid` bone map.
- **Unequip & Switch Cleanup**: When a slot changes or unequips (`item == null`), `_clear_slot_visuals(slot_id)` iterates and frees all tracked nodes in `_slot_visuals[slot_id]` and empties any traditional socket children, leaving zero leftovers.

---

## Main-hand / Holster Swap & Cascading Stow

`Equipment.swap_hand_for_tag(needed_tag)` is the key AI helper:

1. `main_hand` already has the tag -> no-op, return `true`.
2. `holster` has the tag -> swap `main_hand` <-> `holster`, return `true`.
3. Neither -> return `false` (caller fetches from inventory or storage).

`Equipment.stow_and_equip(slot_id, item_def, inventory)` provides safe cascading stow:
1. If the target slot already holds the exact same item, returns `true` (no-op).
2. If the target slot is currently empty, equips the item directly.
3. If the target slot is occupied (e.g. `main_hand` holding a weapon):
   - Attempts to stow the displaced item into `holster` if `holster` is empty and eligible.
   - If `holster` is unavailable, attempts to stow into `inventory` (carry pockets).
   - If neither stow destination has room, the operation fails and returns `false` without modifying equipment.

`BTActionEquipTool` calls `swap_hand_for_tag` before work execution. If the tool is carried in inventory, it removes 1 unit and executes `stow_and_equip(SLOT_MAIN_HAND, tool_def, inventory)` to preserve the previously held weapon/tool.

---

## Desired Loadout & Equipment Fulfillment

Colonists maintain a desired item ID for each slot in `Equipment._desired_slots`. The colony management UI's **Gear** sub-tab lets players configure these targets per colonist (the UI calls them *targets*).

### Audit Trigger Points

`EquipmentAudit.run_audit(colonist, job_board)` runs at two specific points:
1. **At Job Claim Boundaries (`BTActionClaimJob`)**: Called in `_cleanup_incompatible_held_items` before normal labor claims.
2. **At Idle Fallback (`JobBoard.get_best_job_for`)**: Called when no labor or haul job is selected, immediately returning newly posted fetch jobs to prevent idle wandering.

### Audit Resolution Sequence

1. **Hand Pair Audit (`main_hand` & `holster`)**: Checks whether the desired item for either slot is currently in the partner slot. If so, swaps directly without generating a fetch job.
2. **Shield Pair Audit (`off_hand` & `back`)**: Swaps shields between off_hand and back if the desired item is in the opposite slot.
3. **Single Slot Audit (Armor & Remainder)**:
   - If slot is already satisfied -> no-op.
   - If slot has wrong item -> unequip into carry inventory (skipped if carry is full).
   - If desired item is in carry inventory -> equip immediately (no job needed).
   - If a fetch job already targets this slot+item -> skip duplicate.
   - If item is in colony storage -> post `FetchEquipmentJob`.

### Fetch Equipment Job (`FetchEquipmentJobDef`)

- **Priority**: Has priority `500` in `JobBoard.get_best_job_for`, higher than all normal labor (max ~150) but lower than deploy commands (`1000`).
- **Dynamic Crate Resolution**: `work_site()` re-queries `StorageRegistry.find_storage_for()` every navigation cycle so destroyed crates trigger transparent rerouting.
- **Defensive Completion**: In `complete()`, the item is equipped to the slot *before* removing it from the storage crate to ensure no items are destroyed if equip validation fails.
- **Labor Intercept Mode**: Jobs created via `JobBoard._create_and_post_intercept_fetch_job` set `is_labor_intercept = true`. These bypass the colonist `_desired_slots` requirement in `is_available_for()` and `should_close()`, and call `stow_and_equip()` on completion to cleanly stow the held weapon/tool.
- **Stale Invalidation**: Standard loadout fetch jobs check if the desired item for the slot was modified while the job was in flight, retiring stale jobs cleanly.

---

## Colony Management Gear UI

The **Gear** sub-tab (Tab, Colonists, Gear) edits each colonist's desired loadout. Scenes and helpers live in `ui/colony_management/`:

- **`colonist_equipment_panel`** - left: eight one-line `equipment_slot_row` tiles (slot, equipped item, a pending `-> target`, status pip); right: an always-visible picker for the selected slot (equipped/target box with **Unequip** and **Clear target**, search, **In colony only** toggle, grouped list of `equipment_picker_row`s).
- **Refresh model.** Rows and the slot-state box follow `Equipment.slot_changed` / `desired_slot_changed` (no polling). Status reasons and picker stock have no change signal, so the owning `colonist_details_panel` re-evaluates them on a 1.0 s tick while the Gear sub-tab is visible. The picker list itself is rebuilt only on slot select, search, toggle, or a change to the selected slot.
- **Picker list.** `GearPickerModel.build_entries` groups eligible items by the slot's first accepted tag (`SLOT_ACCEPTED_TAGS` order), sorts stocked items first and then by name, and, with **In colony only** on (the default), hides items with no crate stock except the slot's current target and equipped item. Stock is `StorageRegistry.crate_stock` (crates only: that is all a `FetchEquipmentJob` can take). Items without an authored `icon` show a first-letter fallback.
- **Status reasons.** `GearStatus.evaluate` reports why a target is unmet, in the order `EquipmentAudit` fulfils it: in the partner slot (will swap), in pockets (will equip), fetch queued (a `FetchEquipmentJob` for that colonist, slot and item is on the board), in storage (a fetch is posted at the next audit), otherwise none in storage. Its swap-partner pairs mirror `EquipmentAudit._audit_hand_pair` / `_audit_shield_pair`; keep them in sync.
- **Unequip is disabled while the slot has a target**, because the audit would re-equip the item from pockets. Clear the target first.
- **Esc** closes the picker before it closes the screen (`ColonistEquipmentPanel.handle_cancel`, called from its `_unhandled_input`; descendants receive unhandled input before their ancestors and `Main`).
- **Names.** `GearText.item_display_name` (resource name, else id) and `GearText.slot_display_name` are the only naming paths; `holster` is labeled **Sidearm** through `GearText.SLOT_DISPLAY_NAMES`.

---

## Loadouts (Named Slot Templates)

A **loadout** is a player-authored, named `{slot_id: item_id}` template with at most one item per slot. It has no priorities or fall-back ranks: each slot holds one item or is undefined.

- **Stamped, not linked.** Applying a loadout writes each defined slot into the colonist's desired slots through `Equipment.set_desired_item`, then forgets the colonist. The audit, `FetchEquipmentJob`, storage hygiene and `GearStatus` only ever read `equipment.get_desired_item(slot)`, so none of them knows loadouts exist. Editing a loadout later does not change colonists that already received it. Fetch jobs already in flight for a replaced target retire through the existing stale-target check.
- **Partial apply.** A loadout stores only the slots it defines, and apply touches only those. A "Miner" tool loadout does not wipe a colonist's personal armor. A loadout therefore cannot clear a target; use **Clear target** in the Gear picker for that.
- **Eligibility is checked on apply.** `Equipment.set_desired_item` only validates the slot id, so `LoadoutBook.apply_to` resolves each item id through a caller-supplied resolver (`ItemDB.get_def` in the UI) and requires `Equipment.can_equip_to`. Unknown items and items that do not fit the slot are skipped and counted, never written. A loadout may name items the colony does not own yet; the normal target status (`None in colony`) reports the shortage.
- **Matching is derived.** `LoadoutBook.matches` / `find_matching_ids` compare a colonist's targets to each loadout on demand (all defined slots equal; an empty loadout matches nothing). No colonist stores a loadout id.

### Class: LoadoutBook

**Script:** `subsystems/equipment/loadout_book.gd` (`RefCounted`, no autoload access). `Colony.loadouts` owns the single instance as a plain field (not a child node) and saves it under `"loadouts"` in `Colony.serialize()`; `Colony.reset_for_new_game()` clears it and an older save without the key restores an empty book.

| Function | Description |
|---|---|
| `create(name) -> String` | New empty loadout; returns its generated id (`loadout_N`, never reused after a delete) or `""` for a blank or already-used name (case-insensitive). |
| `rename(id, name)`, `delete(id)`, `has(id)`, `list_ids()`, `get_name(id)`, `find_id_by_name(name)` | Identity and lookup. Ids are stable across renames; `list_ids` is creation order. |
| `set_slot(id, slot_id, item_id)`, `clear_slot(id, slot_id)`, `get_slots(id)` | Edit one slot. `set_slot` rejects unknown slot ids and blank item ids; `get_slots` returns a copy. |
| `capture_from(id, equipment)` | Replace the loadout's slots with the colonist's non-empty targets ("save these targets as a loadout"). |
| `apply_to(id, equipment, resolve_item) -> Dictionary` | Stamp onto a colonist. Returns `{"changed": int, "skipped": int}`; a slot already on target is neither. |
| `matches(id, equipment)`, `find_matching_ids(equipment)` | Derived "which loadouts does this colonist match". |
| `serialize()` / `deserialize(data)` / `reset()` | SaveSystem contract. `deserialize` drops malformed entries and unknown slot ids and resumes the id counter past every restored id. |

Signal: `changed()` fires after any mutation (including `deserialize` and `reset`) so open UI refreshes without polling.

### Loadout UI

- **`loadout_strip`** (top of the Gear sub-tab, instanced by `colonist_equipment_panel`): a loadout dropdown, **Apply**, **Save as...** (an inline name row, no popup, so no UiGate involvement), a `Matches: X` / `Custom targets` / `No targets set` label and a one-line result message. **Save as...** is disabled until the colonist has a target; a typed name that already exists turns the confirm button into **Overwrite**. Esc in the name field closes the row and is consumed, so it never closes the screen. The strip listens to the colonist's `desired_slot_changed` and to `LoadoutBook.changed`.
- **`squad_card`**: a `Loadout [v] [Apply to squad]` row that applies to every live member of the squad (`Colony.get_squad_members`) and reports one summed sentence. There is deliberately no separate colonist-group concept: squads already are the group.
- **`LoadoutUi`** (`ui/colony_management/loadout_ui.gd`): stateless helpers shared by both: result sentences, dropdown filling / selection (loadout ids ride as item metadata), `has_targets`, and the item resolver.
- **Not built yet:** rename/delete UI (the book supports both), a dedicated Loadouts tab with a full editor, per-loadout availability preview, and roster multi-select apply.

**Known behavior to be aware of.** `FetchEquipmentJob` has priority 500 (above all labor). Applying a loadout to a whole squad can post up to 8 fetch jobs per colonist at once, and colonists drop work to gear up. Nothing reserves stock: with one rifle and three colonists targeting it, the first fetch wins and the others show `None in colony`.

---

## Inventory vs Equipment

Equipment and carry inventory are **separate stores**. When `BTActionEquipTool` equips a tool from inventory it calls `inventory.remove(item_id, 1)` then `equipment.stow_and_equip(SLOT_MAIN_HAND, item_def, inventory)`. Colonists keep their tool equipped across jobs (no unequip on job end); `swap_hand_for_tag` handles switching for a different job.

When colonists fall idle and perform storage hygiene, `JobBoard._find_best_crate_for_inventory` respects `_is_item_desired_by_colonist`, allowing colonists to keep desired loadout items in their pockets while depositing temporary labor tools back into colony crates.

---

## Class Reference

### Class: Equipment

**Extends:** Node (component on Player + each Colonist)  
**Script:** `subsystems/equipment/equipment.gd`

**Constants:**

`SLOT_HEAD`, `SLOT_TORSO`, `SLOT_LEGS`, `SLOT_FEET`, `SLOT_MAIN_HAND`, `SLOT_OFF_HAND`, `SLOT_HOLSTER`, `SLOT_BACK` — canonical slot ID strings.

`SLOT_ACCEPTED_TAGS: Dictionary` — maps each slot ID to its accepted tag list.

**Signals:**

| Signal | Description |
|---|---|
| `slot_changed(slot_id: String, item: ItemDef)` | Emitted on every equip or unequip. `item` is null on unequip. |
| `desired_slot_changed(slot_id: String, item_id: String)` | Emitted when a desired target item changes. |

**Functions:**

| Function | Returns | Description |
|---|---|---|
| `ensure_on(actor, current)` | `Equipment` | Static. Creates/wires Equipment + EquipmentVisualizer on actor if not already present. Shared by Player/Colonist `_ready`. |
| `can_equip_to(slot_id, item_def)` | `bool` | True if item carries at least one accepted tag for the slot. |
| `equip(slot_id, item_def)` | `bool` | Places item; emits `slot_changed`. False if tags invalid. |
| `equip_preferring_main_hand(item_def)` | `bool` | Equips into main_hand, falling back to `get_slot_for_item`. Shared `equip_item()` policy for Player/Colonist. |
| `unequip(slot_id)` | `ItemDef` | Removes and returns item; emits `slot_changed`. Null if empty. |
| `get_item(slot_id)` | `ItemDef` | Current item in slot, or null. |
| `is_empty(slot_id)` | `bool` | True if slot holds no item. |
| `get_slot_for_item(item_def)` | `String` | First valid empty slot (prefers main_hand/holster), or "". |
| `has_item_with_tag(tag)` | `bool` | True if any equipped slot holds an item with the tag. |
| `has_required_equipment(item_id, tags)` | `bool` | True if any equipped slot matches `item_id` or carries any of `tags`. Checked by `BTConditionHasTool` before falling back to an inventory scan. |
| `swap_hand_for_tag(needed_tag)` | `bool` | main_hand/holster swap helper. See design above. |
| `swap_hand_for_requirements(item_id, tags)` | `bool` | Like `swap_hand_for_tag`, but matches by exact `item_id` or any of `tags`. |
| `swap_hand_to_holster()` | `void` | Unconditional main_hand <-> holster swap. |
| `stow_and_equip(slot_id, item_def, inventory)` | `bool` | Equips item into slot, cascading existing item into holster or inventory if needed. |
| `get_desired_item(slot_id)` | `String` | Returns configured desired item ID for slot ("" if none). |
| `set_desired_item(slot_id, item_id)` | `void` | Sets target desired item ID; emits `desired_slot_changed`. |
| `clear_desired_item(slot_id)` | `void` | Clears target desired item ID. |
| `get_all_desired_items()` | `Dictionary` | Returns duplicate of `_desired_slots`. |
| `is_desired_equipped(slot_id)` | `bool` | True if current equipped item matches desired item ID. |
| `get_eligible_items_for_slot(slot_id)` | `Array[ItemDef]` | Static helper querying `ItemDB` for items accepted by slot. |
| `serialize()` | `Dictionary` | `{slot_id: item_id, "_desired": desired_dict}`. |
| `deserialize(data)` | `void` | Restores slots and desired slot targets from serialized dict. |

### Class: EquipmentVisualizer

**Extends:** Node (sibling of Equipment on Player + each Colonist)  
**Script:** `subsystems/equipment/equipment_visualizer.gd`

**Constants:**

`SLOT_BONE_HINTS: Dictionary` — per-slot ordered list of bone name candidates for auto-socket creation.

**Functions (public):**

| Function | Description |
|---|---|
| `on_slot_changed(slot_id, item)` | Connected to `Equipment.slot_changed` in `_ready`. Clears old visual and attaches new GLB/mesh on the slot socket. |

### Class: EquipmentAudit

**Script:** `subsystems/equipment/equipment_audit.gd`

Static audit and loadout fulfillment coordinator. Evaluates colonist equipment, carry inventory, and colony storage to execute swaps, equips, and job dispatching.

---

## BT Integration

`BTActionEquipTool` (`subsystems/ai/tasks/actions/bt_action_equip_tool.gd`):
- Reads `required_equipped_tags` / `required_tool_tag` from blackboard (falls back to active job's `required_equipped_tags`).
- Calls `equipment.swap_hand_for_tag(tag)` — succeeds if tool already equipped.
- Falls back to `inventory` scan -> `equipment.stow_and_equip(SLOT_MAIN_HAND, item, inventory)`.

`BTActionClaimJob` (`subsystems/ai/tasks/actions/bt_action_claim_job.gd`):
- Calls `EquipmentAudit.run_audit()` in `_cleanup_incompatible_held_items` to ensure colonists equip their desired loadout before starting labor.

`BTConditionHasTool` also checks `Equipment.has_item_with_tag` before scanning inventory, so an already-equipped tool satisfies the condition without carry inventory lookup.

---

## Future scope (not yet built)

- **`LoadoutManager`** (child of Colony autoload) — auto-equip a colonist's assigned loadout on `raid_started` / auto-unequip on `raid_ended`. The templates themselves now exist as `LoadoutBook` (see [Loadouts](#loadouts-named-slot-templates)); only the raid-triggered assignment remains. See tech-debt.md.
- **`DiscoveredGear`** (child of Colony autoload) — tracks item_def_ids ever possessed; gates loadout-slot picker UI.
- **Armor + shield items** — `data/armor/` and `data/shields/` schemas (C9 in TODO.md).
- **Durability sum** — `Equipment.get_total_durability() -> int` for HealthComponent once armor items ship.
- **`hides_body_regions`** — optional array on `WearableParams` to selectively hide body sub-meshes (`head`, `torso`, `arms`, `legs`, `feet`) on modular characters to eliminate joint skin clipping under complex clothing.
