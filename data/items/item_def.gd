class_name ItemDef
extends Resource

@export var id: String = ""
@export var weight: float = 0.0
@export var icon: Texture2D = null
## Loose categorization tags (e.g. ["tool", "axe"]). Read via
## Inventory.has_item_tag; the "tool" tag marks carried tools that job cleanup
## (HaulingJobDef.on_end's surplus dump) must leave with the colonist. Author
## tools with a small weight so one doesn't clog the carry capacity.
@export var tags: Array[String] = []
