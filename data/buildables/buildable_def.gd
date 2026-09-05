extends Resource
class_name BuildableDef
## Base definition for everything the player can build: voxel blocks (walls,
## floors) and free-standing furniture/structures. Subclasses add kind-specific
## concerns — BlockDef adds rotational symmetry; FurnitureDef adds dimensions.
##
## `id` is the canonical identifier across all buildable kinds (inherited by
## subclasses; do not redeclare as block_id/furniture_id/etc.). `scene` and `mesh`
## live here so the build ghost, voxel mesher, and furniture layers can preview
## and instantiate any buildable's shape.
## `texture` is the albedo only — BlockLibrary builds a StandardMaterial3D from
## it (no separate material .tres per block type); the furniture authoring path
## does the same inline (see furniture_authoring.gd). Do NOT add a build_material()
## helper to this class and call it from @tool code: editor tool-script instances
## loaded from .tres bind to stale compiled bytecode after a script edit, so
## has_method() returns true but the call throws — access `texture` directly.
## `texture_variation` opts into a per-block randomization shader that offsets UVs,
## rotates them, and modulates brightness so repeating textures don't tile visibly.
## (Block-only: the shader hashes `floor(world_pos+0.5)`, which assumes unit-cube
## voxel blocks, so it is handled in BlockLibrary, not the furniture path.)
##
## Fields kept out: material-tier (targeting is HP-derived, GDD §17) and
## construction-time-modifier (build time = HP × tool, GDD §7.4).

@export var id: String # e.g. "wood", "wall_stone", "workbench"
@export var display_name: String # UI label
@export var icon: Texture2D = null # UI icon for the build menu (nullable; entry renders without it)
@export var hp: int # Durability-before-HP buffer (GDD §6.11)
## Primary 3D visual scene (e.g. .glb or .tscn). When provided, furniture layers,
## blueprint holograms, and ghost previews use this scene directly. For voxel blocks,
## BlockLibrary/VoxelLibraryGenerator extracts the underlying Mesh automatically.
@export var scene: PackedScene = null
@export var mesh: Mesh # Preview/placement mesh; voxel blocks MUST occupy (0,0,0)->(1,1,1)
@export var texture: Texture2D # Albedo texture; BlockLibrary builds a StandardMaterial3D from this
@export var texture_variation: bool = false # True → use per-block UV/brightness randomization shader
@export var material_cost: Array[ItemAmount] = []
@export var unlocked_by_default: bool = false # available without earning an unlock this run
@export var build_time: float = 0.0
@export var tags: Array[String] = []

var _cached_mesh: Mesh = null


## Returns the effective Mesh resource for this buildable: either the explicitly
## assigned `mesh`, or extracted from the first MeshInstance3D in `scene` if `mesh` is null.
func get_mesh() -> Mesh:
	if mesh != null:
		return mesh
	if _cached_mesh != null:
		return _cached_mesh
	if scene != null:
		var root := scene.instantiate()
		if root != null:
			var stack: Array[Node] = [root]
			while not stack.is_empty():
				var curr: Node = stack.pop_back()
				if curr is MeshInstance3D and (curr as MeshInstance3D).mesh != null:
					_cached_mesh = (curr as MeshInstance3D).mesh
					break
				for child in curr.get_children():
					stack.append(child)
			root.free()
			return _cached_mesh
	return null
