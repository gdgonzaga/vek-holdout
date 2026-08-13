extends Resource
class_name JobDef
## Reusable template for one kind of colonist work (ARCH "Subsystem: Colonists",
## GDD §6.10). One subclass per Labor; a Job instance carries a `def` back-ref
## (like Furniture.def) plus the per-placement binding (which blueprint, where).
##
## Unlike the pure-data defs in data/ (FurnitureDef, ItemDef, ...), a JobDef also
## carries the WORK behaviour: `begin` reports how many seconds the work takes
## (0 = instant) and `complete` fires when that elapses. This mirrors the
## behaviour-bearing Resource precedent (GameAction, Condition) — authored as a
## .tres via script_class, designers tune its fields, each Labor's subclass owns
## its execute logic. The work behaviour lives here rather than on the Furniture
## because it depends on Job parameters the Furniture doesn't know (e.g. a craft
## job's duration = recipe.base_time × quantity).
##
## ColonistAI drives the per-frame tick: on arrival it calls begin(), accumulates
## delta against the returned duration in its WORK state, then calls complete().

@export var id: String             # "construction" — identifies this job template.
@export var display_name: String   # "Construction" — Job Log / UI label.
@export var labor_id: String       # a LaborDef.id; gates get_best_job_for's filter.


## Setup + report the work duration in seconds. Called once when the colonist
## arrives at the job target and enters WORK. Return 0.0 for instant work — the
## AI calls complete() the same tick. Override per Labor. The base default is
## instant, which reproduces the pre-WORK "arrive → complete" behaviour.
func begin(_actor: Node, _target: Node) -> float:
	return 0.0


## Called when the duration returned by begin() has elapsed (or immediately when
## begin returned <= 0). Override per Labor to apply the work's effect. The base
## default is a no-op so a bare JobDef completes without doing anything.
func complete(_actor: Node, _target: Node) -> void:
	pass
