class_name LogHistory
extends Control
## Full-screen scrollback of the game log. Opened via the `log_history` input
## key (toggle) handled in LogFeed, which calls SceneManager.open_screen(...).
## Dismissed by the Close button, the toggle key, or Esc (via Main's
## _unhandled_input).
##
## Live-appends new entries while open via GameLog.entry_added.

signal closed()

@onready var _content: RichTextLabel = %Content
@onready var _close_btn: Button = %CloseButton


func _ready() -> void:
	# Populate from existing history, then subscribe for live appends.
	_rebuild_all()
	GameLog.entry_added.connect(_on_entry_added)
	_close_btn.pressed.connect(_on_close_pressed)


func append_live(entry: LogEntry) -> void:
	_on_entry_added(entry)


func _on_entry_added(entry: LogEntry) -> void:
	_content.append_text(GameLog.bbcode(entry) + "\n")
	# Auto-scroll to bottom so the newest line is visible.
	await get_tree().process_frame
	_content.scroll_to_line(_content.get_line_count() - 1)


func _rebuild_all() -> void:
	_content.clear()
	for entry in GameLog.get_entries():
		_content.append_text(GameLog.bbcode(entry) + "\n")
	# Jump to the newest line.
	await get_tree().process_frame
	_content.scroll_to_line(_content.get_line_count() - 1)


func _on_close_pressed() -> void:
	SceneManager.close_screen()
