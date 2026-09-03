extends BuildableDef
class_name FurnitureDef
## Free-standing buildable (GDD §7.2) — stations (Workbench, Forge, Clinic Bed),
## beds, doors, and larger structures like posts. Distinct from BlockDef: furniture
## is authored with a 3D dimensions cell-box and (eventually) its own Node3D scene
## rather than a single unit-cube voxel. Schema: docs/architecture/data-schemas.md
## (FurnitureDef); Functional Rooms C1 tracking in docs/architecture/tech-debt.md.
##
## Inherits id/display_name/hp/mesh/material_cost/unlocked_by_default from
## BuildableDef. `mesh` is the ghost-preview shape (same as blocks); it does not
## need to fill the dimensions.
##
## Deferred: a capability-unlocking field (working name base_system) so Colony can
## count placed furniture toward Functional Rooms (GDD §7.8). Not on this class
## yet — added when the Colony counting surface is built. `dimensions` is
## consumed now: FurnitureLayer.footprint_cells reads it for placement validity,
## positioning, and rotation.

## Cell-box the item occupies, in cells: x=width, y=height, z=depth
## (GDD §7.2's Height/Width/Depth columns). Default 1x1x1.
## Rotation (R) swaps x/z (the floor plane); y is vertical and unchanged.
## Even-sized x or z shift the placement pivot 0.5m (GDD §7.4).
@export var dimensions: Vector3i = Vector3i.ONE

## Interaction options offered when the player points at this furniture and
## presses E. Each entry is an ActionOption resource (data/action_options/*.tres)
## referencing a GameAction plus optional Conditions. FurnitureLayer copies these
## onto the spawned furniture's InteractionComponent (auto-appending harvest/crop
## options for harvest_params/farm_plot_params defs), so empty (the default)
## means non-interactable — unless those params are set. BlockDef intentionally
## has no equivalent — voxel blocks resolve through the voxel grid, not as
## Node3D instances.
@export var action_options: Array[ActionOption] = []

## Composition-pattern placeholder for capability-specific parameters (crafting
## speed, tier, etc.). Null means no capability data. Real capabilities
## (CraftingParams, ItemDispenserParams, StorageParams, ...) are sibling
## nullable sub-resources of the same shape; see
## docs/architecture/data-schemas.md "FurnitureDef capability parameters" for
## why composition was chosen over subclassing.
@export var test_params: TestParams
@export var item_dispenser_params: ItemDispenserParams
@export var storage_params: StorageParams

## Crafting capability (GDD §7.9): the recipes this station offers. Non-null →
## FurnitureLayer attaches a CraftingStation child (which implements
## MaterialSink from the active order's inputs, so hauling can supply it).
@export var crafting_params: CraftingParams

## Harvesting capability (GDD §6.10): the yields and work time for harvesting this
## node. Non-null → FurnitureLayer attaches a Harvestable child component.
@export var harvest_params: HarvestParams

## Farming capability (GDD §7.2 / Farming): non-null → FurnitureLayer
## attaches Growable and Harvestable child components.
@export var farm_plot_params: FarmPlotParams

## Turret combat capability (GDD §7.10, ARCH combat.md): automated defense that
## targets hostiles and consumes ammunition. Non-null → FurnitureLayer attaches a
## TurretComponent child.
@export var turret_params: TurretParams
