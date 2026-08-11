class_name RotationState
extends RefCounted
## Build rotation state (ARCH "Build", line 451): axis cycle (R: Z->X->Y) and a
## 90-degree step wheel, plus the even-footprint 0.5m pivot rule (GDD §7.4).
##
## STUB: the ghost cube is rotation-symmetric, so rotation has no visible effect
## yet. This class exists so BuildController.rotation_state is real and the
## rotation flow lands as fill-in once non-cubic blocks exist.

enum Axis { Z, X, Y }

var axis: Axis = Axis.Z
var step: int = 0   # 0..3 (quarters)


## Cycle the rotation axis (R key). Z -> X -> Y -> Z.
func cycle_axis() -> void:
	axis = (axis + 1) % 3 as Axis


## Advance the 90-degree step (mouse wheel up). 0 -> 1 -> 2 -> 3 -> 0.
func cycle_step() -> void:
	step = (step + 1) % 4


## Reverse the 90-degree step (mouse wheel down). 0 -> 3 -> 2 -> 1 -> 0.
func cycle_step_back() -> void:
	step = (step - 1 + 4) % 4


## The current yaw rotation in degrees, derived from axis + step.
## TODO: real per-axis basis + the 0.5m pivot rule for even footprints. For now
## returns a Z-axis yaw so the stub compiles and is harmless for a cube.
func get_yaw_degrees() -> float:
	return float(step) * 90.0
