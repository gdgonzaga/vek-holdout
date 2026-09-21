# Subsystem: Player

Third-person controller, camera rig, Mode+State machine (GDD §4), inventory + equipment ownership.

## Files

| File | Type | Responsibility |
|---|---|---|
| `player.tscn` / `player.gd` | Scene/Script | CharacterBody3D + camera rig. Owns the movement *state*, the inline Mode+State enums, the equipped item's LMB action, and (locomotion is the `Motor` child's job and everything done to the world under the crosshair is the `Interactor` child's, see the next rows) build menu interaction (opens `build_menu.tscn` on a CanvasLayer), blueprint mode entry via menu selection + B-driven navigation across three states (Normal → Menu → Placement). Exposes `get_camera()` for BuildController raycasts and `get_look_direction()` / `get_look_pitch()` for the animation controller's facing and look lean. Does NOT own raw input reading (delegates to InputComponent), combat resolution (delegates to Combat), or build UX (delegates to Build when in Blueprint mode). |
| `player_motor.gd` | Script (Node component) | `Motor` child of the Player (`class_name PlayerMotor`). Owns locomotion: gravity, walk/sprint, jump, ledge exit, and the frozen air momentum, plus the tunables (`walk_speed`, `sprint_speed`, `gravity`, `jump_force`, `jump_move_speed`). The Player ticks it explicitly from its own `_physics_process` (it has no `_physics_process` of its own) so the order against `StepClimber` is unchanged. Knows nothing of needs, water, death or busy: the Player folds those into a lock flag and one speed multiplier. **TODO:** source movement stats from CharacterDef instead of `@export` vars. |
| `player_interactor.gd` | Script (Node component) | `Interactor` child of the Player (`class_name PlayerInteractor`). Owns what the player does to the world under the crosshair: the crosshair target (raycast, component lookup, `interactable_changed`), the E-key tap/hold paths (`execute_default_action`, `open_interaction_menu`), and the world half of LMB (`primary_interact`: a manual forage/farm/harvest interaction on the target, else mining the terrain or block under it, with the grid decided by the struck collider's ownership). Ticked explicitly by the Player (`update_target` each physics tick, before the motor); has no `_physics_process` of its own. The equipped item's LMB action, the LMB gates and the animation controller stay with the Player. |
| `player_animation_controller.gd` | Script (Node component) | Child node on the Player (`AnimationController`). Drives the scene `AnimationTree`: the `Locomotion` state machine (Idle/Walk/Sprint blend keyed by horizontal speed, plus jump states) and the upper-body `ActionOneshot` overlay (`trigger_action`). Turns `Visuals` to face the camera's look direction and feeds camera pitch to the `LookLean` node, which leans the Chest/Head bones — see the "Look: Facing and Lean" flow. `_setup_skeleton()` re-homes the imported model skeleton's unique name (`GeneralSkeleton`) to the player scene root so `%GeneralSkeleton:<bone>` tracks bind — see `docs/HOWTO-use-makehuman-mixamo.md`. |
| `input_component.gd` | Script (Node) | Child node on the Player. Reads all raw player input and exposes it via signals (discrete actions: build toggle, primary action (LMB), interact press/release, mouse recapture, ui cancel) and per-frame query methods (`get_movement_input()`, `wants_jump()`, `wants_sprint()`). Does NOT own mouse-motion (CameraRig handles that) or mouse-mode management (Player owns that as a game-state concern). |
| `camera_rig.gd` | Script | Programmatically constructs its own SpringArm3D + Camera3D children in `_ready()`. Mouse look (yaw on rig, pitch on spring arm) via its own `_unhandled_input` — InputComponent does not absorb mouse-motion. Zoom via spring length, collision on spring arm (layer 1). **Over-the-shoulder framing** via `Camera3D.h_offset`/`v_offset` (export `h_offset`/`v_offset`): the frustum shifts so the body sits screen-left/bottom while the aim direction stays along the spring-arm axis (no camera rotation). LMB/RMB reserved for item actions, not consumed here. |
| `player_state_machine.gd` | Script *(planned — not yet implemented)* | Mode + State logic (Normal/Build Menu/Build Placement × Idle/Walk/Sprint/Attack/Interact/Sleep/Dead). Currently inline in `player.gd`; will be extracted as Mode+State grow. |
| `../core/step_climber.gd` | Script (component) | Shared stair-step / hop assist, added as a `StepClimber` child of both `player.tscn` and `colonist.tscn` (lives in core — the AGENTS ambiguous-ownership rule). Ticks after the body's `move_and_slide()` and walks the player over low lips/risers up to `step_height` (0.5); `hop_height` stays 0 on the player (the Space jump remains manual). See the class reference below. |
| `../core/look_lean.gd` | Script (component) | Shared torso/head look lean, added as a `LookLean` child of both `player.tscn` and `colonist.tscn` (lives in core — the AGENTS ambiguous-ownership rule). Holds the lean knobs and bends Chest/Head by whatever pitch its owner's animation controller feeds it each frame. See the class reference below. |
| `Inventory` (scene child) | Scene node | `CharacterInventory`, scene-placed under `player.tscn`. Carry inventory backing `add_item`/`remove_item`/`drop_item`/`has_item`/`can_carry`. See [Inventory](inventory.md). |
| *(code-created in `_ready`)* | — | `HungerComponent` (via `HungerComponent.ensure_on(self)`, see [Hunger](hunger.md)), `SkillSet` (unseeded — every skill reads L1 until trained by use), and `Equipment` + `EquipmentVisualizer` (via `Equipment.ensure_on(self, equipment)`, see [Equipment](equipment.md)). |
| `../colonists/command_controller.gd` | Script (Node, optional) | Child node (`CommandController`), present only when authored in the scene (`get_node_or_null`). Given the active camera in `_ready` for issuing world-space commands (e.g. colonist orders). |
| `../data/characters/player.tres` | Data *(planned — does not exist yet)* | CharacterDef: HP, base move speed, sprint mult, Stamina drain rate, Breath costs. See [Data Schemas](data-schemas.md). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `build_placement_toggled(active)` | `player.gd` | BuildController, HUD (crosshair), `InstructionsLabel` | Yes | Enter Build Placement |
| `build_menu_toggled(open)` | `player.gd` | `InstructionsLabel` | Yes | Build menu visibility |
| `dig_box_toggled(active)` | `player.gd` | DigBoxController, DigBoxHud | Yes | Toggle Dig Box Designation |
| `area_designation_toggled(active)` | `player.gd` | AreaDesignationController, AreaDesignationHud | Yes | Toggle Area Designation |
| `harvest_box_toggled(active)` | `player.gd` | HarvestBoxController, HUD | Yes | Toggle Harvest Box Designation |
| `interactable_changed(component)` | `player_interactor.gd` (`player.interactor`) | HUD (InteractLabel) | No (direct signal on the Player's `Interactor` child) | Target gained/lost under the crosshair |
| `player_died(context)` | `player.gd` | GameState, HUD | Yes | Player Death / Respawn |

> **Interaction routing is split across Player + HUD.** The Player's `Interactor` resolves + caches the crosshair target and emits `interactable_changed`; the **HUD** owns the E-key tap-vs-hold timer (tap → `player.interactor.execute_default_action`, hold → `player.interactor.open_interaction_menu`) — see the "Interact (E key)" flow and the [Actions & Interaction](actions.md) subsystem.

## Flow Trace: Enter Blueprint Mode

**Trigger:** Player presses `build_toggle` (B). B is the single navigation key across the three blueprint states (GDD §4 controls table, line 202: "Toggle Blueprint mode — B"). Esc exits placement straight back to Normal (`_on_ui_cancel`, which marks the event handled so `Main` doesn't also open the Pause overlay); the build menu consumes its own Esc while open.

1. `InputComponent._unhandled_input` catches `build_toggle` → emits `build_toggle_pressed`.
2. `player.gd._on_build_key_pressed` (connected to InputComponent's `build_toggle_pressed`) routes by `mode`:
   - **Normal** → calls `open_build_menu()`: instantiates `res://ui/build_menu/build_menu.tscn` on the CanvasLayer in group `hud_layer`, else `ui_layer` (`_resolve_menu_layer`; the UILayer is SceneManager's full-screen slot, so modals prefer the HUD layer like every other panel-mounting call site; scenes with neither get one fallback layer that joins `hud_layer`, so it is reused rather than re-created per open, mounted on the running scene or the tree root); releases cursor; sets `mode = BUILD_MENU`; tracks the menu in `_build_menu`; emits `build_menu_toggled(true)`.
   - **Build Menu** (`mode == BUILD_MENU`) → calls `_build_menu.close()`: menu emits `closed` → `_on_build_menu_closed` clears `_build_menu`, emits `build_menu_toggled(false)`, re-captures the mouse, and sets `mode = NORMAL`.
   - **Placement** (`mode == BUILD_PLACEMENT`) → calls `_exit_build_placement_mode()` (sets `mode = BUILD_MENU`, emits `build_placement_toggled(false)`), then `open_build_menu()` to return to item selection (which emits `build_menu_toggled(true)`).
3. Player selects a buildable from the menu → menu emits `EventBus.buildable_selected(id)` and frees itself → `player.gd._on_buildable_selected(id)`: clears `_build_menu`; emits `build_menu_toggled(false)`; sets `mode = BUILD_PLACEMENT`; emits `build_placement_toggled(true)` via EventBus; re-captures mouse.
4. The **InstructionsLabel** node — its own `instructions_label.gd`, decoupled from `hud.gd` — self-registers on both signals and drives its own `text` + `visible`: `build_placement_toggled(true)` shows the placement text ("Esc: cancel"), while `hud.gd` hides the crosshair; `build_menu_toggled(true)` shows the menu text ("Click an item to place\nEsc: cancel"). Both emit synchronously across a state change, and the entering-state handler's write lands last (e.g. Menu→Placement: the menu handler hides the label, then the placement handler shows it with placement text — same frame, no flicker). On exit, each handler sets the label's `visible = false`.
5. BuildController activates; routes LMB (place) / RMB (remove) / mouse wheel (rotate step) / R (cycle axis) to placement + rotation.
6. Movement states still apply (player can walk while building).

**End state:** Build UX active; LMB/RMB/wheel/R repurposed; movement unaffected. B exits Placement back to the Menu (quick item swap); Esc exits Placement straight to Normal.

## Flow Trace: Interact (E key)

**Trigger:** Player presses/releases E (`"interact"` input action) in Normal mode while the crosshair is over an interactable. The tap-vs-hold decision is made by the **HUD**, not the Player.

1. Every `_physics_process` tick, `Player` calls `interactor.update_target()`, which runs a screen-center physics raycast (`interact_distance` 8.0, bodies only, the player RID excluded). Skipped entirely when `mode != NORMAL` (no targeting in Blueprint mode). On a target change it emits the direct `interactable_changed(component)` signal → HUD updates the InteractLabel.
2. On a hit, `PlayerInteractor._find_interaction_component(hit.collider)` walks **up** the parent chain looking for a direct child named exactly `"InteractionComponent"`. The result is cached in `_current_interactable`.
3. `InputComponent` emits `interact_pressed` / `interact_released` — **both are wired to the HUD** (`hud.gd`), which runs the tap/hold scheme:
   - **Quick tap** (released within 0.3 s) → `player.interactor.execute_default_action()`: runs `action_options[0].action.execute(self, target)` directly (no menu), then re-emits `interactable_changed` so the label refreshes (e.g. a blueprint's material-progress line).
   - **Long press** (held ≥ 0.3 s) → `player.interactor.open_interaction_menu()`: calls `_current_interactable.interact(player)`, which builds and mounts the full action menu.
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

1. `PlayerMotor.tick` (called from `Player._physics_process`) runs `_try_jump` after gravity and before `move_and_slide()`, so the impulse is applied on the tick the key is seen: if unlocked, on the floor (as seen at the start of the tick) and `_input.wants_jump()`, it sets `velocity.y = jump_force`; captures the current horizontal wish-velocity (from `_input.get_movement_input()`) into `_velocity_on_jump` and the current speed into `_speed_on_jump`. It also marks the takeoff as consumed (`_was_on_floor = false`), so the first airborne tick is not mistaken for a ledge exit that would overwrite the frozen momentum. Stepping off a ledge without jumping captures the same two values on the first airborne tick.
2. Mid-air: the frozen momentum is resolved per-axis (forward/back, strafe) against live camera directions (`CameraRig.get_forward_horizontal()` / `get_right_horizontal()`) via the pure static `PlayerMotor.resolve_air_axis`. Movement input is read each tick via `_input.get_movement_input()` — keys can only *brake* the frozen momentum, they never re-project it, so camera rotation mid-air cannot curve movement.
3. Per-axis braking rules: both keys held = cancel; key held matching momentum direction = preserve; key held opposing momentum = nudge at `jump_move_speed`; neither held = snap stop (no coasting).
4. Speed scale at takeoff is frozen — releasing/pressing Shift mid-air does not change momentum scale. The frozen value comes from the motor's `_ground_speed(speed_multiplier)`, where the Player supplies `_movement_speed_multiplier()` (the depleted-need multiplier × wading drag) once per tick — the same source as ground movement, so jumping or stepping off a ledge cannot shed a slowdown that walking would keep.

**End state:** Jump preserves horizontal momentum from takeoff; player can brake but not steer mid-air.

## Flow Trace: Stepping Over Low Obstacles

**Trigger:** A grounded player walks into a low vertical lip (a few-cm mesh edge, a stair riser) that plain `move_and_slide()` treats as a wall.

1. `PlayerMotor.tick` (called from `Player._physics_process`) runs `move_and_slide()`; the capsule stops against the lip (`is_on_wall()` true — contact normals steeper than `floor_max_angle` read as walls, and the engine default `floor_snap_length` only ever pulls *down*).
2. The `StepClimber` child ticks next (children process after parents): it derives the push direction from the wall normal (`move_and_slide()` has already zeroed the horizontal velocity against the face by then) and probes a climb — lift the capsule to `step_height + clearance`, sweep forward past the lip, sweep down to a landing, then validate the landing normal against `floor_max_angle` (physics queries with the body's own capsule, body RID excluded).
3. A landing within `step_height` teleports the body onto the step and `apply_floor_snap()` re-establishes floor state the same frame, so the mid-air momentum logic above never sees a spurious airborne tick. Obstacles up to `hop_height` would get a solved vertical impulse instead — but the Player leaves `hop_height` at 0 (colonists use the hop; see [Colonists](colonists.md)).
4. The body root sets `floor_snap_length = 0.5` so walking *down* risers stays glued to the steps instead of micro-falling off each edge.

**End state:** Lips and risers up to `step_height` (0.5) are walked over like stairs; taller obstacles still require the manual Space jump.

## Flow Trace: Look: Facing and Lean

**Trigger:** Mouse motion orbits the `CameraRig` (yaw on the rig, pitch on the spring arm). Runs every idle frame in `PlayerAnimationController._process`, whether or not the player is moving.

1. `_update_mesh_rotation` reads `Player.get_look_direction()` (the rig's forward, flattened to horizontal) and eases `Visuals.rotation.y` toward it at `rotation_speed`. Facing follows the camera, not the travel direction, so holding back (S) or strafing moves the body without turning it. There are no directional locomotion clips yet, so walking backward plays the forward walk cycle.
2. `_update_animation_state` sets the `Grounded` blend position and jump transitions; the `AnimationTree` writes the resulting pose to the skeleton in its own process pass.
3. The controller passes `Player.get_look_pitch()` (radians, look-up positive) to `LookLean.apply`, which clamps it to `max_up_deg` / `max_down_deg` and eases toward it at `smoothing` (frame-rate independent). The lean is split between the `Chest` bone (`chest_share`) and the `Head` bone (the rest), each composed onto the pose the tree just wrote as an extra local-X rotation. This rig bends forward on positive local-X rotation, so the applied lean is the negated pitch: looking up leans back, looking down leans forward.
4. Ordering: `_ready` sets the controller's `process_priority` to the tree's plus one, so step 3 always runs after the tree's pose write regardless of scene node order. The tree re-poses Chest and Head every frame, so the additive lean never accumulates. `Skeleton3D`'s deferred update then skins the mesh with the leaned pose.

**End state:** The avatar faces where the camera looks, and its torso/head lean with camera pitch while the legs keep the locomotion pose.

> **Why bones, and why it's subtle from the player's camera.** Pitching the whole `Visuals` node would tip the character over as camera pitch approaches straight up/down; bending two upper-body bones keeps the feet planted. From the default over-the-shoulder camera the lean reads weakly: the camera sits behind the avatar and pitches with it, so a forward/back bend runs mostly along the line of sight. It shows clearly from side angles. Tune it on the `LookLean` node in `player.tscn` (colonists have their own `LookLean` node — see [Colonists](colonists.md)).

## Class Reference

### Class: Player

**Extends:** CharacterBody3D
**Script:** `player.gd`
**Description:** Player avatar. Owns Mode+State transitions and the movement state (locomotion is the `motor` child's job), mouse-mode management. Raw input reading is delegated to the `InputComponent` child. Combat is a `HealthComponent` child plus dispatch through the equipped weapon's `CombatActionParams` — see [Combat](combat.md). Build UX delegates to the Build subsystem.
**Used by:** HUD (interact label + tap/hold interact routing; it hosts the `InventoryPanel`, which reads `inventory` and `equipment`), Build (placement source), Combat (damage target via `health_component`; scanned by enemy/colonist `BTActionScanThreats`).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `motor` | `PlayerMotor` | `@onready` reference to the scene-placed `$Motor` child. Holds the locomotion tunables and frozen air momentum; wired with `motor.setup(_input, _rig)` in `_ready`, ticked from `_physics_process`, cleared with `motor.reset()` on load. |
| `mode` | `Mode` enum | `NORMAL`, `BUILD_MENU`, `BUILD_PLACEMENT`, `DIG_BOX_DESIGNATION`, `AREA_DESIGNATION`, `DESIGNATION_MENU`, or `HARVEST_BOX_DESIGNATION`. |
| `state` | `State` enum | Movement/action state (`IDLE`, `WALK`, `SPRINT`, `ATTACK`, `INTERACT`, `SLEEP`, `DEAD`). Only `IDLE`/`WALK`/`SPRINT`/`DEAD` are actively assigned at runtime; `ATTACK`/`INTERACT`/`SLEEP` are placeholders. `DEAD` is terminal: the per-tick movement update (`_resolve_move_state`) keeps it instead of overwriting it. |
| `_busy` | `bool` | True while a timed action (e.g. a `BuildAction` with `build_time`) holds the player; gates movement, jump, and discrete actions. Set via `is_busy()`/`set_busy()`. Input handlers gate on `is_input_locked()` (`_busy or is_dead`), so a dead player takes no movement, jump, interact, primary-action or hotkey input; `is_busy()` itself reports the timed-action flag only. |
| `interactor` | `PlayerInteractor` | `@onready` reference to the scene-placed `$Interactor` child. Owns the crosshair target and the E/LMB world actions; wired with `interactor.setup(self, _camera)` in `_ready` and ticked from `_physics_process`. |
| `_input` | `InputComponent` | `@onready` reference to the `$InputComponent` child. All raw input reads go through this component. |
| `inventory` | `CharacterInventory` | `@onready` reference to the scene-placed `$Inventory` child. Carry inventory backing `add_item`/`remove_item`/`drop_item`/`has_item`/`can_carry`/`consume_food_item`. |
| `equipment` | `Equipment` | 8-slot gear component; resolved/created in `_ready` via `_ensure_equipment()` (`Equipment.ensure_on`). See [Equipment](equipment.md). |
| `needs` | `ColonistNeeds` | Resolved/created in `_ready`. Manages physiological needs (hunger decay, starvation speed penalties) and `consume_food_item`'s hunger restore. See [Hunger](hunger.md). |
| `skill_set` | `SkillSet` | Code-created, unseeded (every skill reads L1 until trained). Shared with `Colonist` so `MinSkillCondition` reads either actor reflectively. Persisted by `serialize()` under `"skills"`, like a colonist's. |
| `health_component` | `HealthComponent` | `@onready` reference to the scene-placed `$HealthComponent` child (`max_hp = 100`). See [Combat](combat.md). |
| `is_dead` | `bool` *(computed)* | `health_component.is_dead`. Lets threat-scanning tasks skip a dead player the same way they skip dead colonists/enemies. |
| `command_controller` | `CommandController` *(optional)* | `@onready get_node_or_null("CommandController")`; given the active camera in `_ready` if present. |
| `character_def` | `CharacterDef` *(planned)* | Loaded resource (player.tres): max_hp, base_move_speed, sprint_multiplier, stamina_drain_rate, breath costs. |
| `breath_component` | `BreathComponent` *(planned)* | @onready ref; queried for sprint gating + burst-action spending. |
| `stamina_component` | `StaminaComponent` *(planned)* | @onready ref; queried for work/movement multipliers. |

**Functions:**

| Function | Description |
|---|---|
| `get_camera() -> Camera3D` | Public accessor; delegates to CameraRig. Used by BuildController for screen-center raycasts. |
| `get_look_direction() -> Vector3` | The camera rig's forward, flattened to horizontal and normalized (via `CameraRig.get_forward_horizontal()`, the same forward the motor's wish vectors use). Drives `PlayerAnimationController` body facing. |
| `get_look_pitch() -> float` | Camera pitch in radians, look-up positive (`CameraRig.get_pitch()`). Drives the look lean. |
| `_exit_build_placement_mode() -> void` | Placement→menu transition: sets `mode = BUILD_MENU`; emits `build_placement_toggled(false)`. Called by `_on_build_key_pressed` from the placement branch (B to drop the selected buildable and return to item selection). |
| `open_build_menu() -> void` | Instantiates `build_menu.tscn` on a CanvasLayer; releases cursor; sets `mode = BUILD_MENU`; tracks the menu in `_build_menu`; emits `build_menu_toggled(true)`. No-op if a menu is already open. Called by `_on_build_key_pressed` from Normal or Placement. |
| `_on_build_key_pressed() -> void` | B-key state router (connected to InputComponent's `build_toggle_pressed`): Normal → open menu; Build Menu → close menu; Placement → exit placement + reopen menu. |
| `_on_buildable_selected(id: String) -> void` | Enters placement on menu selection: clears `_build_menu`; emits `build_menu_toggled(false)`; sets `mode = BUILD_PLACEMENT`; emits `build_placement_toggled(true)`. |
| `_on_build_menu_closed() -> void` | Menu dismissed without a selection: clears `_build_menu`; emits `build_menu_toggled(false)`; re-captures the mouse; sets `mode = NORMAL`. |
| `_on_primary_action() -> void` | LMB handler (connected to InputComponent's `primary_action_pressed`). No-op while locked (busy or dead), outside Normal mode, or when UiGate blocks input. Dispatch order: the equipped item's primary action (`_try_execute_equipped_action`), else `interactor.primary_interact()` (a manual interaction on the crosshair target, else mining; see `PlayerInteractor`). |
| `_recapture_mouse() -> void` | Sets `Input.mouse_mode = CAPTURED`. Connected to InputComponent's `recapture_requested` signal (click-to-recapture after alt-tab). |
| `_on_ui_cancel() -> void` | Esc handler (connected to InputComponent's `ui_cancel_pressed`). In any tool mode (`BUILD_PLACEMENT`, `DIG_BOX_DESIGNATION`, `AREA_DESIGNATION`, `HARVEST_BOX_DESIGNATION`) it exits straight to Normal via `_exit_tool_mode`: marks the event handled (so `Main._unhandled_input` doesn't also open the Pause overlay), sets `mode = NORMAL`, and emits that mode's toggled signal with `false`. Otherwise a no-op — Normal has nothing to leave, the menus own their own Esc, and plain Esc opens the Pause overlay via `Main`. |
| `is_busy() -> bool` / `set_busy(value: bool) -> void` | Query/set `_busy`. Taken by `BuildAction` before showing its progress gauge, released on the gauge's `completed`/`cancelled` signals. |
| `add_item(item_id, count) -> int` / `remove_item(item_id, count) -> int` | Thin wrappers over `inventory.add`/`inventory.remove`. Return overflow / shortfall respectively. |
| `has_item(item_id, count) -> bool` / `can_carry(item_id, count) -> bool` | Thin wrappers over `inventory.has_item`/`inventory.can_add`. |
| `drop_item(item_id: String, count: int = 1) -> WorldItem` | Removes `count` of `item_id` from inventory and spawns it as a `WorldItem` in front of the player (impulse toss). "In front" is `get_look_direction()` (the camera's horizontal forward): the body never rotates, so its basis cannot say which way the player faces. Only carried items can be dropped: a held (equipped) item is in `equipment`, not the inventory, so it must be unequipped first. Returns null if the item wasn't carried. |
| `consume_food_item(item_id: String) -> bool` | Player's instant-eat path (mirrors the colonist BT eat flow without the animation/timer): validates `ItemDef.food`, removes 1 unit, restores hunger via `needs.restore_need`, and heals via `heal()` if `food.health_restore > 0`. See [Hunger](hunger.md). |
| `take_damage(amount: int, source: Node = null) -> void` | Forwards to `health_component.take_damage()`. On `entity_died`, `_on_health_component_died` sets `state = DEAD` and emits `EventBus.player_died("combat")`. |
| `heal(amount: int) -> void` | Forwards to `health_component.heal()`. |
| `equip_item(item: ItemDef) -> Equipment.EquipResult` | MOVES one carried item out of the inventory into the slot it belongs in (`Equipment.equip_from_inventory`: main_hand for tools/weapons, the tagged slot for apparel), stowing whatever it displaces. Returns `OK` or the reason nothing changed. Visual update is automatic (`EquipmentVisualizer` listens to `Equipment.slot_changed`). See [Equipment](equipment.md). |
| `unequip_slot(slot_id: String) -> bool` | Moves the slot's item back into the inventory; false (still equipped) when the pack has no room. |
| `get_equipped_item() -> ItemDef` | Query main_hand. |
| `_ensure_equipment() -> void` | Auxiliary: resolves/creates `equipment` (+ its visualizer) via `Equipment.ensure_on(self, equipment)`. |
| `_try_execute_equipped_action() -> bool` | First step of the LMB dispatch. Returns true when the main-hand item owns LMB: it has an `EquippableParams.primary_action`, whether that fired or is still in its lockout (a press inside the lockout is swallowed, not passed on to mining). Returns false for an empty hand or an item with no primary action, so LMB falls through to interaction and mining. |
| `_fire_equipped_action(equip_params: EquippableParams) -> void` | Runs the item's primary action unless it is in its lockout: starts the lockout (`get_lockout_duration()`), plays the item's use animation (only when it actually fires, so fast clicking doesn't restart the one-shot), then `action.execute(self)`. |
| `_on_primary_action() -> void` | LMB handler (connected to InputComponent's `primary_action_pressed`). Dispatch order: equipped item's primary action, else the crosshair target's `ForageAction`/`FarmManualAction`/`HarvestAction`, else real-time terrain/block mining (50 HP damage per swing via `SmoothGrid.apply_damage_at` or `BlockyGrid.apply_damage`). Which grid takes the swing is decided by the struck collider's ownership: `_find_struck_grid` returns the nearest `SmoothGrid`/`BlockyGrid` ancestor of the collider and stops there (it never continues up to the `Map`, which owns both grids and would claim every hit). A body no grid owns (furniture, colonists) is not mined. No-op while busy, in Blueprint mode, or when UiGate blocks input. |
| `_on_dig_box_toggle_pressed() -> void` | Toggles `DIG_BOX_DESIGNATION` via `_toggle_tool_mode`; emits `EventBus.dig_box_toggled`. `_on_harvest_box_toggle_pressed` is the same for `HARVEST_BOX_DESIGNATION`. |
| `_toggle_tool_mode(tool_mode: Mode) -> void` | Hotkey toggle shared by the dig-box and harvest-box handlers: gated by `is_input_locked()`; leaves `tool_mode` when already in it, enters it from `NORMAL`, and ignores the press in any other mode so tool modes never stack. |
| `_enter_tool_mode(tool_mode: Mode) -> void` / `_exit_tool_mode(tool_mode: Mode) -> void` | Set `mode` to `tool_mode` (announcing `true`) or back to `NORMAL` (announcing `false`) on the mode's toggled signal. Used by the toggle hotkeys, Esc, `_on_buildable_selected` (placement entry), `_on_area_designation_tool_selected` (area entry) and the area-designation hotkey's exit. |
| `_get_mode_toggled_signal(tool_mode: Mode) -> Signal` | Maps a tool mode to its EventBus toggled signal (`build_placement_toggled`, `dig_box_toggled`, `area_designation_toggled`, `harvest_box_toggled`); a null `Signal` for modes that aren't tool modes, which is how `_on_ui_cancel` knows to ignore the press. |
| `_physics_process(delta: float) -> void` | Per-tick order: cool down the equipped action, `interactor.update_target()`, then one `motor.tick(delta, is_input_locked(), _movement_speed_multiplier())`, then `state = _resolve_move_state(wish)` from the wish it returns. |
| `_movement_speed_multiplier() -> float` | The penalties scaling ground speed and the speed frozen into a jump or ledge exit: the depleted-need multiplier (`needs.get_speed_multiplier()`) × the wading drag (`_get_wading_speed_multiplier()`). One value per tick. |
| `_resolve_move_state(wish: Vector3) -> State` | `DEAD` if `is_dead` (terminal), else `IDLE` with no wish, `SPRINT` when grounded and sprinting, otherwise `WALK`. |
| `is_input_locked() -> bool` | Public. `_busy or is_dead`; the single gate for movement, jump, interact, primary action and hotkeys (the interactor reads it for the E key). |
| `trigger_animation_action(action_name: StringName) -> void` | Plays a tool or interaction action animation on the child animation controller (a no-op when the player has none). Public because both the equipped-item action and the `Interactor` go through it. |
| `_get_wading_speed_multiplier() -> float` | The drag of the fluid at the player's lower torso (`_WADING_SAMPLE_HEIGHT` above the feet), read from the running map's `BlockyGrid` (`SceneManager.get_current_map()`) through `get_wading_speed_mult_at`, which resolves `BlockDef.wading_speed_mult` for fluid blocks. 1.0 in dry cells and between maps. |
| `serialize() -> Dictionary` / `deserialize(data: Dictionary) -> void` | SaveSystem contract: position, camera yaw/pitch, inventory, equipment, needs, skills, HP. Mode/state and the transient interactable target are not persisted. |

### Class: PlayerMotor

**Extends:** Node
**Script:** `player_motor.gd`
**Description:** Player locomotion component (`Motor` child of the Player). Gravity, walk/sprint, jump, ledge exit and the frozen air momentum: at takeoff (jump or ledge exit) the horizontal direction and speed are frozen, and mid-air keys only brake or nudge them per axis, never re-project them, so rotating the camera in the air cannot curve the trajectory. Has no `_physics_process`: the Player calls `tick()` explicitly so the order against `StepClimber` stays fixed. Has no knowledge of needs, water, death or busy; the Player passes a lock flag and a speed multiplier instead.
**Used by:** `Player` (`setup` in `_ready`, `tick` every physics tick, `reset` on load).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `walk_speed` | `float` | `[export default 3.5]` Ground move speed. **TODO:** source from CharacterDef. |
| `sprint_speed` | `float` | `[export default 7.0]` Sprint speed. **TODO:** source from CharacterDef. |
| `gravity` | `float` | `[export default 9.8]` Gravity acceleration. |
| `jump_force` | `float` | `[export default 5.0]` Vertical impulse on jump. |
| `jump_move_speed` | `float` | `[export default 0.5]` Mid-air nudge speed for axis braking. |
| `_velocity_on_jump` | `Vector3` | Horizontal world direction frozen at takeoff (y = 0). |
| `_speed_on_jump` | `float` | Ground speed (with the owner's penalties) frozen at takeoff. |
| `_was_on_floor` | `bool` | Last tick's floor contact, to detect a ledge exit without a jump. |

**Methods:**

| Function | Description |
|---|---|
| `setup(input: InputComponent, rig: CameraRig) -> void` | Wires the collaborators the Player owns. |
| `tick(delta: float, locked: bool, speed_multiplier: float) -> Vector3` | One physics tick: gravity and ledge capture, the jump check (`_try_jump`), wish resolution (zero while `locked`), speed selection (live ground speed on the floor, frozen takeoff speed in the air), then `move_and_slide()`. Returns the horizontal wish so the owner derives its movement state. |
| `reset() -> void` | Clears velocity and frozen momentum (called on load). |
| `static resolve_air_axis(neg_held, pos_held, momentum, nudge_speed) -> float` | Pure per-axis air-control rule: both keys cancel; a key matching the momentum preserves it; a key opposing (or lacking) momentum nudges at `nudge_speed`; no key snaps the axis to a stop. Unit-tested alone. |

### Class: PlayerInteractor

**Extends:** Node
**Script:** `player_interactor.gd`
**Description:** What the player does to the world under the crosshair (`Interactor` child of the Player). Tracks which `InteractionComponent` is looked at, runs the E-key tap/hold paths on it, and resolves the world half of an LMB press. Has no `_physics_process`: the Player calls `update_target()` explicitly each tick, before the motor. It does not own the equipped item's LMB action (the Player owns equipment and its lockout and runs that first), the LMB gates (the Player checks lock, mode and UiGate once), or the animation controller (reached through `Player.trigger_animation_action`).
**Used by:** `Player` (`setup` in `_ready`, `update_target` every tick, `primary_interact` from `_on_primary_action`); the HUD (`interactable_changed`, `execute_default_action`, `open_interaction_menu`); `SceneManager` (`clear_interactable` before a map unload).

**Signals:**

| Signal | Description |
|---|---|
| `interactable_changed(component: InteractionComponent)` | The crosshair target changed (gained, lost, or `null`). Also re-emitted after every E-tap so a status line (a blueprint's "Plank 3/15") re-reads. |

**Properties:**

| Property | Type | Description |
|---|---|---|
| `interact_distance` | `float` | `[export default 8.0]` Max range for the crosshair raycast. |
| `mining_tool` | `DigToolParams` | The tool the bare hands mine with (`player.tscn` assigns `data/mining/dig_tool.tres`); its `swing_damage` is the per-swing damage. An equipped pickaxe supplies its own here once equipped-tool mining lands. |
| `_has_target` | `bool` | True from the moment a target is announced until it is cleared. Needed because a freed component compares equal to `null` in GDScript, so `_current_interactable != null` cannot tell "no target" from "the target was freed". |
| `_current_interactable` | `InteractionComponent` | The component currently under the crosshair (or `null`). |
| `_ray_query` / `_ray_excluded_rids` | `PhysicsRayQueryParameters3D` / `Array[RID]` | Cached query and exclusion buffer, so scanning allocates nothing per frame. |

**Methods:**

| Function | Description |
|---|---|
| `setup(player: Player, camera: Camera3D) -> void` | Wires the collaborators the Player owns. |
| `update_target() -> void` | Per-tick crosshair check. Clears the target outside Normal mode or while UiGate blocks input; otherwise raycasts, finds the owning `InteractionComponent` (`_find_interaction_component` walks **up** the parent chain for a child named exactly `"InteractionComponent"`), refreshes its options, and emits `interactable_changed` on a change. |
| `clear_interactable() -> void` | Clears the target and emits `interactable_changed(null)` once (also when the target was freed since it was announced). Called by `SceneManager` before a map's InteractionComponent children are freed (so the HUD label doesn't linger over the title screen). |
| `execute_default_action() -> void` | Quick-tap E: no-op while the player is locked or has no target. Refreshes the target's options, runs `action_options[0].action.execute(player, target)` directly (no menu), then re-emits `interactable_changed`. |
| `open_interaction_menu() -> void` | Long-press E: refreshes options, then `_current_interactable.interact(player)` to build and mount the full action menu. |
| `primary_interact() -> void` | World half of LMB: `_try_interact_current_target` (a `ForageAction` on forageable `WildFlora`, a `FarmManualAction` on a `Growable`, else a `HarvestAction` on a `Harvestable`), otherwise `_try_mine_terrain`. |
| `_has_live_target() -> bool` | True when a target exists and still exists. A target freed since it was announced (by another system between ticks, or by the action a tap just ran) is dropped and announced lost, so listeners never receive a dead component. Checked at the top of `update_target`, in both E paths and in the LMB path. |
| `_refresh_options(component) -> Node` | Asks the component's owner to rebuild its options (owners with dynamic ones expose `refresh_interaction_options`) and returns that owner. |
| `_interaction_raycast() -> Dictionary` | Screen-center physics raycast (`interact_distance`, bodies only, player excluded). Resolves discrete `WorldItem`s and `Colonist`s prioritized through coarse `BuildBody` bounding boxes. Returns the raw hit dict (empty if nothing struck). |
| `_try_mine_terrain() -> void` | Real-time mining, `mining_tool.swing_damage` HP per swing (data: `DigToolParams`) via `SmoothGrid.apply_damage_at` or `BlockyGrid.apply_damage`. Which grid takes the swing is decided by the struck collider's ownership: `_find_struck_grid` returns the nearest `SmoothGrid`/`BlockyGrid` ancestor of the collider and stops there (it never continues up to the `Map`, which owns both grids and would claim every hit). A body no grid owns (furniture, colonists) is not mined. |

### Class: InputComponent

**Extends:** Node
**Script:** `input_component.gd`
**Description:** Reads raw player input and exposes it to the Player parent via signals (discrete actions) and per-frame query methods (continuous actions). Follows the project's component pattern (`extends Node`, attached as `$InputComponent` child in the scene tree). Does NOT own mouse-motion (CameraRig handles that via its own `_unhandled_input`) or mouse-mode management (Player owns `Input.mouse_mode` as a game-state concern).
**Used by:** `Player` (connects to signals in `_ready`, queries methods in `_physics_process`).

**Signals:**

| Signal | Description |
|---|---|
| `build_toggle_pressed()` | Emitted on B key (`build_toggle` action). |
| `primary_action_pressed()` | Emitted on LMB during gameplay. Handled by `_on_primary_action`: runs `FarmManualAction` / `HarvestAction` on interactables, or damages/mines targeted terrain on LMB. |
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
**Description:** Third-person orbit rig built programmatically in `_ready()` (a `SpringArm3D` child owning a `Camera3D` child, so `player.tscn` only needs the CameraRig node). Tracks the parent Player's position; mouse motion orbits around it — yaw on this rig, pitch on the spring arm (clamped). The rig does NOT inherit the avatar's visual facing, so the camera orbit stays independent of where the capsule looks; the avatar's facing and look lean follow the rig instead (see the "Look: Facing and Lean" flow). LMB/RMB are not consumed here (reserved for item actions).
**Used by:** `Player` (`get_camera`, `get_look_direction`, `get_look_pitch`, save/load orientation).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `sensitivity` | `float` | `[export default 0.0025]` Mouse-look sensitivity. |
| `spring_length` | `float` | `[export default 3.0]` Spring-arm length (camera distance). Applied to the SpringArm3D; there is no runtime zoom control yet. |
| `min_pitch` / `max_pitch` | `float` | `[export, range -1.2..1.2]` Pitch clamp (radians). |
| `height_offset` | `float` | `[export default 1.4]` Pivot height above the Player (eye/shoulder height). |
| `h_offset` | `float` | `[export default 0.5]` `Camera3D.h_offset` — horizontal frustum shift (body frames screen-left). |
| `v_offset` | `float` | `[export default 0.4]` `Camera3D.v_offset` — vertical frustum shift. |
| `smooth_enabled` | `bool` | `[export default true]` Enable/disable camera position smoothing. |
| `smooth_speed_horizontal` | `float` | `[export default 24.0]` Lerp speed for horizontal tracking. |
| `smooth_speed_vertical` | `float` | `[export default 12.0]` Lerp speed for vertical tracking (softer to absorb step teleports). |

> Over-the-shoulder framing uses `h_offset`/`v_offset` (frustum shift) rather than rotating the camera, so the aim direction stays along the spring-arm axis.

**Functions:**

| Function | Description |
|---|---|
| `get_camera() -> Camera3D` | The active Camera3D (child of the spring arm). Returns null if the rig isn't ready yet (callers must wait for `_ready`). |
| `get_forward_horizontal() -> Vector3` / `get_right_horizontal() -> Vector3` | The camera's forward / right flattened to the horizontal plane and normalized. The single source for movement wish vectors (`PlayerMotor`), item drops and body-facing (`Player.get_look_direction`). |
| `get_yaw() -> float` / `get_pitch() -> float` | Current orbit yaw / pitch (radians). Save/load accessors for otherwise-private state. |
| `set_orientation(yaw: float, pitch: float) -> void` | Restore the orbit (radians); pitch is clamped and applied immediately. Used by save/load. |
| `get_target_position() -> Vector3` | Gets the target tracking position in world space (parent position + vertical height offset). |
| `snap_to_target() -> void` | Snaps the rig immediately to the target position without smoothing. |

### Class: PlayerAnimationController

**Extends:** Node  
**Script:** `subsystems/player/player_animation_controller.gd`  
**Description:** Modular animation component attached as an `AnimationController` child of `player.tscn`. Drives the scene `AnimationTree`: the `Locomotion` state machine (a `Grounded` Idle/Walk/Sprint blend space keyed by horizontal speed, plus `JumpUp`/`JumpLoop`/`JumpDown`) and the upper-body `ActionSelect` + `ActionOneshot` overlay for tool and attack animations. Turns `Visuals` to face the camera and applies the look lean (see the "Look: Facing and Lean" flow). `_setup_skeleton()` re-homes the BoneMap-retargeted model skeleton's unique name (`GeneralSkeleton`) to the player scene root so library tracks like `%GeneralSkeleton:Hips` bind at runtime. Asset pipeline: `docs/HOWTO-use-makehuman-mixamo.md`.
**Used by:** `Player` (`trigger_animation_action` calls `trigger_action` for interaction, tool, and attack animations; the interactor and the equipped-item action both go through it).
**Lifecycle:** `_ready` resolves `anim_tree` / `anim_player` / `visuals` / `look_lean` from sibling nodes when unset, hides the legacy capsule mesh, activates the tree, sets `process_priority` to the tree's plus one, and binds the look lean to the skeleton.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `anim_tree` / `anim_player` / `visuals` | `AnimationTree` / `AnimationPlayer` / `Node3D` | `[export]` Auto-resolve to the sibling `AnimationTree`, `AnimationPlayer`, and `Visuals` nodes when left empty. |
| `rotation_speed` | `float` | `[export default 15.0]` How fast `Visuals` turns toward the look direction. |
| `look_lean` | `LookLean` | `[export]` Auto-resolves to the sibling `LookLean` node. Receives the camera pitch each frame; the lean knobs live on that node. |

**Functions:**

| Function | Description |
|---|---|
| `trigger_action(action_name: StringName) -> void` | Fires the upper-body `ActionOneshot` overlay. `_resolve_action_animation_name` maps generic names (`swing`, `attack`, `fire`, `dig`, ...) to `AttackOverhead` / `Interact` / `Digging`. |
| `cancel_action() -> void` | Aborts the active one-shot overlay. |
| `_update_mesh_rotation(delta: float) -> void` | Eases `Visuals.rotation.y` toward `Player.get_look_direction()`. |
| `_update_animation_state() -> void` | Sets the `Grounded` blend position from horizontal speed and travels the jump states. |
| `_setup_skeleton() -> void` | Re-homes the skeleton's owner so `%GeneralSkeleton` tracks bind, then binds `look_lean` to that skeleton. |

### Class: LookLean

**Extends:** Node
**Script:** `../core/look_lean.gd` (shared with [Colonists](colonists.md) — ambiguous ownership → core)
**Description:** Torso/head look lean, added as a `LookLean` child of both `player.tscn` and `colonist.tscn`. Bends the humanoid `Chest` and `Head` bones by a look pitch so looking up or down reads on the avatar without tipping the whole body. It has no `_process` of its own: the owning animation controller decides the pitch (camera pitch for the player, the look target for colonists) and calls `apply` every frame after its AnimationTree has posed the skeleton, which is why both controllers run at the tree's `process_priority` plus one. The lean is composed onto that pose and never accumulates, because the tree re-poses both bones every frame.
**Used by:** `PlayerAnimationController`, `ColonistAnimationController`.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `enabled` | `bool` | `[export default true]` Turns the lean on or off. |
| `max_up_deg` | `float` | `[export default 40.0, range 0..90]` Furthest the upper body leans back when looking up (Chest + Head combined). |
| `max_down_deg` | `float` | `[export default 40.0, range 0..90]` Furthest the upper body leans forward when looking down (Chest + Head combined). |
| `chest_share` | `float` | `[export default 0.6, range 0..1]` Share of the lean bent into the `Chest` bone; `Head` takes the rest. |
| `smoothing` | `float` | `[export default 12.0, range 0..60]` How quickly the lean catches up to its target pitch (exponential ease; higher is snappier, 0 freezes it). |

**Functions:**

| Function | Description |
|---|---|
| `bind(skeleton: Skeleton3D) -> void` | Resolves the `Chest` / `Head` bone indices; warns and leaves the lean disabled if either is missing. |
| `is_bound() -> bool` | Whether both bones were resolved. |
| `apply(target_pitch: float, delta: float) -> void` | Clamps and eases toward `target_pitch` (radians, look-up positive), then composes the lean onto the current Chest/Head poses. Call once per frame, after the AnimationTree. |
| `clamp_pitch(pitch: float) -> float` | Pure clamp of a pitch (radians) to `-max_down_deg .. max_up_deg`. |

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
