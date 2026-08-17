# Subsystem: Expeditions

Scavenge mission (Timed Extraction), world map, POI scene. GDD §17 Expeditions.

> **Implementation status: scaffold.** `ExpeditionManager` (POI discovery + the on/off-expedition flag + depart/return map swaps) and the **list-based** world map UI are live. The hex-grid sector map, fog-of-war, crew selection, threat-edge bump, and the `scavenge_mission.gd` phase timer (free-loot → waves → extraction) are **planned, not yet built**. POI scenes today are per-map `.tscn` files loaded with their own `map.sqlite` (see [Maps](maps.md) subsystem) — no `LootContainer`s or mission timer yet. The depart/return loop itself works end-to-end.

## Files

| File | Type | Responsibility |
|---|---|---|
| `expedition_manager.gd` | Autoload | Tracks discovered POIs (`Array[String]`) + `_on_expedition` flag. `start_expedition` / `end_expedition` emit the EventBus signals and delegate map loading to `SceneManager.swap_map()`. Reset on `EventBus.run_started`. |
| `../maps/map_template.tscn` | Scene | The pristine POI template (owned by Maps subsystem — listed here because it's the expedition destination source). Each POI has its own stamped copy at `data/maps/<id>/map.tscn`; `SceneManager` copies the sqlite to `user://` at runtime. |
| `../ui/world_map/world_map.tscn` / `world_map.gd` | Scene/Script | Full-screen overlay (layer-20). Lists discovered POIs from `ExpeditionManager.get_available_pois()`; each row can Depart; a Return-to-Base button appears when on an expedition. Repopulates on `EventBus.map_loaded`. |
| `../ui/world_map/poi_entry.tscn` / `poi_entry.gd` | Scene/Script | One POI row (name, description, difficulty, Depart button). Emits `depart_requested(poi_id)`. |
| `scavenge_mission.gd` | Script *(planned — not yet implemented)* | Phase timer (free-loot → waves), extraction at vehicle. Container counts per zone placed here (4–6 total: 1 Zone A, 2 Zone B, 2 Zone C per GDD §17 map layout). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `expedition_started(crew, poi_id)` | `ExpeditionManager` | Colony, colonists *(planned listeners; SceneManager swap happens inside `start_expedition` itself)* | Yes | Start Expedition |
| `expedition_ended(result)` | `ExpeditionManager` | Colony, HUD *(planned listeners; SceneManager swap happens inside `end_expedition` itself)* | Yes | End Expedition |

## Flow Trace: Depart to a POI

**Trigger:** Player opens the world map (M) and clicks a POI's **Depart**.

1. `poi_entry.gd` emits `depart_requested(poi_id)` → `world_map.gd._on_depart_requested`.
2. `ExpeditionManager.start_expedition(poi_id)`: validates (not already on one, POI known), sets `_on_expedition = true`, emits `expedition_started([], poi_id)` via EventBus.
3. Calls `SceneManager.swap_map(poi_id)` → MapLibrary lookup → instantiates the per-map `data/maps/<poi_id>/map.tscn` → copy-on-load SQLite redirect to `user://maps/<poi_id>/` → `MapWiring` → `map_loaded`.
4. World map screen is closed (map swap reparents the player; the screen was dismissed by the input handler or remains until Esc/M closes it).

**End state:** Player standing in the POI's terrain (loaded from its runtime `user://` copy); `_on_expedition == true`.

## Flow Trace: Return to base

**Trigger:** Player opens the world map and clicks **Return to Base** (visible only when on an expedition).

1. `world_map.gd._on_return_pressed` → `ExpeditionManager.end_expedition()`.
2. Clears `_on_expedition`; emits `expedition_ended({})`; calls `SceneManager.swap_map("base_colony")`.
3. Base colony loads; `map_loaded` fires; the world map repopulates and the Return button hides.

**End state:** Back at base; return button gone; expedition flag clear. *(Loot banking, crew restore, threat-edge bump are planned — not yet wired.)*

## Flow Trace: Scavenge mission (Timed Extraction) — *planned*

> **Not yet built.** The shape below is the design target once `scavenge_mission.gd` and crew selection land.

**Trigger:** Player selects a POI on the world map + crew, confirms.

1. `world_map.gd` calls `ExpeditionManager.start_expedition` → SceneManager swaps to the POI scene.
2. EventBus emits `expedition_started(crew, poi_id)`.
3. Colony marks crew as "on expedition" (removed from base scene).
4. ThreatModel bumps the POI's edge weight +15.
5. Scavenge mission: 0:30–3:00 free loot window; at 2:30 warning; waves from 3:00.
6. Player returns to vehicle → extract → `expedition_ended({success/partial/narrow})`.
7. SceneManager swaps back to base scene; crew restored.

**End state:** Back at base; loot banked; crew restored; edge weight raised.

## Class Reference

### Class: ExpeditionManager

**Extends:** Node (autoload)
**Script:** `expedition_manager.gd`
**Description:** Tracks discovered POIs and the on/off-expedition flag. The thin orchestration layer between the world map UI and `SceneManager`: depart/return emit the EventBus signals and call `swap_map`. Holds no crew/loot/threat state yet (planned).
**Used by:** `main_menu.gd` (New-Game discovery loop — relocated from the old `main.gd` boot path), `world_map.gd` (depart/return + list source).
**Lifecycle:** `_ready` connects `run_started` (resets discovery + flag on New Game).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `_discovered_pois` | `Array[String]` | POI ids the player can travel to. Populated by `discover()` (idempotent). |
| `_on_expedition` | `bool` | True while the player is away from base. Gates the Return button. |

**Functions:**

| Function | Description |
|---|---|
| `get_available_pois() -> Array[MapDef]` | Discovered POIs that resolve to a `MapDef` with `map_type == POI`. Source for the world map list. |
| `is_on_expedition() -> bool` | Whether the player is currently away from base. |
| `discover(poi_id: String) -> void` | Add a POI to the discovered list (no-op if already present). |
| `start_expedition(poi_id: String, crew: Array = []) -> void` | Validates, sets the flag, emits `expedition_started`, calls `SceneManager.swap_map(poi_id)`. No-op if already on one or POI unknown. |
| `end_expedition(result: Dictionary = {}) -> void` | Clears the flag, emits `expedition_ended`, calls `SceneManager.swap_map("base_colony")`. No-op if not on one. |
