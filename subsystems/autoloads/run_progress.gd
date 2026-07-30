extends Node
## Run-scoped accumulated state (ARCH Tech Debt line 151; renamed from RunState).
## Holds what the player has EARNED this run — currently just buildable unlocks.
## Saved with the run; wiped on New Game.
##
## Deliberately a "dumb bag": it holds ids, nothing more. It does NOT read the
## data definitions — BuildLibrary (or other seeders) push defaults into it, and
## unlock sources (items/skills/quests, later) push earned ids. It does NOT
## listen to lifecycle signals — the New Game orchestrator calls
## reset_for_new_game() directly, then emits EventBus.run_started so seeders can
## re-add defaults (additive only). This keeps reset ordering race-free.
##
## No class_name: it's an autoload singleton, globally accessible as RunProgress.

signal buildable_unlocked(id: String)

var _unlocked: Dictionary = {}   # id (String) -> true (set semantics)


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


## Add an earned unlock. Idempotent — re-adding an existing id is a no-op (so
## seeders can run repeatedly without duplicating). Emits buildable_unlocked on change.
func unlock(id: String) -> void:
	if not _unlocked.has(id):
		_unlocked[id] = true
		buildable_unlocked.emit(id)


# --- SaveSystem contract (called once SaveSystem is real) ---------------------

func serialize() -> Dictionary:
	return {"unlocked": _unlocked.keys()}


func deserialize(data: Dictionary) -> void:
	_unlocked.clear()
	for id in data.get("unlocked", []):
		_unlocked[id] = true


## Clear all earned state. Called by the New Game orchestrator BEFORE it emits
## run_started (seeders re-add defaults on that signal). Not signal-driven itself.
func reset_for_new_game() -> void:
	_unlocked.clear()
