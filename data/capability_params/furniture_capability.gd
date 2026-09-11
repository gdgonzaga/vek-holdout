class_name FurnitureCapability
extends Resource
## Abstract base for all furniture capability param resources. Pure data —
## spawn logic for the corresponding runtime component lives in the
## FurnitureLayer capability registry (see subsystems/build/furniture_layer.gd).
##
## Override collect_action_options() when this capability needs to contribute
## ActionOptions to the furniture's InteractionComponent.


## Returns any ActionOptions this capability adds to the furniture's
## InteractionComponent. Called by FurnitureLayer before InteractionComponent is created.
func collect_action_options() -> Array[ActionOption]:
	return []
