# Subsystem: Debug Console

Dev/playtest console for rapid iteration. GDD §17 Debug Console + the scavenge-specific hooks in §17 Expeditions. **Dev-only — stripped from release builds** (see Tech Debt on the export-time exclusion approach).

**Design notes:**
- **Command registry pattern:** a `DebugConsole` autoload (or scene on a CanvasLayer) holds a registry of `command_name → callable`. Each command is a thin function that mutates state via the *public APIs* of other subsystems (Inventory.add, Colony.spawn_colonist, etc.) — never reaches into subsystem internals. This keeps the debug surface from rotting when subsystem internals change.
- **`id` convention:** commands that take an entity id accept either a colonist_id or the literal string `"player"`. A small resolver (`DebugConsole._resolve_entity(id)`) returns the node; commands query the relevant component on it.
- **Command discovery:** `help` lists all registered commands; tab-completion against the registry. (Both are console-UX details, not GDD-specced, but trivial to include.)
- **Scavenge-specific commands** (force_loot_window, fill_containers, etc.) only function during an active scavenge mission; the registry still holds them, they just early-return with an error if the mission context isn't active.

## Files

| File | Type | Responsibility |
|---|---|---|
| `debug_console.tscn` / `debug_console.gd` | Scene/Script | The console UI (CanvasLayer, toggled by `~` or F1). Owns the command registry; parses input lines; dispatches to registered callables. Renders output history. Does NOT contain command logic itself (commands are registered from their owning subsystems or a central `commands.gd`). |
| `commands.gd` | Script | Central registration of all debug commands as thin wrappers over subsystem public APIs. Loaded by `debug_console.gd` on ready. Each function is one command. |
| `command.gd` | Script (Resource) | Data shape for one registry entry: name, arg spec, help text, callable. |

## Signals

Debug is dev-only and reads/writes state directly via callables — no signals needed. (Console output is written to the console's own buffer, not broadcast.)

## Flow Trace: Player runs a debug command

**Trigger:** Developer/playtester types a command in the console (e.g. `add_resource leather 50`).

1. `debug_console.gd` parses the input line into `[command_name, *args]`.
2. Looks up `command_name` in the registry → gets the `Command` resource (callable + arg spec).
3. Validates arg count/types against the spec; on mismatch, prints usage to console output.
4. Calls the callable with the args. The callable (in `commands.gd`) mutates state via the relevant subsystem's public API:
   - `add_resource` → `Player.inventory.add(item_id, count)` (or colony storage; TBD per Inventory subsystem's "where do added resources go" — flag for Inventory review).
   - `set_hp` → `DebugConsole._resolve_entity(id).health_component.hp = value`.
   - `spawn_wave` → `SpawnManager.spawn_wave(n, edge)`.
   - etc.
5. Callable returns a result string → console prints it to output history.

**End state:** Game state mutated per the command; output shown in console; simulation continues.

## Class Reference

### Class: DebugConsole

**Extends:** CanvasLayer (or Control on a CanvasLayer)
**Script:** `debug_console.gd` (in `debug/`)
**Description:** The console UI + command dispatcher. Holds the command registry; parses input; routes to callables. Dev-only.
**Used by:** (dev only — not referenced by gameplay code).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `registry` | `Dictionary[String, Command]` | command_name → Command resource. |
| `visible` | `bool` | Toggled by `~` / F1. |

**Functions:**

| Function | Description |
|---|---|
| `register_command(cmd: Command) -> void` | Called by `commands.gd` on ready for each command. |
| `execute(input: String) -> void` | Parses + dispatches a console input line. |
| `_resolve_entity(id: String) -> Node` | Returns the player node for `"player"`, else the colonist by id. Used by stat-setter commands. |
