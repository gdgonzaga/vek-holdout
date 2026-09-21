extends Control
## Persistent HUD overlay mounted on the HUDLayer (layer=10).
##
## Contains:
##   - Crosshair (center screen)
##   - Interactable label (name + default action hint, below crosshair)
##   - Inventory side panel (left edge, toggled with I; see ui/inventory/inventory_panel.gd)
##
## Handles quick-tap vs long-press for the interact key (E):
##   - Quick tap (< 0.3s): executes the first action option on the targeted
##     interactable furniture.
##   - Long press (≥ 0.3s): opens the full action menu.

const _HOLD_THRESHOLD := 0.3

@onready var _crosshair: TextureRect = $Crosshair
@onready var _interact_display: Control = $InteractLabel
@onready var _inventory_panel: InventoryPanel = $InventoryPanel
@onready var _day_label: Label = %DayLabel
@onready var _clock_label: Label = %ClockLabel

var _player: Player = null
var _input_component: InputComponent = null

var _hold_timer := 0.0
var _holding_interact := false
var _last_displayed_minute := -1


func _ready() -> void:
	# Initialize digital clock display with current time and day.
	_update_clock_display()


## Called by Main after mounting the HUD on the HUDLayer.
func setup(player: Player) -> void:
	_player = player
	_input_component = player.get_node_or_null("InputComponent") as InputComponent
	if _player.inventory != null:
		_wire_signals()
	else:
		_player.ready.connect(_on_player_ready)


func _on_player_ready() -> void:
	_player.ready.disconnect(_on_player_ready)
	_wire_signals()


func _wire_signals() -> void:
	_player.interactor.interactable_changed.connect(_on_interactable_changed)
	# The panel owns its hotkey, lists and UiGate registration; it just needs the player.
	_inventory_panel.setup(_player)
	# Connect to InputComponent's interact press/release for hold detection.
	if _input_component != null:
		_input_component.interact_pressed.connect(_on_interact_pressed)
		_input_component.interact_released.connect(_on_interact_released)
	# Blueprint mode toggles the crosshair (overview.md expects this listener):
	# the build ghost replaces the crosshair while placing an item.
	EventBus.build_placement_toggled.connect(_on_build_placement_toggled)


func _on_build_placement_toggled(active: bool) -> void:
	_crosshair.visible = not active


func _on_interactable_changed(component: InteractionComponent) -> void:
	_interact_display.update_display(component, _player)


func _process(delta: float) -> void:
	# Update digital clock display when the in-game minute changes.
	_update_clock_display()

	if _holding_interact:
		# A modal opened mid-hold (e.g. Esc -> pause menu) — abandon the
		# tap/hold so the timer can't fire the menu on top of it later.
		if UiGate.is_input_blocked():
			_holding_interact = false
			_hold_timer = 0.0
			return
		_hold_timer += delta
		if _hold_timer >= _HOLD_THRESHOLD:
			_holding_interact = false
			_hold_timer = 0.0
			_player.interactor.open_interaction_menu()


func _update_clock_display() -> void:
	## Auxiliary: Refreshes clock and day labels when the in-game minute changes.
	if _clock_label == null or _day_label == null:
		return
	var current_minute: int = TimeSystem.get_current_minute()
	if current_minute == _last_displayed_minute:
		return
	_last_displayed_minute = current_minute
	_clock_label.text = TimeSystem.get_formatted_clock(true)
	_day_label.text = "Day %d" % GameState.current_day


func _on_interact_pressed() -> void:
	_holding_interact = true
	_hold_timer = 0.0


func _on_interact_released() -> void:
	if _holding_interact:
		# Released before threshold — quick tap, execute default action.
		_holding_interact = false
		_hold_timer = 0.0
		_player.interactor.execute_default_action()
	else:
		# Long-press already fired (menu opening handled in _process).
		_holding_interact = false
		_hold_timer = 0.0
