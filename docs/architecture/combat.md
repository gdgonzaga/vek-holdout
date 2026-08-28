# Subsystem: Combat

Damage resolution (Durability-before-HP, GDD §6.11), weapons, enemy base + Brawler/Shooter archetypes, and LimboAI hostile behavior trees.

> **Implementation status: in-progress.** `HealthComponent` (`subsystems/combat/components/health_component.gd`), `EnemyBase` (`subsystems/combat/enemy_base.gd`), and prototype `EnemySwarmer` (`subsystems/combat/enemies/enemy_swarmer/`) are implemented. LimboAI enemy behavior tree (`enemy_swarmer.tres`) and combat tasks (`BTActionBreachVoxel`, `BTActionMeleeAttack`, `BTActionScanThreats`, `BTConditionPathBlocked`) are implemented in `subsystems/ai/tasks/`. Structural damage primitives exist on `BlockyGrid`. `DamageResolver` and breath components are planned.

---

## Enemy AI & Behavior Trees

Hostile AI execution is driven by LimboAI behavior trees (`data/ai/trees/enemy_swarmer.tres`):

- **Threat Scanning**: `BTActionScanThreats` continuously scans area for target colonists or colony structures.
- **Pathing & Breaching**: `BTActionNavigateTo` targets threats. If pathfinding is blocked (`BTConditionPathBlocked`), the enemy executes `BTActionBreachVoxel` to destroy obstructing voxel terrain.
- **Melee Attack**: `BTActionMeleeAttack` executes physical attacks when within melee range.

---

## Combat & Entity Components

| File | Type | Responsibility |
|---|---|---|
| `subsystems/combat/components/health_component.gd` | Script | Reusable component (Node): HP + Durability + death signal. Attached to player, colonists, enemies. |
| `subsystems/combat/enemy_base.gd` | Script | Base for all enemies; extends `CharacterBody3D`, forwards damage, and manages life cycle. |
| `subsystems/combat/enemies/enemy_swarmer/` | Scene/Script | Prototype swarmer enemy with capsule primitive visual and health component. |
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
