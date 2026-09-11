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
| `custom_subtree` | `BehaviorTree` | Optional LimboAI behavior tree override resource. |

---

## `data/needs/<id>.tres` (Resource: `need_def.gd`) — `NeedDef`

Data-driven definition for colonist needs (`hunger`, `rest`, `recreation`). Loaded from `data/needs/` by `ColonistNeeds`.

| Field | Type | Description |
|---|---|---|
| `id` | `StringName` | Unique need identifier (e.g. `&"hunger"`, `&"rest"`, `&"recreation"`). |
| `decay_per_second` | `float` | Need decay rate per second (from `1.0` satisfied toward `0.0` depleted). |
| `response_curve` | `Curve` | Optional Curve mapping deficit (`0.0`..`1.0`) to Utility AI urgency score (`0.0`..`1.0`). |
| `emergency_threshold` | `float` | Critical threshold (`0.10`) forcing immediate need satisfaction. |
| `goal_name` | `StringName` | High-level goal written to Blackboard on winning arbitration (e.g. `&"eat"`, `&"rest"`). |
| `target_group` | `StringName` | Node group name for spatial proximity lookups of smart objects (e.g. `&"storage_crate"`, `&"bed"`). |

---

## `data/colonists/<id>.tres` (Resource: `colonist_def.gd`) — `ColonistDef`

The implemented actor definition (e.g. `default_colonist.tres`). `ColonistDef extends Resource`.

| Field | Type | Description |
|---|---|---|
| `display_name` | `String` | `[export default "Colonist"]` UI label. |
| `max_hp` | `int` | `[export default 100]` |
| `default_raid_stance` | `int` | `[export default 0]` Stored as int (`RaidStance` enum deferred). |
| `base_move_speed` | `float` | `[export default 3.5]` |
| `sprint_multiplier` | `float` | `[export default 1.5]` |
| `stamina_drain_rate` | `float` | `[export default 1.0]` |
| `breath_costs` | `Dictionary` | `[export]` Per-action Breath costs keyed by name (default `{"sprint": 1.0, "jump": 1.0}`). |
| `starting_skills` | `Dictionary` | `[export]` Starting skill xp/level per labor (default mining + farming at L1). |
| `default_labor_priorities` | `Dictionary` | `[export]` Default labor-priority weights per labor (ships `construction`/`crafting`/`hauling`/`harvesting` at 1). |

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
| `flora_palette` | `Array[FurnitureDef]` | Flora/tree definitions available for dynamic growth and regeneration on this map. |
| `flora_spawns_per_day` | `int` | Number of flora spawn attempts distributed across one in-game day (0 = disabled). |
| `flora_spawn_cap` | `int` | Maximum simultaneous live flora entities permitted on the map. |
| `flora_max_spawn_attempts` | `int` | Maximum random placement attempts per flora before skipping to avoid infinite loops. |
| `flora_min_distance` | `float` | Minimum distance in meters between spawned flora and existing trees or player spawn. |

---

## `data/furniture/<id>.tres` / `data/blocks/<id>.tres` (Resource: `buildable_def.gd`, `furniture_def.gd`) — `BuildableDef` & `FurnitureDef`

Data-driven definition for buildable blocks and free-standing furniture entities.

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

---

## FurnitureDef capability parameters

Nullable sub-resources attached to `FurnitureDef` following the composition pattern.

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
| `mood_modifier` | `String` | Optional moodlet applied to colonist after eating. |
| `spoilage_hours` | `float` | Reserved shelf-life hours for future perishability system. |



