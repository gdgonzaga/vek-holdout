class_name IOccupiable
extends RefCounted
## Duck-typed contract for capability components that ration colonist access to a
## piece of furniture. ColonistBrain discovers implementations via has_method()
## checks while scoring smart-object targets — do NOT extend this script.
##
## Two-phase claiming exists because the brain polls every 1.5s while the
## behavior tree ticks at 60Hz: `reserve` is taken the moment the brain commits
## to a target so rival colonists stop scoring it, and `begin_use` only promotes
## that reservation once the colonist has physically arrived.
##
## Implementations: RecreationComponent, BedComponent.


## True when `user` may claim a slot. MUST return true when `user` already holds
## one — the brain re-scores its own current target every cycle, and a component
## that reported "full" to its own occupant would zero that goal's score and make
## the colonist thrash between goals.
func is_usable_by(_user: Node) -> bool:
	return true


## Take a slot for a colonist en route. Idempotent for the same user.
## Returns false when no slot is free.
func reserve(_user: Node) -> bool:
	return false


## Drop whatever claim `user` holds, reserved or active. Safe to call for a user
## holding nothing, so callers never need to track claim state themselves.
func release(_user: Node) -> void:
	pass


## Promote a reservation to active use once the colonist has arrived.
## Returns false when the user holds no reservation.
func begin_use(_user: Node) -> bool:
	return false


## End active use and free the slot.
func end_use(_user: Node) -> void:
	pass


## Global position this user should stand at to use the object.
func use_position_for(_user: Node) -> Vector3:
	return Vector3.ZERO
