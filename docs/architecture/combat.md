# Subsystem: Combat

Damage resolution (Durability-before-HP, GDD §6.11), weapons, enemy base + Brawler/Shooter archetypes, automated turret defenses, and LimboAI hostile behavior trees.

> **Implementation status: in-progress.** `HealthComponent` (`subsystems/combat/components/health_component.gd`) is attached to Player, Colonist, EnemyBase, WildFlora, and combat-capable Furniture (turrets, walls — any buildable with `def.hp > 0`), and delegates Durability-before-HP arithmetic to `DamageResolver` (`subsystems/combat/damage_resolver.gd`). Enemies are data-driven: `EnemyDef` (`data/enemies/enemy_def.gd`) defines an archetype's stats/tree/attack data, `EnemyLibrary` (`subsystems/combat/enemy_library.gd`) indexes `data/enemies/*.tres` by `id` the same way `ItemDB` indexes items, and `EnemyBase` (`subsystems/combat/enemy_base.gd`) applies a scene's assigned `enemy_def` at `_ready()`. Three archetypes are implemented — `EnemySwarmer` (prototype), `EnemyBrawler`, `EnemyShooter` (GDD §5) — all thin `EnemyBase` subclasses whose scenes differ only in which `EnemyDef` they assign; combat numbers live entirely in data, not per-scene overrides. Automated defenses (`TurretParams`, `TurretComponent`, `Projectile`) are implemented. Colonists fight back reactively via `ColonistCombat` (`subsystems/colonists/colonist_combat.gd`) and `BTActionColonistCombatAttack`, dispatching through the same weapon `EquipActionParams.execute()` path the player uses (GDD §6.7 "Fight" stance, MVP subset — no pursuit). Ranged weapons (player or colonist) can fire either an instant hitscan raycast or a physical `Projectile` (shared with turrets), selected per-weapon via `RangedActionParams.is_hitscan`; enemy ranged/melee attacks apply damage directly to their already-BT-selected target instead (see Enemy AI & Behavior Trees below — the reasons are structural, not a shortcut). LimboAI enemy behavior trees (`enemy_melee.tres`, `enemy_ranged_kiter.tres`) and combat tasks (`BTActionBreachVoxel`, `BTActionMeleeAttack`, `BTActionRangedAttack`, `BTActionScanThreats`, `BTConditionPathBlocked`) are implemented in `subsystems/ai/tasks/`. `BTActionBreachVoxel` applies real per-material voxel HP damage via `BlockyGrid.apply_damage()`. Breath components are planned. Enemies aren't reachable through any spawner/wave selection yet — `night_raid_controller.gd` and `map_wiring.gd` each hold a single hardcoded `PackedScene` reference to the swarmer; wiring Brawler/Shooter into a real selection mechanism is unscoped, tracked in `tech-debt.md`.

---

## Enemy AI & Behavior Trees

Hostile AI execution is driven by LimboAI behavior trees, built by `BTTreeFactory` (`subsystems/ai/bt_tree_factory.gd`) and checked in as `data/ai/trees/enemy_melee.tres` / `enemy_ranged_kiter.tres`, plus locomotion physics (`EnemyBase` + `StepClimber`). `EnemyBase._setup_ai_components()` creates a `BTPlayer` and loads whichever tree the agent's `EnemyDef.behavior_tree` names — none of the shipped enemy scenes pre-place their own `BTPlayer`, so one tree resource is shared by every archetype that uses it (`enemy_melee.tres` serves both `EnemySwarmer` and `EnemyBrawler` today; only the numbers differ, sourced from each archetype's `EnemyDef.attack_params`).

- **Threat Scanning**: `BTActionScanThreats` continuously scans the area for target players, colonists, or colony structures. `use_weapon_range = true` resolves its scan radius from the agent's resolved combat source instead of a fixed `radius` (see `AIUtils.resolve_combat_source`, used by the colonist reactive-combat scan below).
- **Pathing & Breaching**: `BTActionNavigateTo` targets threats with dynamic repathing for moving targets. If pathfinding is blocked (`BTConditionPathBlocked`), the enemy executes `BTActionBreachVoxel` to destroy obstructing voxel terrain. `arrival_distance_from_agent_attack_range = true` resolves the "close enough" distance from the agent's attack range instead of a fixed `arrival_distance` — used by the ranged-kiter tree so its "close distance to reach firing range" step can't drift out of sync with the `RangedActionParams.range_meters` its `BTActionRangedAttack` sibling actually fires at.
- **Stepped Locomotion & Physics Assist**: `EnemyBase` attaches `StepClimber` (`hop_height = 1.3`, `step_height = 0.5`) to negotiate voxel steps and slopes without getting stuck on lips. Waypoint arrival thresholds dynamically clamp to `maxf(threshold, speed * delta * 1.2)` to prevent physics overshoot oscillations, and wall-stuck recovery steers hostiles around corners.
- **Melee Attack**: `BTActionMeleeAttack` executes physical attacks when within melee range. `use_agent_attack_params = true` sources damage/range/windup/cooldown from the agent's `EnemyDef.attack_params` (a `MeleeActionParams`) instead of the task's own exports, letting one tree serve every melee archetype; `false` (default) keeps the task's own exports, kept only because an existing test drives it with a non-`EnemyBase` agent (tracked in `tech-debt.md`).
- **Ranged Attack**: `BTActionRangedAttack` (`subsystems/ai/tasks/actions/bt_action_ranged_attack.gd`) fires the agent's `RangedActionParams` at its already-selected target — no standalone-export fallback, since it's not a rework of an existing task. Both `BTActionMeleeAttack` and `BTActionRangedAttack` deliberately apply damage directly to the locked target rather than delegating to `CombatActionParams.execute()` (the hitscan/hitbox-sweep path Player/Colonist use): that path resolves aim off the actor's own facing, and `EnemyBase` never rotates to face targets, so it would fire/swing in a fixed, usually-wrong direction. This is why enemy ranged attacks have no tracer/impact-particle feedback today — a known, deliberate gap, not an oversight.
- **Ranged Kiting**: `BTTreeFactory.create_enemy_ranged_kiter_tree()` (Shooter archetype) fires whenever the target is within holding range, otherwise closes distance via `BTActionNavigateTo`. It deliberately does not implement the full GDD §5 Reposition/MeleeFallback back-pedaling state machine — see the function's doc comment for the reasoning (the GDD's own state machine doesn't actually specify back-pedaling once already firing, and the design intent explicitly wants an aggressive push to end the threat).

---

## Colonist Reactive Combat

GDD §6.7 "Fight" stance (MVP subset): any colonist with a weapon equipped fights back reactively from wherever it currently is — no pathing toward enemies, no relocation. `data/ai/trees/colonist_root.tres` (generated by `BTTreeFactory.create_colonist_root_tree()`, `subsystems/ai/bt_tree_factory.gd`) prepends a `Sequence[ScanThreats, ColonistCombatAttack]` as the **highest-priority** child of the root `BTDynamicSelector`, so it interrupts eating/needs/work/wander whenever a threat is in range and falls through cleanly otherwise:

- **Threat Scanning**: `BTActionScanThreats` (unmodified, already generic) configured with `threat_groups = ["enemies"]`.
- **Weapon Dispatch**: `BTActionColonistCombatAttack` (`subsystems/ai/tasks/actions/bt_action_colonist_combat_attack.gd`) reads the colonist's `ColonistCombat` component (`subsystems/colonists/colonist_combat.gd`, attached to `colonist.tscn`'s `ColonistCombat` node) to resolve the equipped weapon's `CombatActionParams`, check range/cooldown, and call `action.execute(colonist)` — the exact same dispatch `player.gd::_execute_equipped_primary_action()` uses. Never pursues: halts any in-progress path (`agent.set_path([])`) before attacking.
- **Aim Contract**: `Colonist.get_aim_origin()`/`get_aim_direction()` satisfy the same `has_method()` fallback `MeleeActionParams`/`RangedActionParams` already check for non-Player actors; `get_aim_direction()` points at the colonist's current combat target.

---

## Automated Turret Defenses

Automated defenses (GDD §7.10) protect the colony perimeter against hostile swarms:

- **Capability Composition**: Turrets are authored as `FurnitureDef` with a `TurretParams` capability sub-resource (`data/capability_params/turret_params.gd`). `FurnitureLayer` attaches a `TurretComponent` child when `turret_params` is non-null.
- **Targeting**: Scans active hostiles in group `"enemies"` within `turret_params.range`, filtering out dead targets and engaging the closest hostile. Turrets aim and fire towards the target's center of mass (resolving child `CollisionShape3D` or `MeshInstance3D`, with a +1.0m Y fallback for character entities) rather than floor-level origin coordinates.
- **Ammunition Resolution**: Turrets query their attached `StorageInventory` first. If no local ammo is found, they query `Colony.storage_registry` to consume ammo directly from colony storage crates.
- **Muzzle Position & Spawn Resolution**: `TurretComponent` resolves the projectile launch location in two tiers:
  - *Socket Node (`"Muzzle"`)*: Searches the parent furniture hierarchy for a child node named `"Muzzle"` (e.g. authored as a Blender Empty parented to the turret mesh at the barrel opening) and fires from `muzzle.global_position`.
  - *Data-Driven Offset (`muzzle_offset`)*: If no `"Muzzle"` node is found, falls back to evaluating `params.muzzle_offset` (default `Vector3(0, 2.0, 0)`) transformed by the turret's world orientation.
- **Physical Projectiles & Ammo Mesh Fallback**: `TurretComponent` launches `Projectile` (`Area3D`, `subsystems/combat/components/projectile.gd` — shared with hand-fired ranged weapons, see below), configured via `ProjectileSpec` (`subsystems/combat/components/projectile_spec.gd`), supporting:
  - `REGULAR`: Direct contact damage against single targets.
  - `EXPLOSIVE`: Physics sphere query (`PhysicsShapeQueryParameters3D`) delivering splash damage to all entities within `explosion_radius`.
  - *Visual Fallback*: If `projectile_mesh` is not specified on `TurretParams`, `ProjectileSpec.from_turret_params()` adopts `ammo_type.mesh` (and its material). Meshes modeled upright (+Y) are automatically pitched -90 degrees on X to point forward (-Z) along the flight path.

### Shared Projectile System

`Projectile` is actor-agnostic — it knows nothing about `TurretParams` or `RangedActionParams` directly, only the `ProjectileSpec` bundle passed to `setup()`. This lets player, colonist, and turret ranged weapons share one flying-projectile implementation:

- `ProjectileSpec.from_turret_params(params: TurretParams)` — used by `TurretComponent`.
- `ProjectileSpec.from_ranged_action(params: RangedActionParams)` — used by `RangedActionParams.execute()` when `is_hitscan = false`.

Per-weapon, `RangedActionParams.is_hitscan` picks the resolution mode (matching how games like 7 Days to Die split it): bullets (rifle, musket) stay hitscan — instant raycast, no travel time; slower/visible ammunition (crossbow bolts, explosive ordnance) sets `is_hitscan = false` and flies as a real `Projectile` with travel time and collision. `crossbow.tres` demonstrates the projectile path; new bomb-launcher-style weapons should follow the same pattern with `projectile_type = EXPLOSIVE` and `explosion_radius` set.

### Planned Design: Deployable Sensor & Target Markers

For choke-point control and predictive bombardment with area-of-effect turrets (e.g. Bomb Launcher):
- **Deployable Sensor Markers**: Positionable trigger zones with configurable radii.
- **Target Markers**: Impact coordinates designating the pre-sighted barrage target.
- **Coupled Triggering**: Turrets link sensors to target coordinates, firing automatically into the targeted killzone when hostiles trip the sensor, rather than tracking moving targets individually.

---

## Combat & Entity Components

| File | Type | Responsibility |
|---|---|---|
| `subsystems/combat/components/health_component.gd` | Script | Reusable component (Node): HP + Durability + death signal, delegating resolution to `DamageResolver`. Attached to Player, Colonist, EnemyBase, WildFlora, and combat-capable Furniture. |
| `subsystems/combat/damage_resolver.gd` | Script | Pure static Durability-before-HP arithmetic (§6.11), extracted from `HealthComponent.take_damage()` as the seam a future armor/buff pass hooks. |
| `subsystems/combat/enemy_base.gd` | Script | Base for all enemies; extends `CharacterBody3D`. Applies its assigned `enemy_def` (`EnemyDef`, nullable — see `tech-debt.md`) at `_ready()`: HP/durability, move speed, `BTPlayer` tree, moodlets. Forwards damage, manages life cycle, provides stat/moodlet queries (`get_stat_ratio`, `get_stat_value`, `get_active_moodlets`), and implements the `ICombatSource` contract (`get_combat_action`, `get_attack_range`). |
| `subsystems/combat/enemy_moodlet_visualizer.gd` | Script | In-world 3D billboard visualizer (Node3D) mounted on `EnemyBase` displaying active moodlet icons. |
| `subsystems/combat/enemy_library.gd` | Script (Autoload) | `EnemyLibrary`: recursively indexes `data/enemies/` `EnemyDef` resources by `id` via the shared `ContentDirLoader` (see [Overview](overview.md#content-directory-loading)), the same helper `ItemDB` uses. |
| `data/enemies/enemy_def.gd` | Script (Resource) | `EnemyDef` — one archetype's stats, behavior tree, and `attack_params`. Schema: `data-schemas.md`. |
| `subsystems/core/i_combat_source.gd` | Script (doc-only contract) | `ICombatSource` — duck-typed contract (`get_combat_action`, `get_attack_range`) resolved by `AIUtils.resolve_combat_source()` for either a Colonist's sibling `ColonistCombat` node or an `EnemyBase` agent directly. |
| `subsystems/combat/enemies/enemy_swarmer/` | Scene/Script | Prototype swarmer enemy; capsule primitive visual, `enemy_def` set to `data/enemies/enemy_swarmer.tres`. |
| `subsystems/combat/enemies/enemy_brawler/` | Scene/Script | Brawler archetype (GDD §5); `enemy_def` set to `data/enemies/enemy_brawler.tres`, shares `enemy_melee.tres` with the swarmer. |
| `subsystems/combat/enemies/enemy_shooter/` | Scene/Script | Shooter archetype (GDD §5); `enemy_def` set to `data/enemies/enemy_shooter.tres`, runs `enemy_ranged_kiter.tres`. |
| `subsystems/combat/components/turret_component.gd` | Script | Turret runtime component: targets nearest enemy, consumes ammo, and fires projectiles. |
| `subsystems/combat/components/projectile.gd` | Script | Actor-agnostic physical moving projectile (Area3D) with direct and explosive splash damage. Shared by `TurretComponent` and `RangedActionParams` (non-hitscan weapons). |
| `subsystems/combat/components/projectile_spec.gd` | Script (RefCounted) | Runtime parameter bundle for `Projectile.setup()`, built from either `TurretParams` or `RangedActionParams` via static factory methods. |
| `subsystems/colonists/colonist_combat.gd` | Script | Reactive weapon-combat component (Node) attached to `colonist.tscn`'s `ColonistCombat` node: resolves equipped weapon, range/cooldown, dispatches `execute()`. |
| `subsystems/ai/tasks/actions/bt_action_colonist_combat_attack.gd` | Script | LimboAI action: fires/swings via `ColonistCombat` at a `BTActionScanThreats`-selected target; halts movement, never pursues. |
| `subsystems/ai/tasks/actions/bt_action_ranged_attack.gd` | Script | LimboAI action: fires an enemy's `RangedActionParams` at its already-selected target, applying damage directly (see Enemy AI & Behavior Trees above for why). |
| `data/capability_params/combat_action_params.gd` | Script (Resource) | Base capability sub-resource for combat actions: base damage and effective range. |
| `data/capability_params/melee_action_params.gd` | Script (Resource) | Capability sub-resource for melee actions: windup timing, active hitbox window, impact audio. Projects melee ray from actor chest in camera aim direction against bodies and Area3D hitboxes. |
| `data/capability_params/ranged_action_params.gd` | Script (Resource) | Capability sub-resource for ranged actions: ammo cost/item, hitscan raycast or physical `Projectile` (via `ProjectileSpec.from_ranged_action`), spread, tracers. |
| `data/capability_params/turret_params.gd` | Script (Resource) | Capability sub-resource on `FurnitureDef`: range, fire rate, damage, ammo type, projectile mesh/speed/type. |
| `breath_component.gd` | Script | (Planned) Reusable component (Node): Breath pool (burst energy). |
| `subsystems/colonists/stamina_component.gd` | Script | Reusable component (Node): Stamina pool (daily energy). Lives in `subsystems/colonists/` (ambiguous ownership); attached to Colonist today. |

---

## Signals

| Signal | Emitted by | Listeners | Via EventBus? |
|---|---|---|---|
| `entity_died(entity)` | `health_component.gd` | owner script | No |
| `health_changed(current_hp, max_hp)` | `health_component.gd` | HUD, visualizers | No |
| `durability_changed(current_dur, max_dur)` | `health_component.gd` | HUD, visualizers | No |
| `damaged(amount, source)` | `health_component.gd` | owner script, visualizers | No |
| `healed(amount)` | `health_component.gd` | owner script | No |
| `player_died(context)` | `player.gd` | GameState, HUD | Yes |
| `colonist_died(colonist_id)` | `colonist.gd` | Colony, HUD, Memorial | Yes |
| `projectile_fired(projectile, target)` | `turret_component.gd` | audio, visualizers, tests | No |
