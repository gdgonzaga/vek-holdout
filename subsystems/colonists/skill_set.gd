extends Node
class_name SkillSet
## Per-entity skill progression (GDD §6.3, ARCH "Subsystem: Skills"). Holds
## level + use-progress for each catalog skill for one entity (a Colonist
## or the Player — its SkillSet is code-created in Player._ready, unseeded).
## Use-based leveling: record_use on successful
## completions, level-ups when cumulative uses cross the skill's use_curve.
##
## Work speed: get_multiplier(labor_id) maps Labor → governing skill → level →
## multiplier (L1 = 1.0 … L5 = 2.0, from skills.tres). JobDefs divide their
## begin() duration by it — the documented effective-rate seam
## (base_rate × skill × stamina; StaminaComponent is still a stub). Unskilled
## labors (hauling — no skill maps to it) work at 1.0.
##
## Global definitions (curves, multipliers, labor mapping) are shared data in
## data/skills/skills.tres — never duplicated here; this node owns only the
## per-entity state.

signal skill_progressed(skill_id: String, progress: int)
signal skill_leveled_up(skill_id: String, new_level: int)

## Shared catalog: the 6 skills + their Labor mappings + curves + multipliers.
var skill_defs: SkillDefList = preload("res://data/skills/skills.tres")

## Per-skill state: { skill_id (String): { "level": int, "progress": int } }.
## Entries appear on seed() (from ColonistDef.starting_skills) or the first
## record_use; a skill with no entry reads as L1/0.
var skills: Dictionary = {}

# labor_id (String) -> skill_id (String), built from skill_defs in _ready. One
# skill per skilled labor (construction/crafting/mechanics/mining/harvesting-
# adjacent today); labors with no governing skill (hauling) are absent and read
# as multiplier 1.0.
var _labor_to_skill: Dictionary = {}


func _ready() -> void:
	for def in skill_defs.skills:
		if def.labor != "":
			_labor_to_skill[def.labor] = def.skill_id


## Seed state from a ColonistDef.starting_skills dict ({skill_id: {xp, level}}).
## Unknown skill_ids (e.g. "tree_chopping" — a design leftover) are ignored so
## state always matches the catalog. Runs after _ready in the Colonist scene
## (children ready first), so the labor map exists; ordering doesn't otherwise
## matter. (The default def's "mining" entry became live when mining entered
## the catalog — it seeds L1/0, the neutral baseline.)
func seed(starting_skills: Dictionary) -> void:
	for skill_id in starting_skills:
		if _def_for(skill_id) == null:
			continue
		var entry: Dictionary = starting_skills[skill_id]
		skills[skill_id] = {
			"level": clampi(int(entry.get("level", 1)), 1, 5),
			"progress": maxi(int(entry.get("xp", 0)), 0),
		}


## Count one successful use of `skill_id`: bump progress, emit skill_progressed,
## and level up (with skill_leveled_up) while cumulative uses cross the next
## rung of the skill's use_curve. Unknown skill_ids are ignored — progression
## only happens for catalog skills.
func record_use(skill_id: String) -> void:
	var def := _def_for(skill_id)
	if def == null:
		return
	if not skills.has(skill_id):
		skills[skill_id] = {"level": 1, "progress": 0}
	var state: Dictionary = skills[skill_id]
	state["progress"] = int(state["progress"]) + 1
	skill_progressed.emit(skill_id, int(state["progress"]))
	# use_curve is cumulative uses-to-reach: L1→L2 at use_curve[0], L4→L5 at
	# use_curve[3]. Loop so a long-idle skill crossing several rungs at once
	# (not possible via record_use, possible via deserialize) still settles.
	while int(state["level"]) < 5 and int(state["level"]) - 1 < def.use_curve.size() \
			and int(state["progress"]) >= def.use_curve[int(state["level"]) - 1]:
		state["level"] = int(state["level"]) + 1
		skill_leveled_up.emit(skill_id, int(state["level"]))


## Current level of `skill_id` (1–5). Unknown/unused skills read as L1.
func get_level(skill_id: String) -> int:
	if not skills.has(skill_id):
		return 1
	return int(skills[skill_id]["level"])


## Work-speed multiplier for a Labor (L1 = 1.0 → L5 = 2.0). Labors with no
## governing skill (hauling) return 1.0 — the unskilled baseline.
func get_multiplier(labor_id: String) -> float:
	var def := _def_for(_labor_to_skill.get(labor_id, ""))
	if def == null:
		return 1.0
	return def.multipliers[clampi(get_level(def.skill_id), 1, 5) - 1]


## True if `skill_id` is at least `min_level`. The regular-job L1 gate
## (a skill with no state entry is L1, so min_level 1 passes by default).
func meets_requirement(skill_id: String, min_level: int) -> bool:
	return get_level(skill_id) >= min_level


## Count one successful use of the skill governing `labor_id`. Returns false
## (and grants nothing) when no skill maps to that labor — e.g. hauling. The
## single XP entry point for ColonistAI's job loop.
func record_use_for_labor(labor_id: String) -> bool:
	var skill_id: String = _labor_to_skill.get(labor_id, "")
	if skill_id == "":
		return false
	record_use(skill_id)
	return true


func _def_for(skill_id: String) -> SkillDef:
	for def in skill_defs.skills:
		if def.skill_id == skill_id:
			return def
	return null


# --- SaveSystem contract ------------------------------------------------------
# Only the per-entity state dict round-trips; skill_defs is shared static data
# re-resolved from skills.tres.

func serialize() -> Dictionary:
	return {"skills": skills.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	var saved: Dictionary = data.get("skills", {})
	skills.clear()
	for skill_id in saved:
		skills[skill_id] = {
			"level": clampi(int(saved[skill_id].get("level", 1)), 1, 5),
			"progress": maxi(int(saved[skill_id].get("progress", 0)), 0),
		}
