extends Resource
class_name GameConfig
## Engine-level constants (ARCH "data/game_config.tres", lines 1733-1736).
## Loaded by TimeSystem (loop_length_minutes) and other subsystems. Single
## source of truth for tunable engine-level values.

@export var gravity: float = 9.8                       # Y-axis gravity (m/s^2).
@export var target_fps: int = 60                        # Render floor (30 minimum).
@export var loop_length_minutes: float = 30.0           # Real minutes per in-game day.
@export var max_enemies_on_screen: int = 24             # Spawn cap.

@export_group("Day/Night Celestial Lighting")
@export var max_sun_energy: float = 1.2
@export var max_moon_energy: float = 0.25
@export var sun_color: Color = Color(1.0, 0.95, 0.85)
@export var sunset_color: Color = Color(1.0, 0.5, 0.2)
@export var moon_color: Color = Color(0.65, 0.75, 1.0)
@export var min_ambient_energy: float = 0.15
@export var max_ambient_energy: float = 1.0
@export var min_sky_energy: float = 0.05
@export var max_sky_energy: float = 1.0
