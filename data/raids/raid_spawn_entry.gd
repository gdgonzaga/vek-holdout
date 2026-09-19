class_name RaidSpawnEntry
extends Resource
## One weighted enemy option in a night raid's spawn pool (ARCH raids.md).
## GameConfig.enemy_pool holds these; NightRaidController performs weighted
## random selection over them per spawn.

@export var enemy_scene: PackedScene
@export var weight: float = 1.0
