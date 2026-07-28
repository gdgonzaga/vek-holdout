extends Resource
class_name BlockDef
## One buildable block type (GDD §7.2). Schema: docs/ARCHITECTURE.md "data/blocks/<type>.tres".
##
## Enemy targeting is HP-derived, not tier-based (GDD §17), so there is no
## material-tier field. Build time is a pure function of HP × tool (GDD §7.4),
## so there is no per-block construction-time-modifier field either.

@export var block_id: String                       # e.g. "wood", "scrap", "stone", "metal", "reinforced", "terrain"
@export var display_name: String                   # UI label
@export var hp: int                                # 50/100/300/600/1200 for buildables; terrain uses a large/infinite sentinel
@export var mesh: Mesh                             # Blocky-mode model — MUST occupy local (0,0,0)->(1,1,1) for the fast mesher path
@export var material_cost: Dictionary = {}         # resource_id (String) -> count (int), e.g. {"wood": 3}

## True for the non-buildable world ground (VoxelGeneratorFlat output). Skips
## build-cost validation and is not a valid build target.
@export var is_terrain: bool = false

## Resource path -> count, typed for callers that want a stable read.
func get_cost() -> Dictionary:
	return material_cost

func get_cost_of(resource_id: String) -> int:
	return int(material_cost.get(resource_id, 0))
