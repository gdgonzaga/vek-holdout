class_name SkillDef
extends Resource
## One skill's global definition (GDD §6.3, ARCH "data/skills/"). Pure data —
## leveling math lives on SkillSet, which reads these per entity. Authored as
## sub-resources of data/skills/skills.tres.

@export var skill_id: String = ""          # "construction" — the key SkillSet state uses.
@export var display_name: String = ""      # UI label.
## The LaborDef.id this skill governs (e.g. "construction"). 1:1 — one skill per
## skilled labor; "" for skills with no labor yet (medical/combat are action-
## based; farming gets its labor with the farming jobs).
@export var labor: String = ""
## Work-speed multiplier per level, index 0–4 = L1–L5. L1 = 1.0 (unskilled
## baseline); L5 = 2.0 (master). JobDefs divide their begin() duration by this.
@export var multipliers: Array[float] = [1.0, 1.2, 1.4, 1.7, 2.0]
## Cumulative successful uses required to REACH each level, index 0–3 = L2–L5.
## Progress counts total uses and never resets; level = the highest rung crossed.
@export var use_curve: Array[int] = [20, 50, 100, 200]
