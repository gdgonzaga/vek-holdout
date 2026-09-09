# Subsystem: Combat

Damage resolution (Durability-before-HP, GDD §6.11), weapons, enemy base + Brawler/Shooter archetypes, automated turret defenses, and LimboAI hostile behavior trees.

> **Implementation status: in-progress.** `HealthComponent` (`subsystems/combat/components/health_component.gd`), `EnemyBase` (`subsystems/combat/enemy_base.gd`), prototype `EnemySwarmer` (`subsystems/combat/enemies/enemy_swarmer/`), and automated defenses (`TurretParams`, `TurretComponent`, `TurretProjectile`) are implemented. LimboAI enemy behavior tree (`enemy_swarmer.tres`) and combat tasks (`BTActionBreachVoxel`, `BTActionMeleeAttack`, `BTActionScanThreats`, `BTConditionPathBlocked`) are implemented in `subsystems/ai/tasks/`. Structural damage primitives exist on `BlockyGrid`. `DamageResolver` and breath components are planned.

---

## Enemy AI & Behavior Trees

Hostile AI execution is driven by LimboAI behavior trees (`data/ai/trees/enemy_swarmer.tres`) and locomotion physics (`EnemyBase` + `StepClimber`):

- **Threat Scanning**: `BTActionScanThreats` continuously scans the area for target players, colonists, or colony structures.
- **Pathing & Breaching**: `BTActionNavigateTo` targets threats with dynamic repathing for moving targets. If pathfinding is blocked (`BTConditionPathBlocked`), the enemy executes `BTActionBreachVoxel` to destroy obstructing voxel terrain.
- **Stepped Locomotion & Physics Assist**: `EnemyBase` attaches `StepClimber` (`hop_height = 1.3`, `step_height = 0.5`) to negotiate voxel steps and slopes without getting stuck on lips. Waypoint arrival thresholds dynamically clamp to `maxf(threshold, speed * delta * 1.2)` to prevent physics overshoot oscillations, and wall-stuck recovery steers hostiles around corners.
- **Melee Attack**: `BTActionMeleeAttack` executes physical attacks when within melee range.

---

## Automated Turret Defenses

Automated defenses (GDD §7.10) protect the colony perimeter against hostile swarms:

- **Capability Composition**: Turrets are authored as `FurnitureDef` with a `TurretParams` capability sub-resource (`data/capability_params/turret_params.gd`). `FurnitureLayer` attaches a `TurretComponent` child when `turret_params` is non-null.
- **Targeting**: Scans active hostiles in group `"enemies"` within `turret_params.range`, filtering out dead targets and engaging the closest hostile. Turrets aim and fire towards the target's center of mass (resolving child `CollisionShape3D` or `MeshInstance3D`, with a +1.0m Y fallback for character entities) rather than floor-level origin coordinates.
- **Ammunition Resolution**: Turrets query their attached `StorageInventory` first. If no local ammo is found, they query `Colony.storage_registry` to consume ammo directly from colony storage crates.
- **Muzzle Position & Spawn Resolution**: `TurretComponent` resolves the projectile launch location in two tiers:
  - *Socket Node (`"Muzzle"`)*: Searches the parent furniture hierarchy for a child node named `"Muzzle"` (e.g. authored as a Blender Empty parented to the turret mesh at the barrel opening) and fires from `muzzle.global_position`.
  - *Data-Driven Offset (`muzzle_offset`)*: If no `"Muzzle"` node is found, falls back to evaluating `params.muzzle_offset` (default `Vector3(0, 2.0, 0)`) transformed by the turret's world orientation.
- **Physical Projectiles & Ammo Mesh Fallback**: `TurretComponent` launches `TurretProjectile` (`Area3D`), supporting:
  - `REGULAR`: Direct contact damage against single targets.
  - `EXPLOSIVE`: Physics sphere query (`PhysicsShapeQueryParameters3D`) delivering splash damage to all entities within `explosion_radius`.
  - *Visual Fallback*: If `projectile_mesh` is not specified on `TurretParams`, the projectile automatically adopts `ammo_type.mesh` (and its material). Meshes modeled upright (+Y) are automatically pitched -90 degrees on X to point forward (-Z) along the flight path.

### Planned Design: Deployable Sensor & Target Markers

For choke-point control and predictive bombardment with area-of-effect turrets (e.g. Bomb Launcher):
- **Deployable Sensor Markers**: Positionable trigger zones with configurable radii.
- **Target Markers**: Impact coordinates designating the pre-sighted barrage target.
- **Coupled Triggering**: Turrets link sensors to target coordinates, firing automatically into the targeted killzone when hostiles trip the sensor, rather than tracking moving targets individually.

---

## Combat & Entity Components

| File | Type | Responsibility |
|---|---|---|
| `subsystems/combat/components/health_component.gd` | Script | Reusable component (Node): HP + Durability + death signal. Attached to player, colonists, enemies. |
| `subsystems/combat/enemy_base.gd` | Script | Base for all enemies; extends `CharacterBody3D`, forwards damage, manages life cycle, and provides stat/moodlet queries (`get_stat_ratio`, `get_stat_value`, `get_active_moodlets`). |
| `subsystems/combat/enemy_moodlet_visualizer.gd` | Script | In-world 3D billboard visualizer (Node3D) mounted on `EnemyBase` displaying active moodlet icons. |
| `subsystems/combat/enemies/enemy_swarmer/` | Scene/Script | Prototype swarmer enemy with capsule primitive visual and health component. |
| `subsystems/combat/components/turret_component.gd` | Script | Turret runtime component: targets nearest enemy, consumes ammo, and fires projectiles. |
| `subsystems/combat/components/turret_projectile.gd` | Script | Physical moving projectile (Area3D) with direct and explosive splash damage. |
| `data/capability_params/combat_action_params.gd` | Script (Resource) | Base capability sub-resource for combat actions: base damage and effective range. |
| `data/capability_params/melee_action_params.gd` | Script (Resource) | Capability sub-resource for melee actions: windup timing, active hitbox window, impact audio. Projects melee ray from actor chest in camera aim direction against bodies and Area3D hitboxes. |
| `data/capability_params/ranged_action_params.gd` | Script (Resource) | Capability sub-resource for ranged actions: ammo cost/item, projectile/hitscan, spread, tracers. |
| `data/capability_params/turret_params.gd` | Script (Resource) | Capability sub-resource on `FurnitureDef`: range, fire rate, damage, ammo type, projectile mesh/speed/type. |
| `damage_resolver.gd` | Script | (Planned) Static/class: applies damage per §6.11. AP-equivalent (Durability) depletes first, overflow to HP. |
| `breath_component.gd` | Script | (Planned) Reusable component (Node): Breath pool (burst energy). |
| `stamina_component.gd` | Script | Reusable component (Node): Stamina pool (daily energy). |

---

## Signals

| Signal | Emitted by | Listeners | Via EventBus? |
|---|---|---|---|
| `entity_died(entity)` | `health_component.gd` | owner script | No |
| `health_changed(current_hp, max_hp)` | `health_component.gd` | HUD, visualizers | No |
| `durability_changed(current_dur, max_dur)` | `health_component.gd` | HUD, visualizers | No |
| `player_died(context)` | `player.gd` | GameState, HUD | Yes |
| `colonist_died(colonist_id)` | `colonist.gd` | Colony, HUD, Memorial | Yes |
| `projectile_fired(projectile, target)` | `turret_component.gd` | audio, visualizers, tests | No |
