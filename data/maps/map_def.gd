extends Resource
class_name MapDef
## Loadable map/environment definition. Scanned from data/maps/*.tres by
## MapLibrary. Points to a World .tscn and carries metadata used by SceneManager
## and ExpeditionManager.
##
## Maps are hybrid: .tscn for visual layout + nodes, .tres (this resource) for
## metadata + spawn config. The scene is the runtime contract; the def is the
## catalog entry that picks which scene to load and where the player/enemies go.

enum MapType { BASE, POI, BUILDING, TOWN }

@export var id: String
@export var display_name: String
@export var description: String
@export var scene_path: String                    # -> the World .tscn
@export var map_type: MapType = MapType.BASE
@export var player_spawn: Vector3 = Vector3(0, 5, 0)   # 5 up to land on flat ground
@export var enemy_spawns: Array[Dictionary] = []  # [{ "pos": Vector3, "count": int }]
@export var unlock_condition: String = ""
@export var difficulty: int = 1
