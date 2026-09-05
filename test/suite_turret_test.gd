extends GdUnitTestSuite

## Unit tests for Turret defenses, TurretParams, and TurretProjectile (ARCH combat.md, GDD §7.10).

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const Doubles = preload("res://test/helpers/doubles.gd")

const TurretParamsScript = preload("res://data/capability_params/turret_params.gd")
const TurretComponentScript = preload("res://subsystems/combat/components/turret_component.gd")
const TurretProjectileScript = preload("res://subsystems/combat/components/turret_projectile.gd")
const HealthCompScript = preload("res://subsystems/combat/components/health_component.gd")
const FurnitureDefScript = preload("res://data/furniture/furniture_def.gd")
const FurnitureScript = preload("res://subsystems/furniture/furniture.gd")
const FurnitureLayerScript = preload("res://subsystems/build/furniture_layer.gd")

var _sandbox: ColonySandbox


class MockEnemyTarget extends Node3D:
	var total_damage_received: int = 0
	var health_comp: HealthComponent = null

	func _init() -> void:
		add_to_group(&"enemies")

	func take_damage(amount: int, _source: Node = null) -> void:
		total_damage_received += amount


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	if _sandbox != null:
		_sandbox.restore()
		_sandbox = null


func _make_mock_enemy(pos: Vector3, hp: int = 100) -> MockEnemyTarget:
	var enemy := MockEnemyTarget.new()
	auto_free(enemy)
	_sandbox.container.add_child(enemy)
	enemy.global_position = pos
	var health := HealthCompScript.new() as HealthComponent
	health.name = "HealthComponent"
	health.max_hp = hp
	health.max_durability = 0
	enemy.add_child(health)
	health._ready()
	enemy.health_comp = health
	return enemy


func _make_test_item_def(id_str: String) -> ItemDef:
	var item := ItemDef.new()
	item.id = id_str
	item.weight = 0.5
	return item


func test_turret_params_defaults() -> void:
	var p := TurretParamsScript.new() as TurretParams
	auto_free(p)
	assert_float(p.range).is_equal(15.0)
	assert_float(p.fire_rate).is_equal(1.0)
	assert_int(p.damage).is_equal(10)
	assert_object(p.ammo_type).is_null()
	assert_int(p.projectile_type).is_equal(TurretParams.ProjectileType.REGULAR)
	assert_float(p.explosion_radius).is_equal(3.0)
	assert_vector(p.muzzle_offset).is_equal(Vector3(0, 2.0, 0))


func test_turret_component_initialization() -> void:
	var fdef := FurnitureDefScript.new() as FurnitureDef
	auto_free(fdef)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.range = 25.0
	fdef.turret_params = tparams

	var furniture := FurnitureScript.new() as Furniture
	auto_free(furniture)
	furniture.def = fdef

	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	furniture.add_child(turret)
	turret._ready()

	assert_object(turret.params).is_equal(tparams)
	assert_float(turret.params.range).is_equal(25.0)


func test_turret_targeting_closest_enemy() -> void:
	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.range = 30.0
	turret.params = tparams
	_sandbox.container.add_child(turret)
	turret.global_position = Vector3(0, 0, 0)

	var enemy_far := _make_mock_enemy(Vector3(20, 0, 0))
	var enemy_close := _make_mock_enemy(Vector3(5, 0, 0))

	var target := turret.find_closest_target()
	assert_object(target).is_equal(enemy_close)


func test_turret_ignores_enemy_out_of_range() -> void:
	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.range = 10.0
	turret.params = tparams
	_sandbox.container.add_child(turret)
	turret.global_position = Vector3(0, 0, 0)

	var enemy_out_of_range := _make_mock_enemy(Vector3(25, 0, 0))

	var target := turret.find_closest_target()
	assert_object(target).is_null()


func test_turret_ignores_dead_enemy() -> void:
	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.range = 15.0
	turret.params = tparams
	_sandbox.container.add_child(turret)
	turret.global_position = Vector3.ZERO

	var dead_enemy := _make_mock_enemy(Vector3(5, 0, 0), 20)
	dead_enemy.health_comp.take_damage(20) # kills it
	assert_bool(dead_enemy.health_comp.is_dead).is_true()

	var target := turret.find_closest_target()
	assert_object(target).is_null()


func test_turret_firing_free_ammo() -> void:
	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.ammo_type = null # No ammo required
	tparams.fire_rate = 2.0
	turret.params = tparams
	_sandbox.container.add_child(turret)

	var enemy := _make_mock_enemy(Vector3(5, 0, 0))
	var counter := Doubles.SignalCounter.new(turret.projectile_fired)

	turret._tick(0.1) # Ready to fire
	assert_int(counter.read()).is_equal(1)


func test_turret_firing_with_colony_ammo() -> void:
	var ammo_def := _make_test_item_def("test_arrow")
	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.ammo_type = ammo_def
	turret.params = tparams
	_sandbox.container.add_child(turret)

	# Stock crate in colony storage with 1 ammo
	var crate := _sandbox.make_crate("test_arrow", 0)
	var crate_inv := Colony.storage_registry.inventory_of(crate)
	crate_inv.items["test_arrow"] = 1
	assert_int(crate_inv.get_item_count("test_arrow")).is_equal(1)

	var enemy := _make_mock_enemy(Vector3(5, 0, 0))
	var counter := Doubles.SignalCounter.new(turret.projectile_fired)

	turret._tick(0.1) # Fires and consumes 1 ammo
	assert_int(counter.read()).is_equal(1)
	assert_int(crate_inv.get_item_count("test_arrow")).is_equal(0)


func test_turret_firing_with_local_ammo() -> void:
	var ammo_def := _make_test_item_def("test_stake")
	var fdef := FurnitureDefScript.new() as FurnitureDef
	auto_free(fdef)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.ammo_type = ammo_def
	fdef.turret_params = tparams

	var furniture := FurnitureScript.new() as Furniture
	auto_free(furniture)
	furniture.def = fdef

	var local_storage := StorageInventory.new()
	auto_free(local_storage)
	local_storage.name = "StorageInventory"
	local_storage.capacity = 50.0
	local_storage.items["test_stake"] = 2
	furniture.add_child(local_storage)

	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	furniture.add_child(turret)
	turret.params = tparams
	_sandbox.container.add_child(furniture)

	var enemy := _make_mock_enemy(Vector3(5, 0, 0))
	var counter := Doubles.SignalCounter.new(turret.projectile_fired)

	turret._tick(0.1)
	assert_int(counter.read()).is_equal(1)
	# Local storage consumed 1
	assert_int(local_storage.get_item_count("test_stake")).is_equal(1)


func test_turret_cannot_fire_without_ammo() -> void:
	var ammo_def := _make_test_item_def("test_bullet")
	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.ammo_type = ammo_def
	turret.params = tparams
	_sandbox.container.add_child(turret)

	var enemy := _make_mock_enemy(Vector3(5, 0, 0))
	var counter := Doubles.SignalCounter.new(turret.projectile_fired)

	turret._tick(0.1)
	assert_int(counter.read()).is_equal(0)


func test_turret_respects_cooldown() -> void:
	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.ammo_type = null
	tparams.fire_rate = 1.0 # 1 shot per second
	turret.params = tparams
	_sandbox.container.add_child(turret)

	var enemy := _make_mock_enemy(Vector3(5, 0, 0))
	var counter := Doubles.SignalCounter.new(turret.projectile_fired)

	# Shot 1
	turret._tick(0.1)
	assert_int(counter.count).is_equal(1)

	# Shot 2 attempted immediately -> on cooldown
	turret._tick(0.5)
	assert_int(counter.count).is_equal(1)

	# Cooldown finished after 0.5s more
	turret._tick(0.5)
	assert_int(counter.count).is_equal(2)
	counter.read()


func test_turret_projectile_regular_direct_damage() -> void:
	var proj := TurretProjectileScript.new() as TurretProjectile
	auto_free(proj)
	_sandbox.container.add_child(proj)

	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.damage = 18
	tparams.projectile_type = TurretParams.ProjectileType.REGULAR
	proj.setup(Transform3D.IDENTITY, Vector3.FORWARD, tparams)

	var enemy := _make_mock_enemy(Vector3(0, 0, 2))
	proj._handle_impact(enemy)

	assert_int(enemy.total_damage_received).is_equal(18)


func test_turret_projectile_explosive_splash_damage() -> void:
	var proj := TurretProjectileScript.new() as TurretProjectile
	auto_free(proj)
	_sandbox.container.add_child(proj)
	proj.global_position = Vector3(0, 0, 0)

	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.damage = 30
	tparams.projectile_type = TurretParams.ProjectileType.EXPLOSIVE
	tparams.explosion_radius = 5.0
	proj.setup(Transform3D.IDENTITY, Vector3.FORWARD, tparams)

	var enemy_in_blast1 := _make_mock_enemy(Vector3(2, 0, 0))
	var enemy_in_blast2 := _make_mock_enemy(Vector3(0, 0, 4))
	var enemy_outside := _make_mock_enemy(Vector3(10, 0, 0))

	# Trigger explosion
	proj._explode()

	assert_int(enemy_in_blast1.total_damage_received).is_equal(30)
	assert_int(enemy_in_blast2.total_damage_received).is_equal(30)
	assert_int(enemy_outside.total_damage_received).is_equal(0)


func test_furniture_layer_attaches_turret_component() -> void:
	var fdef := FurnitureDefScript.new() as FurnitureDef
	auto_free(fdef)
	fdef.id = "test_turret"
	fdef.mesh = BoxMesh.new()
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	fdef.turret_params = tparams

	var flayer := FurnitureLayerScript.new() as FurnitureLayer
	auto_free(flayer)
	var node := flayer._create_furniture_node(fdef, Vector3i.ONE, 0)
	auto_free(node)

	assert_object(node.get_node_or_null("TurretComponent")).is_not_null()

func test_turret_muzzle_offset_position() -> void:
	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.muzzle_offset = Vector3(0, 1.5, -0.5)
	turret.params = tparams
	_sandbox.container.add_child(turret)
	turret.global_position = Vector3(10, 0, 10)

	var muzzle_pos := turret.get_muzzle_position()
	assert_float(muzzle_pos.x).is_equal_approx(10.0, 0.01)
	assert_float(muzzle_pos.y).is_equal_approx(1.5, 0.01)
	assert_float(muzzle_pos.z).is_equal_approx(9.5, 0.01)


func test_turret_muzzle_node_overrides_offset() -> void:
	var furniture := Node3D.new()
	auto_free(furniture)
	_sandbox.container.add_child(furniture)
	furniture.global_position = Vector3(10, 0, 10)

	var muzzle_marker := Marker3D.new()
	muzzle_marker.name = "Muzzle"
	furniture.add_child(muzzle_marker)
	muzzle_marker.global_position = Vector3(12, 3, 8)

	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.muzzle_offset = Vector3(0, 1.0, 0)
	turret.params = tparams
	furniture.add_child(turret)

	var muzzle_pos := turret.get_muzzle_position()
	assert_float(muzzle_pos.x).is_equal_approx(12.0, 0.01)
	assert_float(muzzle_pos.y).is_equal_approx(3.0, 0.01)
	assert_float(muzzle_pos.z).is_equal_approx(8.0, 0.01)


func test_turret_projectile_falls_back_to_ammo_mesh() -> void:
	var proj := TurretProjectileScript.new() as TurretProjectile
	auto_free(proj)
	_sandbox.container.add_child(proj)

	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.projectile_mesh = null

	var mock_mesh := BoxMesh.new()
	var ammo_item := _make_test_item_def("test_ammo_with_mesh")
	ammo_item.mesh = mock_mesh
	tparams.ammo_type = ammo_item

	proj.setup(Transform3D.IDENTITY, Vector3.FORWARD, tparams)

	var mesh_inst: MeshInstance3D = null
	for child in proj.get_children():
		if child is MeshInstance3D:
			mesh_inst = child as MeshInstance3D
			break

	assert_object(mesh_inst).is_not_null()
	assert_object(mesh_inst.mesh).is_equal(mock_mesh)


func test_turret_projectile_falls_back_to_ammo_scene() -> void:
	var proj := TurretProjectileScript.new() as TurretProjectile
	auto_free(proj)
	_sandbox.container.add_child(proj)

	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.projectile_mesh = null
	tparams.projectile_scene = null

	var packed_scene := PackedScene.new()
	var root := Node3D.new()
	root.name = "SceneAmmoRoot"
	packed_scene.pack(root)
	root.free()

	var ammo_item := _make_test_item_def("test_ammo_with_scene")
	ammo_item.scene = packed_scene
	tparams.ammo_type = ammo_item

	proj.setup(Transform3D.IDENTITY, Vector3.FORWARD, tparams)

	var scene_child: Node = null
	for child in proj.get_children():
		if child.name == "SceneAmmoRoot":
			scene_child = child
			break

	assert_object(scene_child).is_not_null()


func test_turret_yaw_pitch_node_discovery() -> void:
	var furniture := Node3D.new()
	auto_free(furniture)
	_sandbox.container.add_child(furniture)

	var yaw_node := Node3D.new()
	yaw_node.name = "TurretYaw"
	furniture.add_child(yaw_node)

	var pitch_node := Node3D.new()
	pitch_node.name = "TurretPitch"
	yaw_node.add_child(pitch_node)

	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	furniture.add_child(turret)

	assert_object(turret._find_yaw_node()).is_equal(yaw_node)
	assert_object(turret._find_pitch_node()).is_equal(pitch_node)


func test_turret_yaw_rotation_towards_target() -> void:
	var furniture := Node3D.new()
	auto_free(furniture)
	_sandbox.container.add_child(furniture)
	furniture.global_position = Vector3.ZERO

	var yaw_node := Node3D.new()
	yaw_node.name = "TurretYaw"
	furniture.add_child(yaw_node)

	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.range = 20.0
	tparams.turn_speed = 10.0
	turret.params = tparams
	furniture.add_child(turret)

	# Target directly to the right (+X direction: Vector3(10, 0, 0))
	var enemy := _make_mock_enemy(Vector3(10, 0, 0))

	# Step 1 tick (0.05s * 10 rad/s = 0.5 rad rotation)
	turret._tick(0.05)

	# rotation.y should have rotated towards -PI/2 (-1.57 rad)
	assert_float(yaw_node.rotation.y).is_less(0.0)


func test_turret_pitch_clamping() -> void:
	var furniture := Node3D.new()
	auto_free(furniture)
	_sandbox.container.add_child(furniture)
	furniture.global_position = Vector3.ZERO

	var pitch_node := Node3D.new()
	pitch_node.name = "TurretPitch"
	furniture.add_child(pitch_node)

	var turret := TurretComponentScript.new() as TurretComponent
	auto_free(turret)
	var tparams := TurretParamsScript.new() as TurretParams
	auto_free(tparams)
	tparams.range = 50.0
	tparams.turn_speed = 100.0 # High speed to reach clamp instantly
	tparams.max_pitch_deg = 30.0
	turret.params = tparams
	furniture.add_child(turret)

	# Target high above within range (50m max): Vector3(0, 30, -5) -> dist ~30.4m
	var enemy := _make_mock_enemy(Vector3(0, 30, -5))

	turret._tick(1.0)

	# rotation.x should clamp to 30 deg (0.5236 rad)
	var max_pitch_rad := deg_to_rad(30.0)
	assert_float(pitch_node.rotation.x).is_equal_approx(max_pitch_rad, 0.01)
