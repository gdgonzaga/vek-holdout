class_name TurretParams
extends Resource
## Capability parameters for automated turret defenses (GDD §7.10, ARCH combat.md).
## A nullable sub-resource on FurnitureDef, following the composition pattern.
## Placed furniture with non-null turret_params receives a TurretComponent child
## attached by FurnitureLayer.

enum ProjectileType {
	REGULAR,
	EXPLOSIVE,
}

## Maximum targeting and firing range in meters.
@export var range: float = 15.0

## Fire rate in shots per second (e.g. 1.0 = 1 shot/sec, 0.2 = 1 shot every 5s).
@export var fire_rate: float = 1.0

## Direct hit or base damage dealt to targets.
@export var damage: int = 10

## Required ammo ItemDef. If null, turret fires freely without ammo consumption.
@export var ammo_type: ItemDef = null

@export_group("Projectile")
## 3D visual mesh rendered on the moving projectile. If null, falls back to a default shape.
@export var projectile_mesh: Mesh = null

## Optional material override for the projectile mesh.
@export var projectile_material: Material = null

## Travel speed in meters per second.
@export var projectile_speed: float = 25.0

## Projectile damage behavior (single-target direct hit vs AoE splash).
@export var projectile_type: ProjectileType = ProjectileType.REGULAR

## Splash radius in meters for EXPLOSIVE projectile type.
@export var explosion_radius: float = 3.0
