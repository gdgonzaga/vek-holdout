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
| `required_tool_tag` | `StringName` | Equipment tag required for this job (e.g. `&"pickaxe"`, `&"axe"`, `&"hammer"`). |
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
