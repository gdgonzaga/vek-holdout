class_name ColonistCombat
extends Node
## Reactive weapon-combat component (GDD §6.7 "Fight" stance, MVP subset — any
## armed colonist fights back from wherever it is, no pursuit). Attached to
## colonist.tscn's pre-scaffolded "ColonistCombat" node. Resolves the
## colonist's equipped weapon's primary_action and fires/swings at a target
## already selected by BTActionScanThreats; never moves the colonist.

var _colonist: Colonist
var _cooldown_remaining: float = 0.0
var _current_target: Node3D = null
var _anim_controller: Node = null


func _ready() -> void:
	_colonist = get_parent() as Colonist


func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta


## The equipped weapon's primary combat action, or null if unarmed / the
## equipped item's primary action isn't combat-capable (e.g. a tool).
func get_combat_action() -> CombatActionParams:
	if _colonist == null:
		return null
	var item := _colonist.get_equipped_item()
	if item == null or not item.is_equippable():
		return null
	return item.equippable.primary_action as CombatActionParams


func is_target_in_range(target: Node3D) -> bool:
	var action := get_combat_action()
	if action == null or target == null or not is_instance_valid(target) or _colonist == null:
		return false
	var range_dist: float = action.range_meters if action.range_meters > 0.0 else 2.0
	return _colonist.global_position.distance_to(target.global_position) <= range_dist


func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0


## Fires/swings at `target`. No-ops if unarmed or still on cooldown.
func attack(target: Node3D) -> bool:
	var action := get_combat_action()
	if action == null or is_on_cooldown() or _colonist == null:
		return false
	_current_target = target
	# 1. Attack Animation Trigger: Plays the equipped weapon's one-shot swing
	# animation, mirroring Player._execute_equipped_primary_action(). Only
	# reached on the successful-execution path (already gated by the cooldown
	# check above), so it fires once per attack instead of retriggering mid-swing.
	_trigger_attack_animation()
	action.execute(_colonist)
	_cooldown_remaining = action.get_lockout_duration()
	return true


func get_aim_direction() -> Vector3:
	if _colonist == null:
		return Vector3.FORWARD
	if _current_target == null or not is_instance_valid(_current_target):
		return -_colonist.global_transform.basis.z
	return _colonist.get_aim_origin().direction_to(_current_target.global_position + Vector3(0, 1.0, 0))


func _trigger_attack_animation() -> void:
	## Auxiliary: Plays the equipped weapon's one-shot use_animation via
	## ColonistAnimationController.trigger_action(), the same "AttackOverhead"
	## style call Player makes for the identical weapon.
	var item := _colonist.get_equipped_item()
	if item == null or item.equippable == null:
		return
	_anim_controller = AIUtils.resolve_anim_controller(_anim_controller, _colonist)
	if _anim_controller == null or not _anim_controller.has_method("trigger_action"):
		return
	var equip_params: EquippableParams = item.equippable
	var anim: StringName = equip_params.use_animation if equip_params.use_animation != &"" else &"Interact"
	_anim_controller.trigger_action(anim)
