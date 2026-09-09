class_name LightParams
extends Resource
## Capability parameters for furniture that emits light (GDD §7.2, ARCH data-schemas.md).
## A nullable sub-resource on FurnitureDef, following the composition pattern.
## Placed furniture with non-null light_params receives a LightSourceComponent child
## attached by FurnitureLayer.

## Emission color of the light source.
@export var color: Color = Color(1.0, 0.9, 0.7, 1.0)

## Light intensity energy value.
@export var energy: float = 1.5

## Maximum illumination radius in meters.
@export var range: float = 8.0

## Light attenuation factor determining falloff curve.
@export var attenuation: float = 1.0

## Whether this light casts shadows. Keep false by default for performance.
@export var shadows_enabled: bool = false

## Local position offset relative to the furniture root origin where the light is placed.
@export var local_offset: Vector3 = Vector3(0.0, 1.5, 0.0)
