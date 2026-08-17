# Subsystem: Permadeath & Memorial

> **Implementation status: planned, not yet built.** Nothing on this page exists — there is no `memorial.gd`, no `memorial_entry.tscn`, no Day Summary or Game Over screen (both `ui/` dirs are empty), and the Game Over evaluator is not implemented. Today `colonist.gd` emits `EventBus.colonist_died` and the only listener is **GameLog** (a "has died" line): Colony does not remove the colonist from the roster on death, nothing appends a memorial entry, and `game_over` is declared on EventBus but never emitted. Deeper permadeath mechanics (named-vs-unnamed resolution, "left behind on retreat" rule, incapacitated-state handling) are also TODO. Treat this page as the spec to implement against, not a description of current code.

Tracks deceased colonists as a memorial roster, consumed by the Day Summary "Fallen" section and the Game Over screen. Lives on the **Colony autoload** (roster state must persist across base↔POI scene swaps).

## Files

| File | Type | Responsibility |
|---|---|---|
| `memorial.gd` | Script (on Colony autoload) *(planned)* | Appends to the roster on `colonist_died`; exposes `get_roster()` for UI. Does NOT own death detection (subscribes to the signal). Does NOT own the Game Over evaluator (TODO — see D3 in review notes). |
| `memorial_entry.tscn` | Scene *(planned)* | Reusable subscene: one deceased-colonist row (name, cause of death, day died). Instanced by Day Summary + Game Over. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `colonist_died(colonist_id)` | `colonist.gd` | GameLog (only listener today); **Memorial**, Colony (roster removal), HUD *(planned)* | Yes | Colonist Death |

(Memorial itself emits no signals — UI polls `get_roster()` when it opens.)

## Flow Trace: Colonist death → memorial entry *(planned)*

**Trigger:** A colonist's HP hits 0 (`colonist.gd` emits `colonist_died` via EventBus — live today).

1. `colonist.gd` emits `colonist_died(colonist_id)` via EventBus.
2. **Memorial** (on Colony) listens → appends `{colonist_id, display_name, cause, day_died}` to roster.
3. **Colony** (roster manager) listens → removes colonist from the active roster; re-evaluates Game Over condition (all colonists + player dead → emit `game_over` via EventBus).
4. **HUD** listens → shows death notification (status icon / brief toast).
5. Next Day Summary (on sleep) and any Game Over screen read `Memorial.get_roster()` to render the Fallen section.

**End state:** Colonist removed from active roster; memorial entry persists for the rest of the run; Game Over condition re-checked.

## Class Reference

### Class: Memorial

**Extends:** Node (child of Colony autoload)
**Script:** `memorial.gd`
**Description:** Append-only roster of deceased colonists. Subscribes to `colonist_died`; queried by Day Summary + Game Over UI.
**Used by:** UI (Day Summary, Game Over).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `roster` | `Array[Dictionary]` | Each entry: `{colonist_id, display_name, cause, day_died}`. |

**Functions:**

| Function | Description |
|---|---|
| `get_roster() -> Array[Dictionary]` | Returns the memorial roster (for UI rendering). |
| `_on_colonist_died(colonist_id: String, cause: String) -> void` | EventBus listener; appends an entry using current GameState day. |
