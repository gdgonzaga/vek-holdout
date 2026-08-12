extends CanvasLayer
## Pause overlay opened by Esc from any player mode (NORMAL / BUILD_MENU /
## BUILD_PLACEMENT). Owns pause state through its own lifecycle: entering pauses
## the sim and releases the cursor; being freed (Resume, Esc again, or another
## screen replacing it) unpauses and restores the prior cursor mode.
##
## Rooted on a dedicated layer-30 CanvasLayer so it always renders above the
## layer-20 UI (build menu, screens) and the layer-10 HUD. SceneManager adds this
## node under Main's UILayer; nested CanvasLayers still render at their own layer
## index, so it sits on top regardless of sibling draw order. process_mode =
## ALWAYS keeps it interactive while GameState.set_paused disables map_root.

var _prior_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

@onready var _resume_btn: Button = %Resume
@onready var _quit_btn: Button = %Quit
@onready var _save_btn: Button = %Save


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resume_btn.pressed.connect(_on_resume_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)
	_save_btn.pressed.connect(_on_save_pressed)
	# Snapshot the cursor mode so NORMAL / BUILD_PLACEMENT (captured) are restored
	# on resume, while BUILD_MENU (already visible) round-trips unchanged.
	_prior_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.set_paused(true)


func _exit_tree() -> void:
	# Fires on close_screen() (Resume / Esc) and when open_screen() replaces this.
	GameState.set_paused(false)
	Input.mouse_mode = _prior_mouse_mode


func _on_resume_pressed() -> void:
	# Freeing self runs _exit_tree, which unpauses and restores the cursor.
	SceneManager.close_screen()
	

func _on_save_pressed() -> void:
	# Save before close — _exit_tree unpauses on close, and a paused GameState
	# doesn't affect save_game() (it reads state directly, not via _process).
	# Close happens regardless of save outcome; a future toast can surface failures.
	SaveSystem.save_game()
	SceneManager.close_screen()
	

func _on_quit_pressed() -> void:
	# open_screen closes this first (-> _exit_tree unpauses), then loads the title.
	SceneManager.open_screen("main_menu")
