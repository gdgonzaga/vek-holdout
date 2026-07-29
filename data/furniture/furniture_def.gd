extends BuildableDef
class_name FurnitureDef
## Free-standing buildable (GDD §7.2) — stations (Workbench, Forge, Clinic Bed),
## beds, doors, and larger structures like posts. Distinct from BlockDef: furniture
## is authored with a 3D dimensions cell-box and (eventually) its own Node3D scene
## rather than a single unit-cube voxel. Schema: docs/ARCHITECTURE.md Functional
## Rooms C1 ("data/furniture/").
##
## Inherits id/display_name/hp/mesh/material_cost/unlocked_by_default from
## BuildableDef. `mesh` is the ghost-preview shape (same as blocks); it does not
## need to fill the dimensions.
##
## Deferred: a capability-unlocking field (working name base_system) so Colony can
## count placed furniture toward Functional Rooms (GDD §7.8). Not on this class
## yet — added when the Colony counting surface is built. Dimensions alone is
## enough for the catalog/preview pass.

## Cell-box the item occupies, in cells: x=width, y=height, z=depth
## (GDD §7.2's Height/Width/Depth columns). Default 1x1x1.
## Rotation (R) swaps x/z (the floor plane); y is vertical and unchanged.
## Even-sized x or z shift the placement pivot 0.5m (GDD §7.4).
@export var dimensions: Vector3i = Vector3i.ONE
