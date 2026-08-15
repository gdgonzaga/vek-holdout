class_name SkillDefList
extends Resource
## The global skill catalog (data/skills/skills.tres): the 6 MVP skills, their
## Labor mappings, use-curves, and per-level multipliers (GDD §6.3). Loaded once
## and shared by every SkillSet component — per-entity state lives on SkillSet,
## never here.

@export var skills: Array[SkillDef] = []
