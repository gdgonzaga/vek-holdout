# Subsystem: UI

HUD + all full-screen UIs. Each screen is its own `.tscn` scene; reusable subscenes (health bar, inventory slot, roster row) are standalone scenes.

## Files

| File | Type | Responsibility |
|---|---|---|
| `hud/hud.tscn` / `hud.gd` | Scene/Script | Persistent in-game overlay (CanvasLayer 10): HP/Durability/Stamina/Breath bars, hotbar, build overlay, day counter. |
| `interaction/interaction_ui.tscn` | Scene | E-key pop-up menu: `Label` + button list, one `Button` per `ActionOption` (disabled if its `Condition`s fail). Instantiated by the [Actions & Interaction](actions.md) `InteractionComponent` on a CanvasLayer; label resolved from the target's `label` property (e.g. `Furniture.label`) with `component.display_name` / node-name fallbacks. |
| `player_screen/player_screen.tscn` | Scene | Tabbed: Player Info / Inventory / Gear / Skills(empty). |
| `colony_screen/colony_screen.tscn` | Scene | Tabs: Roster / Labor / Defense / Loadouts / Expeditions. |
| `world_map/world_map.tscn` | Scene | Hex-grid map (also referenced by Expeditions subsystem). |
| `pause_menu/pause_menu.tscn` | Scene | Resume / Settings / Quit. |
| `main_menu/main_menu.tscn` | Scene | Title screen after splash. **New Game** button only for now (Continue / Load / Settings / Quit land later). New Game resets run state, emits `run_started`, discovers POIs, and `swap_map("base_colony")`. |
| `splash/splash.tscn` | Scene | Full-screen splash shown on boot. Auto-advances after `duration` (default 0.2s, inspector-tunable) or on any key/mouse press, then opens the Main Menu. Image auto-loaded from `res://assets/ui/splash.png` (solid-bg fallback if absent). |
| `game_over/game_over.tscn` | Scene | Stats + memorial roster (reads from Memorial) + buttons. |
| `day_summary/day_summary.tscn` | Scene | Post-sleep screen (CanvasLayer 20): day's resource changes, expeditions, Fallen section (reads Memorial), construction, raids survived. See [Core](core.md) "Sleep → Day Summary → Save" flow. |
| `settings/settings.tscn` | Scene | Video / Audio tabs. |
| `shared/health_bar.tscn` | Scene | Reusable subscene: HP + Durability bars. |
| `shared/inventory_slot.tscn` | Scene | Reusable subscene: one inventory slot. |
| `shared/roster_row.tscn` | Scene | Reusable subscene: one colonist row in Roster tab. |
| `shared/job_log_entry.tscn` | Scene | Reusable subscene: one Job Log line. |
| `shared/memorial_entry.tscn` | Scene | Reusable subscene: one deceased-colonist row (name, cause, day died). Instanced by Day Summary + Game Over. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `screen_opened(screen_id)` | each screen's `.gd` | GameState (pause), HUD (hide) | No (SceneManager-mediated) | Open Full-Screen UI |
| `screen_closed(screen_id)` | each screen's `.gd` | GameState (unpause), HUD (show) | No | Close Full-Screen UI |

## Flow Trace: Open Player screen (Z key)

**Trigger:** Player presses Z.

1. Player input → SceneManager.open_screen("player_screen").
2. SceneManager instances `player_screen.tscn` in CanvasLayer 20.
3. Player screen emits `screen_opened` → GameState pauses sim, HUD hides.
4. Player screen reads from Player.inventory, Player.gear, Player.stats.
5. Player presses Esc → `screen_closed` → inverse.

**End state:** Player screen open; game paused; HUD hidden.
