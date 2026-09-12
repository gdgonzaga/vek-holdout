extends GdUnitTestSuite

## Unit tests for EquippableParams and modular action schemas (ARCH "Data Schemas / Capabilities").
## Tests capability composition on ItemDef and polymorphic action params.

func test_item_def_default_not_equippable() -> void:
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "plain_stone"
	assert_bool(item.is_equippable()).is_false()
	assert_object(item.equippable).is_null()


func test_item_def_with_equippable_params() -> void:
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "test_sword"
	item.tags = ["weapon", "melee"]
	var equip: EquippableParams = auto_free(EquippableParams.new())
	equip.stance_animation = &"melee_1h"
	item.equippable = equip

	assert_bool(item.is_equippable()).is_true()
	assert_object(item.equippable).is_not_null()
	assert_bool(item.has_tag("weapon")).is_true()
	assert_str(String(item.equippable.stance_animation)).is_equal("melee_1h")


func test_combat_action_params_polymorphism() -> void:
	var item: ItemDef = auto_free(ItemDef.new())
	var equip: EquippableParams = auto_free(EquippableParams.new())
	var action: RangedActionParams = auto_free(RangedActionParams.new())
	action.id = "pistol_shot"
	action.cooldown_seconds = 0.25
	action.damage = 22.0
	action.range_meters = 40.0
	action.is_hitscan = true
	action.spread_angle_degrees = 2.0
	equip.primary_action = action
	item.equippable = equip

	assert_bool(item.is_equippable()).is_true()
	assert_bool(item.equippable.primary_action is EquipActionParams).is_true()
	assert_bool(item.equippable.primary_action is CombatActionParams).is_true()
	assert_bool(item.equippable.primary_action is RangedActionParams).is_true()

	var ranged: RangedActionParams = item.equippable.primary_action as RangedActionParams
	assert_float(ranged.damage).is_equal(22.0)
	assert_float(ranged.cooldown_seconds).is_equal(0.25)
	assert_bool(ranged.is_hitscan).is_true()


func test_melee_action_params_schema() -> void:
	var item: ItemDef = auto_free(ItemDef.new())
	var equip: EquippableParams = auto_free(EquippableParams.new())
	var melee: MeleeActionParams = auto_free(MeleeActionParams.new())
	melee.id = "baton_strike"
	melee.damage = 5.0
	melee.range_meters = 1.0
	melee.windup_seconds = 0.15
	melee.active_seconds = 0.2
	melee.hit_audio_event = "melee_impact"
	equip.primary_action = melee
	item.equippable = equip

	assert_bool(item.is_equippable()).is_true()
	assert_bool(item.equippable.primary_action is EquipActionParams).is_true()
	assert_bool(item.equippable.primary_action is CombatActionParams).is_true()
	assert_bool(item.equippable.primary_action is MeleeActionParams).is_true()

	var retrieved: MeleeActionParams = item.equippable.primary_action as MeleeActionParams
	assert_float(retrieved.damage).is_equal(5.0)
	assert_float(retrieved.range_meters).is_equal(1.0)
	assert_float(retrieved.windup_seconds).is_equal(0.15)
	assert_float(retrieved.active_seconds).is_equal(0.2)
	assert_str(retrieved.hit_audio_event).is_equal("melee_impact")


func test_load_assault_rifle_tres() -> void:
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "assault_rifle"
	item.tags = ["weapon", "ranged"]
	var equip: EquippableParams = auto_free(EquippableParams.new())
	equip.stance_animation = &"rifle"
	var combat: RangedActionParams = auto_free(RangedActionParams.new())
	combat.id = "rifle_fire"
	combat.damage = 15.0
	combat.cooldown_seconds = 0.15
	combat.is_hitscan = true
	equip.primary_action = combat
	item.equippable = equip

	assert_object(item).is_not_null()
	assert_str(item.id).is_equal("assault_rifle")
	assert_bool(item.is_equippable()).is_true()
	assert_object(item.equippable).is_not_null()
	assert_bool(item.has_tag("weapon")).is_true()
	assert_str(String(item.equippable.stance_animation)).is_equal("rifle")
	assert_object(item.equippable.primary_action).is_not_null()
	assert_bool(item.equippable.primary_action is CombatActionParams).is_true()
	assert_bool(item.equippable.primary_action is RangedActionParams).is_true()

	var retrieved: RangedActionParams = item.equippable.primary_action as RangedActionParams
	assert_str(retrieved.id).is_equal("rifle_fire")
	assert_float(retrieved.damage).is_equal(15.0)
	assert_float(retrieved.cooldown_seconds).is_equal(0.15)
	assert_bool(retrieved.is_hitscan).is_true()


func test_colonist_equip_item() -> void:
	var colonist: Colonist = auto_free(Colonist.new())
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "sample_item"
	item.tags = ["tool"]
	colonist.equip_item(item)
	assert_object(colonist.get_equipped_item()).is_equal(item)


func test_player_equip_and_unequip_item() -> void:
	var player: Player = auto_free(Player.new())
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "sample_weapon"
	item.tags = ["weapon"]
	player.equip_item(item)
	assert_object(player.get_equipped_item()).is_equal(item)
	player.unequip_item()
	assert_object(player.get_equipped_item()).is_null()


func test_player_weapon_visual_attachment_with_skeleton() -> void:
	var player: Player = auto_free(Player.new())
	var skeleton: Skeleton3D = auto_free(Skeleton3D.new())
	skeleton.name = "GeneralSkeleton"
	skeleton.add_bone("RightHand")
	player.add_child(skeleton)

	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "test_club"
	item.tags = ["weapon"]
	item.mesh = BoxMesh.new()

	player.equip_item(item)
	# EquipmentVisualizer creates EquipSocket_main_hand on the skeleton's RightHand bone.
	var socket: BoneAttachment3D = skeleton.get_node_or_null("EquipSocket_main_hand") as BoneAttachment3D
	assert_object(socket).is_not_null()
	assert_str(socket.bone_name).is_equal("RightHand")
	assert_int(socket.get_child_count()).is_equal(1)
	assert_str(socket.get_child(0).name).is_equal("EquippedVisual")

	player.unequip_item()
	assert_int(socket.get_child_count()).is_equal(0)


func test_colonist_weapon_visual_attachment_with_custom_socket() -> void:
	var colonist: Colonist = auto_free(Colonist.new())
	var skeleton: Skeleton3D = auto_free(Skeleton3D.new())
	skeleton.name = "GeneralSkeleton"
	skeleton.add_bone("mixamorig:RightHand")
	skeleton.add_bone("socket_hand_r")
	colonist.add_child(skeleton)

	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "test_baton"
	item.tags = ["tool"]
	item.mesh = CylinderMesh.new()

	colonist.equip_item(item)
	# EquipmentVisualizer prefers socket_hand_r per SLOT_BONE_HINTS["main_hand"].
	var socket: BoneAttachment3D = skeleton.get_node_or_null("EquipSocket_main_hand") as BoneAttachment3D
	assert_object(socket).is_not_null()
	assert_str(socket.bone_name).is_equal("socket_hand_r")
	assert_int(socket.get_child_count()).is_equal(1)

	colonist.unequip_item()
	assert_int(socket.get_child_count()).is_equal(0)


func test_animation_controller_resolves_attack_overhead() -> void:
	var controller: PlayerAnimationController = auto_free(PlayerAnimationController.new())
	assert_str(String(controller._resolve_action_animation_name(&"AttackOverhead"))).is_equal("AttackOverhead")
	assert_str(String(controller._resolve_action_animation_name(&"swing"))).is_equal("AttackOverhead")
	assert_str(String(controller._resolve_action_animation_name(&"fire"))).is_equal("Interact")
	assert_str(String(controller._resolve_action_animation_name(&"dig"))).is_equal("Digging")


func test_melee_action_params_windup_and_active_hitbox() -> void:
	var params: MeleeActionParams = auto_free(MeleeActionParams.new())
	params.windup_seconds = 0.01
	params.active_seconds = 0.05
	params.damage = 10.0
	params.range_meters = 2.0

	var enemy: EnemyBase = auto_free(EnemyBase.new())
	var col_shape: CollisionShape3D = auto_free(CollisionShape3D.new())
	var capsule := CapsuleShape3D.new()
	col_shape.shape = capsule
	enemy.add_child(col_shape)
	var health: HealthComponent = auto_free(HealthComponent.new())
	health.name = "HealthComponent"
	health.max_hp = 50
	enemy.add_child(health)
	add_child(enemy)
	enemy.position = Vector3(0, 0, 1.0)
	enemy._ready()

	var attacker: Node3D = auto_free(Node3D.new())
	add_child(attacker)
	attacker.position = Vector3(0, 0, 0)
	attacker.look_at(enemy.position, Vector3.UP)

	await get_tree().physics_frame
	await params.execute(attacker)
	assert_int(health.current_hp).is_equal(40)




func test_player_gun_fire_damages_enemy() -> void:
	var enemy: EnemyBase = auto_free(EnemyBase.new())
	var health: HealthComponent = auto_free(HealthComponent.new())
	health.name = "HealthComponent"
	health.max_hp = 100
	enemy.add_child(health)
	add_child(enemy)
	enemy._ready()

	var combat_params: CombatActionParams = auto_free(CombatActionParams.new())
	combat_params.damage = 35.0

	var player: Player = auto_free(Player.new())
	# Direct test on enemy damage execution
	enemy.take_damage(int(combat_params.damage), player)
	assert_int(health.current_hp).is_equal(65)


func test_combat_action_execute_on_null_actor_is_safe() -> void:
	var action: CombatActionParams = auto_free(CombatActionParams.new())
	# Should not crash or error
	action.execute(null)
	assert_bool(true).is_true()


func test_ranged_action_params_show_tracer_property() -> void:
	var action: RangedActionParams = auto_free(RangedActionParams.new())
	assert_bool(action.show_tracer).is_true()
	action.show_tracer = false
	assert_bool(action.show_tracer).is_false()


func test_enemy_lethal_damage_triggers_death_and_free() -> void:
	var enemy: EnemyBase = auto_free(EnemyBase.new())
	var health: HealthComponent = auto_free(HealthComponent.new())
	health.name = "HealthComponent"
	health.max_hp = 50
	enemy.add_child(health)
	add_child(enemy)
	enemy._ready()

	var combat_params: CombatActionParams = auto_free(CombatActionParams.new())
	combat_params.damage = 60.0

	var player: Player = auto_free(Player.new())
	enemy.take_damage(int(combat_params.damage), player)

	assert_int(health.current_hp).is_equal(0)
	assert_bool(enemy.is_queued_for_deletion()).is_true()


func test_equippable_params_stance_animation() -> void:
	var equip: EquippableParams = auto_free(EquippableParams.new())
	assert_str(String(equip.stance_animation)).is_equal("idle")
	equip.stance_animation = &"melee_1h"
	assert_str(String(equip.stance_animation)).is_equal("melee_1h")


func test_equippable_params_use_animation() -> void:
	var equip: EquippableParams = auto_free(EquippableParams.new())
	assert_str(String(equip.use_animation)).is_equal("use")
	equip.use_animation = &"swing"
	assert_str(String(equip.use_animation)).is_equal("swing")


func test_equip_action_params_lockout_duration_defaults_to_cooldown() -> void:
	var action: EquipActionParams = auto_free(EquipActionParams.new())
	action.cooldown_seconds = 0.5
	assert_float(action.get_lockout_duration()).is_equal_approx(0.5, 0.001)


func test_melee_action_params_lockout_duration_includes_windup_and_active() -> void:
	# Regression: a weapon whose cooldown_seconds is shorter than its own
	# windup+active window (e.g. baton.tres: windup 0.5, active 0.1, cooldown
	# 0.4) let callers re-trigger execute() before the swing in progress even
	# finished, spamming overlapping windups instead of respecting the timing.
	var action: MeleeActionParams = auto_free(MeleeActionParams.new())
	action.windup_seconds = 0.5
	action.active_seconds = 0.1
	action.cooldown_seconds = 0.4
	assert_float(action.get_lockout_duration()).is_equal_approx(1.0, 0.001)


func test_ranged_action_params_lockout_duration_defaults_to_cooldown() -> void:
	var action: RangedActionParams = auto_free(RangedActionParams.new())
	action.cooldown_seconds = 0.3
	assert_float(action.get_lockout_duration()).is_equal_approx(0.3, 0.001)

