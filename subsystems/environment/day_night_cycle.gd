class_name DayNightCycle
extends Node3D
## Dynamic celestial controller managing revolving sun/moon orbits and lighting transitions.
##
## Drives a single tilted celestial pivot based on TimeSystem.get_time_of_day_fraction().
## Sun and moon are 180 degrees opposing; mutual exclusion prevents underground lighting
## leaks through the voxel terrain and eliminates duplicate shadow maps.

const _CONFIG_PATH := "res://data/game_config.tres"

var sun_energy: float = 1.2
var sun_direct_light_energy: float = 1.2
var moon_energy: float = 1.2
var moon_direct_light_energy: float = 0.25
var overhead_light_min_energy: float = 0.05
var overhead_light_max_energy: float = 0.4
var sun_color: Color = Color(1.0, 0.95, 0.85)
var sunset_color: Color = Color(1.0, 0.5, 0.2)
var moon_color: Color = Color(0.65, 0.75, 1.0)
var night_ambient_energy: float = 0.05
var day_ambient_energy: float = 1.0
var day_sky_top_color: Color = Color(0.38, 0.45, 0.55)
var day_sky_horizon_color: Color = Color(0.65, 0.65, 0.67)
var night_sky_top_color: Color = Color(0.01, 0.02, 0.05)
var night_sky_horizon_color: Color = Color(0.04, 0.06, 0.12)

@onready var _pivot: Node3D = $CelestialPivot
@onready var _sun: DirectionalLight3D = $CelestialPivot/Sun
@onready var _sun_sky: DirectionalLight3D = get_node_or_null("CelestialPivot/SunSky") as DirectionalLight3D
@onready var _moon: DirectionalLight3D = $CelestialPivot/Moon
@onready var _moon_sky: DirectionalLight3D = get_node_or_null("CelestialPivot/MoonSky") as DirectionalLight3D
@onready var _overhead_light: DirectionalLight3D = get_node_or_null("OverheadLight") as DirectionalLight3D
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
	sun_energy = config.sun_energy
	sun_direct_light_energy = config.sun_direct_light_energy
	moon_energy = config.moon_energy
	moon_direct_light_energy = config.moon_direct_light_energy
	overhead_light_min_energy = config.overhead_light_min_energy
	overhead_light_max_energy = config.overhead_light_max_energy
	sun_color = config.sun_color
	sunset_color = config.sunset_color
	moon_color = config.moon_color
	night_ambient_energy = config.night_ambient_energy
	day_ambient_energy = config.day_ambient_energy
	day_sky_top_color = config.day_sky_top_color
	day_sky_horizon_color = config.day_sky_horizon_color
	night_sky_top_color = config.night_sky_top_color
	night_sky_horizon_color = config.night_sky_horizon_color


func _setup_celestial_alignment() -> void:
	## Auxiliary: Rotates moon by 180 degrees on X to place it directly opposite the sun.
	_moon.rotation.x = PI
	if _moon_sky != null:
		_moon_sky.rotation.x = PI


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
	if _moon_sky != null:
		_moon_sky.visible = false
	var intensity: float = clampf(elevation * 3.0, 0.0, 1.0)
	_sun.light_energy = intensity * sun_direct_light_energy
	_sun.light_color = sunset_color.lerp(sun_color, intensity)
	if _sun_sky != null:
		_sun_sky.visible = true
		_sun_sky.light_energy = intensity * sun_energy
		_sun_sky.light_color = sunset_color.lerp(sun_color, intensity)


func _activate_moon(elevation: float) -> void:
	## Auxiliary: Sets moon active with soft night intensity scaling while disabling sun.
	_sun.visible = false
	if _sun_sky != null:
		_sun_sky.visible = false
	_moon.visible = true
	var intensity: float = clampf(elevation * 3.0, 0.0, 1.0)
	_moon.light_energy = intensity * moon_direct_light_energy
	_moon.light_color = moon_color
	if _moon_sky != null:
		_moon_sky.visible = true
		_moon_sky.light_energy = intensity * moon_energy
		_moon_sky.light_color = moon_color


func _update_ambient_lighting() -> void:
	## Auxiliary: Adjusts WorldEnvironment ambient, overhead fill, and sky background energy based on 24h elevation factor.
	if _world_env == null or _world_env.environment == null:
		return
	# Evaluate continuous 24h day factor from elevation: 1.0 at midday, 0.5 at horizon, 0.0 at midnight.
	var elevation: float = _get_sun_elevation()
	var cycle_24h_factor: float = (elevation + 1.0) * 0.5
	_world_env.environment.background_energy_multiplier = lerpf(
		night_ambient_energy, day_ambient_energy, cycle_24h_factor
	)

	# 1. Overhead Fill Update: Scaling top-down zenith light energy across the 24h orbit cycle.
	_update_overhead_light(cycle_24h_factor)

	# 2. Sky Color Transition: Smoothly interpolating ProceduralSkyMaterial colors between night and day presets.
	_update_procedural_sky_colors(cycle_24h_factor)


func _update_overhead_light(cycle_24h_factor: float) -> void:
	## Auxiliary: Modulates overhead zenith light energy between min (midnight) and max (midday).
	if _overhead_light == null:
		return
	_overhead_light.light_energy = lerpf(
		overhead_light_min_energy, overhead_light_max_energy, cycle_24h_factor
	)


func _update_procedural_sky_colors(cycle_24h_factor: float) -> void:
	## Auxiliary: Lerps sky top, horizon, and ground horizon colors of ProceduralSkyMaterial based on 24h cycle factor.
	var sky: Sky = _world_env.environment.sky
	if sky == null or not (sky.sky_material is ProceduralSkyMaterial):
		return
	var sky_mat := sky.sky_material as ProceduralSkyMaterial
	sky_mat.sky_top_color = night_sky_top_color.lerp(day_sky_top_color, cycle_24h_factor)
	var blended_horizon: Color = night_sky_horizon_color.lerp(day_sky_horizon_color, cycle_24h_factor)
	sky_mat.sky_horizon_color = blended_horizon
	sky_mat.ground_horizon_color = blended_horizon
