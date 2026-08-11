# Subsystem: Game Log

Minecraft-style on-screen message feed. When something happens in the world (a colonist dies, the day rolls over, an item is picked up), a short text line slides into the HUD and stays visible briefly before fading out. The last few lines are always shown; full scrollback is one keypress away.

Player-facing counterpart to the [Debug Console](debug-console.md): the Debug Console is dev-only with its own buffer and is stripped from release builds, whereas Game Log ships in every build and shows gameplay events the player is meant to see. Producers must never use Game Log for dev output — see *Design notes* below.

**Design notes:**
- **Autoload owns history, UI only renders.** `GameLog` is a process-lifetime autoload holding a capped ring buffer; `LogFeed` and `LogHistory` are dumb consumers that subscribe to `entry_added`. History survives UI reloads (map swaps, late mounts) and is queryable by any future reader (Day Summary, Debug Console).
- **Two producer tiers.** (1) `GameLog._ready()` auto-subscribes to a handful of high-value EventBus signals, so the feed is useful out of the box with zero per-subsystem wiring. (2) Gameplay code calls `GameLog.log(...)` directly for finer-grained messages (item pickups, crafting results), added incrementally as each subsystem is touched.
- **No `class_name GameLog`.** Like every other autoload in the project, the script declares no `class_name` — declaring one would shadow the singleton and break every `GameLog.xxx` reference (and make bare `log(...)` inside the file resolve to Godot's global natural-log function). Internal callers use `self.log(...)`.
- **Dev output does NOT go here.** `GameLog` is player-facing and ships in release. Use `print()` / `push_warning()` for ad-hoc dev output, or the [Debug Console](debug-console.md) for structured dev logging with its own buffer and export-time exclusion.

## Files

| File | Type | Responsibility |
|---|---|---|
| `subsystems/autoloads/game_log.gd` | Script (autoload) | Single owner of log history. Capped ring buffer; emits `entry_added`; auto-subscribes to EventBus signals; exposes `log()` / `info()` / `combat()` / etc. and query APIs. No `class_name` (autoload convention). |
| `ui/log_feed/log_entry.gd` | Script (`class_name LogEntry`, `RefCounted`) | Immutable value object for one log line: `text`, `category`, `day`, `timestamp`. Cheap to hold by the hundreds in the ring buffer. |
| `ui/log_feed/log_feed.tscn` / `log_feed.gd` | Scene/Script (`class_name LogFeed`) | Persistent HUD tail mounted on the HUDLayer (layer 10) by [Core](core.md). Renders the last N lines; per-line timeout; tween-driven slide-up on arrival. |
| `ui/log_feed/log_history.tscn` / `log_history.gd` | Scene/Script (`class_name LogHistory`) | Full scrollback view opened via `SceneManager.open_screen("log_history")` on the UILayer (layer 20). Live-appends while open. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `entry_added(entry: LogEntry)` | `game_log.gd` | `LogFeed`, `LogHistory` | No (on GameLog itself) | *Log a gameplay event*, *Open scrollback* |

GameLog also **listens** to these existing EventBus signals (no new EventBus signals are introduced by this subsystem):

| EventBus signal | GameLog handler | Line produced |
|---|---|---|
| `colonist_died(colonist_id)` | `_on_colonist_died` | `"<id> has died"` (COLONY) |
| `day_rolled_over(new_day)` | `_on_day_rolled_over` | `"Day <n> begins"` (SYSTEM) |
| `expedition_started(crew, poi_id)` | `_on_expedition_started` | `"Expedition departed for <poi>"` (SYSTEM) |
| `expedition_ended(result)` | `_on_expedition_ended` | `"Expedition returned."` (SYSTEM) — result schema is TBD; refine when ExpeditionManager's result shape is defined. |
| `furniture_placed(def_id, anchor)` | `_on_furniture_placed` | `"Built <def_id>"` (INFO) |
| `furniture_removed(def_id, anchor)` | `_on_furniture_removed` | `"Removed <def_id>"` (INFO) |
| `raid_started(raid_data)` | `_on_raid_started` | `"A raid has begun!"` (COMBAT) — **signal declared but not yet emitted**; raids subsystem unimplemented. |
| `raid_ended(outcome)` | `_on_raid_ended` | `"Raid repelled."` / `"Raid overrun."` (COMBAT) — **signal declared but not yet emitted**; raids subsystem unimplemented. |
| `run_started()` | `_on_run_started` | (clears history — no line) |

## Flow Trace: Log a gameplay event

**Trigger:** Any gameplay code calls `GameLog.log("Picked up 3 × Wood")`, or an auto-subscribed EventBus signal fires (e.g. `colonist_died`).

1. `GameLog.log(message, category)` constructs a `LogEntry` (snapshotting `GameState.current_day` and a timestamp).
2. Appends to `_buffer`; if over `max_entries`, the oldest is `pop_front()`'d (ring buffer).
3. Emits `entry_added(entry)`.
4. `LogFeed._on_entry_added` → `_spawn` builds a `RichTextLabel`, `push_front` into `_lines` (everyone's index shifts up), tweens the new line in at the bottom slot, and tweens all other lines up by one slot. If over `tail_lines`, the oldest is `_exit`'d (fade + slide off top).
5. If `LogHistory` is open, `LogHistory._on_entry_added` appends BBCode to its `RichTextLabel` and auto-scrolls to the bottom.

**End state:** New line visible at the bottom of the HUD tail; older lines shifted up; history buffer contains the entry.

## Flow Trace: Line times out

**Trigger:** A visible line has been on-screen longer than `LogFeed.line_timeout` seconds.

1. `LogFeed._process` scans `_lines` oldest-first; any line whose `spawn_time` is past the timeout is removed.
2. `_exit(line)` moves it to `_exiting`, tweens alpha → 0 and position up by one slot, then frees the node on completion.
3. `_lines.remove_at(i)` — survivors keep their indices, so they do **not** slide. Only the leaving line animates.

**End state:** Expired line fades and slides off the top; remaining lines stay put (no jitter).

## Flow Trace: Open scrollback

**Trigger:** Player presses `log_history` input (key **H**), handled in `main.gd::_unhandled_input`.

1. `SceneManager.open_screen("log_history")` loads `ui/log_feed/log_history.tscn` onto the UILayer (layer 20).
2. `LogHistory._ready` calls `_rebuild_all()` — reads `GameLog.get_entries()` and appends each as BBCode; scrolls to the newest line.
3. Subscribes to `GameLog.entry_added` so new entries while open append live.
4. Player dismisses via Close button, **H** again, or **Esc** → `SceneManager.close_screen()` frees the node.

**End state:** Full history visible and live-updating; closing frees the screen (history persists on the autoload).

## Class Reference

### Class: GameLog

**Extends:** Node
**Script:** `game_log.gd` (in `subsystems/autoloads/`, registered as autoload `GameLog`)
**Description:** Single owner of the game log history. Capped ring buffer of `LogEntry`. Auto-subscribes to high-value EventBus signals in `_ready()` so the feed is usable without per-subsystem wiring. No `class_name` (autoload convention — declaring one shadows the singleton).
**Used by:** Any gameplay code as a producer (`GameLog.log(...)`); `LogFeed` and `LogHistory` as consumers.
**Lifecycle:** Registered after `EventBus` (it connects to EventBus signals in `_ready`). `_ready()` wires the EventBus auto-subscriptions and the `run_started` clear hook.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `max_entries` | `int` (`@export`, default 200) | Ring buffer cap. Older entries are dropped on overflow. |
| `tail_lines` | `int` (`@export`, default 6) | How many recent lines `LogFeed` shows at once. Read by the feed as `GameLog.tail_lines`. |

**Signals:**

| Signal | Description |
|---|---|
| `entry_added(entry: LogEntry)` | Emitted on every `log()` call. Consumers (`LogFeed`, `LogHistory`) use this to append/render. |

**Functions:**

| Function | Description |
|---|---|
| `log(message: String, category: int = INFO) -> void` | Primary entry point. Builds a `LogEntry`, appends to the ring buffer, emits `entry_added`. |
| `info(message) -> void` / `combat(...)` / `system(...)` / `craft(...)` / `colony(...)` | Category convenience wrappers. Internal impl uses `self.log(...)` to avoid clashing with Godot's global `log()` math function. |
| `get_entries() -> Array[LogEntry]` | Full history, oldest → newest. `LogHistory` reads this on open. |
| `recent(count: int) -> Array[LogEntry]` | Last N entries, oldest → newest of the slice. `LogFeed` reads this on mount. |
| `clear() -> void` | Wipes history. Called on `EventBus.run_started`. |
| `bbcode(entry: LogEntry) -> String` (static) | Wraps `entry.text` in a `[color=...]` tag per category. Both UI consumers call this so coloring is defined in one place. |

### Class: LogEntry

**Extends:** RefCounted
**Script:** `log_entry.gd` (in `ui/log_feed/`, `class_name LogEntry`)
**Description:** Immutable snapshot of one log line. Captures `day` and `timestamp` at construction so scrollback shows when the event *happened*, not when it's viewed. `RefCounted` (not `Node`) — pure data held by the hundreds in the ring buffer.
**Used by:** `GameLog` (buffer), `LogFeed` / `LogHistory` (rendering).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `text` | `String` | Already-formatted message body (no color/timestamp — coloring applied at render via `GameLog.bbcode()`). |
| `category` | `int` (Category enum) | `INFO`, `COMBAT`, `SYSTEM`, `CRAFT`, `COLONY`. Drives color. |
| `day` | `int` | Snapshot of `GameState.current_day` at creation. Guarded so unit tests (no autoloads) don't crash. |
| `timestamp` | `float` | `Time.get_ticks_msec() / 1000.0` at creation. Used by `LogFeed` for timeout. |

**Functions:**

| Function | Description |
|---|---|
| `_init(p_text: String = "", p_category: int = INFO) -> void` | Captures timestamp and day. |

### Class: LogFeed

**Extends:** Control
**Script:** `log_feed.gd` (in `ui/log_feed/`, `class_name LogFeed`)
**Description:** Persistent HUD tail mounted on the HUDLayer (layer 10) by [Core](core.md)'s `main.gd`. Renders the last `GameLog.tail_lines` lines bottom-up; each line fades in on arrival and every existing line slides up one slot (tween-driven, Minecraft-style). Per-line timeout fades lines out after N seconds. Purely reactive to `GameLog.entry_added` — holds no gameplay state. `mouse_filter = IGNORE` so it never eats clicks.
**Used by:** Mounted as a sibling of the HUD on the HUDLayer.
**Lifecycle:** `_ready()` repopulates from `GameLog.recent(tail_lines)` (no animation, so late mount shows existing history), then subscribes to `entry_added`. `_process` handles timeout expiry.

**Layout model:** `_lines[0]` = newest = bottom of screen; higher indices stack upward. Each line's Y is a pure function of its index (`_target_y`). Arrival does `push_front` (indices shift up → slide-up tween); removal (timeout/overflow) drops a line *without* re-indexing survivors, so only the leaving line animates — this asymmetry prevents jitter.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `font_size` | `int` (`@export`, default 14) | Line text size. |
| `line_height` | `int` (`@export`, default 20) | Vertical slot size per line. |
| `line_separation` | `int` (`@export`, default 2) | Gap between stacked lines. |
| `feed_width` | `int` (`@export`, default 400) | Label width. |
| `margin_left` | `int` (`@export`, default 16) | Inset from left screen edge. |
| `margin_bottom` | `int` (`@export`, default 16) | Inset from bottom screen edge. |
| `line_timeout` | `float` (`@export`, default 6.0) | Seconds a line stays visible before fading out. ≤ 0 disables timeout. |
| `slide_duration` | `float` (`@export`, default 0.25) | Slide-up tween time per slot. |
| `fade_duration` | `float` (`@export`, default 0.4) | Fade-in / fade-out tween time. |

**Functions:**

| Function | Description |
|---|---|
| `_on_entry_added(entry: LogEntry) -> void` | Delegates to `_spawn(entry, true)`. |
| `_spawn(entry, animate) -> void` | Builds a `RichTextLabel`, `push_front` into `_lines`, animates it in, slides others up, enforces `tail_lines` cap via `_exit`. `animate=false` is the initial repopulate path. |
| `_layout(animate, skip) -> void` | Tween (or snap) every active line to its `_target_y`. `skip` excludes the freshly spawned line (it animates itself). |
| `_target_y(index) -> float` | Pure function: bottom margin minus index-based stack offset. Index 0 = bottom. |
| `_exit(line) -> void` | Move a line to `_exiting`, tween alpha → 0 + slide up, free on completion. `_exiting` keeps dying lines from being counted toward the cap or double-freed. |

### Class: LogHistory

**Extends:** Control
**Script:** `log_history.gd` (in `ui/log_feed/`, `class_name LogHistory`)
**Description:** Full scrollback view. Opened via `SceneManager.open_screen("log_history")` on the UILayer (layer 20); closed via Close button, the `log_history` input toggle, or `ui_cancel` (Esc) — all routed through `SceneManager.close_screen()`. A single scrollable `RichTextLabel` that reads `GameLog.get_entries()` on open and live-appends via `entry_added`. Deliberately simple — none of the index/tween bookkeeping `LogFeed` needs, because the autoload middleman isolates presentation concerns.
**Used by:** Opened by the `log_history` input in `main.gd::_unhandled_input`.
**Lifecycle:** `_ready()` rebuilds from history then subscribes to `entry_added`.

**Signals:**

| Signal | Description |
|---|---|
| `closed()` | Currently unused. The close path goes through `SceneManager.close_screen()` directly (matching `world_map.gd`'s pattern). Retained for future explicit-dismissal flows. |

**Functions:**

| Function | Description |
|---|---|
| `append_live(entry: LogEntry) -> void` | Public alias for the `entry_added` handler; appends BBCode and auto-scrolls to bottom. |
| `_rebuild_all() -> void` | Clears and re-appends all of `GameLog.get_entries()`. |
