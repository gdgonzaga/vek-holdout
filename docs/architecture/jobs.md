# Subsystem: Jobs & Fractional Work System

The **Jobs Subsystem** (`subsystems/jobs/`, `subsystems/colonists/job_board.gd`) manages job registration, reservation, fractional work unit claims, multi-worker assignment, and execution across the colony.

---

## Fractional Job Architecture

Work in Vek: Holdout uses a fractional work unit model (`JobInstance` + `WorkerClaim`):

```
                   +-----------------------+
                   |       JobBoard        |  (Colony-wide job registry)
                   +-----------+-----------+
                               |
                               v
                   +-----------------------+
                   |      JobInstance      |  (Runtime state: total_units, unclaimed_units)
                   +-----------+-----------+
                               |
          +--------------------+--------------------+
          |                                         |
          v                                         v
+-------------------+                     +-------------------+
|    WorkerClaim    | (Worker A: 50 u)    |    WorkerClaim    | (Worker B: 50 u)
+-------------------+                     +-------------------+
```

---

## Core Classes

### 1. `JobInstance` (`subsystems/jobs/job_instance.gd`)

Represents an active, trackable job instance registered on `JobBoard`.

- **Work Unit Tracking**: Tracks `total_units`, `unclaimed_units`, and `completed_units`.
- **Fractional Worker Claims**: Manages `active_claims: Dictionary` mapping colonist ID to active `WorkerClaim` instances.
- **Multi-Worker Support**: Allows up to `JobDef.max_assignees` colonists to reserve work units concurrently.
- **Lifecycle Methods**:
  - `create(...)` / `create_haul(...)`: Static factories for standard and hauling jobs.
  - `try_claim_units(colonist, requested_units)`: Reserves a batch of work units for a colonist.
  - `abandon_claim(colonist_id)`: Releases unworked units back into `unclaimed_units` pool if interrupted.
  - `complete_claim(colonist_id, finished_units)`: Records completed work units and checks job completion.
  - `cancel_job()`: Cancels job and releases all active claims.

### 2. `WorkerClaim` (`subsystems/jobs/worker_claim.gd`)

Lightweight data model tracking a colonist's active reservation on a `JobInstance`.

- **Properties**: `job_instance`, `colonist_id`, `claimed_units`, `completed_units`, `target_position`, `source_position`.
- **Methods**: `is_finished() -> bool` (returns `true` when `completed_units >= claimed_units`).

### 3. `JobBoard` (`subsystems/colonists/job_board.gd`)

Colony-wide registry owned by `Colony` autoload (`Colony.job_board`).

- **Selection**: `get_best_job_for(colonist)` filters jobs by colonist labor priorities (`labor_priorities[labor_id] > 0`), requirement checks (`JobDef.meets_requirements_any`), availability (`is_available`), and temporary job blacklists.
- **Job Blacklisting**: `blacklist_job_for(job_id, colonist_id, duration_sec)` temporarily ignores unreachable jobs for specific colonists to prevent pathfinding loops. `clear_blacklists()` resets all cooldowns.
- **Dead Job Pruning**: `_prune_dead_jobs()` automatically removes completed, cancelled, or invalid jobs.

---

## JobDef Virtual Contract

Every job template (`data/jobs/*.gd` + `.tres`) implements the lifecycle below (base defaults in `data/jobs/job_def.gd`; base implementations are sane, defs override per labor). This is the contract the LimboAI work tree drives — see ARCH AI for the tree itself.

| Virtual | Default | Purpose |
| --- | --- | --- |
| `is_available(job)` | `true` | Claimability beyond the board's slot gate. Drought-waiting defs (hauling) return `false` while unsatisfied but keep the job registered. |
| `should_close(job)` | `not is_available(job)` | Board lifetime: `true` = leave the registry (checked by the prune when no assignees remain). Drought-persistent defs decouple this from availability. |
| `job_complete(job)` | `true` | Did a finished run actually satisfy the work (vs. stalling short of it — a hauler that drained the crates). |
| `begin(actor, job)` | `0.0` | Cycle duration in **unskilled** seconds (the tree applies the skill multiplier). Only consulted when `work_duration <= 0.0` — dynamic-duration defs (construction `build_time`, crafting `base_time`, crop-driven harvest) author the `.tres` with `work_duration = 0.0`. |
| `complete(actor, job)` | `_finish` | Terminal effect of one PerformWork cycle (carve the voxel, materialize the blueprint, ...). `_finish` records skill XP and drops the job from the board; looping labors (hauling) skip `_finish`. |
| `on_abort(actor, job, elapsed)` | no-op | The cycle was preempted mid-work (a need won the dynamic selector): persist partial progress, release held claims. |
| `work_site(actor, job)` | `null` | Walk target for this cycle; `null` = the board default (anchor cell / target node). Multi-site labors override — hauling walks to a source crate while empty-handed and to the sink while carrying. |

Content rule: durations/animations/units are authored in the `.tres` (`work_duration`, `work_animation`, `default_units_per_cycle`), never as script constants.

### Def inventory

- **DigJobDef** — emits `EventBus.dig_job_completed` (MiningSystem carves the voxel); claimable while the cell holds terrain AND has a walkable neighbour (buried cells wait).
- **ConstructionJobDef** — materializes via `Blueprint.complete` (the colonist twin of the player's BuildAction); `begin` reads the target's `BuildableDef.build_time`; an occupied volume hides the job and blocks completion; aborts persist `Blueprint.work_done`.
- **CraftingJobDef** — works a station's ready order, produces via `CraftingStation.produce`, resolves via `complete_order` (maintain orders requeue). Claims the station for the craft (arbitration vs. the player's CraftAction); claim races no-op and retry.
- **HarvestJobDef** — resolves yields via `Harvestable.complete`; `begin` = crop-driven `effective_work_time()` minus persisted partial work.
- **FarmingJobDef + Sow/Water/Tend** — one cycle against the plot's `Growable` (`_needs` predicate + `_apply` effect); availability tracks what the plot currently needs.
- **HaulingJobDef** — repeated fetch/deliver cycles through the generic work tree (no dedicated leg tree): `work_site` picks crate-vs-sink by carry state, `complete` does the instant transfer, and the loop ends by satisfaction (`should_close`) — never a terminal `_finish`. Drought-persistent: unclaimable while no crate stocks a needed material, registered until the sink is satisfied. Surplus after a satisfied deliver returns to the nearest crate (tools exempt).

---

## Behavior Tree Integration

Behavior trees interact with jobs using dedicated custom tasks (`subsystems/ai/tasks/actions/`):

- **`BTActionClaimJob`**: Ticked by `bt_generic_work.tres` / `bt_haul_single_trip.tres`. Queries `JobBoard.get_best_job_for()`, claims via `try_claim_units()` (fractional) or `try_assign()` (legacy `Job`), populates blackboard variables (`active_job`, `target_pos`, `source_node`, `target_node`), and manages lazy tool retention. Legacy claims consult `JobDef.work_site` for this cycle's walk target. Spent claims and completed/cancelled jobs on the blackboard are dropped so a fresh claim is made instead of re-satisfying finished work.
- **`BTActionPerformWork`**: Ticked while adjacent to work site. Plays `work_animation`, runs for the def-derived duration (`work_duration`, dynamic `begin`, divided by the actor's skill multiplier), then fires the terminal effect — `apply_work_units()` on `JobInstance`/`WorkerClaim`, or `JobDef.complete(actor, job)` on legacy `Job`s — releasing the blackboard reference (and the legacy assignee slot) so the next tick claims fresh work. Preempted cycles fire `JobDef.on_abort`.
