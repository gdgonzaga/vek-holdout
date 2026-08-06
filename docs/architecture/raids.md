# Subsystem: Raids

Raid scheduler, threat-direction weights, spawn manager. GDD §17 Raids subsystem.

## Files

| File | Type | Responsibility |
|---|---|---|
| `raid_scheduler.gd` | Script (on the base Map, base scene only) | Triggers raids per escalation curve; emits `raid_started`. Does NOT own enemy spawning (SpawnManager does). |
| `threat_model.gd` | Script (on Colony autoload) | Per-edge threat weights; POI visit bump, decay, random floor. |
| `spawn_manager.gd` | Script | Spawns enemies at chosen edge; enforces 24-enemy cap; throttles waves. |
| `../data/raid_curve.tres` | Data | Escalation table (D1–D20+ waves/enemies/shooter %). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `raid_started(raid_data)` | `raid_scheduler.gd` | HUD, Colony, colonists | Yes | Raid Begins |
| `raid_ended(outcome)` | `raid_scheduler.gd` | HUD, Colony, SaveSystem | Yes | Raid Resolves |

## Flow Trace: Nightly raid begins

**Trigger:** TimeSystem emits `day_rolled_over` (midnight).

1. RaidScheduler listens; checks colony size (≥ 3 colonists required — safety net).
2. Looks up wave count + enemies/wave for `current_day` in `raid_curve.tres`.
3. ThreatModel selects weighted-random edge; SpawnManager gets spawn points along edge.
4. RaidScheduler emits `raid_started` via EventBus.
5. Colony assigns colonists to their raid stances (Fight/Fight Post/Shelter).
6. SpawnManager spawns wave 1; respects 24-enemy cap.

**End state:** Raid in progress; colonists in stance; enemies spawning.

## Class Reference

### Class: ThreatModel

**Extends:** Node
**Script:** `threat_model.gd`
**Description:** Per-edge threat weights (N/S/E/W). Owned by Colony autoload because POI visits (which bump weights) happen during expeditions. The visibility bonus (+3 per functional-furniture item to all edges) is applied here via `Colony.count_functional_furniture()` (see [Functional Rooms](functional-rooms.md) subsystem — **planned, not yet built**).
**Used by:** Raids (edge selection), Expeditions (POI visit bumps weights).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `weights` | `Dictionary[String, int]` | Edge → weight (start 25 each). |

**Functions:**

| Function | Description |
|---|---|
| `bump_edge(edge: String, amount: int) -> void` | POI visit raises edge weight. |
| `apply_visibility_bonus() -> void` | Adds `Colony.count_functional_furniture() × 3` to all edges. Called at raid-start. *(Depends on Functional Rooms — planned.)* |
| `decay_all() -> void` | Daily −2/edge, floored at 10. |
| `select_edge() -> String` | Weighted-random + 10% floor. |
