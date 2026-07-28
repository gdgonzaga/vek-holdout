extends Resource
class_name GameConfig
## Engine-level constants (ARCH "data/game_config.tres", lines 1733-1736).
## Loaded by TimeSystem (loop_length_minutes) and other subsystems. Single
## source of truth for tunable engine-level values.

@export var gravity: float = 9.8                       # Y-axis gravity (m/s^2).
@export var target_fps: int = 60                        # Render floor (30 minimum).
@export var loop_length_minutes: float = 30.0           # Real minutes per in-game day.
@export var max_enemies_on_screen: int = 24             # Spawn cap.
