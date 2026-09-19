class_name ICombatSource
extends RefCounted
## Duck-typed contract for a combat-capable agent or its combat-owning
## component, resolved by AIUtils.resolve_combat_source() (via has_method()
## checks -- do NOT extend this script) for BT tasks that need an effective
## attack range or the underlying CombatActionParams without caring whether
## the agent is a Colonist (delegates to its sibling ColonistCombat node) or
## an EnemyBase (implements this directly, sourced from EnemyDef.attack_params).
##
## Partial implementation is expected: EnemyBase implements only the two
## resolution methods below (no independent cooldown/attack-dispatch yet --
## BTActionMeleeAttack keeps its own windup/cooldown timer state instead of
## delegating execution). ColonistCombat additionally implements
## is_target_in_range()/is_on_cooldown()/attack(), used by
## BTActionColonistCombatAttack, which are not part of this shared contract.


## The agent's currently equipped/authored combat action, or null if it
## cannot currently attack (unarmed colonist, or an enemy with no
## attack_params authored on its EnemyDef).
func get_combat_action() -> CombatActionParams:
	return null


## Effective attack range in meters for the resolved combat action, or 0.0
## if none is currently available.
func get_attack_range() -> float:
	return 0.0
