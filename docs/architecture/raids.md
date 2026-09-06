# Subsystem: Raids

Raid scheduler, threat-direction weights, spawn manager. GDD §17 Raids subsystem.

> **Implementation status: in-progress (v1 Night Raids live).** `NightRaidController` (`subsystems/raids/night_raid_controller.gd`) is mounted on the active Map via `MapWiring.wire_raids(m)`. It manages nocturnal hostile spawns around the player within configurable distance limits (`spawn_distance_min`, `spawn_distance_max`), paces spawns via real-time `spawns_per_minute` modulated by `spawn_rate_curve`, and emits `EventBus.raid_started` and `raid_ended`. Colony threat model and edge-based wave escalation remain planned for future iterations.

## Files

| File | Type | Responsibility |
|---|---|---|
| `night_raid_controller.gd` | Script (on active Map) | Controls night raid lifecycle; computes spawn pacing and generates hostiles radially around player. |
| `raid_scheduler.gd` | Script (Planned) | Triggers structured edge raids per escalation curve; emits `raid_started`. |
| `threat_model.gd` | Script (Planned on Colony autoload) | Per-edge threat weights; POI visit bump, decay, random floor. |
| `spawn_manager.gd` | Script (Planned) | Spawns enemies at chosen edge; throttles waves. |
| `../data/raid_curve.tres` | Data (Planned) | Escalation table (D1-D20+ waves/enemies/shooter %). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `raid_started(raid_data)` | `night_raid_controller.gd` | HUD, Colony, colonists, GameLog | Yes | Raid Begins |
| `raid_ended(outcome)` | `night_raid_controller.gd` | HUD, Colony, SaveSystem, GameLog | Yes | Raid Resolves |

## Flow Trace: Nightly raid begins

**Trigger:** In-game clock reaches `spawn_start_hour` (e.g. 21:00).

1. `NightRaidController` detects entry into night window across midnight.
2. Emits `raid_started` via `EventBus` (logged by `GameLog`).
3. Evaluates real-time night duration from `GameConfig.loop_length_minutes`.
4. Evaluates instantaneous spawn frequency scaled by `spawn_rate_curve`.
5. Raycasts downward from Y = 512.0 to find terrain elevation around the player.
6. Instantiates enemy entities into the map's `EnemyContainer` and wires pathfinding.
7. On reaching `spawn_end_hour` (e.g. 04:30), emits `raid_ended` via `EventBus`.

**End state:** Raid in progress; colonists in stance; enemies spawning.

## Class Reference

### Class: NightRaidController

**Extends:** Node  
**Script:** `subsystems/raids/night_raid_controller.gd`  
**Description:** Manages nocturnal raid timing, evaluates dynamic spawn pacing via `GameConfig` distribution curves, and spawns hostile entities radially around the active player on the terrain surface. Mounted on the active map via `MapWiring.wire_raids(m)`.  

**Properties:**

| Property | Type | Description |
|---|---|---|
| `config_path` | `String` | Path to `GameConfig` resource (`res://data/game_config.tres`). |
| `enemy_scene` | `PackedScene` | Hostile prototype scene to instantiate (`enemy_swarmer.tscn`). |
| `map` | `Map` | Active map instance owning voxel grid, player, and enemy container. |
| `config` | `GameConfig` | Loaded game config reference containing raid tunables. |
| `raid_active` | `bool` | True when in-game clock is within the raid window (`spawn_start_hour` to `spawn_end_hour`). |

**Functions:**

| Function | Description |
|---|---|
| `_resolve_current_in_game_hour() -> float` | Converts `TimeSystem.get_time_of_day_fraction()` to continuous 24h clock hour. |
| `_is_hour_in_night_window(hour: float, start_h: float, end_h: float) -> bool` | Evaluates if hour is inside raid window, handling midnight rollover. |
| `_calculate_night_progress(hour: float, start_h: float, end_h: float) -> float` | Returns normalized progress [0.0, 1.0] from raid start to raid end. |
| `_evaluate_spawn_rate_per_second(base_per_min, curve, progress, curve_mean) -> float` | Computes per-second spawn rate normalized by curve mean (`sample_baked(progress) / curve_mean`). |
| `_calculate_curve_mean(curve: Curve) -> float` | Samples curve across [0.0, 1.0] to compute its mean value for quota-preserving rate normalization. |
| `_find_valid_spawn_position(player_pos: Vector3) -> Vector3` | Samples radial polar coordinates around player and queries terrain height via `map.ground_height_at(x, z)`. |
| `_spawn_raid_enemy() -> bool` | Instantiates enemy at valid surface coordinate and wires pathfinder walkability via `MapWiring.wire_enemy_pathfinder()`. |


### Class: ThreatModel

**Extends:** Node
**Script:** `threat_model.gd`
**Description:** Per-edge threat weights (N/S/E/W). Owned by Colony autoload because POI visits (which bump weights) happen during expeditions. The visibility bonus (+3 per functional-furniture item to all edges) is applied here via `Colony.count_functional_furniture()` (see [Functional Rooms](functional-rooms.md) subsystem — **planned, not yet built**).
**Used by:** Raids (edge selection), Expeditions (POI visit bumps weights).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `weights` | `Dictionary[String, int]` | Edge -> weight (start 25 each). |

**Functions:**

| Function | Description |
|---|---|
| `bump_edge(edge: String, amount: int) -> void` | POI visit raises edge weight. |
| `apply_visibility_bonus() -> void` | Adds `Colony.count_functional_furniture() * 3` to all edges. Called at raid-start. *(Depends on Functional Rooms — planned.)* |
| `decay_all() -> void` | Daily -2/edge, floored at 10. |
| `select_edge() -> String` | Weighted-random + 10% floor. |
