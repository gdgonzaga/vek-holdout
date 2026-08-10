class_name CharacterInventory
extends Inventory

@export var base_capacity: float = 50.0
var bonus_capacity: float = 0.0

func _ready() -> void:
	_recalc_capacity()
	# TODO: Connect to bag equipment change signal

func _on_bag_equipment_changed() -> void:
	_recalc_capacity()

func _recalc_capacity() -> void:
	capacity = base_capacity + bonus_capacity
