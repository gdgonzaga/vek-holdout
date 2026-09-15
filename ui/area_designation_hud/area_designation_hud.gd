extends Control
## HUD overlay for Area Designation mode (ARCH "UI").
## Displays control instructions, active tool, and current stage.

@onready var _title_label: Label = %TitleLabel
@onready var _stage_label: Label = %StageLabel
@onready var _instructions_label: Label = %InstructionsLabel

var _current_tool_label: String = "Area Designation"
var _current_stage: String = "pick corner A"


# =================
# Primary Functions
# =================

func _ready() -> void:
	visible = false
	EventBus.area_designation_toggled.connect(_on_area_designation_toggled)
	EventBus.area_designation_stage_changed.connect(_on_stage_changed)
	EventBus.area_designation_tool_changed.connect(_on_tool_changed)
	# 1. Display Initialization: Sets default labels for stage display.
	_update_hud("pick corner A")


func _on_area_designation_toggled(active: bool) -> void:
	visible = active
	if active:
		# 1. State Reset: Restores HUD indicators to baseline on toggle activation.
		_update_hud("pick corner A")


func _on_stage_changed(stage_name: String) -> void:
	_current_stage = stage_name
	# 1. Stage Label Refresh: Formats and sets stage indicator text.
	_refresh_stage_display()
	# 2. Instruction Refresh: Updates contextual help text for the current stage.
	_update_instructions()


func _on_tool_changed(_tool_id: String, tool_label: String) -> void:
	_current_tool_label = tool_label
	# 1. Title Label Refresh: Updates the panel title to match the active tool.
	_refresh_title_display()


# ===================
# Auxiliary Functions
# ===================

func _update_hud(stage_name: String) -> void:
	## Auxiliary: Updates stage label and refreshes instructions.
	_current_stage = stage_name
	# 1. Title Display Update: Sets the active tool title.
	_refresh_title_display()
	# 2. Stage Display Update: Formats and assigns text to the stage indicator.
	_refresh_stage_display()
	# 3. Controls Update: Updates keyboard and mouse guidance text.
	_update_instructions()


func _refresh_title_display() -> void:
	## Auxiliary: Formats and assigns text to the title label.
	if _title_label != null:
		_title_label.text = _current_tool_label.to_upper()


func _refresh_stage_display() -> void:
	## Auxiliary: Formats and assigns text to the stage label.
	if _stage_label != null:
		var display_stage := "Pick First Corner" if _current_stage == "pick corner A" else "Pick Second Corner"
		_stage_label.text = "Stage: %s" % display_stage


func _update_instructions() -> void:
	## Auxiliary: Updates instructions label with controls and stage action.
	if _instructions_label == null:
		return
	if _current_stage == "pick corner A":
		_instructions_label.text = "LMB: Set First Corner (A)\nT: Menu · Esc: Cancel"
	else:
		_instructions_label.text = "LMB: Set Second Corner (B) to Commit\nRMB: Reset Corner · T: Menu · Esc: Cancel"
