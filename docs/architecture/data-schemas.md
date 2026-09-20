# Reference: Data Schemas

Authoritative reference for all `.tres` Resource schemas in `data/`.

---

## `data/jobs/<id>.tres` (Resource: `job_def.gd`) — `JobDef`

Reusable declarative template for one kind of colonist work (`data/jobs/*.tres`). Configures required tools, animations, work cycle parameters, priority score, and optional custom LimboAI behavior subtrees.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Identifies this template (e.g. `"construction"`, `"hauling"`). |
| `display_name` | `String` | Human-readable label shown in UI and logs. |
| `labor_id` | `String` | A `LaborDef.id`; gates `JobBoard.get_best_job_for` filtering. |
| `required_equipped` | `String` | Specific item ID required equipped for this job (e.g. `"laser_drill"`). |
| `required_equipped_tags` | `Array[StringName]` | Equipment tags required for this job (e.g. `[&"mining_tool"]`, `[&"construction_tool"]`). |
| `work_animation` | `StringName` | Animation played during work execution cycles (default `&"Interact"`; must match a case-sensitive key in `assets/mixamo/mixamo.res`). |
| `work_duration` | `float` | Duration in seconds per work cycle/swing (default `1.2`). |
| `default_units_per_cycle` | `int` | Work units completed per cycle/swing (default `20`). |
| `base_priority` | `float` | Base priority score evaluated by Utility AI (`ColonistBrain`) (default `0.5`). |
| `max_assignees` | `int` | Maximum simultaneous worker claims allowed (default `1`). |
| `conditions` | `Array[Condition]` | Actor requirements (skill/item gates), evaluated hot by `get_best_job_for`. |
| `requires_adjacent` | `bool` | `[export default true]` Whether the colonist must navigate to a cell adjacent to the target (mining/building) rather than stand directly on it (deploy/stationing). |
| `custom_subtree` | `BehaviorTree` | Optional LimboAI behavior tree override resource. |

---

## `data/needs/<id>.tres` (Resource: `data/schemas/need_def.gd`) — `NeedDef`

Data-driven definition for colonist needs (`hunger`, `rest`, `recreation`). The `.tres` instances live under `data/needs/`; the schema script itself lives in `data/schemas/` alongside other cross-cutting Resource definitions. Loaded from `data/needs/` by `ColonistNeeds`.

| Field | Type | Description |
|---|---|---|
| `id` | `StringName` | Unique need identifier (e.g. `&"hunger"`, `&"rest"`, `&"recreation"`). |
| `decay_per_game_hour` | `float` | Need decay rate per second (from `1.0` satisfied toward `0.0` depleted). |
| `response_curve` | `Curve` | Optional Curve mapping deficit (`0.0`..`1.0`) to Utility AI urgency score (`0.0`..`1.0`). |
| `emergency_threshold` | `float` | Critical threshold (`0.10`) forcing immediate need satisfaction. |
| `release_threshold` | `float` | Raw need value (`0.5` default) a hard-locked need must recover to before `ColonistBrain` will arbitrate away from it. See [AI Brain & Decision Making](ai-brain.md). |
| `goal_name` | `StringName` | High-level goal written to Blackboard on winning arbitration (e.g. `&"eat"`, `&"rest"`). |
| `target_group` | `StringName` | Node group name for spatial proximity lookups of smart objects (e.g. `&"storage_crate"`, `&"bed"`). |

---

## `data/colonists/<id>.tres` (Resource: `colonist_def.gd`) — `ColonistDef`

The implemented actor definition (e.g. `default_colonist.tres`). `ColonistDef extends Resource`.

| Field | Type | Description |
|---|---|---|
| `display_name` | `String` | `[export default "Colonist"]` UI label. The colonist's fixed name when `name_pool` is null or has no usable names. |
| `name_pool` | `NamePool` | `[export, nullable]` When set, `Colony.spawn_colonist` rolls a roster-unique random name from it (see `NamePool` below). Leave null for a fixed (named) colonist. |
| `max_hp` | `int` | `[export default 100]` |
| `default_raid_stance` | `int` | `[export default 0]` Stored as int (`RaidStance` enum deferred). |
| `base_move_speed` | `float` | `[export default 3.5]` |
| `sprint_multiplier` | `float` | `[export default 1.5]` |
| `stamina_drain_rate` | `float` | `[export default 1.0]` |
| `breath_costs` | `Dictionary` | `[export]` Per-action Breath costs keyed by name (default `{"sprint": 1.0, "jump": 1.0}`). |
| `starting_skills` | `Dictionary` | `[export]` Starting skill xp/level per labor (default mining + farming at L1). |
| `default_labor_priorities` | `Dictionary` | `[export]` Default labor-priority weights per labor (ships `construction`/`crafting`/`hauling`/`harvesting` at 1). |
| `moodlet_defs` | `Array[MoodletDef]` | `[export]` The moodlet catalog this colonist's `ColonistMoodletVisualizer` evaluates (see Moodlets below). |

---

## `data/naming/<id>.tres` (Resource: `name_pool.gd`) — `NamePool`

Authored pool of names for randomly naming generic (unnamed) colonists, referenced by `ColonistDef.name_pool`. `NamePool extends Resource`; filename matches `id` (e.g. `names.tres`).

| Field | Type | Description |
|---|---|---|
| `id` | `String` | `[export]` Identity; matches the filename. |
| `male_first_names` | `PackedStringArray` | `[export]` First names in the male list. |
| `female_first_names` | `PackedStringArray` | `[export]` First names in the female list. A name may appear in both lists. |
| `last_names` | `PackedStringArray` | `[export]` Surnames. |

`ColonistNamer` flips a fair coin between the non-empty first-name lists (so the mix does not depend on list length), then picks uniformly. Colonists store no gender; the split only shapes which names appear. Any list may be empty (a pool with only `last_names` gives single-name colonists). Blank or whitespace-only entries are ignored, and a list that is entirely blank counts as empty. A pool with every list empty behaves as "no pool".

**`names.tres` provenance.** Generated once from two US federal datasets (public domain): the SSA national baby-names file for first names (names with at least 500 births per sex, male and female kept separate; 587 male, 586 female, 33 in both) and the Census top-1,000 surnames (all caps in the source, title-cased). The 40 surnames whose plain title-case would be wrong (`McX`, `O'X` written without the apostrophe, `DeX`, `MacDonald`, `LeBlanc`) were dropped, leaving 960. The year of the SSA file is not recorded in it. The generator script is not in the repo; names are ranked by frequency in the file but picked uniformly.

---

## `data/enemies/<id>.tres` (Resource: `enemy_def.gd`) — `EnemyDef`

Data-driven definition for one hostile enemy archetype (GDD §5: Swarmer prototype, Brawler, Shooter). `EnemyDef extends Resource`, indexed by `id` in the `EnemyLibrary` autoload (`subsystems/combat/enemy_library.gd`) the same way `ItemDB` indexes `ItemDef`. Backs `EnemyBase.enemy_def` (`subsystems/combat/enemy_base.gd`), applied at `_ready()`: `HealthComponent.setup(max_hp, max_durability)`, movement speed, the `BTPlayer`'s loaded tree, and `moodlet_defs`.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Identity string `EnemyLibrary` indexes by — never the filename. |
| `display_name` | `String` | `[export default "Enemy"]` UI label. |
| `max_hp` | `int` | `[export default 100]` |
| `max_durability` | `int` | `[export default 0]` Durability-before-HP per GDD §6.11 (shared damage resolution with Player/Colonist). |
| `base_move_speed` | `float` | `[export default 5.0]` |
| `detect_range` | `float` | `[export default 16.0]` Not yet consumed by any AI task — both the melee and ranged-kiter trees' scan nodes still author their own `radius` directly. |
| `los_loss_timeout` | `float` | `[export default 5.0]` Seconds without line of sight before a chasing enemy should give up (GDD Brawler table). Not consumed by any AI task yet — no LOS-tracking state exists. |
| `behavior_tree` | `BehaviorTree` | The LimboAI tree this archetype runs. `EnemyBase._setup_ai_components()` creates the `BTPlayer` and loads this tree only when the scene doesn't already pre-place its own `BTPlayer` node — none of the shipped enemy scenes do, so this is the live source of truth for all three. |
| `attack_params` | `CombatActionParams` | Polymorphic — assign a `MeleeActionParams` or `RangedActionParams` instance (`data/capability_params/`). Null means this archetype never attacks. Resolved via the `ICombatSource` duck-typed contract (`subsystems/core/i_combat_source.gd`, implemented by `EnemyBase.get_combat_action()`/`get_attack_range()`), consumed by `BTActionMeleeAttack.use_agent_attack_params`, `BTActionRangedAttack`, and `BTActionNavigateTo.arrival_distance_from_agent_attack_range`. |
| `loot_table` | `LootTable` | `[export default null]` Rolled by `EnemyBase` when the enemy dies (see [Loot](loot.md)). Null means the archetype drops nothing. |
| `moodlet_defs` | `Array[MoodletDef]` | `[export]` Same shape as `ColonistDef.moodlet_defs`, evaluated by `EnemyMoodletVisualizer`. |

---

## `data/loot/<id>.tres` (Resource: `loot_table.gd`) — `LootTable`

Data-driven drop table, rolled by `LootRoller` (`subsystems/loot/loot_roller.gd`, see [Loot](loot.md)). `LootTable extends Resource`. Today only `EnemyDef.loot_table` references one; there is no id-indexed library yet, so tables are wired by direct `ext_resource` reference.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | `[export default ""]` Identity string per the data conventions. Nothing indexes by it yet. |
| `guaranteed` | `Array[ItemAmount]` | `[export]` Always dropped, with the exact `ItemAmount.count`. Entries with a null `item_def` or `count <= 0` are skipped. |
| `entries` | `Array[LootEntry]` | `[export]` Each entry rolls independently after `guaranteed`. Every entry that passes drops; there is no cap and no pick-one behavior. |

All sources are merged into one stack per item id, so an item that appears in `guaranteed` and in several entries drops as a single summed stack.

---

## `data/loot/<id>.tres` sub-resource (Resource: `loot_entry.gd`) — `LootEntry`

One independently rolled drop inside a `LootTable`. `LootEntry extends Resource`. It first rolls `chance`, then on success drops a uniform count in `[min_count, max_count]` (inclusive). Author "50% for 3 to 7 pieces" as one entry. A second low-chance entry for the same item stacks on top of it as a bonus drop.

| Field | Type | Description |
|---|---|---|
| `item_def` | `ItemDef` | The item to drop. An entry with a null item is skipped. |
| `chance` | `float` | `[export_range 0.0..1.0, default 1.0]` Probability the entry drops. `1.0` always drops and `0.0` never does. |
| `min_count` | `int` | `[export default 1]` Lower bound of the count roll. Values below 1 are raised to 1. |
| `max_count` | `int` | `[export default 1]` Upper bound of the count roll. A value below `min_count` is raised to `min_count`. |

---

## `data/labors/<id>.tres` (Resource: `labor_def.gd`) — `LaborDef`

The canonical declaration of which labor ids exist. `LaborDef extends Resource`.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | The labor id (e.g. `"construction"`) — the key everything else references. |
| `display_name` | `String` | UI label (e.g. `"Construction"`). |
| `description` | `String` | Short blurb, unused in MVP UI. |

---

## `data/moodlets/<id>.tres` (Resource: `moodlet_def.gd`, `stat_threshold_moodlet_def.gd`, `activity_moodlet_def.gd`) — Moodlets

Data-driven definition for colonist status and activity moodlet icons displayed in 3D billboard space (`ColonistMoodletVisualizer`).

### Base Schema: `MoodletDef`

| Field | Type | Description |
|---|---|---|
| `id` | `StringName` | Unique identifier (e.g. `&"hunger"`, `&"activity"`). |
| `display_name` | `String` | UI tooltip label. |
| `icons` | `Array[Texture2D]` | Array of texture assets for active tiers or states. |
| `icon_hframes` | `Array[int]` | Optional 1-to-1 array mapping each icon tier to its horizontal spritesheet frame count (defaults to `1`). |
| `frame_fps` | `float` | Default animation playback speed in FPS for animated spritesheets (default `6.0`). |
| `icon_fps` | `Array[float]` | Optional 1-to-1 array mapping each icon tier to a custom FPS override. |

### Subclass: `StatThresholdMoodletDef`
Extends `MoodletDef`. Evaluates stat ratios (`colonist.get_stat_ratio(stat_id)`) against ordered cutoff thresholds (`thresholds`).

### Subclass: `ActivityMoodletDef`
Extends `MoodletDef`. Maps `colonist.get_current_activity()` StringNames (`&"idle"`, `&"mining"`, `&"construction"`, `&"crafting"`, `&"hauling"`, `&"eat"`, `&"rest"`) to `icons` array indices via `activity_icon_map`.

### Subclass: `PlantOrderMoodletDef`
Extends `MoodletDef`. Evaluates `Harvestable` mark status and maps plant designation orders (`&"chop"`, `&"forage"`, `&"remove"`, `&"harvest"`) to `icons` array indices via `order_icon_map`.

---

## `data/maps/<id>/map_def.tres` (Resource: `map_def.gd`) — `MapDef`

Loadable map and environment metadata definition scanned by `MapLibrary`. Links the authored `map.tscn` with runtime configuration, terrain settings, and dynamic flora parameters.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique map identifier (must match the containing folder name under `data/maps/<id>/`). |
| `display_name` | `String` | Human-readable map title shown in menus and world map. |
| `description` | `String` | Description shown in expedition selection and map logs. |
| `scene_path` | `String` | Path to the map scene file (`res://data/maps/<id>/map.tscn`). |
| `map_type` | `MapType` | Map category: `BASE` (0), `POI` (1), `BUILDING` (2), or `TOWN` (3). |
| `player_spawn` | `Vector3` | Fallback player entry spawn coordinate if no `PlayerSpawn` marker is present in the scene. |
| `enemy_spawns` | `Array[Dictionary]` | Fallback hostile entity spawn definitions (`[{"pos": Vector3, "count": int}]`). |
| `unlock_condition` | `String` | Unlock prerequisite identifier. |
| `difficulty` | `int` | Difficulty tier (1 to 10). |
| `world_bounds` | `AABB` | Discrete playable colony bounding box defining generation and pathfinding limits. |
| `terrain_gen` | `TerrainGenDef` | Natural smooth terrain parameters (`null` for blocky-only maps). |
| `water_enabled` | `bool` | Authoring flag indicating whether water flooding was enabled in the editor. |
| `water_level` | `float` | Baseline water level elevation in meters. |
| `flora_palette` | `Array[BuildableDef]` | Flora/tree definitions available for dynamic growth and regeneration on this map. |
| `flora_spawns_per_day` | `int` | Number of flora spawn attempts distributed across one in-game day (0 = disabled). |
| `flora_spawn_cap` | `int` | Maximum simultaneous live flora entities permitted on the map. |
| `flora_max_spawn_attempts` | `int` | Maximum random placement attempts per flora before skipping to avoid infinite loops. |
| `flora_min_distance` | `float` | Minimum distance in meters between spawned flora and existing trees or player spawn. |

---

## `data/furniture/<id>.tres` / `data/blocks/<id>.tres` (Resource: `buildable_def.gd`, `furniture_def.gd`, `wild_flora_def.gd`) — `BuildableDef`, `FurnitureDef`, & `WildFloraDef`

Data-driven definition for buildable blocks, free-standing furniture entities, and natural wild flora (trees, berry bushes, shrubs).

### Base Schema: `BuildableDef`

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Canonical identifier across all buildable assets. |
| `display_name` | `String` | UI label displayed in build menus and inspection tooltips. |
| `icon` | `Texture2D` | Optional build menu UI icon texture. |
| `hp` | `int` | Structure durability and damage buffer. |
| `scene` | `PackedScene` | Optional primary 3D scene (e.g. `.glb` model with sockets/colliders). |
| `mesh` | `Mesh` | Preview and placement fallback mesh. |
| `texture` | `Texture2D` | Albedo texture used to construct standard materials. |
| `texture_variation` | `bool` | Enables per-block UV and brightness randomization shader for blocky voxels. |
| `material_cost` | `Array[ItemAmount]` | Construction item requirements. |
| `unlocked_by_default` | `bool` | Whether the item is available at the start of a run. |
| `build_time` | `float` | Construction time requirement. |
| `tags` | `Array[String]` | Classification tags (e.g. `["live_flora"]`, `["bed"]`, `["storage"]`) for system queries. |

### Subclass: `FurnitureDef`
Extends `BuildableDef`. Adds `dimensions` (`Vector3i`, default `1x1x1`) representing the bounding cell-box occupied on the voxel grid, with rotation swapping X and Z extents.

### Subclass: `WildFloraDef` (Resource: `wild_flora_def.gd`)
Extends `BuildableDef`. Represents natural, dynamic wild vegetation (trees, bushes, herbs) with stage-based visual progression, weapon damage felling, and optional fruit foraging.

| Field | Type | Description |
|---|---|---|
| `dimensions` | `Vector3i` | Cell footprint on the voxel grid (default `1x1x1`). |
| `default_scene` | `PackedScene` | Default visual 3D scene fallback if stage scene is not specified. |
| `blocks_movement` | `bool` | When `true`, enables Layer 1 physics collider to block movement. When `false`, entities can walk through (e.g. berry bushes, shrubs). |
| `growth_time_hours` | `float` | In-game hours required to grow through all stages to 100% maturity (0 = static / fully grown). |
| `destroy_on_fruit_harvest` | `bool` | If `true`, harvesting fruit removes the plant entirely. |
| `regrowth_stage_index` | `int` | Stage index to revert to after harvesting fruit (`-1` = stay at current stage, `0` = revert to seedling, `1` = revert to mature plant without fruit). |
| `impact_audio_event` | `String` | Optional audio bus / sound event on physical weapon hit. |
| `hit_particles_color` | `Color` | Color of particle splatter on weapon impact. |
| `stages` | `Array[WildFloraStage]` | Ordered growth milestones and per-stage properties. |

### Sub-Resource: `WildFloraStage` (Resource: `wild_flora_stage.gd`)
Defines the state of a plant at a specific growth threshold.

| Field | Type | Description |
|---|---|---|
| `min_progress` | `float` | Normalized growth milestone (0.0 to 1.0) when this stage activates. |
| `max_hp` | `int` | Maximum health at this stage (scaled into `HealthComponent`). |
| `scene` | `PackedScene` | 3D visual scene instantiated when this stage is active. |
| `visual_scale` | `Vector3` | Scale factor applied to the visual stage instance. |
| `fell_yields` | `Array[ItemAmount]` | Items dropped when plant is chopped down / killed with weapons. |
| `can_harvest_fruit` | `bool` | Whether player can interact (E) to forage / pick fruit at this stage. |
| `harvest_yields` | `Array[ItemAmount]` | Items dropped or picked when fruit is harvested. |

---

## FurnitureDef capability parameters

Nullable sub-resources attached to `FurnitureDef` following the composition pattern. All capability resources inherit from `FurnitureCapability` (`data/capability_params/furniture_capability.gd`).

### Base Resource: `FurnitureCapability` (`furniture_capability.gd`)
Base class for all pluggable furniture capabilities. Pure data definitions; runtime component instantiation logic is isolated in `FurnitureLayer`'s static capability registry. Exposes virtual `collect_action_options() -> Array[ActionOption]` allowing capabilities to dynamically inject context options into the furniture's `InteractionComponent`.

Capability querying is unified via `Furniture.get_capability(furniture, CapabilityType) -> FurnitureCapability`.
Capability components carrying state implement the duck-typed contract `ICapabilityComponent` (`serialize_state() -> Dictionary`, `deserialize_state(data: Dictionary) -> void`), discovered automatically by `Furniture.serialize` and `Furniture.deserialize`.

### `BedParams` (Resource: `bed_params.gd`)
Configures colonist rest capability (GDD §6.8). When non-null, `FurnitureLayer` attaches a `BedComponent` node that manages colonist reservations and occupancy.

| Field | Type | Description |
|---|---|---|
| `sleep_offset` | `Vector3` | Local position offset relative to furniture origin where colonist sleeps (default `Vector3.ZERO`). |
| `rest_per_game_hour` | `float` | Rate at which the rest need is restored per second on a 0.0 to 1.0 scale (default `0.15`). |

### `RecreationParams` (Resource: `recreation_params.gd`)
Configures colonist recreation capability (see [Recreation](recreation.md)). When non-null, `FurnitureLayer` attaches a `RecreationComponent` node that rations simultaneous users and resolves stand positions. The owning `FurnitureDef` must also declare `tags = ["recreation_object"]` so it joins the group `need_recreation.tres` targets.

| Field | Type | Description |
|---|---|---|
| `recreation_per_game_hour` | `float` | Rate at which the recreation need is restored per second while in use, on a 0.0 to 1.0 scale (default `0.08`). |
| `min_session_game_hours` | `float` | Minimum seconds a colonist commits to once a session starts, even if the need fills earlier (default `4.0`). |
| `max_session_game_hours` | `float` | Ceiling on one session; the colonist leaves and re-arbitrates even if the need is unfilled (default `20.0`). |
| `capacity` | `int` | Simultaneous users. `1` is exclusive, `N` allows N at once, `-1` is unlimited (default `1`). |
| `use_radius` | `float` | Maximum distance in meters at which a colonist still accrues. `1.5` requires adjacency (default `1.5`). |
| `use_offsets` | `Array[Vector3]` | Optional standing spots local to the furniture origin, rotated by the furniture transform at runtime. When non-empty they are the exact positions colonists are sent to and they cap the effective capacity (default empty). |
| `use_animation` | `StringName` | Animation override played for the session duration (default `&"Interact"`). |

### `LightParams` (Resource: `light_params.gd`)
Configures light emission properties for furniture (torches, lamps, campfires). When non-null, `FurnitureLayer` attaches a `LightSourceComponent` node holding an `OmniLight3D`.

| Field | Type | Description |
|---|---|---|
| `color` | `Color` | Emission light color (default warm light `Color(1.0, 0.9, 0.7, 1.0)`). |
| `energy` | `float` | Light intensity energy value (default `1.5`). |
| `range` | `float` | Maximum illumination radius in meters (default `8.0`). |
| `attenuation` | `float` | Light attenuation falloff curve factor (default `1.0`). |
| `shadows_enabled` | `bool` | Whether light casts dynamic shadows (default `false`). |
| `local_offset` | `Vector3` | Position offset relative to furniture root origin (default `Vector3(0.0, 1.5, 0.0)`). |

### `FarmPlotParams` (Resource: `farm_plot_params.gd`)
Configures domestic crop cultivation on furniture (e.g. growing troughs). When non-null, `FurnitureLayer` attaches `Growable` and `Harvestable` components, and contributes farming `ActionOption`s (`inspect_crop`, `select_crop`, `toggle_harvest`).

| Field | Type | Description |
|---|---|---|
| `allowed_crops` | `Array[String]` | Allowed `CropDef` IDs for this plot. Empty means any crop is accepted. |
| `crop_slots` | `int` | Number of crop slots on the plot (default `1`). |
| `growth_rate_multiplier` | `float` | Multiplier applied on top of crop growth speed (default `1.0`). |
| `hydration_mode` | `String` | Hydration source mode: `"manual"` (default) or `"irrigated"`. |

### `StorageParams` (Resource: `storage_params.gd`)
Configures storage container properties. When non-null, `FurnitureLayer` attaches a `StorageInventory` node.

| Field | Type | Description |
|---|---|---|
| `capacity` | `float` | Weight capacity in kg (default `100.0`). |
| `allowed_item_ids` | `Array[String]` | Item ID whitelist for accepted items. Copied to the `StorageInventory`, where the Storage Options panel edits it per crate. |
| `allowed_tags` | `Array[String]` | Item tag whitelist for accepted items. An item matching either list is accepted. Copied to the `StorageInventory` and shown read-only in the Storage Options panel (there is no in-game editor for it). |
| `priority` | `int` | Hauling priority from 1 to 5 (default `3`). Editable per crate in the Storage Options panel. |

### `CraftingParams` (Resource: `crafting_params.gd`)
Configures crafting station recipes. When non-null, `FurnitureLayer` attaches a `CraftingStation` node.

| Field | Type | Description |
|---|---|---|
| `recipes` | `Array[RecipeDef]` | Ordered list of recipes craftable at this station. |

### `TurretParams` (Resource: `turret_params.gd`)
Configures automated turret defenses. When non-null, `FurnitureLayer` attaches a `TurretComponent` node.

| Field | Type | Description |
|---|---|---|
| `range` | `float` | Maximum targeting range in meters (default `15.0`). |
| `fire_rate` | `float` | Fire rate in shots per second (default `1.0`). |
| `damage` | `int` | Direct damage per hit (default `10`). |
| `ammo_type` | `ItemDef` | Required ammunition item, or null for infinite/free firing. |
| `muzzle_offset` | `Vector3` | Local position where projectiles spawn if no "Muzzle" node is found (default `(0, 2.0, 0)`). |
| `turn_speed` | `float` | Turret rotation speed tracking its target, in radians/second (default `5.0`). |
| `min_pitch_deg` / `max_pitch_deg` | `float` | Vertical aim clamp in degrees (defaults `-15.0` / `60.0`). |
| `projectile_scene` | `PackedScene` | Optional projectile visual scene; falls back to `projectile_mesh`/`projectile_material` when unset. |
| `projectile_mesh` / `projectile_material` | `Mesh` / `Material` | Fallback projectile visuals when `projectile_scene` is unset. |
| `projectile_speed` | `float` | Projectile travel speed in meters/second (default `25.0`). |
| `projectile_type` | `ProjectileType` | `REGULAR` or explosive-on-impact variant; gates `explosion_radius` handling. |
| `explosion_radius` | `float` | Area-damage radius on impact for explosive projectile types (default `3.0`). |
| `enable_muzzle_flash` / `enable_projectile_trail` / `enable_explosion_particles` | `bool` | Toggle each particle effect independently (all default `true`). |
| `explosion_particle_scene` | `PackedScene` | Optional custom explosion particle scene override. |

### `HarvestParams` (Resource: `harvest_params.gd`)
Configures direct resource harvesting. When non-null, `FurnitureLayer` attaches a `Harvestable` node and contributes `toggle_harvest` `ActionOption`. Must not be used on farm plots (which resolve yields dynamically via `CropDef`).

| Field | Type | Description |
|---|---|---|
| `yields` | `Array[ItemAmount]` | Items granted upon completing harvest. |
| `work_time` | `float` | Work seconds demanded to harvest. |
| `respawn_time` | `float` | Respawn delay in seconds (0.0 = destroyed on harvest). |
| `required_tool_tag` | `String` | Required tool tag to harvest (e.g. "axe", "pickaxe"). |

---

## `data/items/<id>.tres` (Resource: `data/items/item_def.gd`) — `ItemDef` & `ItemAmount`

Global inventory and world item definition. `ItemDef extends Resource`. Loaded and indexed by `ItemDB`. `ItemDef` follows the capability composition pattern, attaching optional sub-resources for equippable, food, and wearable behaviors.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Canonical item identifier (e.g. `"laser_drill"`, `"wood"`). |
| `weight` | `float` | Item weight in kg (default `0.0`). `0.0` means weightless: the item takes no carry or storage capacity (`Inventory.max_addable` returns `UNLIMITED_COUNT`), so set a real weight unless that is intended. |
| `icon` | `Texture2D` | Inventory and UI icon texture. |
| `scene` | `PackedScene` | 3D scene (.glb) rendered when dropped in the world as a `WorldItem`. Takes precedence over `mesh`. |
| `mesh` | `Mesh` | 3D fallback visual mesh for `WorldItem`. |
| `material` | `Material` | Material override applied to the `WorldItem` mesh. |
| `visual_scale` | `Vector3` | Scale factor applied to visual mesh/scene and collision box (default `(1, 1, 1)`). |
| `tags` | `Array[String]` | Classification tags (e.g. `["tool", "mining_tool"]`). |
| `equippable` | `EquippableParams` | Nullable equippable capability (actions, animations). |
| `food` | `FoodParams` | Nullable food capability (nutrition, health, eat duration). |
| `wearable` | `WearableParams` | Nullable wearable capability (garment mesh or rigid bone sockets). |

There is no separate display-name field: the player-facing name is the authored `resource_name`, falling back to `id`, exposed as `ItemDef.get_display_name()` (and `ItemDB.get_display_name(item_id)` for ids whose def may no longer exist). Author `resource_name` on every item.

### Sub-Resource: `ItemAmount` (Resource: `data/items/item_amount.gd`)
Couples an item reference with a quantity. Used in recipe inputs/outputs, loot tables, and building costs.

| Field | Type | Description |
|---|---|---|
| `item_def` | `ItemDef` | Referenced item definition. |
| `count` | `int` | Quantity (default `1`). |

---

## `data/crops/<id>.tres` (Resource: `data/crops/crop_def.gd`) — `CropDef` & `CropYieldTier`

Global definition for farmable crops (GDD §6 / Farming). `CropDef extends Resource`.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique crop identifier (e.g. `"synth_wheat"`). |
| `display_name` | `String` | UI display label. |
| `growth_time_hours` | `float` | In-game hours required to reach maturity (default `12.0`). |
| `growth_stages` | `int` | Number of visual growth stages (default `3`). |
| `stage_scenes` | `Array[PackedScene]` | Optional 3D scenes for each growth stage. |
| `max_water` | `float` | Maximum water capacity percentage (default `100.0`). |
| `water_decay_per_hour` | `float` | Water decay rate in percent per in-game hour (default `4.0`). |
| `thirsty_threshold` | `float` | Water percent threshold below which a Water job is posted (default `30.0`). |
| `tending_mode` | `TendingMode` | Tending mode: `NONE` (0), `MILESTONE` (1), `DECAY` (2). |
| `tending_milestones` | `Array[float]` | Progress milestones (0.0 to 1.0) requiring tending. |
| `tending_decay_hours` | `float` | In-game hours a tended state lasts before needing tending again. |
| `untended_growth_mult` | `float` | Growth multiplier while needing tending (default `0.0` = halted). |
| `neglect_hours` | `float` | In-game hours crop can remain untended before yield penalties accumulate. |
| `neglect_yield_penalty` | `float` | Fraction of yield lost per `neglect_hours` exceeded. |
| `plant_conditions` | `Array[Condition]` | Conditions required to sow/plant this crop. |
| `tend_conditions` | `Array[Condition]` | Conditions required to tend this crop. |
| `seed_item_id` | `String` | Optional seed item ID consumed to plant. |
| `yield_tiers` | `Array[CropYieldTier]` | Yield definitions by reached growth progress. |
| `base_harvest_time` | `float` | Base work seconds to harvest (default `3.0`). |
| `wither_hours` | `float` | In-game hours a mature crop can sit unharvested before withering (0.0 = never). |

### Sub-Resource: `CropYieldTier` (Resource: `data/crops/crop_yield_tier.gd`)
Specifies yields granted when harvesting at or above a progress threshold.

| Field | Type | Description |
|---|---|---|
| `min_growth_progress` | `float` | Minimum growth progress required (default `1.0`). |
| `yields` | `Array[ItemAmount]` | Items harvested at this tier. |

---

## `data/crafting/<id>.tres` (Resource: `data/crafting/recipe_def.gd`) — `RecipeDef`

Declarative conversion recipe for crafting stations. `RecipeDef extends Resource`.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique recipe identifier. |
| `display_name` | `String` | Human-readable label in craft panels and logs. |
| `inputs` | `Array[ItemAmount]` | Materials consumed per craft. |
| `outputs` | `Array[ItemAmount]` | Items produced per craft. |
| `base_time` | `float` | Base work duration in seconds, scaled by crafter's skill (default `1.0`). |
| `conditions` | `Array[Condition]` | Hot-evaluated actor gates (e.g. `MinSkillCondition`). |

---

## `data/skills/skills.tres` (Resource: `data/skills/skill_def.gd`) — `SkillDef`

Definition for colonist skill disciplines (GDD §6.3). Authored as sub-resources in `data/skills/skills.tres`.

| Field | Type | Description |
|---|---|---|
| `skill_id` | `String` | Skill identifier key (e.g. `"construction"`, `"farming"`). |
| `display_name` | `String` | UI display label. |
| `labor` | `String` | Associated `LaborDef.id` governed by this skill. |
| `multipliers` | `Array[float]` | Work-speed multipliers per level (L1 to L5, default `[1.0, 1.2, 1.4, 1.7, 2.0]`). |
| `use_curve` | `Array[int]` | Cumulative successful uses required to reach L2 through L5 (default `[20, 50, 100, 200]`). |

---

## `data/terrain/<id>.tres` (Resource: `data/terrain/terrain_gen_def.gd`) — `TerrainGenDef`

Parameters for smooth natural terrain generation in the dual-voxel system. `TerrainGenDef extends Resource`.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique generator identifier. |
| `display_name` | `String` | UI display label. |
| `noise_seed` | `int` | FastNoiseLite seed for reproducible procedural generation (default `0`). |
| `noise_frequency` | `float` | Frequency shaping terrain slope and features (default `0.012`). |
| `heightmap` | `Texture2D` | Optional grayscale heightmap image overriding procedural noise. |
| `height_start` | `float` | Base elevation floor in meters (default `-4.0`). |
| `height_range` | `float` | Vertical elevation span in meters (default `12.0`). |
| `max_walk_slope_deg` | `float` | Maximum walkable slope gate in degrees for pathfinding (default `45.0`). |
| `water_enabled` | `bool` | Whether baseline water plane is enabled (default `false`). |
| `water_level` | `float` | Baseline water elevation in meters (default `-2.0`). |

---

## ItemDef capability parameters

Nullable sub-resources attached to `ItemDef` (`data/capability_params/`) following the composition pattern.

### `EquippableParams` (Resource: `equippable_params.gd`)
Configures animation and combat actions for equippable items. Slot routing is tag-based via `ItemDef.tags` (accepted tags in `Equipment.SLOT_ACCEPTED_TAGS`).

| Field | Type | Description |
|---|---|---|
| `stance_animation` | `StringName` | Idle stance animation when equipped (default `&"idle"`). |
| `use_animation` | `StringName` | Attack/use animation triggered by primary action (default `&"use"`). |
| `primary_action` | `EquipActionParams` | Action triggered on primary input / weapon swing. |
| `secondary_action` | `EquipActionParams` | Action triggered on secondary input / block / aim. |

### `FoodParams` (Resource: `food_params.gd`)
Configures physiological nutrition, healing, and consumption properties for edible items attached via `ItemDef.food`.

| Field | Type | Description |
|---|---|---|
| `nutrition_value` | `float` | Satiety restored to `HungerComponent` upon consumption (default `0.4`). |
| `health_restore` | `int` | Immediate hit points healed upon ingestion (default `0`). |
| `eat_duration` | `float` | Time in seconds required for eating cycle (default `2.0`). |
| `eating_animation` | `StringName` | Animation override key played during consumption (default `&"eat"`). |
| `mood_modifier` | `StringName` | Optional moodlet applied to colonist after eating. |
| `spoilage_hours` | `float` | Reserved shelf-life hours for future perishability system. |

### `WearableParams` (Resource: `wearable_params.gd`)
Configures visual representation for wearable equipment (armor, clothing, headwear, footwear) attached via `ItemDef.wearable`. Managed by `EquipmentVisualizer`.

| Field | Type | Description |
|---|---|---|
| `skinned_scene` | `PackedScene` | Deformable garment `.glb` exported on the humanoid armature and retargeted with `SkeletonProfileHumanoid`. Meshes carrying an active `skin` are reparented directly under the character's `Skeleton3D`. |
| `rigid_parts` | `Array[WearablePart]` | Array of rigid mesh parts attached to individual skeleton bones via auto-created `WearBone_<bone>` sockets. |

### Sub-Resource: `WearablePart` (Resource: `wearable_part.gd`)
Defines a single rigid mesh component of a wearable item.

| Field | Type | Description |
|---|---|---|
| `bone` | `StringName` | Target humanoid bone name matching `SkeletonProfileHumanoid` (e.g. `&"Head"`, `&"Chest"`, `&"LeftUpperLeg"`). |
| `mesh` | `Mesh` | 3D visual mesh rendered for this part. |
| `material` | `Material` | Optional material override applied to the part mesh. |
| `offset` | `Transform3D` | Local transform offset relative to the bone attachment origin. |




