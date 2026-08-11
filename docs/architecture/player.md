# Subsystem: Player

Third-person controller, camera rig, Mode+State machine (GDD §4), inventory + equipment ownership.

## Files

| File | Type | Responsibility |
|---|---|---|
| `player.tscn` / `player.gd` | Scene/Script | CharacterBody3D + camera rig. Owns movement physics (WASD + sprint + jump with mid-air momentum preservation), inline Mode+State enums, build menu interaction (opens `build_menu.tscn` on a CanvasLayer), blueprint mode entry via menu selection + B-driven navigation across three states (Normal → Menu → Placement). Exposes `get_camera()` for BuildController raycasts. Does NOT own raw input reading (delegates to InputComponent), combat resolution (delegates to Combat), or build UX (delegates to Build when in Blueprint mode). **TODO:** source movement stats from CharacterDef instead of `@export` vars. |
| `input_component.gd` | Script (Node) | Child node on the Player. Reads all raw player input and exposes it via signals (discrete actions: build toggle, interact, mouse recapture, ui cancel) and per-frame query methods (`get_movement_input()`, `wants_jump()`, `wants_sprint()`). Does NOT own mouse-motion (CameraRig handles that) or mouse-mode management (Player owns that as a game-state concern). |
| `camera_rig.gd` | Script | Programmatically constructs its own SpringArm3D + Camera3D children in `_ready()`. Mouse look (yaw on rig, pitch on spring arm) via its own `_unhandled_input` — InputComponent does not absorb mouse-motion. Zoom via spring length, collision on spring arm (layer 1). LMB/RMB reserved for item actions, not consumed here. |
| `player_state_machine.gd` | Script *(planned — not yet implemented)* | Mode + State logic (Normal/Blueprint × Idle/Walk/Sprint/Attack/Interact/Sleep/Dead). Currently inline in `player.gd`; will be extracted as Mode+State grow. |
| `../data/characters/player.tres` | Data | CharacterDef: HP, base move speed, sprint mult, Stamina drain rate, Breath costs. See [Data Schemas](data-schemas.md). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `blueprint_mode_toggled(active)` | `player.gd` | BuildController, HUD | Yes | Enter Blueprint Mode |
| `player_died(context)` | `player.gd` *(planned — not yet emitted)* | GameState, HUD | Yes | Player Death / Respawn |

> **Interaction** is not signal-driven. The player resolves a target via crosshair raycast and calls `InteractionComponent.interact(self)` directly — see the "Interact (E key)" flow and the [Actions & Interaction](actions.md) subsystem.

## Flow Trace: Enter Blueprint Mode

**Trigger:** Player presses `build_toggle` (B). B is the single navigation key across the three blueprint states (GDD §4 controls table, line 202: "Toggle Blueprint mode — B"). Esc no longer participates in blueprint navigation — it is reserved for the future Pause Menu (GDD line 214).

1. `InputComponent._unhandled_input` catches `build_toggle` → emits `build_toggle_pressed`.
2. `player.gd._on_build_toggle` (connected in `_ready`) routes by current state:
   - **Normal** → calls `open_build_menu()`: instantiates `res://ui/build_menu/build_menu.tscn` on a CanvasLayer (in `"ui_layer"` group, or a new one); releases cursor; tracks the menu in `_build_menu`.
   - **Menu open** (`_build_menu != null`) → calls `_build_menu.close()`: menu emits `closed` → `_on_build_menu_closed` clears `_build_menu` and re-captures the mouse; mode stays `NORMAL`.
   - **Placement** (`mode == BLUEPRINT`) → calls `exit_blueprint_mode()` (sets `mode = NORMAL`, emits `blueprint_mode_toggled(false)`), then `open_build_menu()` to return to item selection.
3. Player selects a buildable from the menu → menu emits `EventBus.buildable_selected(id)` and frees itself → `player.gd._on_buildable_selected(id)`: clears `_build_menu`; sets `mode = BLUEPRINT`; emits `blueprint_mode_toggled(true)` via EventBus; re-captures mouse.
4. HUD listens to `blueprint_mode_toggled`: hides the crosshair on `(true)`, restores it on `(false)`.
5. BuildController activates; routes LMB (place) / RMB (remove) / mouse wheel (rotate step) / R (cycle axis) to placement + rotation.
6. Movement states still apply (player can walk while building).

**End state:** Build UX active; LMB/RMB/wheel/R repurposed; movement unaffected. Exit is via B (Placement → Menu → Normal), not Esc.

## Flow Trace: Interact (E key)

**Trigger:** Player presses E (`"interact"` input action) in Normal mode while the crosshair is over an interactable.

1. Every `_physics_process` tick, `_update_interaction_target` runs a screen-center physics raycast (`interact_distance` 8.0, bodies only, the player RID excluded). Skipped entirely when `mode != NORMAL` (no targeting in Blueprint mode).
2. On a hit, `_find_interaction_component(hit.collider)` walks **up** the parent chain looking for a direct child named exactly `"InteractionComponent"`. The result is cached in `_current_interactable`.
3. E press → `InputComponent` emits `interact_pressed` → `player.gd._try_interact`: if `_current_interactable` is non-null **and** its `action_options` is non-empty, calls `_current_interactable.interact(self)`.
4. The `InteractionComponent` builds and mounts the interaction menu — see [Actions & Interaction](actions.md) for the rest of the chain (UI mount, button building, `GameAction.execute`).

**End state:** The interaction menu is open (or the action has run). Interaction does **not** change movement state — `State.INTERACT` is defined in the enum but never assigned; the player keeps walking/idle underneath.

## Flow Trace: Sprint and Breath

> **Implementation status: planned, not yet built.** Sprint currently works as an unconditional Shift hold with no Breath gating or drain. The design below is the intended shape. Treat this as the spec to implement against, not a description of current code.

**Trigger:** Player holds Shift while moving (and Breath > 20%).

1. Player checks `breath_component.can_sprint()` (> 20%); if blocked, ignore Shift.
2. `player.gd` reads `_input.wants_sprint()`; sets `state = SPRINT`; speed = base × sprint_multiplier (1.6×).
3. Player calls `breath_component.set_sprinting(true)`.
4. BreathComponent._process: `breath -= sprint_drain_rate (20) × delta`; emits `breath_changed`.
5. If `breath ≤ 0` → emit `sprint_available(false)`; Player forced to WALK.
6. Player Shift-release OR Breath empty → `state = WALK`; `set_sprinting(false)`.
7. BreathComponent._process (not sprinting): `breath += regen_rate (10) × delta` (capped 100); emits `breath_changed`.

**Other burst actions** (jump/melee/ranged) call `breath_component.spend(cost)` — blocked if `breath < cost`. Stamina drains independently via StaminaComponent (ambient always; ×2 while working).

**End state:** Sprint drains Breath, regenerates when not sprinting; Stamina unaffected by sprint.

## Flow Trace: Jump and Mid-Air Control

**Trigger:** Player presses jump while on floor.

1. `player.gd` checks `_input.wants_jump()`; if true, sets `velocity.y = jump_force`; captures current horizontal wish-velocity (from `_input.get_movement_input()`) into `_velocity_on_jump` and current speed into `_speed_on_jump`.
2. Mid-air: the frozen momentum is resolved per-axis (forward/back, strafe) against live camera directions via `_resolve_air_axis`. Movement input is read each tick via `_input.get_movement_input()` — keys can only *brake* the frozen momentum, they never re-project it, so camera rotation mid-air cannot curve movement.
3. Per-axis braking rules: both keys held = cancel; key held matching momentum direction = preserve; key held opposing momentum = nudge at `jump_move_speed`; neither held = snap stop (no coasting).
4. Speed scale at takeoff is frozen — releasing/pressing Shift mid-air does not change momentum scale.

**End state:** Jump preserves horizontal momentum from takeoff; player can brake but not steer mid-air.

## Class Reference

### Class: Player

**Extends:** CharacterBody3D
**Script:** `player.gd`
**Description:** Player avatar. Owns movement physics, Mode+State transitions, mouse-mode management. Raw input reading is delegated to the `InputComponent` child. Delegates combat to Combat subsystem, build UX to Build subsystem.
**Used by:** HUD (health bar), Combat (damage target), Build (placement source).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `walk_speed` | `float` | `[export default 3.5]` Ground move speed. **TODO:** source from CharacterDef. |
| `sprint_speed` | `float` | `[export default 7.0]` Sprint speed. **TODO:** source from CharacterDef. |
| `gravity` | `float` | `[export default 9.8]` Gravity acceleration. |
| `jump_force` | `float` | `[export default 5.0]` Vertical impulse on jump. |
| `jump_move_speed` | `float` | `[export default 0.5]` Mid-air nudge speed for axis braking. |
| `mode` | `Mode` enum | `NORMAL` or `BLUEPRINT`. |
| `state` | `State` enum | Movement/action state (`IDLE`, `WALK`, `SPRINT`, `ATTACK`, `INTERACT`, `SLEEP`, `DEAD`). Only `IDLE`/`WALK`/`SPRINT` are actively assigned at runtime; the rest are placeholders. |
| `interact_distance` | `float` | `[export default 8.0]` Max range for the interaction crosshair raycast. |
| `_current_interactable` | `InteractionComponent` | The component currently under the crosshair (or `null`). Refreshed every tick by `_update_interaction_target`. |
| `_input` | `InputComponent` | `@onready` reference to the `$InputComponent` child. All raw input reads go through this component. |
| `character_def` | `CharacterDef` *(planned)* | Loaded resource (player.tres): max_hp, base_move_speed, sprint_multiplier, stamina_drain_rate, breath costs. |
| `breath_component` | `BreathComponent` *(planned)* | @onready ref; queried for sprint gating + burst-action spending. |
| `stamina_component` | `StaminaComponent` *(planned)* | @onready ref; queried for work/movement multipliers. |

**Functions:**

| Function | Description |
|---|---|
| `get_camera() -> Camera3D` | Public accessor; delegates to CameraRig. Used by BuildController for screen-center raycasts. |
| `exit_blueprint_mode() -> void` | One-way exit: sets `mode = NORMAL`; emits `blueprint_mode_toggled(false)`. Called by `_on_build_toggle` when leaving placement for the menu. |
| `open_build_menu() -> void` | Instantiates `build_menu.tscn` on a CanvasLayer; releases cursor; tracks the menu in `_build_menu`. No-op if a menu is already open. Called by `_on_build_toggle` from Normal or Placement. |
| `_on_build_toggle() -> void` | B-key state router (connected to InputComponent's `build_toggle_pressed`): Normal → open menu; menu open → close menu; Placement → exit + reopen menu. |
| `_on_buildable_selected(id: String) -> void` | Enters Blueprint mode on menu selection: clears `_build_menu`; sets `mode = BLUEPRINT`; emits `blueprint_mode_toggled(true)`. |
| `_try_interact() -> void` | E-key handler (connected to InputComponent's `interact_pressed` signal): calls `_current_interactable.interact(self)` if a target is cached and offers actions. |
| `_recapture_mouse() -> void` | Sets `Input.mouse_mode = CAPTURED`. Connected to InputComponent's `recapture_requested` signal (click-to-recapture after alt-tab). |
| `_on_ui_cancel() -> void` | Esc handler (connected to InputComponent's `ui_cancel_pressed`). No-op for blueprint — Esc is reserved for the future Pause Menu (GDD line 214). |
| `_interaction_raycast() -> Dictionary` | Screen-center physics raycast (`interact_distance`, bodies only, player excluded). Returns the raw hit dict (empty if nothing struck). |
| `_update_interaction_target() -> void` | Per-tick crosshair check; updates `_current_interactable` via `_find_interaction_component`. Skipped in Blueprint mode. |
| `_find_interaction_component(node: Node) -> InteractionComponent` | Walks up the parent chain from a hit collider looking for a child named exactly `"InteractionComponent"`. |
| `take_damage(amount: int, source: Node) -> void` *(planned)* | Forwards to Combat's damage resolver. |

### Class: InputComponent

**Extends:** Node
**Script:** `input_component.gd`
**Description:** Reads raw player input and exposes it to the Player parent via signals (discrete actions) and per-frame query methods (continuous actions). Follows the project's component pattern (`extends Node`, attached as `$InputComponent` child in the scene tree). Does NOT own mouse-motion (CameraRig handles that via its own `_unhandled_input`) or mouse-mode management (Player owns `Input.mouse_mode` as a game-state concern).
**Used by:** `Player` (connects to signals in `_ready`, queries methods in `_physics_process`).

**Signals:**

| Signal | Description |
|---|---|
| `build_toggle_pressed()` | Emitted on B key (`build_toggle` action). |
| `interact_pressed()` | Emitted on E key (`interact` action). |
| `recapture_requested()` | Emitted on mouse click while cursor is visible. |
| `ui_cancel_pressed()` | Emitted on Esc (`ui_cancel` action). |

**Functions:**

| Function | Description |
|---|---|
| `get_movement_input() -> Vector2` | Normalized WASD input. Positive y = backward, negative y = forward, positive x = right. |
| `wants_jump() -> bool` | Whether the jump key (Space) is held. |
| `wants_sprint() -> bool` | Whether the sprint key (Shift) is held. |

### Class: CameraRig
