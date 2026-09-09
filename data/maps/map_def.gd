extends Resource
class_name MapDef
## Loadable map/environment definition. Scanned from data/maps/*/map_def.tres by
## MapLibrary. Points to a Map .tscn and carries metadata used by SceneManager
## and ExpeditionManager.
##
## Maps are hybrid: .tscn for visual layout + nodes, .tres (this resource) for
## metadata + spawn config. The scene is the runtime contract; the def is the
## catalog entry that picks which scene to load and where the player/enemies go.

enum MapType { BASE, POI, BUILDING, TOWN }

@export var id: String
@export var display_name: String
@export var description: String
@export var scene_path: String                    # -> the Map .tscn
@export var map_type: MapType = MapType.BASE
@export var player_spawn: Vector3 = Vector3(0, 5, 0)   # 5 up to land on flat ground
@export var enemy_spawns: Array[Dictionary] = []  # [{ "pos": Vector3, "count": int }]
@export var unlock_condition: String = ""
@export var difficulty: int = 1

## Bounding box defining the discrete playable colony volume.
## Bounds outside this box will not generate, mesh, or be pathfindable.
## Default is 192m (X) x 64m (Y) x 192m (Z), centered at X/Z: 0, with Y ranging from -48 to +16.
@export var world_bounds: AABB = AABB(Vector3(-96.0, -48.0, -96.0), Vector3(192.0, 64.0, 192.0))

## Natural (smooth) terrain parameters; null = the map has no smooth terrain
## and any SmoothGrid node in its scene frees itself at _ready (dual-voxel
## conversion, docs/TODO.md D2). SceneManager injects this into the SmoothGrid
## before the map enters the tree.
@export var terrain_gen: TerrainGenDef = null

## Authoring metadata for the Map Editor: whether water flooding was enabled on creation.
@export var water_enabled: bool = false

## Authoring metadata for the Map Editor: baseline water height in meters (Y axis).
@export var water_level: float = -2.0

# ==========================================
# Flora & Vegetation Regeneration Parameters
# ==========================================
## Flora definitions available to spawn dynamically on this map.
@export var flora_palette: Array[FurnitureDef] = []

## Total number of plants/trees to attempt spawning across an in-game day (0 = disabled).
@export var flora_spawns_per_day: int = 0

## Maximum number of alive flora items allowed on the map simultaneously.
@export var flora_spawn_cap: int = 60

## Maximum random placement attempts per spawn cycle to find valid soil before skipping.
@export var flora_max_spawn_attempts: int = 15

## Minimum distance in meters between spawned flora and existing trees or player spawn.
@export var flora_min_distance: float = 4.0


func get_horizontal_size() -> Vector2:
	return Vector2(world_bounds.size.x, world_bounds.size.z)


func get_depth() -> float:
	return -world_bounds.position.y


func get_ceiling() -> float:
	return world_bounds.position.y + world_bounds.size.y
