extends ColorRect
## Full-screen splash shown on boot, then advances to the Main Menu.
##
## Opened via SceneManager.open_screen("splash") from boot.gd. Auto-advances
## after `duration` seconds, or on any key/mouse press (whichever comes first).
## The splash image is auto-loaded from `splash_texture`, or — if that's null —
## from the well-known path `res://assets/ui/splash.png` (if present). When no
## texture is available the scene still loads (solid-bg fallback), so nothing
## breaks while the art is pending.

## How long the splash stays before auto-advancing. Tunable in the inspector.
@export var duration: float = 0.2

## Optional explicit texture. If null, the script falls back to loading
## `res://assets/ui/splash.png` at runtime.
@export var splash_texture: Texture2D

const _DEFAULT_PATH := "res://assets/ui/splash.png"

@onready var _texture_rect: TextureRect = %SplashImage

var _advanced: bool = false


func _ready() -> void:
	_resolve_texture()
	# Auto-advance after the configured duration.
	get_tree().create_timer(duration).timeout.connect(_advance)


func _unhandled_input(_event: InputEvent) -> void:
	# Any key or mouse press skips the splash.
	if (_event is InputEventKey and _event.pressed) or \
			(_event is InputEventMouseButton and _event.pressed):
		_advance()


func _resolve_texture() -> void:
	var tex: Texture2D = splash_texture
	if tex == null and ResourceLoader.exists(_DEFAULT_PATH):
		tex = load(_DEFAULT_PATH)
	_texture_rect.texture = tex
	_texture_rect.visible = tex != null


## Advance from splash to the main menu. Idempotent — only fires once.
func _advance() -> void:
	if _advanced:
		return
	_advanced = true
	SceneManager.close_screen()
	SceneManager.open_screen("main_menu")
