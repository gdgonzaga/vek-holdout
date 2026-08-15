class_name RecipeDef
extends Resource
## One craftable conversion (GDD §7.9): inputs → outputs over base_time at a
## crafting station. Pure data — the station owns "which recipes live here"
## (CraftingParams on the FurnitureDef), the CraftingJobDef owns the craft math.
## One unified shape for every output kind (furniture, armor, weapons, ammo,
## smelting) per the GDD's "no tech tree in MVP" note: the constraint is
## materials + station + skill gate.
##
## `conditions` are recipe-level actor gates (e.g. MinSkillCondition) evaluated
## HOT by CraftingJobDef.meets_requirements on every poll/claim — same contract
## as JobDef.conditions, never cached.

@export var id: String = ""            # "planks" — the queue/craft-job key.
@export var display_name: String = ""  # "Planks" — craft panel + log label.

## Materials consumed per craft (withdrawn from colony storage by hauling).
@export var inputs: Array[ItemAmount] = []

## Items produced per craft (deposited to the crafter, overflow to storage).
@export var outputs: Array[ItemAmount] = []

## Seconds of work at skill 1.0 — divided by the crafter's SkillSet multiplier
## for the def's labor (CraftingJobDef.begin, the ConstructionJobDef pattern).
@export var base_time: float = 1.0

## Actor gates for this recipe — evaluated by CraftingJobDef.meets_requirements
## (fresh each poll; see JobDef.conditions for the hot-condition contract).
@export var conditions: Array[Condition] = []


## UI/log label: display_name when authored, else the id.
func label() -> String:
	return display_name if display_name != "" else id
