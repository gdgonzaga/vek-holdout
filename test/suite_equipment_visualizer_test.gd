extends GdUnitTestSuite

func _create_test_player(skeleton_bones: Array[String] = []) -> Dictionary:
	var player: Player = auto_free(Player.new())
	player.equipment = Equipment.ensure_on(player, null)
	var skeleton: Skeleton3D = auto_free(Skeleton3D.new())
	skeleton.name = "GeneralSkeleton"
	for bone in skeleton_bones:
		skeleton.add_bone(bone)
	player.add_child(skeleton)
	return {"player": player, "skeleton": skeleton}


func test_rigid_parts_create_wear_bone_attachments_on_right_bones() -> void:
	var setup: Dictionary = _create_test_player(["Head", "Chest"])
	var player: Player = setup["player"]
	var skeleton: Skeleton3D = setup["skeleton"]

	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "test_armor"
	item.tags = ["equip_torso"]
	var wearable: WearableParams = auto_free(WearableParams.new())

	var part_head: WearablePart = auto_free(WearablePart.new())
	part_head.bone = &"Head"
	part_head.mesh = SphereMesh.new()

	var part_chest: WearablePart = auto_free(WearablePart.new())
	part_chest.bone = &"Chest"
	part_chest.mesh = BoxMesh.new()

	wearable.rigid_parts = [part_head, part_chest]
	item.wearable = wearable

	player.equipment.equip("torso", item)

	var wear_head: BoneAttachment3D = skeleton.get_node_or_null("WearBone_Head") as BoneAttachment3D
	assert_object(wear_head).is_not_null()
	assert_str(wear_head.bone_name).is_equal("Head")
	assert_int(wear_head.get_child_count()).is_equal(1)
	assert_str(wear_head.get_child(0).name).is_equal("WearableVisual")

	var wear_chest: BoneAttachment3D = skeleton.get_node_or_null("WearBone_Chest") as BoneAttachment3D
	assert_object(wear_chest).is_not_null()
	assert_str(wear_chest.bone_name).is_equal("Chest")
	assert_int(wear_chest.get_child_count()).is_equal(1)


func test_missing_bone_part_skipped_without_error() -> void:
	var setup: Dictionary = _create_test_player(["Head"])
	var player: Player = setup["player"]
	var skeleton: Skeleton3D = setup["skeleton"]

	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "test_partial_gear"
	item.tags = ["equip_head"]
	var wearable: WearableParams = auto_free(WearableParams.new())

	var part_valid: WearablePart = auto_free(WearablePart.new())
	part_valid.bone = &"Head"
	part_valid.mesh = SphereMesh.new()

	var part_missing: WearablePart = auto_free(WearablePart.new())
	part_missing.bone = &"NonExistentBone"
	part_missing.mesh = BoxMesh.new()

	wearable.rigid_parts = [part_valid, part_missing]
	item.wearable = wearable

	player.equipment.equip("head", item)

	assert_object(skeleton.get_node_or_null("WearBone_NonExistentBone")).is_null()
	var wear_head: BoneAttachment3D = skeleton.get_node_or_null("WearBone_Head") as BoneAttachment3D
	assert_object(wear_head).is_not_null()
	assert_int(wear_head.get_child_count()).is_equal(1)


func test_unequip_removes_all_slot_visuals() -> void:
	var setup: Dictionary = _create_test_player(["Head", "Chest"])
	var player: Player = setup["player"]
	var skeleton: Skeleton3D = setup["skeleton"]

	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "test_suit"
	item.tags = ["equip_torso"]
	var wearable: WearableParams = auto_free(WearableParams.new())

	var part_head: WearablePart = auto_free(WearablePart.new())
	part_head.bone = &"Head"
	part_head.mesh = SphereMesh.new()

	var part_chest: WearablePart = auto_free(WearablePart.new())
	part_chest.bone = &"Chest"
	part_chest.mesh = BoxMesh.new()

	wearable.rigid_parts = [part_head, part_chest]
	item.wearable = wearable

	player.equipment.equip("torso", item)
	var wear_head: BoneAttachment3D = skeleton.get_node_or_null("WearBone_Head") as BoneAttachment3D
	var wear_chest: BoneAttachment3D = skeleton.get_node_or_null("WearBone_Chest") as BoneAttachment3D
	assert_int(wear_head.get_child_count()).is_equal(1)
	assert_int(wear_chest.get_child_count()).is_equal(1)

	player.equipment.unequip("torso")
	assert_int(wear_head.get_child_count()).is_equal(0)
	assert_int(wear_chest.get_child_count()).is_equal(0)


func test_switching_items_leaves_no_leftovers() -> void:
	var setup: Dictionary = _create_test_player(["Head"])
	var player: Player = setup["player"]
	var skeleton: Skeleton3D = setup["skeleton"]

	var item_a: ItemDef = auto_free(ItemDef.new())
	item_a.id = "hat_a"
	item_a.tags = ["equip_head"]
	var wearable_a: WearableParams = auto_free(WearableParams.new())
	var part_a: WearablePart = auto_free(WearablePart.new())
	part_a.bone = &"Head"
	part_a.mesh = SphereMesh.new()
	wearable_a.rigid_parts = [part_a]
	item_a.wearable = wearable_a

	var item_b: ItemDef = auto_free(ItemDef.new())
	item_b.id = "hat_b"
	item_b.tags = ["equip_head"]
	var wearable_b: WearableParams = auto_free(WearableParams.new())
	var part_b: WearablePart = auto_free(WearablePart.new())
	part_b.bone = &"Head"
	part_b.mesh = BoxMesh.new()
	wearable_b.rigid_parts = [part_b]
	item_b.wearable = wearable_b

	player.equipment.equip("head", item_a)
	var wear_head: BoneAttachment3D = skeleton.get_node_or_null("WearBone_Head") as BoneAttachment3D
	assert_int(wear_head.get_child_count()).is_equal(1)
	assert_bool((wear_head.get_child(0) as MeshInstance3D).mesh is SphereMesh).is_true()

	player.equipment.equip("head", item_b)
	assert_int(wear_head.get_child_count()).is_equal(1)
	assert_bool((wear_head.get_child(0) as MeshInstance3D).mesh is BoxMesh).is_true()


func test_two_slots_sharing_bone_do_not_delete_each_others_meshes() -> void:
	var setup: Dictionary = _create_test_player(["Chest"])
	var player: Player = setup["player"]
	var skeleton: Skeleton3D = setup["skeleton"]

	var item_torso: ItemDef = auto_free(ItemDef.new())
	item_torso.id = "torso_armor"
	item_torso.tags = ["equip_torso"]
	var wear_torso: WearableParams = auto_free(WearableParams.new())
	var part_torso: WearablePart = auto_free(WearablePart.new())
	part_torso.bone = &"Chest"
	part_torso.mesh = BoxMesh.new()
	wear_torso.rigid_parts = [part_torso]
	item_torso.wearable = wear_torso

	var item_back: ItemDef = auto_free(ItemDef.new())
	item_back.id = "back_pack"
	item_back.tags = ["equip_back"]
	var wear_back: WearableParams = auto_free(WearableParams.new())
	var part_back: WearablePart = auto_free(WearablePart.new())
	part_back.bone = &"Chest"
	part_back.mesh = SphereMesh.new()
	wear_back.rigid_parts = [part_back]
	item_back.wearable = wear_back

	player.equipment.equip("torso", item_torso)
	player.equipment.equip("back", item_back)

	var wear_chest: BoneAttachment3D = skeleton.get_node_or_null("WearBone_Chest") as BoneAttachment3D
	assert_int(wear_chest.get_child_count()).is_equal(2)

	player.equipment.unequip("torso")
	assert_int(wear_chest.get_child_count()).is_equal(1)
	assert_bool((wear_chest.get_child(0) as MeshInstance3D).mesh is SphereMesh).is_true()

	player.equipment.unequip("back")
	assert_int(wear_chest.get_child_count()).is_equal(0)


func test_skinned_scene_mounts_under_skeleton_and_unequips_cleanly() -> void:
	var setup: Dictionary = _create_test_player(["Hips"])
	var player: Player = setup["player"]
	var skeleton: Skeleton3D = setup["skeleton"]

	var root := Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "SkinnedGarment"
	mesh_inst.mesh = BoxMesh.new()
	mesh_inst.skin = Skin.new()
	root.add_child(mesh_inst)
	mesh_inst.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	root.free()

	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "test_robe"
	item.tags = ["equip_torso"]
	var wearable: WearableParams = auto_free(WearableParams.new())
	wearable.skinned_scene = packed
	item.wearable = wearable

	player.equipment.equip("torso", item)

	var mounted_mesh: MeshInstance3D = skeleton.get_node_or_null("SkinnedGarment") as MeshInstance3D
	assert_object(mounted_mesh).is_not_null()
	assert_object(mounted_mesh.get_parent()).is_equal(skeleton)
	assert_str(String(mounted_mesh.skeleton)).is_equal("..")

	player.equipment.unequip("torso")
	assert_object(skeleton.get_node_or_null("SkinnedGarment")).is_null()


func test_non_wearable_items_use_equip_socket_path() -> void:
	var setup: Dictionary = _create_test_player(["RightHand"])
	var player: Player = setup["player"]
	var skeleton: Skeleton3D = setup["skeleton"]

	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "test_mace"
	item.tags = ["weapon"]
	item.mesh = CylinderMesh.new()

	player.equip_item(item)
	var socket: BoneAttachment3D = skeleton.get_node_or_null("EquipSocket_main_hand") as BoneAttachment3D
	assert_object(socket).is_not_null()
	assert_object(skeleton.get_node_or_null("WearBone_RightHand")).is_null()
	assert_int(socket.get_child_count()).is_equal(1)

	player.unequip_item()
	assert_int(socket.get_child_count()).is_equal(0)

