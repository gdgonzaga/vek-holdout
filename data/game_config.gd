extends Resource
class_name GameConfig
## Engine-level constants (ARCH "data/game_config.tres", lines 1733-1736).
## Loaded by TimeSystem (loop_length_minutes) and other subsystems. Single
## source of truth for tunable engine-level values.

@export var gravity: float = 9.8                       # Y-axis gravity (m/s^2).
@export var target_fps: int = 60                        # Render floor (30 minimum).
@export var loop_length_minutes: float = 30.0           # Real minutes per in-game day.
@export_group("Night Raid Spawning")
@export var spawn_distance_min: float = 24.0           # Minimum spawn distance from player (meters).
@export var spawn_distance_max: float = 48.0           # Maximum spawn distance from player (meters).
@export var spawn_start_hour: float = 21.0             # 24h clock: 9:00 PM raid start.
@export var spawn_end_hour: float = 4.5                # 24h clock: 4:30 AM raid end.
@export var spawns_per_minute: float = 4.0             # Base enemies spawned per real-time minute.
@export var spawn_rate_curve: Curve                    # Distribution curve modulating spawn intensity across the night.

@export_group("Day/Night Celestial Lighting")
@export var sun_energy: float = 1.2
@export var sun_direct_light_energy: float = 1.2
@export var moon_energy: float = 1.2
@export var moon_direct_light_energy: float = 0.25
@export var overhead_light_min_energy: float = 0.05
@export var overhead_light_max_energy: float = 0.4
@export var sun_color: Color = Color(1.0, 0.95, 0.85)
@export var sunset_color: Color = Color(1.0, 0.5, 0.2)
@export var moon_color: Color = Color(0.65, 0.75, 1.0)
@export var night_ambient_energy: float = 0.05
@export var day_ambient_energy: float = 1.0
@export var day_sky_top_color: Color = Color(0.38, 0.45, 0.55)
@export var day_sky_horizon_color: Color = Color(0.65, 0.65, 0.67)
@export var night_sky_top_color: Color = Color(0.01, 0.02, 0.05)
@export var night_sky_horizon_color: Color = Color(0.04, 0.06, 0.12)

@export_group("Debug Logging")
@export var log_to_file: bool = true
@export var log_to_console: bool = false
@export var log_file_path: String = "user://logs/debug.log"
@export var colonist_debug_logging: bool = true
