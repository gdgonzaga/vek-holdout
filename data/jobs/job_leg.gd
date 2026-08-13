extends RefCounted
class_name JobLeg
## One leg of a colonist job's walk→act sequence (ARCH "Subsystem: Colonists").
##
## A Job produces a stream of JobLegs via JobDef.get_next_leg; ColonistAI walks to
## each leg's location, then runs the leg's action through JobDef.begin/complete
## (a begin that returns 0 = instant). Pure routing data — the *what to do here*
## lives in the JobDef, dispatched on `kind`. This keeps legs reusable across
## labors (construction = one WORK leg; hauling = repeated FETCH/DELIVER legs) and
## lets the AI stay dumb about both.
##
## `kind` is an opaque, def-owned discriminator (each JobDef subclass declares
## its own constants, e.g. HaulingJobDef.FETCH/DELIVER). Kept as a plain int
## rather than a shared enum so the base leg stays labor-agnostic — a future
## equip/carry labor just adds its own kind constants without touching this class.

## World-space point the colonist walks toward for this leg. Typically a stand-
## adjacent approach to `target_node`; ColonistAI refines it into a real adjacent
## standing cell at navigation time. Set by the JobDef at leg creation.
var location: Vector3 = Vector3.ZERO

## The in-world node this leg acts on (a crate, a blueprint, ...), or null for a
## pure-position leg. Held as a weak Node ref so a freed target can be detected
## (ColonistAI aborts if it vanishes mid-walk). Also the node passed to
## JobDef.begin/complete for this leg.
var target_node: Node = null

## Opaque discriminator the JobDef's complete() switches on to run this leg's
## action (e.g. HaulingJobDef.FETCH vs DELIVER). Def-owned; 0 = unspecified.
var kind: int = 0
