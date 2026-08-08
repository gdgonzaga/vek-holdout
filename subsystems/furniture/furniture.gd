class_name Furniture
extends Node3D
## Runtime instance of one placed furniture item (GDD §7.2). Holds a back-ref
## to its definition for static data (mesh, display_name, hp_max, etc.); only
## per-instance state lands here as subsystems are built. Placement bookkeeping
## (anchor → node maps, cell ownership) stays in FurnitureLayer.
##
## Capabilities deferred: HP/damage (§7.7), Functional Rooms counting (§7.8),
## crafting/storage/door/bed component slots (§7.9–§7.11) — none exist yet.

## Canonical def id (e.g. "workbench"). Replaces the old node.name parsing in
## FurnitureLayer.remove_at; also the save/load key once persistence lands.
@export var def_id: String = ""

## Back-ref to the definition (runtime only — not serialized). Read static
## data through this (def.hp, def.dimensions) so .tres balance changes
## propagate to already-placed instances without respawning.
var def: BuildableDef = null

## Human-readable label for menus/HUD. Computed from the def via getter so the
## UI never references def directly.
@export var label: String :
	get:
		return def.display_name if def != null else ""
