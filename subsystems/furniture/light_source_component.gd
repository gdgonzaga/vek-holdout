class_name LightSourceComponent
extends Node3D
## Component attached to placed furniture entities that emit light (GDD §7.2).
## Reads LightParams from the parent Furniture definition and manages an OmniLight3D node.

## Back-reference to the capability definition.
var params: LightParams = null

## Instanced light node child.
var light_node: OmniLight3D = null


func _ready() -> void:
	# 1. Capability Resolution: Extracts LightParams from the parent furniture definition.
	_resolve_light_params()
	
	if params == null:
		return
		
	# 2. Light Instantiation: Spawns and configures the child OmniLight3D node.
	_create_light_node()


## Returns the active OmniLight3D child node, or null if uninitialized.
func get_light_node() -> OmniLight3D:
	return light_node


func _resolve_light_params() -> void:
	## Auxiliary: Locates parent Furniture node and assigns its light_params.
	var furniture := get_parent() as Furniture
	if furniture == null or furniture.def == null:
		return
	if furniture.def is FurnitureDef:
		var fdef := furniture.def as FurnitureDef
		params = fdef.light_params


func _create_light_node() -> void:
	## Auxiliary: Instantiates OmniLight3D and applies configuration parameters.
	var light := OmniLight3D.new()
	light.name = "OmniLight3D"
	add_child(light)
	
	# 1. Configuration Application: Sets light properties and spatial offset.
	_apply_light_configuration(light)
	light_node = light


func _apply_light_configuration(light: OmniLight3D) -> void:
	## Auxiliary: Applies color, energy, range, attenuation, shadows, and offset to OmniLight3D.
	if params == null or light == null:
		return
	light.light_color = params.color
	light.light_energy = params.energy
	light.omni_range = params.range
	light.omni_attenuation = params.attenuation
	light.shadow_enabled = params.shadows_enabled
	light.position = params.local_offset
