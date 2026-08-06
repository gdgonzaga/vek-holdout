# Subsystem: Colonists

Colonist entities, roster (in Colony autoload), Job Board, labor AI, raid stances. GDD §6.

## Files

| File | Type | Responsibility |
|---|---|---|
| `colonist_base.gd` | Script | Base for all colonists. Holds HP, skills, labor priorities, raid stance, current Job. Does NOT own job discovery (Job Board does). |
| `colonist.tscn` | Scene | Capsule mesh + CollisionShape + components. |
| `../autoloads/colony.gd` | Autoload | Roster + Job Board. Cross-scene (colonists persist base↔POI). |
| `job_board.gd` | Script (on Colony) | Job registry; claim/unclaim/fail logic. Early-MVP: log+skip+auto-remove-3. Late-MVP: blocked-state + Retry. |
| `colonist_ai.gd` | Script | Idle → query Job Board → claim → path (A*) → work → release. Does NOT own pathfinding (uses A* on voxel grid). |
| `colonist_combat.gd` | Script | Reactive engagement logic (hold position; fire missile if in range; melee if adjacent). GDD §6.7. |
| `../data/labors/` | Data | Labor definitions (Construction, Crafting, Smelting, Mechanics, Hauling; Repair/Farming/Cooking post-MVP). Crafting + Smelting Labors claim Jobs produced by the Crafting subsystem's stations. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `colonist_died(colonist_id)` | `colonist_base.gd` | Colony, HUD, Memorial | Yes | Colonist Death |
| `job_claimed(job_id, colonist_id)` | `job_board.gd` | (internal) | No | Colonist Works a Job |
| `job_failed(job_id, reason)` | `job_board.gd` | Job Log UI | No | Job Failure Handling |
| `job_logged(entry)` | `job_board.gd` | Job Log UI (when open) | Yes | Job Failure Handling |

## Flow Trace: Colonist works a job (claim → path → work)

**Trigger:** Colonist becomes idle.

1. `colonist_ai.gd` queries `JobBoard.get_best_job_for(colonist)` — highest-priority Labor with an available Job the colonist meets the L1 skill gate for (`skill_set.meets_requirement`), then nearest by proximity.
2. JobBoard atomically claims the Job (returns job or null).
3. Colonist A* paths to job location (via voxel grid).
4. On arrival, each work tick: effective rate = `job.base_rate × skill_set.get_multiplier(labor) × stamina_component.get_work_multiplier()`. Marks `stamina_component.set_working(true)` while active.
5. On completion → `skill_set.record_use(skill_id)` (grants skill progress); `stamina_component.set_working(false)`; `JobBoard.complete(job_id)`; colonist returns to step 1.

**End state:** Job complete at combined skill × Stamina rate; skill progressed; Stamina burned at ×2; colonist seeks next.

## Flow Trace: Job failure handling (early-MVP)

**Trigger:** Colonist can't finish a job (no materials / blocked path / target destroyed).

1. `colonist_ai.gd` calls `JobBoard.fail(job_id, reason)`.
2. JobBoard logs entry; emits `job_logged` via EventBus.
3. JobBoard increments job's failure_count.
4. If failure_count >= 3 → auto-remove from board (blueprint stays placed if construction).
5. Colonist queries next enabled Job.

**End state:** Failed job logged + skipped; colonist continues; no player action required.

## Class Reference

### Class: Colony

**Extends:** Node
**Script:** `autoloads/colony.gd`
**Description:** The colony roster and Job Board. Cross-scene because colonists persist during expeditions. Owns colonist lifecycle and job discovery.
**Used by:** HUD (roster UI), Colony Management screen, Combat (damage targets), Raids (stance execution).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `colonists` | `Array[ColonistBase]` | Active colonists (max 5 in MVP). |
| `job_board` | `JobBoard` | The Job Board instance. |

**Functions:**

| Function | Description |
|---|---|
| `add_colonist(colonist: ColonistBase) -> void` | Recruits a colonist (random event / radio). |
| `remove_colonist(colonist_id: String) -> void` | On death or departure. |

### Class: ColonistBase

**Extends:** CharacterBody3D
**Script:** `colonist_base.gd`
**Description:** Base class for all colonists. Holds stats, skills, labor priorities, raid stance, current Job.
**Used by:** Colony (roster), Combat (target), Colonist Management screen.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `colonist_id` | `String` | Unique ID. |
| `display_name` | `String` | Shown in UI. |
| `max_hp` | `int` | [export] 100 baseline (companion +20%). |
| `labor_priorities` | `Dictionary` | Labor → 0–5 priority. |
| `raid_stance` | `RaidStance` enum | Fight / Fight Post / Shelter. |
| `skill_set` | `SkillSet` | @onready ref; holds this colonist's 6 skills + progress. See [Skills](skills.md) subsystem. |
| `stamina_component` | `StaminaComponent` | @onready ref; work/move multipliers + collapse state. See [Energy](energy.md) subsystem. |
