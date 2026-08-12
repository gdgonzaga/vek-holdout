extends Node
## GameLog autoload. Single owner of the game log history. Gameplay code calls
## GameLog.log(...) to announce things that should appear as on-screen text
## (Minecraft-style). The UI (LogFeed tail + LogHistory scrollback) subscribes
## to entry_added and renders from the ring buffer held here.
##
## Decouples producers (gameplay, EventBus) from consumers (UI). History
## survives UI reloads and is queryable by the future debug console / day
## summary.

signal entry_added(entry: LogEntry)

# Category -> BBCode hex color, used by the UI to colorize lines.
const COLORS: Dictionary = {
	LogEntry.Category.INFO:   "#ffffff",
	LogEntry.Category.COMBAT: "#ff7d7d",
	LogEntry.Category.SYSTEM: "#7dcdff",
	LogEntry.Category.CRAFT:  "#ffd24a",
	LogEntry.Category.COLONY: "#7dff9a",
}

@export var max_entries: int = 200
@export var tail_lines: int = 6

var _buffer: Array[LogEntry] = []


func _ready() -> void:
	# Auto-subscribe to high-value EventBus signals so the feed is usable
	# without wiring every producer. Gameplay code can also call
	# GameLog.log(...) directly for finer-grained messages.
	EventBus.colonist_died.connect(_on_colonist_died)
	EventBus.day_rolled_over.connect(_on_day_rolled_over)
	EventBus.expedition_started.connect(_on_expedition_started)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.furniture_placed.connect(_on_furniture_placed)
	EventBus.furniture_removed.connect(_on_furniture_removed)
	EventBus.raid_started.connect(_on_raid_started)
	EventBus.raid_ended.connect(_on_raid_ended)
	EventBus.run_started.connect(_on_run_started)


# --- Primary API ---------------------------------------------------------

## Main entry point. Gameplay code calls GameLog.log("...", LogEntry.Category.X).
func log(message: String, category: int = LogEntry.Category.INFO) -> void:
	var entry := LogEntry.new(message, category)
	_buffer.append(entry)
	while _buffer.size() > max_entries:
		_buffer.pop_front()
	entry_added.emit(entry)


func info(message: String) -> void:
	self.log(message, LogEntry.Category.INFO)


func combat(message: String) -> void:
	self.log(message, LogEntry.Category.COMBAT)


func system(message: String) -> void:
	self.log(message, LogEntry.Category.SYSTEM)


func craft(message: String) -> void:
	self.log(message, LogEntry.Category.CRAFT)


func colony(message: String) -> void:
	self.log(message, LogEntry.Category.COLONY)


## Full history, oldest -> newest. LogHistory reads this on open.
func get_entries() -> Array[LogEntry]:
	return _buffer.duplicate()


## Last N entries, oldest -> newest of the slice. LogFeed reads this on mount.
func recent(count: int) -> Array[LogEntry]:
	if _buffer.size() <= count:
		return _buffer.duplicate()
	return _buffer.slice(_buffer.size() - count)


func clear() -> void:
	_buffer.clear()


# --- BBCode helper -------------------------------------------------------

## Returns entry.text wrapped in a [color=...] tag matching its category.
## Used by both LogFeed and LogHistory so coloring is defined in one place.
static func bbcode(entry: LogEntry) -> String:
	var hex: String = COLORS.get(entry.category, COLORS[LogEntry.Category.INFO])
	return "[color=%s]%s[/color]" % [hex, entry.text]


# --- EventBus auto-subscriptions -----------------------------------------

func _on_colonist_died(colonist_id: String) -> void:
	colony("%s has died" % colonist_id)


func _on_day_rolled_over(new_day: int) -> void:
	system("Day %d begins" % new_day)


func _on_expedition_started(_crew: Array, poi_id: String) -> void:
	system("Expedition departed for %s" % poi_id)


func _on_expedition_ended(_result: Dictionary) -> void:
	# Result schema is TBD (ExpeditionManager is a scaffold emitting an empty
	# dict). Refine the message once the result shape is defined.
	system("Expedition returned.")


func _on_furniture_placed(def_id: String, _anchor: Vector3i) -> void:
	info("Built %s" % def_id)


func _on_furniture_removed(def_id: String, _anchor: Vector3i) -> void:
	info("Removed %s" % def_id)


func _on_raid_started(_raid_data: Dictionary) -> void:
	combat("A raid has begun!")


func _on_raid_ended(outcome: Dictionary) -> void:
	var survived: bool = outcome.get("survived", true)
	if survived:
		combat("Raid repelled.")
	else:
		combat("Raid overrun.")


func _on_run_started() -> void:
	clear()


# --- SaveSystem contract -----------------------------------------------------
# The log history ring buffer. LogEntry.timestamp is engine-uptime (transient),
# so only text/category/day are persisted. Restored entries are appended to
# _buffer WITHOUT emitting entry_added — the UI reads get_entries()/recent() on
# mount, so re-emitting would only flood live listeners during a load.

func serialize() -> Dictionary:
	var entries: Array = []
	for e in _buffer:
		entries.append({"text": e.text, "category": e.category, "day": e.day})
	return {"entries": entries}


func deserialize(data: Dictionary) -> void:
	clear()
	for rec in data.get("entries", []):
		var entry := LogEntry.new(
			String(rec.get("text", "")),
			int(rec.get("category", LogEntry.Category.INFO)))
		entry.day = int(rec.get("day", 1))
		_buffer.append(entry)
