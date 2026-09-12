# Subsystem: Recreation

Colonists carry a `recreation` need alongside hunger and rest. Recreation furniture — a game table, a statue — restores it while a colonist stands and uses the object. The subsystem is a `FurnitureDef` capability (`RecreationParams`), an occupancy component that rations simultaneous users, and one goal-gated branch in the colonist behavior tree. The GDD has no recreation section yet; the decay rate and object archetypes here are the de-facto design (tracked in `docs/TODO.md`).

> **Implementation status: implemented.** `RecreationParams`, `RecreationComponent`, `BTActionUseRecreation`, `BTConditionGoalIs` and the availability-filtered target search all exist. The moodlet definition (`data/moodlets/recreation_moodlet.tres`) exists but ships with an empty `icons` array and is deliberately unregistered on `default_colonist.tres` because the gauge art does not exist yet — see `docs/TODO.md`.

**Design notes:**

- **Rate, not flat restore.** `recreation_per_second` plus a min/max session window is what lets one capability express both a fast exclusive object and a slow shared one. Object quality is purely data — no code branches per furniture type.
- **Capacity is the whole concurrency model.** `capacity = 1` is exclusive, `N` is N at once, `-1` is unlimited. Authored `use_offsets` refine exact standing spots and cap the effective capacity, because there is nowhere sensible to put a user past the last authored spot.
- **`use_radius` decouples benefit from adjacency.** `1.5` means the colonist must stand next to the object. A television would author roughly `6.0` and be watched from across a room. There is no line-of-sight check.
- **Occupancy is transient.** `serialize_state()` returns `{}`. Claims are runtime-only; colonists re-arbitrate from scratch on load rather than restoring a phantom reservation.
- **Two-phase claiming.** [ColonistBrain](ai-brain.md) polls at 1.5s while the behavior tree ticks at 60Hz, so a claim is `reserve`d the moment the brain commits to a target — stopping rivals from scoring it — and only promoted to `begin_use` once the colonist physically arrives.

## Files

| File | Type | Responsibility |
|---|---|---|
| `../data/capability_params/recreation_params.gd` | Data schema | `RecreationParams` capability resource. Pure data; spawns nothing. See [Data Schemas](data-schemas.md). |
| `subsystems/furniture/recreation_component.gd` | Script | `RecreationComponent`. Slot rationing and stand-position resolution. Does NOT own the need value or navigation. |
| `subsystems/furniture/i_occupiable.gd` | Script (doc-only) | `IOccupiable` duck-typed contract. Implementations do not extend it. |
| `subsystems/ai/tasks/actions/bt_action_use_recreation.gd` | Script | `BTActionUseRecreation`. Session lifecycle and per-second need accrual. |
| `subsystems/ai/tasks/conditions/bt_condition_goal_is.gd` | Script | `BTConditionGoalIs`. Generic goal gate for need branches. |
| `../data/needs/need_recreation.tres` | Data | `NeedDef` for the need. `goal_name = &"recreation"`, `target_group = &"recreation_object"`. See [Data Schemas](data-schemas.md). |
| `../data/furniture/game_table.tres` | Data | Sample exclusive object: `capacity = 1`, adjacent, fast. |
| `../data/furniture/stone_statue.tres` | Data | Sample shared object: `capacity = -1`, `use_radius = 4.0`, slow. |
| `../data/moodlets/recreation_moodlet.tres` | Data | `StatThresholdMoodletDef` on `stat_id = &"recreation"`. Art pending. |

## Signals

*(No new signals — recreation uses direct refs and the existing blackboard contract. Occupancy is polled by `ColonistBrain`, never broadcast.)*

## Flow Trace: Colonist takes a break

**Trigger:** `ColonistNeeds` decays `recreation` far enough that its curve-sampled score beats work in `ColonistBrain.evaluate_goals()`.

1. `ColonistBrain` samples the `NeedDef` response curve on the deficit, then calls `_resolve_nearest_group_target(colonist, &"recreation_object")`.
2. That delegates to `AIUtils.find_nearest_in_group_where()` with an availability predicate, so any object whose `RecreationComponent.is_usable_by()` returns false is skipped entirely. With no usable object the score falls to `0.0` and recreation cannot win.
3. The winning goal `&"recreation"` and the furniture node are written to the blackboard. `_sync_reservation()` releases whatever the colonist held before and calls `reserve()` on the winner.
4. `_resolve_stand_pos()` writes `target_stand_pos` — the authored `use_offsets` slot transformed into world space, or the furniture origin when no offsets exist.
5. `BTConditionGoalIs(&"recreation")` admits the branch; `BTActionNavigateTo` paths to `target_stand_pos`.
6. `BTActionUseRecreation._enter()` promotes the reservation via `begin_use()` and plays `use_animation`.
7. Each tick accrues `recreation_per_second * delta` and enforces `use_radius`. The session ends once `min_session_seconds` has elapsed **and** either the need is full or `max_session_seconds` is reached.
8. `_exit()` calls `end_use()`, freeing the slot. The goal is cleared to `&"none"` so the brain re-arbitrates.

**End state:** the need is restored (fully, or partially if the ceiling hit first), the slot is free, and the colonist is back in open arbitration.

## Class Reference

### Class: RecreationParams

**Extends:** `FurnitureCapability`
**Script:** `recreation_params.gd` (in `data/capability_params/`)
**Description:** Pure-data authoring surface for a recreation object. Attached as the nullable `FurnitureDef.recreation_params` export; `FurnitureLayer`'s capability registry spawns `RecreationComponent` when it is non-null. The owning def must also carry `tags = ["recreation_object"]` so it joins the group `need_recreation.tres` targets — `RecreationComponent` warns when it does not.
**Used by:** `FurnitureLayer`, `RecreationComponent`, `BTActionUseRecreation`.

**Properties:** see the `RecreationParams` table in [Data Schemas](data-schemas.md).

**Functions:**

| Function | Description |
|---|---|
| `effective_capacity() -> int` | Authored capacity, clamped down by `use_offsets.size()` when offsets exist. `-1` means unlimited. |
| `session_ceiling_seconds() -> float` | `max_session_seconds` floored at `min_session_seconds`, so a misauthored window can't make the minimum unsatisfiable. |

### Class: RecreationComponent

**Extends:** `Node`
**Script:** `recreation_component.gd` (in `subsystems/furniture/`)
**Description:** Rations access to one recreation object and resolves where each user stands. Implements `IOccupiable`. Generalises `BedComponent`'s single `reserved_by`/`occupied_by` pair to N slots. Does NOT add its furniture to the `recreation_object` group — that comes from `FurnitureDef.tags` via `Furniture._register_tag_groups()`; this component only warns when the tag is absent.
**Used by:** `ColonistBrain` (via the `IOccupiable` probe), `BTActionUseRecreation`.
**Lifecycle:** attached by `FurnitureLayer` when the def carries `RecreationParams`. `_ready()` validates the group tag against `def.tags` rather than group membership, because child `_ready` runs before the parent `Furniture`'s.

**Functions:**

| Function | Description |
|---|---|
| `capacity() -> int` | `params().effective_capacity()`. |
| `is_usable_by(user: Node) -> bool` | True when a slot is free **or** `user` already holds one. The self-claim case is load-bearing: the brain re-scores its own target each cycle and would thrash if told it was full. |
| `reserve(user: Node) -> bool` | Takes a slot for a colonist en route. Idempotent for the same user. |
| `release(user: Node) -> void` | Drops any claim, reserved or active. Safe for a user holding nothing. |
| `begin_use(user: Node) -> bool` | Promotes a reservation to active use on arrival. Refuses when the slots were taken meanwhile. |
| `end_use(user: Node) -> void` | Ends active use and frees the slot. |
| `slot_index_of(user: Node) -> int` | Stable slot index used to pick an offset; `-1` when unheld. |
| `holds_slot(user: Node) -> bool` | Whether `user` holds a reserved or active slot. |
| `use_position_for(user: Node) -> Vector3` | Global stand position: the slot's authored offset through the furniture transform, else the furniture origin. |
| `params() -> RecreationParams` | Capability lookup through `Furniture.get_capability`. |
| `serialize_state()` / `deserialize_state(data)` | Persist nothing — occupancy is transient. |

### Class: IOccupiable

**Extends:** `RefCounted`
**Script:** `i_occupiable.gd` (in `subsystems/furniture/`)
**Description:** Duck-typed contract for capability components that ration colonist access to furniture. Discovered by `ColonistBrain` via `has_method()` checks. Implementations (`RecreationComponent`, `BedComponent`) do **not** extend it, matching `ICapabilityComponent`.

### Class: BTActionUseRecreation

**Extends:** `BTAction`
**Script:** `bt_action_use_recreation.gd` (in `subsystems/ai/tasks/actions/`)
**Description:** Owns one recreation session: promotes the brain's reservation, accrues the need at the furniture's authored rate, enforces `use_radius` and the session window, and frees the slot on exit — including on interruption, so a preempted colonist never leaks a slot. Distinct from `BTActionUseSmartObject`, which restores a flat amount over a fixed duration and models no occupancy.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `smart_object_var` | `StringName` | Blackboard key holding the target furniture. Default `&"target_smart_object"`. |
| `goal_var` | `StringName` | Blackboard key holding the active goal. Default `&"current_goal"`. |
| `stand_pos_var` | `StringName` | Blackboard key holding the stand position, cleared on success. Default `&"target_stand_pos"`. |
| `need_id` | `StringName` | Need to replenish. Matches `NeedDef.id`, not `goal_name`. Default `&"recreation"`. |
| `fallback_animation` | `StringName` | Used when the furniture authors no `use_animation`. |

### Class: BTConditionGoalIs

**Extends:** `BTCondition`
**Script:** `bt_condition_goal_is.gd` (in `subsystems/ai/tasks/conditions/`)
**Description:** Gates a behavior-tree branch on the goal `ColonistBrain` arbitrated this cycle. Returns `SUCCESS` on match, `FAILURE` otherwise — the intended fall-through for the root `BTDynamicSelector`, not the "never fail mid-task" case in [AI Brain](ai-brain.md). An empty `expected_goal` matches any goal.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `goal_var` | `StringName` | Blackboard key to read. Default `&"current_goal"`. |
| `expected_goal` | `StringName` | Goal this branch serves. Empty leaves the branch ungated. |
