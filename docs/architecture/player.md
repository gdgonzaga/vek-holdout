# Subsystem: Player

Third-person controller, camera rig, Mode+State machine (GDD §4), inventory + equipment ownership.

## Files

| File | Type | Responsibility |
|---|---|---|
| `player.tscn` / `player.gd` | Scene/Script | CharacterBody3D + camera rig. Owns movement (WASD + sprint + jump with mid-air momentum preservation), inline Mode+State enums, build menu interaction (opens `build_menu.tscn` on a CanvasLayer), blueprint mode entry via menu selection + exit via `ui_cancel` (Esc). Exposes `get_camera()` for BuildController raycasts. Does NOT own combat resolution (delegates to Combat) or build UX (delegates to Build when in Blueprint mode). **TODO:** source movement stats from CharacterDef instead of `@export` vars. |
| `camera_rig.gd` | Script | Programmatically constructs its own SpringArm3D + Camera3D children in `_ready()`. Mouse look (yaw on rig, pitch on spring arm), zoom via spring length, collision on spring arm (layer 1). LMB/RMB reserved for item actions, not consumed here. |
| `player_state_machine.gd` | Script *(planned — not yet implemented)* | Mode + State logic (Normal/Blueprint × Idle/Walk/Sprint/Attack/Interact/Sleep/Dead). Currently inline in `player.gd`; will be extracted as Mode+State grow. |
| `../data/characters/player.tres` | Data | CharacterDef: HP, base move speed, sprint mult, Stamina drain rate, Breath costs. See [Data Schemas](data-schemas.md). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `blueprint_mode_toggled(active)` | `player.gd` | BuildController, HUD | Yes | Enter Blueprint Mode |
| `player_died(context)` | `player.gd` *(planned — not yet emitted)* | GameState, HUD | Yes | Player Death / Respawn |

> **Interaction** is not signal-driven. The player resolves a target via crosshair raycast and calls `InteractionComponent.interact(self)` directly — see the "Interact (E key)" flow and the [Actions & Interaction](actions.md) subsystem.

## Flow Trace: Enter Blueprint Mode

**Trigger:** Player presses `build_toggle` in Normal mode.

1. `player.gd` instantiates `res://ui/build_menu/build_menu.tscn` on a CanvasLayer (layer in `"ui_layer"` group, or a new one); releases cursor for menu interaction.
2. Player selects a buildable from the menu → menu emits its selection signal → `player.gd._on_buildable_selected(id)`: sets `mode = BLUEPRINT`; emits `blueprint_mode_toggled(true)` via EventBus; re-captures mouse.
3. HUD updates: shows build-mode controls hint, ghost preview enabled.
4. BuildController activates; routes LMB/RMB/mouse-wheel to placement/rotation.
5. Movement states still apply (player can walk while building).
6. Player presses `ui_cancel` (Esc) → `exit_blueprint_mode()`: sets `mode = NORMAL`; emits `blueprint_mode_toggled(false)`.
7. Dismissing the build menu without selecting → re-captures cursor; mode stays `NORMAL`.

**End state:** Build UX active; LMB/RMB repurposed; movement unaffected. Exit is via Esc, not B.

## Flow Trace: Interact (E key)

**Trigger:** Player presses E (`"interact"` input action) in Normal mode while the crosshair is over an interactable.

1. Every `_physics_process` tick, `_update_interaction_target` runs a screen-center physics raycast (`interact_distance` 8.0, bodies only, the player RID excluded). Skipped entirely when `mode != NORMAL` (no targeting in Blueprint mode).
2. On a hit, `_find_interaction_component(hit.collider)` walks **up** the parent chain looking for a direct child named exactly `"InteractionComponent"`. The result is cached in `_current_interactable`.
3. E press → `_try_interact`: if `_current_interactable` is non-null **and** its `action_options` is non-empty, calls `_current_interactable.interact(self)`.
4. The `InteractionComponent` builds and mounts the interaction menu — see [Actions & Interaction](actions.md) for the rest of the chain (UI mount, button building, `GameAction.execute`).

**End state:** The interaction menu is open (or the action has run). Interaction does **not** change movement state — `State.INTERACT` is defined in the enum but never assigned; the player keeps walking/idle underneath.

## Flow Trace: Sprint and Breath

> **Implementation status: planned, not yet built.** Sprint currently works as an unconditional Shift hold with no Breath gating or drain. The design below is the intended shape. Treat this as the spec to implement against, not a description of current code.

**Trigger:** Player holds Shift while moving (and Breath > 20%).

1. Player checks `breath_component.can_sprint()` (> 20%); if blocked, ignore Shift.
2. `player.gd` sets `state = SPRINT`; speed = base × sprint_multiplier (1.6×).
3. Player calls `breath_component.set_sprinting(true)`.
4. BreathComponent._process: `breath -= sprint_drain_rate (20) × delta`; emits `breath_changed`.
5. If `breath ≤ 0` → emit `sprint_available(false)`; Player forced to WALK.
6. Player Shift-release OR Breath empty → `state = WALK`; `set_sprinting(false)`.
7. BreathComponent._process (not sprinting): `breath += regen_rate (10) × delta` (capped 100); emits `breath_changed`.

**Other burst actions** (jump/melee/ranged) call `breath_component.spend(cost)` — blocked if `breath < cost`. Stamina drains independently via StaminaComponent (ambient always; ×2 while working).

**End state:** Sprint drains Breath, regenerates when not sprinting; Stamina unaffected by sprint.

## Flow Trace: Jump and Mid-Air Control

**Trigger:** Player presses jump while on floor.

1. `player.gd` sets `velocity.y = jump_force`; captures current horizontal wish-velocity into `_velocity_on_jump` and current speed into `_speed_on_jump`.
2. Mid-air: the frozen momentum is resolved per-axis (forward/back, strafe) against live camera directions via `_resolve_air_axis`. Keys can only *brake* the frozen momentum — they never re-project it, so camera rotation mid-air cannot curve movement.
3. Per-axis braking rules: both keys held = cancel; key held matching momentum direction = preserve; key held opposing momentum = nudge at `jump_move_speed`; neither held = snap stop (no coasting).
4. Speed scale at takeoff is frozen — releasing/pressing Shift mid-air does not change momentum scale.

**End state:** Jump preserves horizontal momentum from takeoff; player can brake but not steer mid-air.

## Class Reference

### Class: Player

**Extends:** CharacterBody3D
**Script:** `player.gd`
**Description:** Player avatar. Owns movement, Mode+State transitions, input routing. Delegates combat to Combat subsystem, build UX to Build subsystem.
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
| `character_def` | `CharacterDef` *(planned)* | Loaded resource (player.tres): max_hp, base_move_speed, sprint_multiplier, stamina_drain_rate, breath costs. |
| `breath_component` | `BreathComponent` *(planned)* | @onready ref; queried for sprint gating + burst-action spending. |
| `stamina_component` | `StaminaComponent` *(planned)* | @onready ref; queried for work/movement multipliers. |

**Functions:**

| Function | Description |
|---|---|
| `get_camera() -> Camera3D` | Public accessor; delegates to CameraRig. Used by BuildController for screen-center raycasts. |
| `exit_blueprint_mode() -> void` | One-way exit: sets `mode = NORMAL`; emits `blueprint_mode_toggled(false)`. Called on `ui_cancel` (Esc) in Blueprint mode. |
| `_open_build_menu() -> void` | Instantiates `build_menu.tscn` on a CanvasLayer; releases cursor for menu interaction. |
| `_on_buildable_selected(id: String) -> void` | Enters Blueprint mode on menu selection: sets `mode = BLUEPRINT`; emits `blueprint_mode_toggled(true)`. |
| `_try_interact() -> void` | E-key handler: calls `_current_interactable.interact(self)` if a target is cached and offers actions. |
| `_interaction_raycast() -> Dictionary` | Screen-center physics raycast (`interact_distance`, bodies only, player excluded). Returns the raw hit dict (empty if nothing struck). |
| `_update_interaction_target() -> void` | Per-tick crosshair check; updates `_current_interactable` via `_find_interaction_component`. Skipped in Blueprint mode. |
| `_find_interaction_component(node: Node) -> InteractionComponent` | Walks up the parent chain from a hit collider looking for a child named exactly `"InteractionComponent"`. |
| `take_damage(amount: int, source: Node) -> void` *(planned)* | Forwards to Combat's damage resolver. |
