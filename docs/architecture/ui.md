# Subsystem: UI

HUD + all full-screen UIs. Each screen is its own `.tscn` scene; reusable subscenes (health bar, inventory slot, roster row) are standalone scenes *(planned — none implemented yet; `ui/shared/` is empty)*. Real screens live in `ui/`; several GDD-planned screens (`player_screen`, `colony_screen`, `day_summary`, `game_over`, `settings`) have empty placeholder directories and are marked *(planned)* below.

## Files

| File | Type | Responsibility |
|---|---|---|
| `hud/hud.tscn` / `hud.gd` | Scene/Script | Persistent in-game overlay mounted on the HUDLayer (CanvasLayer 10). Contains the **Crosshair**, the **InstructionsLabel** (see its own row below), the **InteractLabel** (target name + default-action hint under the crosshair), and an **InventoryPanel** side panel toggled with **I**. Also owns the E-key tap-vs-hold timer (tap → `Player.execute_default_action`, hold → `Player.open_interaction_menu`) and listens to `build_placement_toggled` (hides the crosshair during placement). HP/Durability/Stamina/Breath bars, hotbar, and day counter are **planned** (not yet built). |
| `hud/instructions_label.gd` | Script (on the `InstructionsLabel` `Label` node in `hud.tscn`) | Self-registers in `_ready()` on `EventBus.build_placement_toggled` / `build_menu_toggled` and drives its own `text` + `visible` (placement → "Esc: cancel"; menu → "Click an item to place · Esc: cancel"). Decoupled from `hud.gd`, which no longer references the label. |
| `interaction/interaction_ui.tscn` | Scene | E-key pop-up menu: `Label` + button list, one `Button` per `ActionOption` (disabled if its `Condition`s fail). Instantiated by the [Actions & Interaction](actions.md) `InteractionComponent` on a CanvasLayer; label resolved from the target's `label` property (e.g. `Furniture.label`) with `component.display_name` / node-name fallbacks. |
| `log_feed/log_feed.tscn` | Scene | The persistent game-log HUD tail mounted on the HUDLayer. Reads from the `GameLog` autoload — see [Game Log](game-log.md). |
| `log_history/log_history.tscn` | Scene | Full-screen game-log scrollback opened with **H** (`SceneManager.open_screen("log_history")`). Also reads from `GameLog`. |
| `colony_management/colony_management.tscn` | Scene | Full-screen colony overview opened with **Tab** (`SceneManager.open_screen("colony_management")`). Tabbed sections: colony overview, colonist roster, labor assignments, crafting stations, storage management. Sub-scenes: `colonist_entry`, `labor_cell`, `crafting_station_row`, `storage_container_row`. Reads/writes via the `Colony` autoload's public methods. |
| `build_menu/build_menu.tscn` (+ `build_menu_entry.tscn`) | Scene | The build-mode selection menu: one entry per unlocked buildable + a Deconstruct tool entry. Clicking an entry emits `EventBus.buildable_selected(id)` and frees itself. See [Build](build.md). |
| `storage/storage_panel.tscn` | Scene | Player↔container transfer panel, instantiated by `OpenStorageAction` on a CanvasLayer when the player opens a piece of furniture with storage. |
| `crafting/craft_panel.tscn` | Scene | Crafting panel for one station — the dual-mode surface (`Queue` colony orders incl. maintain-until-stock vs `Craft` reserved-for-player orders, deposit progress, Craft now / Cancel). Opened by `OpenCraftingAction`. See [Crafting](crafting.md). |
| `crop_inspect/crop_inspect.tscn` | Scene | Farm-plot inspector: growth progress, hydration, tending state, estimated harvest. Opened by `InspectCropAction`; can chain into the crop picker. See [Farming](farming.md). |
| `crop_picker/crop_picker.tscn` | Scene | Modal crop selector for empty farm plots (lists `CropLibrary` crops). Registers with UiGate. |
| `action_progress/action_progress.tscn` | Scene | Radial/linear progress gauge for timed manual actions (today: `BuildAction`; any action that runs over a fixed duration). Instantiated by the triggering action, registers with UiGate, emits `completed` / `cancelled`. |
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
- **Opening keys** (routed in `Main._unhandled_input`): **Esc** closes an open screen, else opens `pause_menu` — unless a modal panel is open (it owns that Esc); **M** toggles `world_map`; **H** toggles `log_history`; **Tab** toggles `colony_management`. M/H/Tab never open on top of an open panel. The HUD toggles its inventory panel with **I** directly (same no-stacking rule).
- **Pause** is driven by the `pause_menu` node itself: its `_ready` calls `GameState.set_paused(true)`; being freed (Resume / Esc / replaced) unpauses. Other full-screen screens (world map, log history) do **not** pause, and the HUD does not hide on screen open.

## Input gating (UiGate)

The `UiGate` autoload is the single source of truth for "a modal UI is open". Every modal registers/unregisters with it:

- **Freed panels** (interaction menu, storage, crafting, build menu, action gauge) register in `_ready` / unregister in `_exit_tree`.
- **Persistent panels** (HUD inventory) register/unregister in their open/close functions.
- **Full-screen screens** are registered by `SceneManager.open_screen` / `close_screen`.

While any modal is open, `UiGate.is_input_blocked()` is true and `InputComponent` — the single choke point for gameplay input — goes dead: no E/B/Esc signals (so screens can't stack, e.g. repeated E on a shelf) and movement/jump/sprint polling returns zero (WASD freezes under a panel). Panels still own their own Esc handling in `_unhandled_input`; `Main` only opens the pause menu when nothing else is open. Esc also exits build mode: the build menu closes itself on Esc/B, and Esc in placement returns the Player to NORMAL (`Player._on_ui_cancel` marks the event handled so Main doesn't also open the pause menu).

UiGate also owns the cursor mode: the 0→N modal transition shows the mouse, N→0 re-captures it. Panels must not write `Input.mouse_mode` themselves — call-order between chained opens/closes (e.g. interaction menu → storage panel) used to leave the cursor captured over a clickable panel. The only other mouse-mode writers are `Player._ready` (initial capture) and the click-to-recapture recovery path.

### Adding a new screen or dialog

First, pick which kind of UI you're adding — the recipe differs.

**A. Ad-hoc panel / dialog** — instantiated on a CanvasLayer by gameplay code (a GameAction, the player, another panel) and freed on close. Examples: storage panel, crafting panel, interaction menu, action gauge.

1. Register with UiGate from the panel's script:
   ```gdscript
   func _ready() -> void:
       UiGate.open_modal(self)

   func _exit_tree() -> void:
       UiGate.close_modal(self)
   ```
   That one registration is the whole "stop gameplay input" step: WASD/E/B/etc. die automatically (InputComponent checks the gate) and the cursor shows. Freeing the panel reverses both. Panels that persist in the scene instead of being freed — like the HUD inventory — register/unregister in their open/close functions instead of `_ready`/`_exit_tree`.
2. Own your dismiss keys. Handle Esc in your own `_unhandled_input` and consume the event so nothing behind you reacts to the same press:
   ```gdscript
   func _unhandled_input(event: InputEvent) -> void:
       if event.is_action_pressed("ui_cancel"):
           close()
           get_viewport().set_input_as_handled()
   ```
3. Do **not** write `Input.mouse_mode` — UiGate owns the cursor (see above).

You do **not** touch `Main` for a panel: panels are opened by gameplay code (E on furniture, a button), not by global hotkeys, and all gameplay keys are already dead while the panel is registered.

**B. Full-screen screen** — one scene per screen at `ui/<id>/<id>.tscn`, swapped through the layer-20 slot. Examples: world map, log history, colony management, pause menu.

1. Nothing UiGate-related goes in the screen's script: `SceneManager.open_screen(id)` / `close_screen()` register and unregister it for you.
2. Esc needs no code either — `Main._unhandled_input` closes any open screen before doing anything else. Just add a Close button that calls `SceneManager.close_screen()`.
3. `Main._unhandled_input` is edited **only** when the screen opens from a new global hotkey. Follow the existing toggle pattern (M/H): close if a screen is already open, otherwise open only when no modal is blocking:
   ```gdscript
   elif event.is_action_pressed("my_toggle"):
       if SceneManager.is_screen_open():
           SceneManager.close_screen()
       elif not UiGate.is_input_blocked():
           SceneManager.open_screen("my_screen")
   ```

### Who owns which key

`Main._unhandled_input` is **not** where input goes in general — it's only the router for global screen hotkeys (M, H, Tab), the close-on-Esc for full-screen screens, and the pause-menu fallback. Everything else lives where it belongs:

| Input | Owner | While a modal is open |
|---|---|---|
| Gameplay keys (WASD, E, B, jump, sprint, click-to-recapture) | `InputComponent` (signals + polled queries) | Dead — it checks `UiGate.is_input_blocked()` |
| A panel's own close keys (Esc, close button) | The panel's `_unhandled_input`, consumed with `set_input_as_handled()` | Active — the panel *is* the current UI |
| A full-screen screen's Esc | `Main._unhandled_input` (first branch closes the open screen) | Active |
| Global screen hotkeys (M, H, Tab) + Esc → pause fallback | `Main._unhandled_input` | Ignored while a panel is open (`is_input_blocked()` guard); they still toggle their *own* screen closed |

One caveat: InputComponent's gate only covers input read *through* InputComponent. Gameplay code that reads actions on its own — `BuildController`'s LMB/RMB/R during placement, for example — must check `UiGate.is_input_blocked()` itself before acting (as BuildController does), otherwise its keys stay live under an open screen.

## Flow Trace: Open / close a full-screen screen (Esc / M / H)

**Trigger:** Player presses Esc, M, or H during gameplay.

1. `Main._unhandled_input` reads the key (Esc, M, and H all route here).
2. If a screen is already open, `SceneManager.close_screen()` frees it and the press does nothing further (so Esc closes the world map before it ever opens pause).
3. Otherwise, if any modal panel is open, the key is ignored (panels own Esc; M/H don't stack).
4. Otherwise `SceneManager.open_screen(id)` → loads `res://ui/<id>/<id>.tscn` into the layer-20 slot and registers it with UiGate (gameplay input dies, cursor shows).
5. For `pause_menu` specifically, the new node's `_ready` pauses the sim (see above); freeing it reverses both.

**End state:** The requested screen is mounted (or the previous one closed). Only the pause overlay pauses; world map / log history / inventory panel do not — but all of them block gameplay input via UiGate.
