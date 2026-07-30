class_name Boot
extends Node
## Project entry point (ARCH "Scene Tree", line 69; resolves Tech Debt line 147).
## Loads main.tscn (the persistent session shell) and — TODO — opens the Main
## Menu on the UI layer. For now it just loads Main; the menu is deferred until
## the UI subsystem lands.
##
## Decision (locked 2026-07-28): boot.tscn loads Main + Menu. main.tscn is NOT
## the entry point.

func _ready() -> void:
	var main: Node = preload("res://subsystems/core/main.tscn").instantiate()
	add_child(main)
	# TODO: SceneManager.open_screen("main_menu") once Main Menu exists.
	print("[Boot] Main loaded. Main Menu open is TODO (UI subsystem).")
