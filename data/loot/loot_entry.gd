class_name LootEntry
extends Resource
## One independently rolled drop in a LootTable. The entry first rolls `chance`;
## on success it drops a uniform count in [min_count, max_count]. Several entries
## for the same item stack, so a rare bonus entry can sit on top of a common one.

@export var item_def: ItemDef
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
@export var min_count: int = 1
@export var max_count: int = 1
