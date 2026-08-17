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
## default_material is a plain export and is set directly by tests.
class RecordingSmoothGrid extends SmoothGrid:
	var carves: Array = []   # [{pos: Vector3, radius: float}]

	func carve(pos: Vector3, radius: float) -> void:
		carves.append({"pos": pos, "radius": radius})
