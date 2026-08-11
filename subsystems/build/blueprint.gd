class_name Blueprint
extends Furniture
## Non-physical "plan" of a buildable (GDD §7.4 Blueprint mode). Represented as
## an interactable furniture-like node so it reuses the Furniture +
## InteractionComponent + GameAction machinery: the player aims at it and
## presses E to run the Build action.
##
## Incremental step toward blueprint-then-build (GDD §7.1/§7.4): completion is
## instant for now, but it funnels through one entry point (complete()) so a
## future colonist work-tick / JobBoard can drive the same path with no
## architecture change — see BlueprintLayer.complete_blueprint.

## The def this blueprint materializes into when built.
@export var target_def_id: String = ""

## Saved placement yaw (RotationState.step) of the target, so the materialized
## block/furniture keeps the player's intended rotation.
@export var target_rotation_step: int = 0

## The anchor cell this blueprint was placed at (set by BlueprintLayer at spawn;
## used by complete() to tell the layer where to materialize the target).
var anchor_cell: Vector3i = Vector3i.ZERO

# Back-ref to the owning layer (untyped to avoid a Blueprint <-> BlueprintLayer
# class_name cycle). Set at spawn; complete() forwards through it.
var layer = null


## Build the target into the world and remove this blueprint. `builder` is the
## player now; it is passed through so the colonist labor loop can attribute
## skill/stamina later. Returns true on success.
func complete(builder: Node = null) -> bool:
	if layer == null:
		return false
	return layer.complete_blueprint(self, builder)
