# Subsystem: AI Brain & Decision Making

The **Colonist AI Brain** is the decision-making engine that directs colonist behavior in Vek Holdout. It balances survival needs (hunger, rest, recreation) against colony labor (construction, mining, hauling, farming, crafting) using a hybrid **Utility AI + Behavior Tree (LimboAI)** architecture.

---

## 1. Architecture & Execution Hierarchy

Decision-making and execution are decoupled into distinct tiers operating on different update frequencies:

```
[ Tier 1: State & Desires ]       ColonistNeeds (continuous decay per second)
                                         |
                                         v
[ Tier 2: Goal Arbitration ]      ColonistBrain (Utility AI polled every 1.5s)
                                         |
                                         | Writes: current_goal, target_smart_object
                                         v
[ Tier 3: Shared Memory ]         LimboAI Blackboard (runtime key-value state)
                                         |
                                         v
[ Tier 4: Execution Hierarchy ]   BTPlayer -> colonist_root.tres (ticked every frame)
                                         |
                                         +---> BTDynamicSelector (Reactive Root)
                                                  |-- 1. Critical Needs (Emergency thresholds)
                                                  |-- 2. Need Satisfaction (Smart objects / food)
                                                  |-- 3. Universal Work Sequence (Jobs & claims)
                                                  |-- 4. Idle Wander (Fallback movement)
```

### Separation of Responsibilities

1. **`ColonistNeeds` (`subsystems/ai/colonist_needs.gd`)**:
   - Passive numerical model tracking need saturation (`0.0` = empty, `1.0` = full).
   - Evaluates linear decay in `_process(delta)`.
   - Fires threshold events (e.g. emergency threshold `<=` 0.10) for critical reactions.
   - Pure state container; does not dictate actions.

2. **`ColonistBrain` (`subsystems/ai/colonist_brain.gd`)**:
   - Polled utility arbitrator running every 1.5 seconds (`EVAL_INTERVAL = 1.5`).
   - Evaluates curve-based desire scores from deficits, penalizes choices by distance to nearest smart objects, applies action commitment bonuses (inertia), and picks the winning goal (`current_goal`).
   - Writes the winning goal and target node to the colonist's LimboAI `Blackboard`.

3. **`LimboAI Blackboard`**:
   - The shared memory bus connecting `ColonistBrain` and behavior tree tasks.
   - Keys include `current_goal`, `target_smart_object`, `active_job`, `active_claim`, `target_pos`, `required_equipped`, and `required_equipped_tags`.

4. **`BTPlayer` / Behavior Tree (`data/ai/trees/colonist_root.tres`)**:
   - Reactive behavior tree running under a `BTDynamicSelector`.
   - Evaluates leaf tasks every frame to step navigation, play animations, and execute work progress.

5. **`JobBoard` (`subsystems/colonists/job_board.gd`)**:
   - Authoritative job registry for labor assignments.
   - Evaluates colonist labor priorities, skills, distance, and equipment availability to vend jobs.

---

## 2. Decision Cycle: How the Brain Evaluates Goals

Every 1.5 seconds, `ColonistBrain.evaluate_goals()` executes the following pipeline:

### Step 1: Need Deficit Scoring
For each registered `NeedDef` in `ColonistNeeds`:
- Deficit is calculated: `deficit = 1.0 - current_value`.
- Base score is sampled from the authored curve: `base_score = def.response_curve.sample(deficit)`.
- If no curve is defined, it defaults to a linear score: `base_score = deficit`.

### Step 2: Distance Attenuation
Desire alone is insufficient; a colonist cannot eat if there is no food, or rest if there are no beds.
- The brain searches for reachable target objects (e.g. food in inventory/crates, beds in colony furniture).
- Distance penalty is applied:
  `final_score = base_score * clampf(1.0 - (distance / 100.0), 0.2, 1.0)`
- If no valid unblacklisted target exists on the map, `final_score` drops to `0.0`.

### Step 3: Work Score Evaluation
- `_get_work_score(actor)` queries `JobBoard.get_best_job_for(colonist)`; if no job is available, the work score is `0.0` (no baseline desire to work absent actual work).
- Otherwise the score is `(labor_priority / 5.0) * def.base_priority` — the colonist's own 0-5 labor priority slider scaled by the job def's authored `base_priority` (defaults to `0.5` if the def doesn't export one).
- **Special case:** a `DeployJobDef` (or any job with `labor_id == "deploy"`) always scores `2.0`, guaranteeing it outranks every other goal.
- **Test fallback:** a non-`Colonist` actor (mock actors in unit tests) always scores `0.5`, independent of `JobBoard` state.

### Step 4: Action Commitment (Inertia Bonus)
To prevent "thrashing" (rapidly oscillating between eating, resting, and working when scores are close):
- If the colonist is already pursuing a goal (`active_goal != &"none"`), and has **no critical needs** (`current_value > emergency_threshold` across all needs):
  - A `+0.30` inertia bonus is added to `scores[active_goal]`.
- This ensures colonists finish current tasks before switching desires, unless an emergency occurs.

### Step 5: Winning Goal Selection & Blackboard Write
- The highest-scoring goal is selected (`winning_goal`). If all scores are `<= 0.0`, it defaults to `&"work"`.
- The brain writes `current_goal` and `target_smart_object` into the blackboard.

---

## 3. Behavior Tree Execution Order (`colonist_root.tres`)

The root task of the colonist behavior tree is a **`BTDynamicSelector`**. Unlike a standard selector that sticks to a running task until it finishes, a dynamic selector re-evaluates all children from highest to lowest priority every frame:

1. **Need Satisfaction Sequence (`BTSequence_gqtk8` - Food / Eating)**:
   - `BTActionFindFood`: Checks if `current_goal == &"eat"`. Finds carried or stored food.
   - `BTActionNavigateTo`: Walks to food container or eating location.
   - `BTActionFetchFood`: Extracts food item into colonist hands.
   - `BTActionEatFood`: Consumes food and restores hunger need.

2. **Smart Object Sequence (`BTSequence_ekcvg` - Beds / Recreation)**:
   - `BTActionNavigateTo`: Walks to `target_smart_object`.
   - `BTActionUseSmartObject`: Interacts with furniture (e.g. bed sleep cycle) until need is replenished.

3. **Universal Work Sequence (`BTSequence_0bgy2` - Colony Labor)**:
   - `BTActionClaimJob`: Evaluates `JobBoard.get_best_job_for()`. Claims a job, syncs tool requirements and target coordinates.
   - `BTSelector` (`BTConditionHasTool`): Verifies the required tool is in inventory or equipped.
   - `BTActionEquipTool`: Swaps tool into `main_hand` from `holster` or carry inventory.
   - `BTActionNavigateTo`: Navigates to job site (`target_pos` / anchor cell / target node).
   - `BTActionPerformWork`: Plays work animation, steps work duration with skill scaling, and materializes progress or finishes job.

4. **Idle Wander (Fallback, bare leaf under the root selector)**:
   - `BTActionWander`: Picks a random walkable cell within radius and walks there, then holds position for `wait_duration` before wandering again.

---

## 4. Multi-Leg Job & Hauling Contracts

Certain labors in Vek Holdout cannot be satisfied in a single instant interaction. In particular, hauling and construction operate across multiple distinct legs.

### Hauling Lifecycle (Fetch -> Deliver)
1. **Leg 1 (Pickup / Fetch)**:
   - Colonist navigates to the ground item (`WorldItem`) or source crate.
   - Colonist executes pickup: the items move into the colonist's inventory pockets, and the ground item count drops to 0 (`item.hide_item()`).
   - **Critical Invariant**: Leg 1 is NOT the end of the job. `JobDef.job_complete(job)` must return `false` while items remain in transit.
2. **Leg 2 (Delivery / Deposit)**:
   - `BTActionClaimJob` detects that the colonist already holds an active hauling job, preserves `active_job` on the blackboard, and invokes `_update_active_job_target_pos()`.
   - `_update_active_job_target_pos()` queries `job.def.work_site(colonist, job)`, dynamically redirecting `target_pos` to the destination storage crate or construction sink.
   - `BTActionNavigateTo` walks the colonist to the crate.
   - `BTActionPerformWork` verifies proximity (`distance_to(crate) <= 2.2`), transfers the carried materials into crate inventory, and calls `_finish(actor, job)`.
   - `_finish()` marks `job.is_completed = true`, unassigns the actor, and prunes the job from `Colony.job_board`.

### Terminal vs. Progressive Job Completion in `BTActionPerformWork`
- **Legacy Single-Shot Jobs** (Digging, Single Harvest): Calling `job.def.complete(agent, job)` immediately triggers `_finish()`, setting `job.is_completed = true`.
- **Multi-Leg & Progressive Jobs** (Hauling, Fractional Jobs): Calling `complete()` only concludes the active leg. `BTActionPerformWork` calls `_is_job_def_completed(job)`:
  - If `job.is_completed` or `job.is_finished()` is true, or `def.job_complete(job)` returns true, `_release_job_reference()` clears `active_job` from the blackboard.
  - If the job requires further legs, `active_job` is retained on the blackboard so `BTActionClaimJob` steps to the next phase on the subsequent tick.

---

## 5. Inventory Hygiene & Item Dribbling Prevention

When a colonist finishes a job, switches goals, or claims a new task, carried items must be reconciled without causing infinite AI feedback loops.

### The "Item Dribbling" Loop
- If a colonist holding surplus materials (e.g. remaining wood from an interrupted build or canceled haul) blindly drops those items onto the ground (`WorldItem.spawn_at`), `Colony.register_world_item()` immediately detects the new world item.
- `Colony` registers a fresh hauling job for that item on `JobBoard`.
- On the next frame, the same colonist (or a nearby colonist) evaluates `JobBoard.get_best_job_for()`, claims the hauling job, picks up the dropped item, runs hygiene checks, drops it again, and repeats infinitely (the "dribbling" loop).

### The Solution: Stow-or-Cleanup
- In `BTActionClaimJob._cleanup_incompatible_held_items()`:
  - Carried tools are preserved or equipped via `EquipmentAudit`.
  - Needed materials for the active job (e.g. materials for the target sink) are never discarded.
  - Any surplus unneeded materials are handled via `_stow_or_cleanup_unneeded_items()`: the system attempts to deposit them directly into colony crates before falling back to dropping them on the ground.

---

## 6. Spatial Bounds & Void Filtering

Vek Holdout supports arbitrary voxel terrain depth, including deep mining shafts, underground caverns, and open sky voids.

- **Dynamic Map Bounds**:
  - `MapDef` defines the playable coordinate volume (`world_bounds: AABB`).
  - During map startup, `MapWiring.wire_colonists()` injects this volume into the colony coordinator:
    `Colony.set_world_bounds(map.get_world_bounds())`
- **Void Rejection**:
  - When blocks are mined or destroyed over voids, items may fall below the lowest playable floor.
  - `Colony.register_world_item()` and `Colony._spawn_world_item_haul_job()` verify that:
    `if _world_bounds.has_volume() and item.global_position.y < _world_bounds.position.y: return`
  - This dynamically adapts to deep mines of any depth while preventing out-of-bounds items from creating unreachable jobs that stall colonists.

---

## 7. Critical AI Gotchas & Lessons Learned

Developing and debugging the hybrid Utility + LimboAI system revealed several subtle edge cases. Keep these invariants in mind when modifying AI or job systems.

### 1. The Dynamic Selector 60 Hz Preemption Gotcha
- **The Issue**: `BTDynamicSelector` evaluates its branches from top to bottom on **every single frame (60 Hz)**.
- **The Pitfall**: If an active sequence returns `FAILURE` for even a single frame (e.g. a momentary null target or temporary check failure), the dynamic selector instantly falls through to lower-priority branches (such as `Wander`).
- **Rule**: Never return `FAILURE` in an active sequence unless the task is genuinely aborted or impossible. If a task is waiting for a multi-frame subsystem or async result, return `RUNNING`.

### 2. Job Slot Capacity Self-Rejection (The Claim/Drop Loop)
- **The Issue**: Single-colonist jobs (like Construction or Harvesting) have `max_assignees = 1`. When a colonist claims the job, `_assigned_colonists` has size 1.
- **The Pitfall**: On the very next tick, `BTActionClaimJob` validates the ongoing job by calling `job.is_available_for(colonist)`. If `is_available_for` checks `_assigned_colonists.size() >= max_assignees` without verifying if the querying colonist is **already assigned**, it evaluates `1 >= 1` (true) and reports the job as unavailable!
- **Symptom**: The colonist unassigns the job, drops `active_job`, claims it again on the same frame, and loops at 60 Hz. The behavior tree is trapped in `ClaimJob`, wiping navigation every frame and causing the colonist to wander while UI displays flickering activity badges.
- **Fix**: In `Job.is_available_for(colonist)`:
  ```gdscript
  var is_already_assigned: bool = colonist != null and is_assigned(colonist.colonist_id)
  if not is_already_assigned and _assigned_colonists.size() >= max_assignees:
      return false
  ```

### 3. Blueprint Volume Self-Occupancy
- **The Issue**: Construction jobs require clear space around the blueprint to prevent entities from being entombed inside solid structures upon completion (`_is_blueprint_occupied()`).
- **The Pitfall**: If `ConstructionJobDef.is_available_for(job, actor)` does not pass `actor` as `exclude_actor` to `_is_blueprint_occupied(bp, actor)`, the builder standing at or adjacent to the blueprint will flag the blueprint as occupied by *themselves*.
- **Symptom**: The builder claims the job, walks up to the blueprint, and immediately drops the job because they are standing inside their own construction bounding box.
- **Fix**: In `ConstructionJobDef`:
  ```gdscript
  func is_available_for(job: Variant, actor: Node = null) -> bool:
      var bp := _blueprint_of(job)
      if bp == null:
          return false
      return not _is_blueprint_occupied(bp, actor)
  ```

### 4. Blackboard vs. Colonist State Desynchronization (`active_job` vs `current_job`)
- **The Issue**: `Colonist.get_current_activity()` drives overhead UI badges and moodlets by checking `blackboard.get_var("active_job")` with a fallback to `colonist.current_job`.
- **The Pitfall**: If a failure or exit handler (e.g. `_handle_navigation_failure()` or `_release_job_reference()`) erases `active_job` from the blackboard but forgets to set `colonist.current_job = null`, the colonist will physically execute the `Wander` task while overhead badges and management screens display "Construction" or "Mining".
- **Rule**: Whenever `blackboard.erase_var(job_var)` is called, `(agent as Colonist).current_job = null` must be executed simultaneously.

### 5. Navigation Path Ownership Across Sibling Tasks
- **The Issue**: Both `BTActionNavigateTo` and `BTActionWander` control colonist movement by calling `agent.set_path(path)`.
- **The Pitfall**: In a `BTDynamicSelector`, sibling branches are evaluated and exited regularly. If an exiting `NavigateTo` clears the agent path (`agent.set_path([])`), it could wipe the path generated by `Wander` or another active navigation task.
- **Fix**: Use path ownership metadata (`set_meta("bt_nav_path_owner", get_instance_id())`). A task may only clear the agent's path on exit if it was the task that authored the active path.

### 6. Synchronous Disk I/O Stuttering in 60 Hz Telemetry
- **The Issue**: Logging state changes is vital for troubleshooting AI behavior loops.
- **The Pitfall**: Calling `FileAccess.flush()` or opening/writing log files synchronously inside `_process` or behavior tree ticks causes severe main-thread stuttering (10-50ms frame spikes).
- **Rule**: Use the buffered `DebugLogger` / `ColonistLogger` pipeline. Buffers are flushed on application cadence or test completion, never on every per-frame blackboard check.

---

## 8. Telemetry & Debugging AI Loops

When colonists exhibit stuttering, rapid state oscillation, or idle wandering during active work:

1. Enable colonist logging in `tmp/debug.log`:
   - Inspect `[COLONIST] [Colonist:<name>(<id>)]` entries.
2. Filter by category:
   - `[BRAIN]`: Shows utility scores, deficits, winning goals, and inertia application.
   - `[JOB]`: Shows `JobClaim` events (`CLAIMED`, `REJECT`), slot unassignments, and dead job prunes.
   - `[JOB_BOARD]`: Shows job evaluation rejections (e.g. `tool requirement failed`).
   - `[TOOL]`: Shows `ConditionHasTool` or `EquipTool` failures.
   - `[TASK]`: Shows behavior tree task lifecycle transitions (`ENTER`, `RUNNING`, `SUCCESS`, `FAILURE`).
3. Look for repetition patterns:
   - **Frame oscillation (16ms repetitions)**: If `JobClaim CLAIMED` appears every frame, check `is_available_for` capacity gates or blueprint occupancy.
   - **Navigation resets**: If `NavigateTo ENTER` immediately alternates with `Wander ENTER`, check if an action is failing on path generation or wiping sibling path ownership.
