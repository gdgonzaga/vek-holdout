class_name WearablePart
extends Resource
## Defines a rigid mesh piece for a wearable item (ARCH: equipment.md).
##
## Attached to a specific humanoid bone via an auto-created BoneAttachment3D
## named "WearBone_<bone>". Used for rigid gear like helmets, pauldrons,
## shoes, or primitive prototype garments.

@export var bone: StringName = &""
@export var mesh: Mesh = null
@export var material: Material = null
@export var offset: Transform3D = Transform3D.IDENTITY
