class_name LogFeed
extends Control
## Persistent HUD tail showing the last few game-log lines, Minecraft-style.
## Mounted on the HUDLayer (layer=10) by Main, alongside hud.tscn.
##
## Behavior:
##   - Lines are fully opaque while shown (no age-based dimming).
##   - Each line disappears after `line_timeout` seconds (fade + slide off top).
##   - When a new line arrives, every existing line slides up by one slot; if
##     the feed is full the oldest is pushed off the top (fade + slide).
##
## Layout is index-based: _lines[0] is the newest and sits at the bottom;
## higher indices stack upward. Arrival does push_front (indices shift up →
## slide-up); removal (timeout/overflow) drops a line without re-indexing the
## rest (survivors keep their slots, only the leaving line animates out).
##
## Purely reactive to GameLog.entry_added — holds no gameplay state.

@export var font_size: int = 14
@export var line_height: int = 20
@export var line_separation: int = 2
@export var feed_width: int = 400
@export var margin_left: int = 16
@export var margin_bottom: int = 16
## Seconds a line stays fully visible before fading out. <= 0 disables timeout.
@export var line_timeout: float = 6.0
@export var slide_duration: float = 0.25
@export var fade_duration: float = 0.4


class _Line:
	extends RefCounted
	var label: RichTextLabel
	var spawn_time: float
	func _init(p_label: RichTextLabel, p_time: float) -> void:
		label = p_label
		spawn_time = p_time


var _lines: Array[_Line] = []     # newest at index 0 (bottom)
var _exiting: Array[_Line] = []   # lines animating out; not counted toward cap


func _ready() -> void:
	GameLog.entry_added.connect(_on_entry_added)
	# Late mount: repopulate from existing history without animation. recent()
	# returns oldest->newest; pushing in that order leaves newest at index 0.
	for entry in GameLog.recent(GameLog.tail_lines):
		_spawn(entry, false)
	_layout(false)


func _notification(what: int) -> void:
	# Keep positions correct when the viewport resizes.
	if what == NOTIFICATION_RESIZED:
		_layout(false)


func _process(_delta: float) -> void:
	if line_timeout <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var expired := false
	# Oldest first (highest index). Removing from the top leaves survivors'
	# indices unchanged, so they don't slide — only the expired line fades out.
	for i in range(_lines.size() - 1, -1, -1):
		if now - _lines[i].spawn_time >= line_timeout:
			_exit(_lines[i])
			_lines.remove_at(i)
			expired = true
	if expired:
		_layout(true)


func _on_entry_added(entry: LogEntry) -> void:
	_spawn(entry, true)


## Instantiate a line for an entry. animate=false is used for the initial
## repopulate (no tween — just place it).
func _spawn(entry: LogEntry, animate: bool) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = GameLog.bbcode(entry)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_contents = true
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	add_child(label)
	label.size = Vector2(feed_width, line_height)
	label.position.x = float(margin_left)

	var line := _Line.new(label, Time.get_ticks_msec() / 1000.0)
	_lines.push_front(line)

	if animate:
		# Fade/slide the new line in at the bottom slot from one slot below.
		label.modulate.a = 0.0
		label.position.y = _target_y(0) + float(line_height)
		var enter := create_tween()
		enter.set_parallel(true)
		enter.tween_property(label, "modulate:a", 1.0, fade_duration)
		enter.tween_property(label, "position:y", _target_y(0), slide_duration) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		# Slide everyone else up by one slot (skip the new line — it has its
		# own tween).
		_layout(true, line)
		# Enforce the visible cap: push the oldest off the top.
		while _lines.size() > _max_visible():
			_exit(_lines.pop_back())
	else:
		label.position.y = _target_y(0)
		label.modulate.a = 1.0


## Tween (or snap) every active line to its index-based target Y. `skip` is
## excluded — used for the freshly spawned line which animates itself.
func _layout(animate: bool, skip: _Line = null) -> void:
	for i in _lines.size():
		var line: _Line = _lines[i]
		if line == skip:
			continue
		var ty := _target_y(i)
		if animate:
			var tween := create_tween()
			tween.tween_property(line.label, "position:y", ty, slide_duration) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			line.label.position.y = ty


## Top-left Y for the line at `index` (0 = newest = bottom).
func _target_y(index: int) -> float:
	var bottom := size.y - float(margin_bottom)
	return bottom - float(index + 1) * float(line_height) \
			- float(index) * float(line_separation)


## Animate a line out: fade to transparent while sliding up off the top, then
## free it. The line is tracked in _exiting until its tween completes.
func _exit(line: _Line) -> void:
	if line == null:
		return
	_exiting.append(line)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(line.label, "modulate:a", 0.0, fade_duration)
	tween.tween_property(line.label, "position:y",
			line.label.position.y - float(line_height), fade_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_on_exit_finished.bind(line))


func _on_exit_finished(line: _Line) -> void:
	if is_instance_valid(line.label):
		line.label.queue_free()
	_exiting.erase(line)


func _max_visible() -> int:
	return GameLog.tail_lines
