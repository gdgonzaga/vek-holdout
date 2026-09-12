class_name ProjectileSpec
extends RefCounted
## Actor-agnostic runtime parameter bundle for Projectile.setup() (ARCH combat.md).
## Built by whichever weapon schema is firing (TurretParams or RangedActionParams)
## so Projectile itself never needs to know about either authoring schema.

enum Kind {
	REGULAR,
	EXPLOSIVE,
}

var speed: float = 25.0
var damage: int = 10
var kind: int = Kind.REGULAR
var explosion_radius: float = 3.0
var visual_scene: PackedScene = null
var visual_mesh: Mesh = null
var visual_material: Material = null
var enable_trail: bool = true
var enable_explosion_particles: bool = true
var explosion_particle_scene: PackedScene = null


## Builds a spec from a turret's authored capability params, reproducing the
## ammo-visual fallback (adopt the ammo ItemDef's own visual when the turret
## defines none) that previously lived inline in Projectile.setup().
static func from_turret_params(params: TurretParams) -> ProjectileSpec:
	var spec := ProjectileSpec.new()
	spec.speed = params.projectile_speed
	spec.damage = params.damage
	spec.kind = params.projectile_type
	spec.explosion_radius = params.explosion_radius
	spec.visual_scene = params.projectile_scene
	spec.visual_mesh = params.projectile_mesh
	spec.visual_material = params.projectile_material
	# 1. Ammo Visual Fallback: adopt the ammo ItemDef's own visual if the turret defines none.
	if spec.visual_scene == null and spec.visual_mesh == null and params.ammo_type != null:
		spec.visual_scene = params.ammo_type.scene
		spec.visual_mesh = params.ammo_type.mesh
		if spec.visual_material == null:
			spec.visual_material = params.ammo_type.material
	spec.enable_trail = params.enable_projectile_trail
	spec.enable_explosion_particles = params.enable_explosion_particles
	spec.explosion_particle_scene = params.explosion_particle_scene
	return spec


## Builds a spec from a hand-fired weapon's ranged action params.
static func from_ranged_action(params: RangedActionParams) -> ProjectileSpec:
	var spec := ProjectileSpec.new()
	spec.speed = params.projectile_speed
	spec.damage = int(params.damage)
	spec.kind = params.projectile_type
	spec.explosion_radius = params.explosion_radius
	spec.visual_scene = params.projectile_scene
	spec.visual_mesh = params.projectile_mesh
	spec.visual_material = params.projectile_material
	spec.enable_trail = params.enable_projectile_trail
	spec.enable_explosion_particles = params.enable_explosion_particles
	return spec
