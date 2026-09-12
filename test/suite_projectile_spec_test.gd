extends GdUnitTestSuite

## Unit tests for ProjectileSpec — the actor-agnostic runtime parameter bundle
## Projectile.setup() consumes, built from either TurretParams or
## RangedActionParams so both share one flying-projectile implementation.

const TurretParamsScript = preload("res://data/capability_params/turret_params.gd")
const RangedActionParamsScript = preload("res://data/capability_params/ranged_action_params.gd")
const ProjectileSpecScript = preload("res://subsystems/combat/components/projectile_spec.gd")


func test_from_turret_params_copies_fields() -> void:
	var params := TurretParamsScript.new() as TurretParams
	auto_free(params)
	params.projectile_speed = 30.0
	params.damage = 25
	params.projectile_type = TurretParams.ProjectileType.EXPLOSIVE
	params.explosion_radius = 4.5
	params.projectile_mesh = BoxMesh.new()
	params.enable_projectile_trail = false
	params.enable_explosion_particles = false

	var spec := ProjectileSpecScript.from_turret_params(params)

	assert_float(spec.speed).is_equal(30.0)
	assert_int(spec.damage).is_equal(25)
	assert_int(spec.kind).is_equal(ProjectileSpecScript.Kind.EXPLOSIVE)
	assert_float(spec.explosion_radius).is_equal(4.5)
	assert_object(spec.visual_mesh).is_equal(params.projectile_mesh)
	assert_bool(spec.enable_trail).is_false()
	assert_bool(spec.enable_explosion_particles).is_false()


func test_from_turret_params_falls_back_to_ammo_visual() -> void:
	var params := TurretParamsScript.new() as TurretParams
	auto_free(params)
	var ammo := ItemDef.new()
	auto_free(ammo)
	ammo.mesh = BoxMesh.new()
	params.ammo_type = ammo
	params.projectile_mesh = null
	params.projectile_scene = null

	var spec := ProjectileSpecScript.from_turret_params(params)

	assert_object(spec.visual_mesh).is_equal(ammo.mesh)


func test_from_ranged_action_copies_fields() -> void:
	var params := RangedActionParamsScript.new() as RangedActionParams
	auto_free(params)
	params.damage = 45.0
	params.projectile_speed = 20.0
	params.projectile_type = ProjectileSpecScript.Kind.EXPLOSIVE
	params.explosion_radius = 2.0
	params.projectile_mesh = BoxMesh.new()

	var spec := ProjectileSpecScript.from_ranged_action(params)

	assert_int(spec.damage).is_equal(45)
	assert_float(spec.speed).is_equal(20.0)
	assert_int(spec.kind).is_equal(ProjectileSpecScript.Kind.EXPLOSIVE)
	assert_float(spec.explosion_radius).is_equal(2.0)
	assert_object(spec.visual_mesh).is_equal(params.projectile_mesh)
