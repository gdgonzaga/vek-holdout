# Subsystem: Player

Third-person controller, camera rig, Mode+State machine (GDD §4), inventory + equipment ownership.

## Files

| File | Type | Responsibility |
|---|---|---|
| `player.tscn` / `player.gd` | Scene/Script | CharacterBody3D + camera rig. Owns movement physics (WASD + sprint + jump with mid-air momentum preservation), inline Mode+State enums, build menu interaction (opens `build_menu.tscn` on a CanvasLayer), blueprint mode entry via menu selection + B-driven navigation across three states (Normal → Menu → Placement). Exposes `get_camera()` for BuildController raycasts. Does NOT own raw input reading (delegates to InputComponent), combat resolution (delegates to Combat), or build UX (delegates to Build when in Blueprint mode). **TODO:** source movement stats from CharacterDef instead of `@export` vars. |
| `input_component.gd` | Script (Node) | Child node on the Player. Reads all raw player input and exposes it via signals (discrete actions: build toggle, primary action (LMB), interact press/release, mouse recapture, ui cancel) and per-frame query methods (`get_movement_input()`, `wants_jump()`, `wants_sprint()`). Does NOT own mouse-motion (CameraRig handles that) or mouse-mode management (Player owns that as a game-state concern). |
| `camera_rig.gd` | Script | Programmatically constructs its own SpringArm3D + Camera3D children in `_ready()`. Mouse look (yaw on rig, pitch on spring arm) via its own `_unhandled_input` — InputComponent does not absorb mouse-motion. Zoom via spring length, collision on spring arm (layer 1). **Over-the-shoulder framing** via `Camera3D.h_offset`/`v_offset` (export `h_offset`/`v_offset`): the frustum shifts so the body sits screen-left/bottom while the aim direction stays along the spring-arm axis (no camera rotation). LMB/RMB reserved for item actions, not consumed here. |
| `player_state_machine.gd` | Script *(planned — not yet implemented)* | Mode + State logic (Normal/Build Menu/Build Placement × Idle/Walk/Sprint/Attack/Interact/Sleep/Dead). Currently inline in `player.gd`; will be extracted as Mode+State grow. |
| `../core/step_climber.gd` | Script (component) | Shared stair-step / hop assist, added as a `StepClimber` child of both `player.tscn` and `colonist.tscn` (lives in core — the AGENTS ambiguous-ownership rule). Ticks after the body's `move_and_slide()` and walks the player over low lips/risers up to `step_height` (0.5); `hop_height` stays 0 on the player (the Space jump remains manual). See the class reference below. |
| `../data/characters/player.tres` | Data *(planned — does not exist yet)* | CharacterDef: HP, base move speed, sprint mult, Stamina drain rate, Breath costs. See [Data Schemas](data-schemas.md). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `build_placement_toggled(active)` | `player.gd` | BuildController, HUD (crosshair), `InstructionsLabel` | Yes | Enter Build Placement |
| `build_menu_toggled(open)` | `player.gd` | `InstructionsLabel` | Yes | Build menu visibility |
| `interactable_changed(component)` | `player.gd` | HUD (InteractLabel) | No (direct Player signal) | Target gained/lost under the crosshair |
| `player_died(context)` | `player.gd` *(planned — not yet emitted)* | GameState, HUD | Yes | Player Death / Respawn |

> **Interaction routing is split across Player + HUD.** The Player resolves + caches the crosshair target and emits `interactable_changed`; the **HUD** owns the E-key tap-vs-hold timer (tap → `execute_default_action`, hold → `open_interaction_menu`) — see the "Interact (E key)" flow and the [Actions & Interaction](actions.md) subsystem.

## Flow Trace: Enter Blueprint Mode

**Trigger:** Player presses `build_toggle` (B). B is the single navigation key across the three blueprint states (GDD §4 controls table, line 202: "Toggle Blueprint mode — B"). Esc exits placement straight back to Normal (`_on_ui_cancel`, which marks the event handled so `Main` doesn't also open the Pause overlay); the build menu consumes its own Esc while open.

1. `InputComponent._unhandled_input` catches `build_toggle` → emits `build_toggle_pressed`.
2. `player.gd._on_build_key_pressed` (connected to InputComponent's `build_toggle_pressed`) routes by `mode`:
   - **Normal** → calls `open_build_menu()`: instantiates `res://ui/build_menu/build_menu.tscn` on a CanvasLayer; releases cursor; sets `mode = BUILD_MENU`; tracks the menu in `_build_menu`; emits `build_menu_toggled(true)`.
   - **Build Menu** (`mode == BUILD_MENU`) → calls `_build_menu.close()`: menu emits `closed` → `_on_build_menu_closed` clears `_build_menu`, emits `build_menu_toggled(false)`, re-captures the mouse, and sets `mode = NORMAL`.
   - **Placement** (`mode == BUILD_PLACEMENT`) → calls `_exit_build_placement_mode()` (sets `mode = BUILD_MENU`, emits `build_placement_toggled(false)`), then `open_build_menu()` to return to item selection (which emits `build_menu_toggled(true)`).
3. Player selects a buildable from the menu → menu emits `EventBus.buildable_selected(id)` and frees itself → `player.gd._on_buildable_selected(id)`: clears `_build_menu`; emits `build_menu_toggled(false)`; sets `mode = BUILD_PLACEMENT`; emits `build_placement_toggled(true)` via EventBus; re-captures mouse.
4. The **InstructionsLabel** node — its own `instructions_label.gd`, decoupled from `hud.gd` — self-registers on both signals and drives its own `text` + `visible`: `build_placement_toggled(true)` shows the placement text ("Esc: cancel"), while `hud.gd` hides the crosshair; `build_menu_toggled(true)` shows the menu text ("Click an item to place\nEsc: cancel"). Both emit synchronously across a state change, and the entering-state handler's write lands last (e.g. Menu→Placement: the menu handler hides the label, then the placement handler shows it with placement text — same frame, no flicker). On exit, each handler sets the label's `visible = false`.
5. BuildController activates; routes LMB (place) / RMB (remove) / mouse wheel (rotate step) / R (cycle axis) to placement + rotation.
6. Movement states still apply (player can walk while building).

**End state:** Build UX active; LMB/RMB/wheel/R repurposed; movement unaffected. B exits Placement back to the Menu (quick item swap); Esc exits Placement straight to Normal.

## Flow Trace: Interact (E key)

**Trigger:** Player presses/releases E (`"interact"` input action) in Normal mode while the crosshair is over an interactable. The tap-vs-hold decision is made by the **HUD**, not the Player.

1. Every `_physics_process` tick, `_update_interaction_target` runs a screen-center physics raycast (`interact_distance` 8.0, bodies only, the player RID excluded). Skipped entirely when `mode != NORMAL` (no targeting in Blueprint mode). On a target change it emits the direct `interactable_changed(component)` signal → HUD updates the InteractLabel.
2. On a hit, `_find_interaction_component(hit.collider)` walks **up** the parent chain looking for a direct child named exactly `"InteractionComponent"`. The result is cached in `_current_interactable`.
3. `InputComponent` emits `interact_pressed` / `interact_released` — **both are wired to the HUD** (`hud.gd`), which runs the tap/hold scheme:
   - **Quick tap** (released within 0.3 s) → `Player.execute_default_action()`: runs `action_options[0].action.execute(self, target)` directly (no menu), then re-emits `interactable_changed` so the label refreshes (e.g. a blueprint's material-progress line).
   - **Long press** (held ≥ 0.3 s) → `Player.open_interaction_menu()`: calls `_current_interactable.interact(self)`, which builds and mounts the full action menu.
4. The `InteractionComponent` builds and mounts the interaction menu (long-press path) — see [Actions & Interaction](actions.md) for the rest of the chain (UI mount, button building, `GameAction.execute`).

**End state:** Either the default action ran (tap) or the interaction menu is open (hold). Interaction does **not** change movement state — `State.INTERACT` is defined in the enum but never assigned; the player keeps walking/idle underneath.

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

## Flow Trace: Stepping Over Low Obstacles

**Trigger:** A grounded player walks into a low vertical lip (a few-cm mesh edge, a stair riser) that plain `move_and_slide()` treats as a wall.

1. `player.gd._handle_move_keys` runs `move_and_slide()`; the capsule stops against the lip (`is_on_wall()` true — contact normals steeper than `floor_max_angle` read as walls, and the engine default `floor_snap_length` only ever pulls *down*).
2. The `StepClimber` child ticks next (children process after parents): it derives the push direction from the wall normal (`move_and_slide()` has already zeroed the horizontal velocity against the face by then) and probes a climb — lift the capsule to `step_height + clearance`, sweep forward past the lip, sweep down to a landing, then validate the landing normal against `floor_max_angle` (physics queries with the body's own capsule, body RID excluded).
3. A landing within `step_height` teleports the body onto the step and `apply_floor_snap()` re-establishes floor state the same frame, so the mid-air momentum logic above never sees a spurious airborne tick. Obstacles up to `hop_height` would get a solved vertical impulse instead — but the Player leaves `hop_height` at 0 (colonists use the hop; see [Colonists](colonists.md)).
4. The body root sets `floor_snap_length = 0.5` so walking *down* risers stays glued to the steps instead of micro-falling off each edge.

**End state:** Lips and risers up to `step_height` (0.5) are walked over like stairs; taller obstacles still require the manual Space jump.

## Class Reference

### Class: Player

**Extends:** CharacterBody3D
**Script:** `player.gd`
**Description:** Player avatar. Owns movement physics, Mode+State transitions, mouse-mode management. Raw input reading is delegated to the `InputComponent` child. Delegates combat to Combat subsystem, build UX to Build subsystem.
**Used by:** HUD (interact label + inventory panel + tap/hold interact routing), Build (placement source), Combat (damage target — planned).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `walk_speed` | `float` | `[export default 3.5]` Ground move speed. **TODO:** source from CharacterDef. |
| `sprint_speed` | `float` | `[export default 7.0]` Sprint speed. **TODO:** source from CharacterDef. |
| `gravity` | `float` | `[export default 9.8]` Gravity acceleration. |
| `jump_force` | `float` | `[export default 5.0]` Vertical impulse on jump. |
| `jump_move_speed` | `float` | `[export default 0.5]` Mid-air nudge speed for axis braking. |
| `mode` | `Mode` enum | `NORMAL`, `BUILD_MENU`, `BUILD_PLACEMENT`, or `DIG_BOX_DESIGNATION`. |
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
| `_exit_build_placement_mode() -> void` | Placement→menu transition: sets `mode = BUILD_MENU`; emits `build_placement_toggled(false)`. Called by `_on_build_key_pressed` from the placement branch (B to drop the selected buildable and return to item selection). |
| `open_build_menu() -> void` | Instantiates `build_menu.tscn` on a CanvasLayer; releases cursor; sets `mode = BUILD_MENU`; tracks the menu in `_build_menu`; emits `build_menu_toggled(true)`. No-op if a menu is already open. Called by `_on_build_key_pressed` from Normal or Placement. |
| `_on_build_key_pressed() -> void` | B-key state router (connected to InputComponent's `build_toggle_pressed`): Normal → open menu; Build Menu → close menu; Placement → exit placement + reopen menu. |
| `_on_buildable_selected(id: String) -> void` | Enters placement on menu selection: clears `_build_menu`; emits `build_menu_toggled(false)`; sets `mode = BUILD_PLACEMENT`; emits `build_placement_toggled(true)`. |
| `_on_build_menu_closed() -> void` | Menu dismissed without a selection: clears `_build_menu`; emits `build_menu_toggled(false)`; re-captures the mouse; sets `mode = NORMAL`. |
| `execute_default_action() -> void` | Quick-tap E path (the HUD calls this on a <0.3s tap): runs `action_options[0].action.execute(self, target)` directly with no menu, then re-emits `interactable_changed` so the label refreshes. |
| `open_interaction_menu() -> void` | Long-press E path (the HUD calls this after a ≥0.3s hold): calls `_current_interactable.interact(self)` to build + mount the full action menu. |
| `_on_primary_action() -> void` | LMB handler (connected to InputComponent's `primary_action_pressed`). In Normal mode with a crosshair target: runs `FarmManualAction` on a `Growable` target or `HarvestAction` on a `Harvestable` target. No-op while busy, in Blueprint mode, or when UiGate blocks input. |
| `clear_interactable() -> void` | Clears `_current_interactable` and emits `interactable_changed(null)`. Called by `SceneManager.unload_current_map` before the map's InteractionComponent children are freed (so the HUD label doesn't linger over the title screen). |
| `_recapture_mouse() -> void` | Sets `Input.mouse_mode = CAPTURED`. Connected to InputComponent's `recapture_requested` signal (click-to-recapture after alt-tab). |
| `_on_ui_cancel() -> void` | Esc handler (connected to InputComponent's `ui_cancel_pressed`). In `BUILD_PLACEMENT` it exits straight to Normal: marks the event handled (so `Main._unhandled_input` doesn't also open the Pause overlay), sets `mode = NORMAL`, emits `build_placement_toggled(false)`. Otherwise a no-op — the build menu owns its own Esc, and plain Esc opens the Pause overlay via `Main`. |
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
| `primary_action_pressed()` | Emitted on LMB during gameplay. Handled by `_on_primary_action`: runs `FarmManualAction` / `HarvestAction` on the crosshair target when it carries a `Growable` / `Harvestable` component. |
| `interact_pressed()` | Emitted on E key-down (`interact` action). Consumed by the HUD for hold detection. |
| `interact_released()` | Emitted on E key-up (`interact` action). Consumed by the HUD: release before the hold threshold = quick tap. |
| `recapture_requested()` | Emitted on mouse click while cursor is visible. |
| `ui_cancel_pressed()` | Emitted on Esc (`ui_cancel` action). |

**Functions:**

| Function | Description |
|---|---|
| `get_movement_input() -> Vector2` | Normalized WASD input. Positive y = backward, negative y = forward, positive x = right. |
| `wants_jump() -> bool` | Whether the jump key (Space) is held. |
| `wants_sprint() -> bool` | Whether the sprint key (Shift) is held. |

### Class: CameraRig

**Extends:** Node3D
**Script:** `camera_rig.gd`
**Description:** Third-person orbit rig built programmatically in `_ready()` (a `SpringArm3D` child owning a `Camera3D` child, so `player.tscn` only needs the CameraRig node). Tracks the parent Player's position; mouse motion orbits around it — yaw on this rig, pitch on the spring arm (clamped). The rig does NOT inherit the avatar's visual facing, so the camera orbit stays independent of where the capsule looks. LMB/RMB are not consumed here (reserved for item actions).
**Used by:** `Player` (`get_camera`, save/load orientation).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `sensitivity` | `float` | `[export default 0.0025]` Mouse-look sensitivity. |
| `spring_length` | `float` | `[export default 3.0]` Spring-arm length (camera distance). Applied to the SpringArm3D; there is no runtime zoom control yet. |
| `min_pitch` / `max_pitch` | `float` | `[export, range -1.2..1.2]` Pitch clamp (radians). |
| `height_offset` | `float` | `[export default 1.4]` Pivot height above the Player (eye/shoulder height). |
| `h_offset` | `float` | `[export default 0.5]` `Camera3D.h_offset` — horizontal frustum shift (body frames screen-left). |
| `v_offset` | `float` | `[export default 0.4]` `Camera3D.v_offset` — vertical frustum shift. |

> Over-the-shoulder framing uses `h_offset`/`v_offset` (frustum shift) rather than rotating the camera, so the aim direction stays along the spring-arm axis.

**Functions:**

| Function | Description |
|---|---|
| `get_camera() -> Camera3D` | The active Camera3D (child of the spring arm). Returns null if the rig isn't ready yet (callers must wait for `_ready`). |
| `get_yaw() -> float` / `get_pitch() -> float` | Current orbit yaw / pitch (radians). Save/load accessors for otherwise-private state. |
| `set_orientation(yaw: float, pitch: float) -> void` | Restore the orbit (radians); pitch is clamped and applied immediately. Used by save/load. |

### Class: StepClimber

**Extends:** Node
**Script:** `../core/step_climber.gd` (shared with [Colonists](colonists.md) — ambiguous ownership → core)
**Description:** Stair-step / hop locomotion assist, added as a child node of both `player.tscn` and `colonist.tscn`. Children tick after their parent in `_physics_process`, so the component sees the body's post-`move_and_slide()` state and needs no hooks in either body's movement kernel. When a grounded body presses into an obstacle (`is_on_wall()` — which only turns true when the body actually moved into the wall that frame) it first tries to STEP onto it (lift probe → forward sweep → down sweep, teleport + `apply_floor_snap()`), and — when `hop_height > 0` — HOPS obstacles up to `hop_height` with a vertical impulse solved from the probed rise; the body's own gravity and horizontal steering carry it over. The pathfinder knows nothing of this component — walkability stays a pure graph question.
**Used by:** Player, Colonist (scene child in both).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `step_height` | `float` | `[export default 0.5]` Tallest obstacle stepped onto (teleport + floor snap). |
| `hop_height` | `float` | `[export default 0.0]` Tallest obstacle hopped (impulse). 0 disables hopping; `colonist.tscn` sets 1.05 — one voxel block. |
| `hop_gravity` | `float` | `[export default 9.8]` Gravity used to solve the hop impulse (`sqrt(2·g·(rise + clearance))`). |
| `hop_cooldown` | `float` | `[export default 0.25]` Minimum seconds between hop impulses — no pogo against unclimbable walls. |
