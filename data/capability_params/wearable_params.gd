class_name WearableParams
extends Resource
## Capability parameters for wearable equipment (armor, clothes, hats, shoes).
##
## Attached to an ItemDef via ItemDef.wearable following the composition pattern
## documented in AGENTS.md. Slot eligibility remains tag-based via ItemDef.tags.
## ARCH: equipment.md.
##
## Supports two visualization modes (or a combination):
## - skinned_scene: A garment PackedScene (.glb) exported against the humanoid
##   Mixamo armature and imported with the same SkeletonProfileHumanoid BoneMap.
##   Its skinned meshes are reparented directly under the character's Skeleton3D.
## - rigid_parts: Array of WearablePart resources, each attaching a rigid mesh
##   to an auto-created "WearBone_<bone>" BoneAttachment3D on the skeleton.

@export var skinned_scene: PackedScene = null
@export var rigid_parts: Array[WearablePart] = []
