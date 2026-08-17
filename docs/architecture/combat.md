# Subsystem: Combat

Damage resolution (Durability-before-HP, GDD §6.11), weapons, enemy base + Brawler/Shooter archetypes.

> **Implementation status: planned, not yet built.** Nothing on this page exists yet — `subsystems/combat/` is an empty directory, there is no `DamageResolver`, `HealthComponent`, `BreathComponent`, weapon or enemy script, and `data/characters/`, `data/weapons/`, and `data/armor/` are empty/uncreated. Treat this as the spec to implement against, not a description of current code. The pieces that *do* exist today: `colonist.gd` tracks HP directly (`take_damage(amount, source)` / `heal(amount)`, emitting `EventBus.colonist_died` at 0), the `player_died` signal is declared on EventBus (no emitter), and block-level durability-vs-HP already works in `BlockyGrid` (`get_hp_at` / `apply_damage` + `block_destroyed`) — the structural weak-point analysis in [Tech Debt](tech-debt.md) builds on that seam.

## Files

| File | Type | Responsibility |
|---|---|---|
| `damage_resolver.gd` | Script | Static/class: applies damage per §6.11. AP-equivalent (Durability) depletes first, overflow to HP. Used by player, colonists, enemies. |
| `health_component.gd` | Script | Reusable component (Node): HP + Durability + death signal. Attached to player, colonists, enemies. |
| `breath_component.gd` | Script | Reusable component (Node): Breath pool (burst energy). Attached to player, colonists, enemies. See [Energy](energy.md) subsystem. |
| `stamina_component.gd` | Script | Reusable component (Node): Stamina pool (daily energy). Attached to player + colonists (enemies future). See [Energy](energy.md) subsystem. |
| `weapon_base.gd` | Script | Base for weapons; defines damage/rate/range. |
| `enemy_base.gd` | Script | Base for all enemies. Owns state machine hook, navigation. Does NOT own damage rules (uses DamageResolver). |
| `brawler.gd` / `brawler.tscn` | Script/Scene | Brawler archetype: Chase state, 1.5m melee, 5s LOS timeout. |
| `shooter.gd` / `shooter.tscn` | Script/Scene | Shooter archetype: Reposition state, 10m holding, melee fallback. |
| `../data/characters/` | Data | CharacterDef per type (player.tres, colonist.tres, companion.tres, brawler.tres, shooter.tres). Supersedes the retired `data/player_stats.tres` and `data/enemies/`. |
| `../data/weapons/` | Data | Weapon stats (Knife, Pistol; Club/Bow post-MVP). |
| `../data/armor/` | Data | Armor Durability per piece per tier (Cloth/Leather/Scrap). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `entity_died(entity)` | `health_component.gd` | owner script (player/colonist/enemy) | No | Damage Resolution |
| `player_died(context)` | `player.gd` (on death signal) | GameState, HUD | Yes | Player Death |
| `colonist_died(colonist_id)` | `colonist.gd` (on death) | Colony, HUD, Memorial | Yes | Colonist Death |

## Flow Trace: Damage resolution (Durability-before-HP)

**Trigger:** Any entity takes a hit (melee swing connects, ranged shot hits).

1. Attacker calls `target.health_component.take_damage(amount, source)`.
2. `health_component` calls `DamageResolver.apply(amount, current_durability, current_hp)`.
3. DamageResolver: if Durability > 0, reduce Durability first; overflow to HP.
4. Returns new `{durability, hp}`; health_component updates.
5. If hp ≤ 0 → emit `entity_died`.

**End state:** Durability/HP updated; death signal if applicable.

## Flow Trace: Brawler engages player

**Trigger:** Player enters Brawler's 10m detection radius with LOS.

1. Brawler transitions Idle → Chase; acquires player as target.
2. NavigationAgent paths toward player.
3. Every 0.5s, re-targets nearest reachable colonist/player.
4. On reaching 1.5m → Chase → Attack.
5. Attack windup 0.4s → applies 25 damage to player via `health_component.take_damage`.
6. If player leaves 1.5m → back to Chase; if LOS lost 5s → Idle.

**End state:** Brawler in melee combat; player taking damage.

## Class Reference

### Class: DamageResolver

**Extends:** RefCounted (static class)
**Script:** `damage_resolver.gd`
**Description:** Pure damage math per GDD §6.11. No state, no signals — just computes new Durability/HP from inputs.
**Used by:** Combat (player/colonist/enemy damage), UI (display).

**Functions:**

| Function | Description |
|---|---|
| `static apply(damage: int, durability: int, hp: int) -> Dictionary` | Returns `{durability, hp, died: bool}`. Durability depletes first, overflow to HP. |

### Class: HealthComponent

**Extends:** Node
**Script:** `health_component.gd`
**Description:** Reusable component attached to any damageable entity. Holds HP + Durability; delegates math to DamageResolver. One of three paired character-stat components on the player/colonists (with BreathComponent + StaminaComponent); enemies get HealthComponent + BreathComponent only.
**Used by:** Player, Colonists, Enemies.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `max_hp` | `int` | [export] 200 (player) / 100 (colonist) / varies (enemy). |
| `max_durability` | `int` | Derived at runtime from the character's `Equipment` component (`equipment.get_total_durability()`); recalculated on equip/unequip. 0 if no armor equipped. |
| `hp` / `durability` | `int` | Current values. |

**Signals:**

| Signal | Description |
|---|---|
| `hp_changed(new_hp)` | For UI health bars. |
| `durability_changed(new_durability)` | For UI armor bars. |
| `entity_died()` | HP hit 0. |
