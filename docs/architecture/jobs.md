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

## Behavior Tree Integration

Behavior trees interact with jobs using dedicated custom tasks (`subsystems/ai/tasks/actions/`):

- **`BTActionClaimJob`**: Ticked by `bt_generic_work.tres` / `bt_haul_single_trip.tres`. Queries `JobBoard.get_best_job_for()`, claims work units via `try_claim_units()`, populates blackboard variables (`active_job`, `target_pos`, `source_node`, `target_node`), and manages lazy tool retention.
- **`BTActionPerformWork`**: Ticked while adjacent to work site. Plays `work_animation`, advances work units per cycle duration, and calls `complete_claim()`.
