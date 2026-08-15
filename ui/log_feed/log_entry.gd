class_name LogEntry
extends RefCounted
## One immutable line in the game log. Held by GameLog's ring buffer and passed
## to LogFeed / LogHistory for rendering. Cheap (RefCounted, no Node overhead).

enum Category {INFO, COMBAT, SYSTEM, CRAFT, COLONY, DEBUG}

var text: String
var category: int = Category.INFO
var day: int = 1
var timestamp: float = 0.0


func _init(p_text: String = "", p_category: int = Category.INFO) -> void:
	text = p_text
	category = p_category
	timestamp = Time.get_ticks_msec() / 1000.0
	# GameState is an autoload that initializes before GameLog, so it is always
	# valid here. Guard keeps unit tests (no autoloads) from crashing.
	if GameState != null:
		day = GameState.current_day
