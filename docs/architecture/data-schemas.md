# Data Schemas

## `data/game_config.tres` (Resource: `game_config.gd`)

| Field | Type | Description |
|---|---|---|
| `gravity` | `float` | 9.8 (Y). |
| `target_fps` | `int` | 60 (floor 30). |
| `loop_length_minutes` | `float` | 30 (1 in-game day). |
| `max_enemies_on_screen` | `int` | 24. |

## `data/maps/<id>/map_def.tres` (Resource: `map_def.gd`)

One `MapDef` per loadable map. Scanned from `data/maps/*/map_def.tres` by `MapLibrary`. The catalog entry that picks which scene to load and where actors spawn; the `.tscn` is the runtime contract. **`id` must equal the folder name** — `SceneManager` derives the runtime sqlite path from it. Maps are hybrid: per-map `.tscn` for visual layout/nodes (terrain stream + furniture markers), this `.tres` for metadata + spawn config. Authored via the Voxel Paint "+ New Map" button (see `docs/HOWTO-create-a-map.md`).

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Map id; **must match the folder name** (`data/maps/<id>/`). Drives the runtime sqlite path. |
| `display_name` | `String` | Player-facing name (world map list). |
| `description` | `String` | One-liner shown under the name in the world map. |
| `scene_path` | `String` | The `Map` scene to instantiate. POIs → per-map `res://data/maps/<id>/map.tscn`; base → `res://subsystems/voxel/map.tscn`. |
| `map_type` | `MapType` enum | `BASE` / `POI` / `BUILDING` / `TOWN`. `POI` maps are auto-discovered at boot and listed in the world map. |
| `player_spawn` | `Vector3` | Fallback player spawn (default `(0, 5, 0)`). Overridden by a `SpawnPoints/PlayerSpawn` Marker3D if present. |
| `enemy_spawns` | `Array[Dictionary]` | `[{ "pos": Vector3, "count": int }]`. Overridden by `SpawnPoints/EnemySpawn_*` markers. |
| `unlock_condition` | `String` | *(Unused — reserved for gated discovery.)* |
| `difficulty` | `int` | 1–N; shown in the world map row. |

## `data/characters/<type>.tres` (Resource: `character_def.gd`) — *(planned)*

> **Status: planned, not yet implemented.** `data/characters/` is empty; `character_def.gd` and the `CharacterType` enum do not exist. The intended union schema (GDD §6) is `display_name` / `character_type` / `max_hp` / `max_durability` / `base_move_speed` / `sprint_multiplier` / `stamina_drain_rate` / `breath_*` costs + regen / `detection_range` / `damage` / `attack_range`. `player.gd` still sources its stats from `@export` vars (TODO: source from a CharacterDef once it lands). The only actor def implemented today is `ColonistDef` (below).

## `data/colonists/<id>.tres` (Resource: `colonist_def.gd`) — `ColonistDef`

The implemented actor definition (e.g. `default_colonist.tres`). `ColonistDef extends Resource`.

| Field | Type | Description |
|---|---|---|
| `max_hp` | `int` | `[export default 100]` |
| `base_move_speed` | `float` | `[export default 3.5]` |
| `sprint_multiplier` | `float` | `[export default 1.5]` |
| `stamina_drain_rate` | `float` | `[export default 1.0]` |
| `breath_costs` | `Dictionary` | `[export]` Per-action Breath costs keyed by name (default `{"sprint": 1.0, "jump": 1.0}`). |
| `starting_skills` | `Dictionary` | `[export]` Starting skill xp/level per labor (default mining + farming at L1). |
| `default_labor_priorities` | `Dictionary` | `[export]` Default labor-priority weights per labor. |

## `data/labors/<id>.tres` (Resource: `labor_def.gd`) — `LaborDef`

The canonical declaration of which labor ids exist. `LaborDef extends Resource`. Labors are referenced elsewhere by their String `id` — a `Colonist`'s `labor_priorities` Dict and a `Job`'s `labor_id` — so these resources are the single source of truth for labor identity + display metadata. Five instances ship today: `construction`, `crafting`, `hauling`, `mechanics`, `smelting` (Repair/Farming/Cooking post-MVP). They are inert data for now — there is no registry autoload; future skill gates / UI load them by path.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | `[export]` The labor id (e.g. `"construction"`) — the key everything else references. |
| `display_name` | `String` | `[export]` UI label (e.g. `"Construction"`). |
| `description` | `String` | `[export default ""]` Short blurb, unused in MVP UI. |

## `data/energy_config.tres` (Resource: `energy_config.gd`) — *(planned)*

> **Status: planned — `energy_config.gd`/`.tres` do not exist yet.** Field table below is the intended schema (Energy subsystem, GDD §17).

Global Energy values (shared across all characters). Per-character rates (Stamina drain, Breath costs) live in `data/characters/`.

| Field | Type | Description |
|---|---|---|
| `work_threshold` | `float` | 0.45 — Stamina below this triggers Tired band (work penalty). |
| `move_threshold` | `float` | 0.25 — Stamina below this triggers Exhausted band (move penalty too). |
| `collapse_threshold` | `float` | 0.0 — Stamina at this triggers Collapsed band. |
| `work_floor` | `float` | 0.6 — minimum work-speed multiplier (at collapse). |
| `move_floor` | `float` | 0.4 — minimum move-speed multiplier (at collapse). |
| `stamina_work_multiplier` | `float` | 2.0 — drain multiplier while `working == true`. |
| `sprint_gate` | `float` | 0.20 — Breath below this blocks sprint. |

## `data/blocks/<type>.tres` (Resource: `block_def.gd`)

`BlockDef` `extends BuildableDef` — voxel blocks. Inherits `id` / `display_name` / `icon` / `hp` / `mesh` / `texture` / `texture_variation` / `material_cost` / `unlocked_by_default` from `BuildableDef`. The string id is also referred to as "block_id" throughout the voxel subsystem (`VoxelGrid`, `BlockLibrary`).

| Field | Type | Description |
|---|---|---|
| `is_terrain` | `bool` | `[export default false]` BlockDef's own field. True for the indestructible terrain block (forced to voxel-tool library index 1 by `BlockLibrary`). |
| `id` | `String` | *(inherited)* e.g. `"wood"`, `"scrap"`, `"stone"`. |
| `hp` | `int` | *(inherited)* Block HP (50/100/300/600/1200). |
| `mesh` | `Mesh` | *(inherited)* Blocky-mode mesh (unit cube). |
| `material_cost` | `Array[ItemAmount]` | *(inherited)* Materials consumed when building (see `ItemAmount`). |

## `data/buildables/<id>.tres` (Resource: `buildable_def.gd`)

Base `BuildableDef` — player-placed objects not on the voxel grid (e.g. `pole`). Also the parent class of `BlockDef` and `FurnitureDef`, which is where `id` / `display_name` / `icon` / `hp` / `mesh` / `texture` / `texture_variation` / `material_cost` / `unlocked_by_default` are inherited from.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique buildable id (e.g. `"pole"`, `"workbench"`, `"wood"`). Catalog key for `BuildLibrary`. |
| `display_name` | `String` | UI label. `Furniture.label` exposes this to the interaction menu via a getter. |
| `icon` | `Texture2D` | UI icon for the build menu (nullable; entries render without it). Inherited by `BlockDef` and `FurnitureDef`. |
| `hp` | `int` | Durability-before-HP buffer (GDD §6.11). |
| `mesh` | `Mesh` | Preview/placement mesh; for voxel blocks MUST occupy `(0,0,0)→(1,1,1)`. |
| `texture` | `Texture2D` | Albedo texture. `BlockLibrary` builds a `StandardMaterial3D` from this (no separate material `.tres` per type); the furniture authoring path does the same inline. |
| `texture_variation` | `bool` | `[export default false]` Block-only: opts into a per-block UV/brightness randomization shader so repeating textures don't tile visibly (handled in `BlockLibrary`). |
| `material_cost` | `Array[ItemAmount]` | Materials consumed to build (each entry = an `ItemDef` + count; see `ItemAmount`). Enforced by the blueprint deposit flow (`BlueprintPlacementStrategy`); the `InstantPlacementStrategy` debug fallback still defers it. |
| `unlocked_by_default` | `bool` | Available without earning an unlock this run; seeded by `BuildLibrary`. |

_(No cost-helper methods — `material_cost` is read directly as an `Array[ItemAmount]`.)_

## `data/furniture/<id>.tres` (Resource: `furniture_def.gd`)

`FurnitureDef` `extends BuildableDef` — free-standing buildables (Workbench, Forge, Clinic Bed, Workshop, etc.). Inherits all `BuildableDef` fields. Partial (C1) — see [Actions & Interaction](actions.md) and [Build](build.md).

> **Workshop** (`workshop.tres`) — `dimensions = Vector3i(2, 1, 1)`, `unlocked_by_default = true`, empty `material_cost`, `build_time = 10.0`. It reuses the Workbench mesh as a cosmetic placeholder and exists as the colonist sprint's build-job proof target: placing its blueprint is what produces the construction Job a colonist walks to (see [Colonists](colonists.md)).

| Field | Type | Description |
|---|---|---|
| `dimensions` | `Vector3i` | `[export default ONE]` Cell-box the item occupies: x=width, y=height, z=depth (GDD §7.2). Rotation (R) swaps x/z; even-sized x or z shift the placement pivot 0.5m (GDD §7.4). |
| `action_options` | `Array[ActionOption]` | `[export default []]` Interaction options offered on E-press. Each entry is an `ActionOption` `.tres` (see below). Empty (default) means non-interactable — `FurnitureLayer` attaches no `InteractionComponent`. |
| `test_params` | `TestParams` | `[export, nullable]` Composition-pattern placeholder for capability-specific parameters. Null = no capability data. See "FurnitureDef capability parameters" below. |
| `item_dispenser_params` | `ItemDispenserParams` | `[export, nullable]` Capability sub-resource consumed by `GiveItemAction` (the items it dispenses, as `Array[ItemAmount]`). Schema in `data/capability_params/`. |
| `storage_params` | `StorageParams` | `[export, nullable]` Capability sub-resource consumed by `StorageInventory` (its `capacity`, default 100.0). Schema in `data/capability_params/`. |

> **FurnitureDef capability parameters** *(decided, partially seeded — `test_params` is not yet read by any GameAction)*
>
> When two furniture defs differ only in parameters a `GameAction` reads (e.g. a Workbench vs Workbench-T2 differing in craft speed and max recipe tier), those parameters live on **nullable sub-resources referenced from `FurnitureDef`**, not on the def itself. The pattern: each capability gets a small `Resource` subclass (`CraftingParams`, `StorageParams`, …) exposed as a nullable `@export` on `FurnitureDef`; a placed furniture reads it via `def.crafting` (null if absent). Param schemas live in `data/capability_params/`; `test_params` is the seed of this pattern.
>
> **Why this shape:**
> - **Over `CrafterDef extends FurnitureDef`** — single inheritance dead-ends when a station needs two capabilities (a Workbench that crafts *and* stores ingredients). Composition composes.
> - **Over a flat `params: Dictionary`** on the base — loses typing, inspector ergonomics, and discoverability (a `Dictionary` field is a key-value table of `Variant`; typos like `work_sped` fail silently at runtime, and the UI can't show a tier badge without knowing the magic key). Typed sub-resources give autocompleteable, named fields per capability.
> - **Chosen for the multi-capability case specifically.** For a single capability on a single furniture type, a `CrafterDef` subclass would also be fine; composition wins once combinations are plausible (Workbench, Clinic Bed, Storage Crate per GDD §7.9–§7.11).
>
> **Escape hatch:** a `params: Dictionary` on the base `FurnitureDef` remains valid for genuinely one-off, action-local values that no other system will ever read (e.g. a signal fire's smoke color). Typed, named, cross-consumer data goes on a sub-resource; truly bespoke single-action data goes in the dict.

## `data/actions/<id>.tres` (Resource: `game_action.gd`)

One `.tres` per concrete `GameAction` — "what happens" when the player picks the option. Subclasses override `execute(actor, target)`. Concrete subclasses: `PrintAction` (smoke test), `BuildAction`, `AddMaterialsAction`, `GiveItemAction`, `OpenStorageAction` (each in `data/actions/`). See [Actions & Interaction](actions.md).

| Field | Type | Description |
|---|---|---|
| `label` | `String` | `[export]` Button text shown in the interaction menu. |

**Virtual method:** `execute(actor: Node, target: Node) -> void` — override in a subclass. `actor` is the player; `target` is the interactable node.

## Condition resources (Resource: `condition.gd`)

`Condition` `extends Resource` — gates an `ActionOption`. One `.tres` per condition instance. Composites (`AnyOf`/`AllOf`/`NotCondition`) live in `subsystems/actions/`; leaf conditions live in `data/conditions/` (e.g. `CanCarryDispensedItems`). See [Actions & Interaction](actions.md).

| Class | File | Fields | Semantics |
|---|---|---|---|
| `Condition` (base) | `subsystems/actions/condition.gd` | — | Virtual `is_met(actor, target) -> bool` (default `true`). |
| `AnyOf` | `subsystems/actions/any_of.gd` | `conditions: Array[Condition]` | true if **any** child `is_met`. |
| `AllOf` | `subsystems/actions/all_of.gd` | `conditions: Array[Condition]` | true only if **all** children `is_met` (redundant inside an option, which already ANDs). |
| `NotCondition` | `subsystems/actions/not.gd` | `condition: Condition` | Inverts a single child. |

## `data/action_options/<id>.tres` (Resource: `action_option.gd`)

One `.tres` per `ActionOption` — one row in the interaction menu. Binds a `GameAction` to its gating `Condition`s. Five exist: `build_action_option`, `add_materials_action_option`, `give_item_action_option`, `open_storage_action_option`, `test_action_option`. See [Actions & Interaction](actions.md); authoring walkthrough: `docs/HOWTO-author-interactions.md`.

| Field | Type | Description |
|---|---|---|
| `action` | `GameAction` | `[export]` The action to execute when the button is pressed. |
| `conditions` | `Array[Condition]` | `[export default []]` Gates the option. All must be met for the button to be enabled. |

**Method:** `is_available(actor: Node, target: Node) -> bool` — returns `false` on the first failing condition; `true` if empty. Drives each button's `disabled` state.

## `data/raid_curve.tres` (Resource: `raid_curve.gd`) — *(planned)*

> **Status: planned — `raid_curve.gd`/`.tres` do not exist yet** (Raids subsystem). Intended schema below.

Array of `{day_threshold, waves, enemies_per_wave, shooter_percent}` rows. See GDD §17 Raids for values.

## `data/items/<id>.tres` (Resource: `item_def.gd`)

One `ItemDef` per item type. The **canonical item identity is the `id` field** (e.g. `"wood_block"`) — what `ItemDB` keys by, inventories store, and `material_cost` references. The `.tres` filename is just the file location. Scanned at startup by the `ItemDB` autoload.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Canonical item identity (e.g. `"wood_block"`). Keyed by `ItemDB`; the dict key in inventories and in blueprint `_given` material progress. |
| `weight` | `float` | Weight per unit (kg). Used by `Inventory` for capacity enforcement. |
| `icon` | `Texture2D` | UI icon (nullable). |

## `data/items/item_amount.gd` (Resource: `ItemAmount`)

A counted item reference — the element type of `BuildableDef.material_cost` (and any other "N of this item" list).

| Field | Type | Description |
|---|---|---|
| `item_def` | `ItemDef` | Direct reference to the item definition (read `.id` for the identity). |
| `count` | `int` | `[export default 1]` How many of the item. |

## `data/loot/<table>.tres` (Resource: `loot_table.gd`) — *(planned)*

> **Status: planned — `data/loot/` is empty; `loot_table.gd`/`loot_entry.gd` do not exist yet** (Loot subsystem). Intended schema below.

One per container type: `standard.tres` (Zones A/B), `deep.tres` (Zone C). Each table is an array of `LootEntry` resources (see `loot_entry.gd`). See GDD §17 "Loot tables" for the MVP values.

| Field | Type | Description |
|---|---|---|
| `table_id` | `String` | `"standard"` or `"deep"`. |
| `entries` | `Array[LootEntry]` | One per rollable item. See below. |

**LootEntry** (`loot_entry.gd extends Resource`) — one row of a loot table:

| Field | Type | Description |
|---|---|---|
| `item_id` | `String` | What this entry rolls (e.g. `"scrap"`, `"components"`, `"key_item_pending"`). |
| `min_count` | `int` | Minimum stack if the roll succeeds. |
| `max_count` | `int` | Maximum stack if the roll succeeds. |
| `drop_chance` | `float` | 0.0–1.0 probability per container roll. `1.0` = "always included". |

**Standard container values** (GDD §17): scrap 20–50 (1.0), components 5–15 (0.7), fuel 5–15 (0.4), med_supplies 1–3 (0.25), key_item_pending — — (0.05).
**Deep container values**: scrap 40–90 (1.0), components 10–25 (0.85), fuel 10–20 (0.55), med_supplies 2–5 (0.40), key_item_pending — — (0.20).

## `data/loot/key_items.tres` (Resource: `key_item_pool_def.gd`) — *(planned)*

> **Status: planned — `key_item_pool_def.gd`/`key_item_def.gd` do not exist yet.** Intended schema below.

The Key Item pool. Each Key Item drops at most once per playthrough (enforced by `KeyItemPool.found` on the Colony autoload). See GDD §17 "Key Item Table".

| Field | Type | Description |
|---|---|---|
| `items` | `Array[KeyItemDef]` | The 7 MVP Key Items. See below. |

**KeyItemDef** (`key_item_def.gd extends Resource`):

| Field | Type | Description |
|---|---|---|
| `item_id` | `String` | e.g. `"radio_transceiver_unit"`. |
| `display_name` | `String` | UI label. |
| `upgrade_target` | `String` | The T2 base upgrade this item gates (e.g. `"command_center_t2"`). |

**MVP Key Items** (GDD §17): Radio Transceiver Unit (Command Center T2), Portable Generator (Workshop T2), Water Pump Motor (Farm T2), Medical Fridge Unit (Infirmary T2), Heavy Jack Lift (Garage T2), Insulation Panels (Living Quarters T2), Welding Gas Cylinders (Defenses T2).

## `data/skills/skills.tres` (Resource: `skill_def_list.gd`) — *(planned)*

> **Status: planned — `data/skills/` is empty; `skill_def_list.gd`/`skill_def.gd` do not exist yet** (Skills subsystem). Intended schema below.

Global skill definitions: the 6 MVP skills, their Labor mappings, use-curves, and per-level work-speed multipliers. Loaded once and shared by all `SkillSet` components. See GDD §6.3.

| Field | Type | Description |
|---|---|---|
| `skills` | `Array[SkillDef]` | The 6 skills. See below. |

**SkillDef** (`skill_def.gd extends Resource`) — one skill:

| Field | Type | Description |
|---|---|---|
| `skill_id` | `String` | `"medical"`, `"mechanical"`, `"construction"`, `"crafting"`, `"combat"`, `"farming"`. |
| `display_name` | `String` | UI label. |
| `labor` | `String` | The Labor this skill governs (e.g. `"construction"`). Skills map 1:1 to Labors except Farming (no Labor in MVP). |
| `multipliers` | `Array[float]` | Work-speed multiplier per level, index 0–4 = L1–L5. Default `[1.0, 1.2, 1.4, 1.7, 2.0]`. |
| `use_curve` | `Array[int]` | Successful uses required to reach each level, index 0–3 = L2–L5. Default `[20, 50, 100, 200]`. |

**MVP skills** (GDD §6.3): Medical (Clinic Bed), Mechanical (Vehicle Lift), Construction (build/repair blocks), Crafting (Workbench + Forge), Combat (raids/expeditions), Farming (Growing Trough, post-MVP — progression tracked but no Labor to consume it yet).

## `data/recipes/<station>.tres` (Resource: `recipe_list.gd`) — *(planned)*

> **Status: planned — `data/recipes/` is empty; `recipe_list.gd`/`recipe.gd` do not exist yet** (Crafting subsystem). Intended schema below.

One RecipeList per station: `workbench.tres` (furniture, armor, weapons, ammo), `forge.tres` (smelting). Each list is an array of `Recipe` resources. See GDD §7.9 + §17 Equipment for the MVP recipe values.

| Field | Type | Description |
|---|---|---|
| `station_id` | `String` | `"workbench"` or `"forge"`. |
| `recipes` | `Array[Recipe]` | All recipes craftable at this station. See below. |

**Recipe** (`recipe.gd extends Resource`) — one craftable output:

| Field | Type | Description |
|---|---|---|
| `recipe_id` | `String` | Unique; e.g. `"clinic_bed"`, `"leather_armor_body"`, `"knife"`, `"bullet"`, `"smelt_metal"`. |
| `output_item` | `String` | Item ID produced (e.g. `"clinic_bed"`, `"leather_armor_body"`). |
| `output_count` | `int` | How many of `output_item` per craft (usually 1; ammo may batch). |
| `inputs` | `Dictionary` | `{item_id: count}` consumed (e.g. `{scrap: 100}` for Clinic Bed; `{metal: 2}` for Knife). |
| `station_id` | `String` | Which station crafts this (must match the list's `station_id`). |
| `skill_id` | `String` | Governing skill: `"crafting"` for Workbench recipes, `"smelting"` (mapped via Crafting Labor) for Forge recipes. |
| `base_time` | `float` | Base craft time in seconds (modified by skill × Stamina multipliers at runtime). |

**MVP recipe sources** (values already in GDD, modeled here as Recipes):
- **Furniture** (GDD §7.2 Buildables `Materials` column): Clinic Bed `{scrap: 100}`, Workbench `{scrap: 60, components: 10}`, Forge `{scrap: 80, components: 20}`, Colonist Bed `{scrap: 40, components: 5}`, Command Desk `{scrap: 120, components: 30}`, Vehicle Lift `{scrap: 120, components: 40}`.
- **Armor** (GDD §17 Equipment, per-slot per-tier): e.g. Leather Body `{leather: 6}`, Cloth Body `{cloth: 4}`, Scrap Body `{scrap: 6}`.
- **Weapons + ammo** (GDD §17 Equipment): Knife `{metal: 2}`, Pistol `{metal: 5, components: 5}`, Bullet `{scrap: 1}`. (Club/Bow/arrows are post-MVP.)
- **Smelting** (GDD §7.3 items): Ore→Metal, Scrap→Components, Metal+Components→Reinforced.

## `data/loadouts/<template>.tres` (Resource: `loadout_template.gd`) — *(planned)*

> **Status: planned — `data/loadouts/` is empty; `loadout_template.gd` does not exist yet** (Equipment subsystem). Intended schema below.

Player-created loadout templates, saved per run. Each template is an abstract slot→item_def_id mapping (resolved to concrete items from storage at equip time). Created/edited via the Colony screen Loadouts tab. See GDD §17 Equipment + §12.

| Field | Type | Description |
|---|---|---|
| `template_id` | `String` | Unique per run. |
| `display_name` | `String` | Player-assigned name. |
| `slots` | `Dictionary[String, String]` | slot_id → item_def_id. Keys: `"armor_head"`, `"armor_body"`, `"armor_arms"`, `"armor_legs"`, `"armor_feet"`, `"armor_hands"`, `"melee"`, `"ranged"`. Values are item_def_ids (e.g. `"leather_armor_body"`, `"knife"`). Missing/empty slots = unequipped. |

**Slot validity** (which item_def_ids can go in which slot):
- `armor_*` slots: armor defs matching the slot (e.g. `armor_body` accepts `cloth_armor_body`, `leather_armor_body`, `scrap_armor_body`).
- `melee`: weapon defs with `class == "melee"` (Knife in MVP; Club post-MVP).
- `ranged`: weapon defs with `class == "ranged"` (Pistol in MVP; Bow post-MVP).

**Equip resolution at runtime:** when auto-equip fires, LoadoutManager resolves each slot's `item_def_id` to the nearest unclaimed concrete item of that type in colony storage. If none available, the slot stays empty (partial equip; logged).

**MVP note:** templates are per-colonist (one template assigned per colonist). "Colonist Groups" (assign a template to a group of colonists) is pinned post-MVP per GDD §12.
