# Subsystem: UI

HUD + all full-screen UIs. Each screen is its own `.tscn` scene; reusable subscenes (health bar, inventory slot, roster row) are standalone scenes *(planned — none implemented yet; `ui/shared/` is empty)*. Real screens live in `ui/`; several GDD-planned screens (`player_screen`, `colony_screen`, `day_summary`, `game_over`, `settings`) have empty placeholder directories and are marked *(planned)* below.

## Files

| File | Type | Responsibility |
|---|---|---|
| `hud/hud.tscn` / `hud.gd` | Scene/Script | Persistent in-game overlay mounted on the HUDLayer (CanvasLayer 10). Contains the **Crosshair**, the **InstructionsLabel** (see its own row below), the **InteractLabel** (target name + default-action hint under the crosshair), and an **InventoryPanel** side panel toggled with **I**. Also owns the E-key tap-vs-hold timer (tap → `Player.execute_default_action`, hold → `Player.open_interaction_menu`) and listens to `build_placement_toggled` (hides the crosshair during placement). HP/Durability/Stamina/Breath bars, hotbar, and day counter are **planned** (not yet built). |
| `hud/instructions_label.gd` | Script (on the `InstructionsLabel` `Label` node in `hud.tscn`) | Self-registers in `_ready()` on `EventBus.build_placement_toggled` / `build_menu_toggled` and drives its own `text` + `visible` (placement → "B: cancel"; menu → "Click an item to place · B: cancel"). Decoupled from `hud.gd`, which no longer references the label. |
| `interaction/interaction_ui.tscn` | Scene | E-key pop-up menu: `Label` + button list, one `Button` per `ActionOption` (disabled if its `Condition`s fail). Instantiated by the [Actions & Interaction](actions.md) `InteractionComponent` on a CanvasLayer; label resolved from the target's `label` property (e.g. `Furniture.label`) with `component.display_name` / node-name fallbacks. |
| `log_feed/log_feed.tscn` (+ `log_history.tscn`) | Scene | The on-screen game log: `log_feed` is the persistent HUD tail (mounted on the HUDLayer); `log_history` is the full-screen scrollback opened with **H** (`SceneManager.open_screen("log_history")`). Both read from the `GameLog` autoload — see [Game Log](game-log.md). |
| `build_menu/build_menu.tscn` (+ `build_menu_entry.tscn`) | Scene | The build-mode selection menu: one entry per unlocked buildable + a Deconstruct tool entry. Clicking an entry emits `EventBus.buildable_selected(id)` and frees itself. See [Build](build.md). |
| `storage/storage_panel.tscn` | Scene | Player↔container transfer panel, instantiated by `OpenStorageAction` on a CanvasLayer when the player opens a piece of furniture with storage. |
| `world_map/world_map.tscn` | Scene | World map, opened with **M** (`SceneManager.open_screen("world_map")`). *(Hex-grid + Expeditions integration are partial/planned.)* |
| `pause_menu/pause_menu.tscn` | Scene | Pause overlay (a **layer-30 `CanvasLayer`**, not layer-20, so it renders above the build menu and full-screen screens). Resume / Save / Quit to Main Menu. Entering pauses the sim + releases the cursor; Resume/Esc/replace restores them. Save calls `SaveSystem.save_game()`; Quit discards the active slot if the run was never saved (`SaveSystem.discard_unsaved_active_slot()`), unloads the live map, then opens the Main Menu. |
| `main_menu/main_menu.tscn` | Scene | Title screen after splash. **New Game** + **Load Game** buttons (Continue / Settings land later). New Game allocates a fresh save slot (`SaveSystem.create_save`), resets run state, emits `run_started`, discovers POIs, and `swap_map("base")`. Load Game opens the Load Game screen (see `load_menu`). |
| `load_menu/load_menu.tscn` | Scene | Load Game screen, opened from the Main Menu. Lists every save slot from `SaveSystem.list_saves()` (newest-first); rows are built in code (no per-row scene). Click a row to `await SaveSystem.load_game(slot)` then `close_screen` (on failure it stays open so the user can pick another save); the `X` button calls `delete_save(slot)` (no confirmation in v1); Back returns to the Main Menu. |
| `splash/splash.tscn` | Scene | Full-screen splash shown on boot. Auto-advances after `duration` (default 0.2s, inspector-tunable) or on any key/mouse press, then opens the Main Menu. Image auto-loaded from `res://assets/ui/splash.png` (solid-bg fallback if absent). |
| `player_screen/player_screen.tscn` | Scene *(planned — dir empty)* | Tabbed: Player Info / Inventory / Gear / Skills. |
| `colony_screen/colony_screen.tscn` | Scene *(planned — dir empty)* | Tabs: Roster / Labor / Defense / Loadouts / Expeditions. |
| `day_summary/day_summary.tscn` | Scene *(planned — dir empty)* | Post-sleep screen: day's resource changes, expeditions, Fallen section (reads Memorial), construction, raids survived. See [Core](core.md) "Sleep → Day Summary → Save" flow (planned). |
| `game_over/game_over.tscn` | Scene *(planned — dir empty)* | Stats + memorial roster (reads from Memorial) + buttons. (`EventBus.game_over()` exists; no screen yet.) |
| `settings/settings.tscn` | Scene *(planned — dir empty)* | Video / Audio tabs. |
| `shared/*.tscn` | Scene *(planned — none implemented)* | Reusable subscenes: health_bar, inventory_slot, roster_row, job_log_entry, memorial_entry. |

## Screen lifecycle (how screens actually open/close)

There is **no `screen_opened` / `screen_closed` signal**. Screens are mounted/freed imperatively by `SceneManager`, and pause is owned by the pause overlay's own node lifecycle:

- **Full-screen screens** swap through the layer-20 slot via `SceneManager.open_screen(id)` (loads `res://ui/<id>/<id>.tscn`, closing any open screen first) and `SceneManager.close_screen()`. `is_screen_open()` reports whether one is mounted.
- **Opening keys** (routed in `Main._unhandled_input`): **Esc** closes an open screen, else opens `pause_menu`; **M** toggles `world_map`; **H** toggles `log_history`. The HUD toggles its inventory panel with **I** directly.
- **Pause** is driven by the `pause_menu` node itself: its `_ready` calls `GameState.set_paused(true)` + releases the mouse; being freed (Resume / Esc / replaced) unpause + restores the prior cursor mode. Other full-screen screens (world map, log history) do **not** pause, and the HUD does not hide on screen open.

## Flow Trace: Open / close a full-screen screen (Esc / M / H)

**Trigger:** Player presses Esc, M, or H during gameplay.

1. `Main._unhandled_input` (Esc, M) or the HUD (H, via `log_history` action) reads the key.
2. If a screen is already open, `SceneManager.close_screen()` frees it and the press does nothing further (so Esc closes the world map before it ever opens pause).
3. Otherwise `SceneManager.open_screen(id)` → loads `res://ui/<id>/<id>.tscn` into the layer-20 slot.
4. For `pause_menu` specifically, the new node's `_ready` pauses the sim and releases the cursor (see above); freeing it reverses both.

**End state:** The requested screen is mounted (or the previous one closed). Only the pause overlay pauses; world map / log history / inventory panel do not.
