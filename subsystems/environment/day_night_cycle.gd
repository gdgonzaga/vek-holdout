class_name DayNightCycle
extends Node3D
## Dynamic celestial controller managing revolving sun/moon orbits and lighting transitions.
##
## Drives a single tilted celestial pivot based on TimeSystem.get_time_of_day_fraction().
## Sun and moon are 180 degrees opposing; mutual exclusion prevents underground lighting
## leaks through the voxel terrain and eliminates duplicate shadow maps.

const _CONFIG_PATH := "res://data/game_config.tres"

var max_sun_energy: float = 1.2
var max_moon_energy: float = 0.25
var sun_color: Color = Color(1.0, 0.95, 0.85)
var sunset_color: Color = Color(1.0, 0.5, 0.2)
var moon_color: Color = Color(0.65, 0.75, 1.0)
var min_ambient_energy: float = 0.15
var max_ambient_energy: float = 1.0
var min_sky_energy: float = 0.05
var max_sky_energy: float = 1.0

@onready var _pivot: Node3D = $CelestialPivot
@onready var _sun: DirectionalLight3D = $CelestialPivot/Sun
@onready var _moon: DirectionalLight3D = $CelestialPivot/Moon
@onready var _world_env: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment


func _ready() -> void:
	# 1. Configuration: Loading celestial lighting parameters from game_config.tres.
	_load_config()

	# 2. Celestial Alignment: Configuring initial moon rotation opposing the sun across the celestial sphere.
	_setup_celestial_alignment()


func _process(_delta: float) -> void:
	var fraction: float = TimeSystem.get_time_of_day_fraction()

	# 1. Pivot Rotation: Calculating celestial angle from day fraction and applying to pivot.
	_apply_celestial_rotation(fraction)

	# 2. Celestial Update: Evaluating sun horizon elevation to modulate light energy and visibility.
	_update_celestial_bodies()

	# 3. Environment Adjustment: Modulating ambient illumination to reflect daylight transitions.
	_update_ambient_lighting()


# =============================================================================
# Auxiliary Functions (Step-Down Rule: Defined after usage)
# =============================================================================

func _load_config() -> void:
	## Auxiliary: Loads lighting parameters from game_config.tres.
	var config: GameConfig = load(_CONFIG_PATH) as GameConfig
	if config == null:
		return
	max_sun_energy = config.max_sun_energy
	max_moon_energy = config.max_moon_energy
	sun_color = config.sun_color
	sunset_color = config.sunset_color
	moon_color = config.moon_color
	min_ambient_energy = config.min_ambient_energy
	max_ambient_energy = config.max_ambient_energy
	min_sky_energy = config.min_sky_energy
	max_sky_energy = config.max_sky_energy


func _setup_celestial_alignment() -> void:
	## Auxiliary: Rotates moon by 180 degrees on X to place it directly opposite the sun.
	_moon.rotation.x = PI


func _apply_celestial_rotation(fraction: float) -> void:
	## Auxiliary: Computes orbit rotation angle and rotates the celestial pivot.
	# Convert normalized fraction [0.0, 1.0] to radians with sunrise offset.
	var angle: float = _compute_orbit_angle(fraction)
	_pivot.rotation.x = angle


func _compute_orbit_angle(fraction: float) -> float:
	## Auxiliary: Pure function converting day fraction [0.0, 1.0] to orbit pitch angle.
	## Dawn (0.0) begins at 0 rad, Midday (0.25) peaks overhead at -PI/2 rad (-90 deg).
	return -fraction * TAU


func _update_celestial_bodies() -> void:
	## Auxiliary: Updates sun and moon intensities and visibilities based on sun elevation.
	# Evaluate sun elevation angle relative to world up.
	var elevation: float = _get_sun_elevation()
	if elevation > 0.0:
		# Calculate sunlight properties for daytime.
		_activate_sun(elevation)
	else:
		# Calculate moonlight properties for nighttime.
		_activate_moon(-elevation)


func _get_sun_elevation() -> float:
	## Auxiliary: Calculates dot product of the sun's sky position vector against world UP.
	var sun_sky_dir: Vector3 = _sun.global_transform.basis.z.normalized()
	return sun_sky_dir.dot(Vector3.UP)


func _activate_sun(elevation: float) -> void:
	## Auxiliary: Sets sun active with smooth horizon intensity scaling and dusk/dawn color blending.
	_sun.visible = true
	_moon.visible = false
	var intensity: float = clampf(elevation * 3.0, 0.0, 1.0)
	_sun.light_energy = intensity * max_sun_energy
	_sun.light_color = sunset_color.lerp(sun_color, intensity)


func _activate_moon(elevation: float) -> void:
	## Auxiliary: Sets moon active with soft night intensity scaling while disabling sun.
	_sun.visible = false
	_moon.visible = true
	var intensity: float = clampf(elevation * 3.0, 0.0, 1.0)
	_moon.light_energy = intensity * max_moon_energy
	_moon.light_color = moon_color


func _update_ambient_lighting() -> void:
	## Auxiliary: Adjusts WorldEnvironment ambient and sky background energy based on sun elevation factor.
	if _world_env == null or _world_env.environment == null:
		return
	# Evaluate sun elevation angle relative to world up.
	var elevation: float = _get_sun_elevation()
	var daylight_factor: float = clampf(elevation * 2.0, 0.0, 1.0)
	_world_env.environment.ambient_light_energy = lerpf(
		min_ambient_energy, max_ambient_energy, daylight_factor
	)
	_world_env.environment.background_energy_multiplier = lerpf(
		min_sky_energy, max_sky_energy, daylight_factor
	)
