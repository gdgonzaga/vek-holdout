class_name Boot
extends Node
## Project entry point (ARCH "Scene Tree", line 69; resolves Tech Debt line 147).
## Loads main.tscn (the persistent session shell), then opens the Splash screen
## on the UI layer. The Splash auto-advances to the Main Menu after its
## `duration` (or on any keypress); the Main Menu's New Game button loads the
## base colony.
##
## Decision (locked 2026-07-28, updated): boot.tscn loads Main, then opens
## Splash → Main Menu. main.tscn is NOT the entry point and no longer auto-loads
## any map — the menu gates gameplay.

func _ready() -> void:
	var main: Node = preload("res://subsystems/core/main.tscn").instantiate()
	add_child(main)
	# main._ready() runs synchronously during add_child() and hands the UI layer
	# to SceneManager, so it's safe to open the splash immediately.
	SceneManager.open_screen("splash")
