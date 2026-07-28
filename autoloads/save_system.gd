extends Node
## Autosave (sleep/midnight/quit) + load (ARCH lines 82, 236).
##
## STUB: real API surface, bodies are TODOs + push_warning. No file I/O, no
## format commitment. The autosave path is wired (day_rolled_over listener)
## even though the body is a stub, so the flow is exercisable.
##
## Deferred decisions (see TODO.md):
##  - Save-file format (JSON vs binary) — undecided.
##  - Voxel-world serialization — Zylann has its own format (Tech Debt line 206).

const _SAVE_DIR := "user://saves/"


func _ready() -> void:
	# Autosave hook: midnight/day-rollover triggers the save path (ARCH line 256).
	EventBus.day_rolled_over.connect(_on_day_rolled_over)


## Serialize run state to the current save slot. STUB.
## Per ARCH line 236: GameState (day/scene/slot), Colony (roster + job board +
## Memorial + KeyItemPool.found), voxel world, world-map reveal, player/colonist
## inventories + loadouts + raid stances.
func save_game() -> void:
	push_warning("SaveSystem.save_game(): not implemented (stub)")


## Load a save slot into live state. STUB.
func load_game(slot: String) -> void:
	push_warning("SaveSystem.load_game('%s'): not implemented (stub)" % slot)


## Enumerate available save slots. STUB.
func list_saves() -> Array:
	push_warning("SaveSystem.list_saves(): not implemented (stub)")
	return []


## True if the slot exists on disk. STUB.
func has_save(slot: String) -> bool:
	push_warning("SaveSystem.has_save('%s'): not implemented (stub)" % slot)
	return false


## Create a new save slot for a New Game. STUB. Returns the slot name.
func create_save(playthrough_name: String) -> String:
	push_warning("SaveSystem.create_save('%s'): not implemented (stub)" % playthrough_name)
	return ""


func _on_day_rolled_over(_new_day: int) -> void:
	# Autosave on midnight (and sleep, which forces midnight). Body is a stub.
	save_game()
