extends RefCounted
## Shared test doubles with one home for every suite (AGENTS.md testing
## conventions). Plain inner classes — not gdUnit suites — so the runner never
## scans this file. Use via `const Doubles = preload(...)` and
## `Doubles.SignalCounter.new(...)`, `Doubles.MockInventory.new()`, ...


## Counts signal emissions between construction and read() (read disconnects).
## The loose _on_signal args cover EventBus signals' up-to-two-payload shape.
class SignalCounter extends RefCounted:
	var count := 0
	var _callable: Callable
	var _signal: Signal

	func _init(signal_ref: Signal) -> void:
		_signal = signal_ref
		_callable = Callable(self, "_on_signal")
		_signal.connect(_callable)

	func _on_signal(_a = null, _b = null) -> void:
		count += 1

	func read() -> int:
		_signal.disconnect(_callable)
		return count


## Inventory with mockable item definitions, so add/remove/transfer run the
## production code path without needing .tres files registered in ItemDB.
class MockInventory extends Inventory:
	var _defs: Dictionary = {}

	func _get_def(item_id: String) -> ItemDef:
		return _defs.get(item_id)


## StorageInventory variant of MockInventory — extends the real class so
## transfer_to/can_add run the production code path; only _get_def is stubbed.
class MockStorageInventory extends StorageInventory:
	var _defs: Dictionary = {}

	func _get_def(item_id: String) -> ItemDef:
		return _defs.get(item_id)


## SmoothGrid double that records sphere edits instead of touching voxel_tool —
## dig/placement tests assert on the recorded calls. Never enters the tree, so
## the @onready terrain ref stays unresolved (the overrides never call super).
## default_material is a plain export and is set directly by tests;
## material_def is what the per-position get_material_def_at answers (null =
## "no stats at this position").
class RecordingSmoothGrid extends SmoothGrid:
	var carves: Array = []       # [{pos: Vector3, radius: float}]
	var box_carves: Array = []   # [{min: Vector3, max: Vector3}]
	var adds: Array = []         # [{pos: Vector3, material_id: String, radius: float}]
	var material_def: TerrainMaterialDef = null

	func carve(pos: Vector3, radius: float) -> void:
		carves.append({"pos": pos, "radius": radius})

	func carve_box(min_pos: Vector3, max_pos: Vector3) -> void:
		box_carves.append({"min": min_pos, "max": max_pos})

	func add_material(pos: Vector3, material_id: String, radius: float) -> void:
		adds.append({"pos": pos, "material_id": material_id, "radius": radius})

	func get_material_def_at(_pos: Vector3i) -> TerrainMaterialDef:
		return material_def


## Minimal IStatProvider double (subsystems/core/i_stat_provider.gd) — extends
## Node (not RefCounted) because MoodletDef.evaluate_icon_index(entity: Node)
## and its has_method() checks require a real Node, mirroring
## PathRecordingAgent's approach below. Lets StatThresholdMoodletDef/
## ActivityMoodletDef/MoodletLayoutResolver be tested off plain dictionaries,
## with zero real game content.
class FakeStatProvider extends Node:
	var stat_ratios: Dictionary = {}
	var stat_values: Dictionary = {}
	var current_activity: StringName = &""

	func get_stat_ratio(stat_name: StringName) -> float:
		return stat_ratios.get(stat_name, -1.0)

	func get_stat_value(stat_name: StringName) -> float:
		return stat_values.get(stat_name, -1.0)

	func get_current_activity() -> StringName:
		return current_activity


## Duck-typed BTActionWander/BTActionNavigateTo agent double (pathfinder,
## global_position, set_path, has_arrived) that records every path handed to
## set_path() so tests can assert on the planned path without a full Colonist
## scene tree.
class PathRecordingAgent extends CharacterBody3D:
	var pathfinder: VoxelPathfinder = null
	var received_paths: Array = []

	func set_path(path: Array) -> void:
		received_paths.append(path)

	func has_arrived() -> bool:
		return false
