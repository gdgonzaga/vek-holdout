class_name EnemyBase
extends CharacterBody3D
## Base class for all hostile entities (ARCH combat.md).
## Requires a HealthComponent child node.

@export var speed: float = 5.0
@export var gravity: float = 9.8

@onready var health_component: HealthComponent = $HealthComponent


func _ready() -> void:
	add_to_group(&"enemies")
	if not health_component:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component:
		if not health_component.entity_died.is_connected(_on_entity_died):
			health_component.entity_died.connect(_on_entity_died)
	else:
		push_warning("EnemyBase: missing HealthComponent child node on %s" % name)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


## Convenience forwarder to HealthComponent.
func take_damage(amount: int, source: Node = null) -> void:
	if not health_component:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component:
		health_component.take_damage(amount, source)


func _on_entity_died(_entity: Node) -> void:
	queue_free()


## Persistence for SaveSystem.
func serialize() -> Dictionary:
	var data := {
		"position": [
			position.x, position.y, position.z
		],
		"velocity": [
			velocity.x, velocity.y, velocity.z
		],
	}
	if not health_component:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component:
		data["health"] = health_component.serialize()
	return data


func deserialize(data: Dictionary) -> void:
	if data.has("position"):
		var p: Array = data["position"]
		if p.size() >= 3:
			position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if data.has("velocity"):
		var v: Array = data["velocity"]
		if v.size() >= 3:
			velocity = Vector3(float(v[0]), float(v[1]), float(v[2]))
	if not health_component:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component and data.has("health"):
		health_component.deserialize(data["health"])
