class_name DamageResolver
extends RefCounted
## Pure Durability-before-HP arithmetic (GDD §6.11), extracted from
## HealthComponent.take_damage() as the seam a future armor/buff pass hooks
## (ARCH combat.md "planned: damage_resolver.gd").

## Remaining durability after `amount` damage is absorbed, floored at 0.
static func resolve_durability(amount: int, current_durability: int) -> int:
	if current_durability <= 0:
		return current_durability
	return maxi(0, current_durability - amount)


## Portion of `amount` left over once durability has absorbed what it can.
static func resolve_overflow(amount: int, current_durability: int) -> int:
	if current_durability <= 0:
		return amount
	return maxi(0, amount - current_durability)
