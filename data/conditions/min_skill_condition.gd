class_name MinSkillCondition
extends Condition

## Actor must have `skill_id` at level >= `min_level` (the regular-job L1 gate,
## or specialist gates post-MVP). Reads the actor's SkillSet component; an actor
## without one (a bare Node) fails closed — a gate that can't be evaluated
## shouldn't pass. The Player carries a SkillSet too (personal crafting).

@export var skill_id: String = ""
@export var min_level: int = 1

func is_met(actor: Node, _target: Node) -> bool:
    if skill_id == "" or actor == null:
        return false
    var skill_set = actor.get("skill_set")
    if skill_set == null or not skill_set is SkillSet:
        return false
    return skill_set.meets_requirement(skill_id, min_level)
