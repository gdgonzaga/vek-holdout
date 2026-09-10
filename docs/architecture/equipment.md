# Subsystem: Equipment

Per-character 8-slot gear system. `Equipment` (Node component) holds concrete `ItemDef` references keyed by slot ID. `EquipmentVisualizer` (sibling Node) owns all 3D visual attachment logic. Both live under `subsystems/equipment/`. GDD §17 Equipment.

> **Implementation status: implemented.** `equipment.gd` and `equipment_visualizer.gd` exist and are code-created on every `Colonist` and `Player` in `_ready`. Loadout templates (`LoadoutManager`, `DiscoveredGear`) and armor/shield data schemas are future scope.

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
| `holster` | `SLOT_HOLSTER` | `tool`, `weapon` | Stored tool; swaps with main_hand |
| `back` | `SLOT_BACK` | `equip_back`, `shield` | Back carry; shield stow destination |

Slot routing is **tag-based**: items declare eligibility via `ItemDef.tags`. `EquippableParams` no longer has a `SlotType` enum — it owns only animation and action parameters.

---

## Files

| File | Type | Responsibility |
|---|---|---|
| `equipment.gd` | Script (`class_name Equipment`, extends Node) | Per-character slot state. No visual logic. Serializable. |
| `equipment_visualizer.gd` | Script (`class_name EquipmentVisualizer`, extends Node) | Visual attachment: listens to `Equipment.slot_changed`, instantiates GLB/mesh on per-slot skeleton sockets. |

Both are code-created as child nodes in `Colonist._ready` and `Player._ready`. `Equipment` must be added before `EquipmentVisualizer` so the sibling exists when the visualizer wires `slot_changed` in its own `_ready`.

---

## Signals

| Signal | Emitted by | Listeners | Via EventBus? |
|---|---|---|---|
| `slot_changed(slot_id, item)` | `Equipment` | `EquipmentVisualizer` (direct ref), HUD (direct ref) | No |

---

## Visual Socket Architecture

`EquipmentVisualizer` resolves one `BoneAttachment3D` socket per slot from the parent's `Skeleton3D`. Resolution order:

1. **Scene-authored socket** — looks for a child named `EquipSocket_<slot_id>` on the skeleton (e.g. `EquipSocket_main_hand`). Author these in `colonist.tscn` / `player.tscn` for precise placement.
2. **Auto-created socket** — if not found, tries bone names from `SLOT_BONE_HINTS[slot_id]` (e.g. `["socket_hand_r", "RightHand", "mixamorig:RightHand"]` for `main_hand`). Creates a `BoneAttachment3D` named `EquipSocket_<slot_id>` on the first match.
3. **Skip** — if no bone hint matches (e.g. `holster` with no authored socket), the slot has no visual and is silently ignored.

Armor slots (`head`, `torso`, `legs`, `feet`, `back`) are scaffolded but fire no visuals until art assets and scene sockets are added.

---

## Main-hand / Holster Swap

`Equipment.swap_hand_for_tag(needed_tag)` is the key AI helper:

1. `main_hand` already has the tag → no-op, return `true`.
2. `holster` has the tag → swap `main_hand` ↔ `holster`, return `true`.
3. Neither → return `false` (caller fetches from inventory).

`BTActionEquipTool` calls this before work execution and falls back to pulling the tool from the carry inventory.

---

## Inventory vs Equipment

Equipment and carry inventory are **separate stores**. When `BTActionEquipTool` equips a tool from inventory it calls `inventory.remove(item_id, 1)` then `equipment.equip(slot, item_def)`. Colonists keep their tool equipped across jobs (no unequip on job end); `swap_hand_for_tag` handles switching for a different job.

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

**Functions:**

| Function | Returns | Description |
|---|---|---|
| `can_equip_to(slot_id, item_def)` | `bool` | True if item carries at least one accepted tag for the slot. |
| `equip(slot_id, item_def)` | `bool` | Places item; emits `slot_changed`. False if tags invalid. |
| `unequip(slot_id)` | `ItemDef` | Removes and returns item; emits `slot_changed`. Null if empty. |
| `get_item(slot_id)` | `ItemDef` | Current item in slot, or null. |
| `is_empty(slot_id)` | `bool` | True if slot holds no item. |
| `get_slot_for_item(item_def)` | `String` | First valid empty slot (prefers main_hand/holster), or "". |
| `has_item_with_tag(tag)` | `bool` | True if any equipped slot holds an item with the tag. |
| `swap_hand_for_tag(needed_tag)` | `bool` | main_hand/holster swap helper. See design above. |
| `swap_hand_to_holster()` | `void` | Unconditional main_hand ↔ holster swap. |
| `serialize()` | `Dictionary` | `{slot_id: item_id}` — empty slots stored as "". |
| `deserialize(data)` | `void` | Restores from serialized dict via `ItemDB`. Unknown IDs silently null. |

### Class: EquipmentVisualizer

**Extends:** Node (sibling of Equipment on Player + each Colonist)  
**Script:** `subsystems/equipment/equipment_visualizer.gd`

**Constants:**

`SLOT_BONE_HINTS: Dictionary` — per-slot ordered list of bone name candidates for auto-socket creation.

**Functions (public):**

| Function | Description |
|---|---|
| `on_slot_changed(slot_id, item)` | Connected to `Equipment.slot_changed` in `_ready`. Clears old visual and attaches new GLB/mesh on the slot socket. |

---

## BT Integration

`BTActionEquipTool` (`subsystems/ai/tasks/actions/bt_action_equip_tool.gd`):
- Reads `required_tool_tag` from blackboard (falls back to active job's `required_tool_tag`).
- Calls `equipment.swap_hand_for_tag(tag)` — succeeds if tool already equipped.
- Falls back to `inventory` scan → `equipment.equip(SLOT_MAIN_HAND, item)`.

`BTConditionHasTool` also checks `Equipment.has_item_with_tag` before scanning inventory, so an already-equipped tool satisfies the condition without carry inventory lookup.

---

## Future scope (not yet built)

- **`LoadoutManager`** (child of Colony autoload) — player-created slot→item_def_id templates, auto-equip on `raid_started` / auto-unequip on `raid_ended`. See tech-debt.md.
- **`DiscoveredGear`** (child of Colony autoload) — tracks item_def_ids ever possessed; gates loadout-slot picker UI.
- **Armor + shield items** — `data/armor/` and `data/shields/` schemas (C9 in TODO.md).
- **Durability sum** — `Equipment.get_total_durability() -> int` for HealthComponent once armor items ship.

