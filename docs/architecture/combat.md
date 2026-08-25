# Subsystem: Combat

Damage resolution (Durability-before-HP, GDD §6.11), weapons, enemy base + Brawler/Shooter archetypes, and LimboAI hostile behavior trees.

> **Implementation status: in-progress.** LimboAI enemy behavior tree (`enemy_swarmer.tres`) and combat tasks (`BTActionBreachVoxel`, `BTActionMeleeAttack`, `BTActionScanThreats`, `BTConditionPathBlocked`) are implemented in `subsystems/ai/tasks/`. Structural damage primitives exist on `BlockyGrid`. `colonist.gd` tracks HP directly (`take_damage` / `heal`, emitting `EventBus.colonist_died` at 0). `DamageResolver` and dedicated health components are planned.

---

## Enemy AI & Behavior Trees

Hostile AI execution is driven by LimboAI behavior trees (`data/ai/trees/enemy_swarmer.tres`):

- **Threat Scanning**: `BTActionScanThreats` continuously scans area for target colonists or colony structures.
- **Pathing & Breaching**: `BTActionNavigateTo` targets threats. If pathfinding is blocked (`BTConditionPathBlocked`), the enemy executes `BTActionBreachVoxel` to destroy obstructing voxel terrain.
- **Melee Attack**: `BTActionMeleeAttack` executes physical attacks when within melee range.

---

## Planned Components

| File | Type | Responsibility |
|---|---|---|
| `damage_resolver.gd` | Script | Static/class: applies damage per §6.11. AP-equivalent (Durability) depletes first, overflow to HP. |
| `health_component.gd` | Script | Reusable component (Node): HP + Durability + death signal. Attached to player, colonists, enemies. |
| `breath_component.gd` | Script | Reusable component (Node): Breath pool (burst energy). |
| `stamina_component.gd` | Script | Reusable component (Node): Stamina pool (daily energy). |
| `enemy_base.gd` | Script | Base for all enemies; holds `BTPlayer` executing `enemy_swarmer.tres`. |

---

## Signals

| Signal | Emitted by | Listeners | Via EventBus? |
|---|---|---|---|
| `entity_died(entity)` | `health_component.gd` | owner script | No |
| `player_died(context)` | `player.gd` | GameState, HUD | Yes |
| `colonist_died(colonist_id)` | `colonist.gd` | Colony, HUD, Memorial | Yes |
