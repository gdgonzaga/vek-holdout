class_name LootTable
extends Resource
## Data-driven drop table. `guaranteed` always drops; every entry in `entries`
## then rolls independently (no global cap). Rolled by LootRoller.

@export var id: String = ""
## Always-dropped amounts, reusing the shared ItemAmount authoring type.
@export var guaranteed: Array[ItemAmount] = []
@export var entries: Array[LootEntry] = []
