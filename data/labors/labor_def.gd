extends Resource
class_name LaborDef
## A category of colonist work (ARCH "data/labors/", GDD §6 labor model).
##
## Labors are referenced elsewhere by their String `id` (e.g. a Colonist's
## `labor_priorities` Dict and a Job's `labor_id`), so these resources are the
## canonical declaration of which labor ids exist + their display names. They are
## inert data for now (no registry autoload); future skill gates / UI load them
## by path to resolve display metadata.

@export var id: String               # "construction" — the key everything else references.
@export var display_name: String     # "Construction" — shown in UI.
@export var description: String = "" # Short blurb, unused in MVP UI.
