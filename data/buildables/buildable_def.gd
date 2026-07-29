extends Resource
class_name BuildableDef
## Base definition for everything the player can build: voxel blocks (walls,
## floors) and free-standing furniture/structures. Subclasses add kind-specific
## concerns — BlockDef adds `is_terrain` for the voxel grid; a future FurnitureDef
## would add footprint/scene.
##
## `id` is the canonical identifier across all buildable kinds (inherited by
## subclasses; do not redeclare as block_id/furniture_id/etc.). `mesh` lives here
## so the build ghost can preview any buildable's shape, not just voxel blocks.
##
## Fields kept out: material-tier (targeting is HP-derived, GDD §17) and
## construction-time-modifier (build time = HP × tool, GDD §7.4).

@export var id: String                             # e.g. "wood", "wall_stone", "workbench"
@export var display_name: String                   # UI label
@export var hp: int                                # Durability-before-HP buffer (GDD §6.11)
@export var mesh: Mesh                             # Preview/placement mesh; voxel blocks MUST occupy (0,0,0)->(1,1,1)
@export var material_cost: Dictionary = {}         # resource_id (String) -> count (int), e.g. {"wood": 3}
@export var unlocked_by_default: bool = false      # available without earning an unlock this run


## resource_id -> count, typed for callers that want a stable read.
func get_cost() -> Dictionary:
	return material_cost


func get_cost_of(resource_id: String) -> int:
	return int(material_cost.get(resource_id, 0))
