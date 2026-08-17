# Subsystem: Skills

Per-entity skill progression (L1–L5, use-based). Determines work-speed multiplier; gates regular jobs at L1. GDD §6.3. Lives on Colonists AND the Player as a `SkillSet` component (the Player's is code-created in `Player._ready`, unseeded — personal crafting consumes and trains it; see [Crafting](crafting.md)). The Player screen's Skills *tab* is post-MVP (the data progresses now; the UI to view it is deferred).

**Work-speed combination:** effective work rate = `base_rate × skill_multiplier × stamina_multiplier`. `SkillSet.get_multiplier(labor)` returns the skill factor (1.0 at L1 → 2.0 at L5); `StaminaComponent.get_work_multiplier()` returns the Stamina factor (**still a stub** — the stamina half of the formula is deferred). JobDefs divide their `begin()` duration by the skill factor (construction, crafting, harvest, and the farming defs today; see [Jobs](jobs.md)). See Flow Trace below.

## Files

| File | Type | Responsibility |
|---|---|---|
| `subsystems/colonists/skill_set.gd` | Script (component) | Holds the 7 skills' level + progress for one entity. Owns use-based leveling (increments progress on successful completions; levels up at cumulative-use thresholds). Exposes `get_multiplier(labor)`. Does NOT own global skill definitions or curves (those are data). |
| `../data/skills/skills.tres` | Data | Global SkillDefList: the 7 skills (construction, crafting, mechanical, medical, combat, farming, tree_chopping) + use-curves + per-level multipliers + Labor mappings. See [Data Schemas](data-schemas.md). |
| `../data/skills/skill_def.gd` / `skill_def_list.gd` | Script (Resource) | The SkillDef / SkillDefList shapes authored by `skills.tres`. |

*The component script lives in `subsystems/colonists/` — colocated with the Colonist entity it serves (the standalone `skills/` folder doesn't exist). It's consumed by Colonist + ColonistAI + job defs, not combat-specific; see [Tech Debt & Unimplemented](tech-debt.md) on a possible future `core/components/` home.*

## Signals

All same-scene (No EventBus) — skills are per-entity, read locally. No listeners yet (the Skills-tab HUD is post-MVP); `Colonist.serialize` persists the state dict directly.

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `skill_progressed(skill_id, progress)` | `skill_set.gd` | HUD (skill bar, future Skills tab) | No | Skill Gains Progress |
| `skill_leveled_up(skill_id, new_level)` | `skill_set.gd` | HUD (notification), Day Summary (skill gains) | No | Skill Levels Up |

## Flow Trace: Skill gains progress on a successful job completion

**Trigger:** A colonist successfully completes a skilled Job — `ColonistAI._end_job(true)`.

1. ColonistAI calls `skill_set.record_use_for_labor(job.labor_id)` — the single XP entry point.
2. `SkillSet` maps the Labor to its governing skill via `skills.tres` (construction, crafting, mechanics, and farming are mapped; labors with no skill — hauling, harvesting today — grant nothing and return false; `tree_chopping` has no labor).
3. `SkillSet` increments the skill's cumulative use count.
4. Emits `skill_progressed(skill_id, progress)` (for the future Skills-tab UI).
5. If uses cross the next level's `use_curve` threshold: increment level, emit `skill_leveled_up(skill_id, new_level)`.

**End state:** Skill progress updated; level may have increased; work-speed multiplier for that Labor is now higher.

## Flow Trace: Work-speed multiplier resolves a Job's duration

**Trigger:** A colonist arrives at a timed WORK leg (`ColonistAI._begin_work`).

1. The JobDef's `begin()` computes `base_duration / skill_set.get_multiplier(labor_id)` — construction: `BuildableDef.build_time ÷ multiplier`, crafting: `recipe.base_time ÷ multiplier`, harvest/farming: the def's work time ÷ multiplier.
2. `get_multiplier` maps Labor → governing skill → level → `multipliers[level-1]` from `skills.tres` (L1 = 1.0 → L5 = 2.0). Unskilled labors (hauling) read 1.0.
3. The returned duration drives the WORK tick in ColonistAI. (The Stamina factor would multiply here too once `StaminaComponent.get_work_multiplier()` exists.)

**End state:** Skilled colonists finish timed legs proportionally faster; completion grants skill progress (Flow Trace above).

## Class Reference

### Class: SkillSet

**Extends:** Node
**Script:** `subsystems/colonists/skill_set.gd` (child of the Colonist scene)
**Description:** Per-entity skill progression. Holds level + cumulative use-count for each of the 7 skills. Use-based leveling on successful job completions. Exposes the work-speed multiplier per Labor.
**Used by:** Colonist (`_ready` seeds from `colonist_def.starting_skills`; `serialize` round-trips), ColonistAI (`record_use_for_labor` on job success), the construction/crafting/harvest/farming JobDefs (`get_multiplier` in `begin`), `MinSkillCondition` (`meets_requirement`).
**Lifecycle:** `_ready` builds the labor→skill map from the shared `skills.tres`. `Colonist._ready` (parent, runs after children) then calls `seed(colonist_def.starting_skills)` — unknown ids (the default def's `mining`) are ignored so state always matches the catalog.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `skill_defs` | `SkillDefList` | Preloaded from `data/skills/skills.tres` (shared by every SkillSet) — curves, multipliers, labor mapping. |
| `skills` | `Dictionary` | Per-skill state, keyed by skill_id: `{ "level": int (1–5), "progress": int (cumulative uses) }`. Entries appear on `seed` or first `record_use`; a missing entry reads as L1/0. |

**Signals:**

| Signal | Description |
|---|---|
| `skill_progressed(skill_id: String, progress: int)` | Emitted on every `record_use`. |
| `skill_leveled_up(skill_id: String, new_level: int)` | Emitted on each threshold cross. |

**Functions:**

| Function | Description |
|---|---|
| `seed(starting_skills: Dictionary) -> void` | Merge a `ColonistDef.starting_skills` dict (`{skill_id: {xp, level}}`); unknown skill_ids skipped, levels clamped 1–5. |
| `record_use(skill_id: String) -> void` | Increments cumulative uses; levels up while uses cross the next `use_curve` rung. Unknown skill_ids are ignored. |
| `record_use_for_labor(labor_id: String) -> bool` | `record_use` on the skill governing that Labor; false (no XP) when the Labor maps to no skill. ColonistAI's entry point. |
| `get_level(skill_id: String) -> int` | Returns 1–5 (missing entry = 1). |
| `get_multiplier(labor: String) -> float` | Labor → skill → level → `multipliers` entry (L1 = 1.0 → L5 = 2.0). Unmapped Labor = 1.0. |
| `meets_requirement(skill_id: String, min_level: int) -> bool` | `get_level >= min_level` — the regular-job L1 gate; specialist gates (post-MVP) at higher levels. |
| `serialize() / deserialize(data)` | Round-trip the state dict (skill_defs is shared static data, re-resolved from `skills.tres`). |

### Class: SkillDef / SkillDefList

See [Data Schemas](data-schemas.md) — the `data/skills/skills.tres` schema.
