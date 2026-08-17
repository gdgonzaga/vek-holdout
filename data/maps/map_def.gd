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

## Natural (smooth) terrain parameters; null = the map has no smooth terrain
## and any SmoothGrid node in its scene frees itself at _ready (dual-voxel
## conversion, docs/TODO.md D2). SceneManager injects this into the SmoothGrid
## before the map enters the tree.
@export var terrain_gen: TerrainGenDef = null
