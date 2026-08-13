# Subsystem: Skills

Per-entity skill progression (L1–L5, use-based). Determines work-speed multiplier; gates regular jobs at L1. GDD §6.3. Lives on both Player and Colonists via a reusable `SkillSet` component. The Player screen's Skills *tab* is post-MVP (the data progresses in MVP; the UI to view it is deferred).

**Work-speed combination (locked):** effective work rate = `base_rate × skill_multiplier × stamina_multiplier`. `SkillSet.get_multiplier(labor)` returns the skill factor (1.0 at L1 → 2.0 at L5); `StaminaComponent.get_work_multiplier()` returns the Stamina factor (1.0 fresh → 0.6 at collapse). The Job Board / colonist AI multiplies them. See Flow Trace below.

## Files

| File | Type | Responsibility |
|---|---|---|
| `skill_set.gd` | Script (component) | Holds the 6 skills + their current level + progress for one entity. Owns use-based leveling (increments progress on successful completions; levels up at thresholds). Exposes `get_multiplier(labor)`. Does NOT own global skill definitions or curves (those are data). |
| `../data/skills/skills.tres` | Data | Global SkillDef list (6 skills) + use-curves + per-level multipliers. See [Data Schemas](data-schemas.md). |

*The component script lives in `subsystems/colonists/` — colocated with the Colonist entity it serves this sprint (the standalone `skills/` folder doesn't exist yet). It's consumed by Colonist + Player + UI, not combat-specific; see [Tech Debt & Unimplemented](tech-debt.md) on a possible future `core/components/` home.*

## Signals

All same-scene (No EventBus) — skills are per-entity, read locally.

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `skill_progressed(skill_id, progress)` | `skill_set.gd` | HUD (skill bar, future Skills tab) | No | Skill Gains Progress |
| `skill_leveled_up(skill_id, new_level)` | `skill_set.gd` | HUD (notification), Day Summary (skill gains) | No | Skill Levels Up |

## Flow Trace: Skill gains progress on a successful job completion

**Trigger:** A colonist (or player) successfully completes a skilled Job (craft/build/smelt/treat/repair) — fired by the Job Board or the labor AI on success.

1. Caller invokes `skill_set.record_use(skill_id)` on the entity.
2. `SkillSet` increments the skill's progress counter.
3. Emits `skill_progressed(skill_id, progress)` (for future Skills-tab UI).
4. If progress crosses the next level's threshold (from `skills.tres` use-curve): increment level, emit `skill_leveled_up(skill_id, new_level)`.
5. HUD shows a brief level-up notification; Day Summary logs the gain.

**End state:** Skill progress updated; level may have increased; work-speed multiplier for that Labor is now higher.

## Flow Trace: Work-speed multiplier resolves a Job tick

**Trigger:** A colonist is actively working a Job (per Job Board flow); each work tick applies progress.

1. Colonist AI reads `skill_set.get_multiplier(job.labor)` → returns skill factor (1.0–2.0 by level).
2. Colonist AI reads `stamina_component.get_work_multiplier()` → returns Stamina factor (1.0–0.6 by band).
3. Effective rate = `job.base_rate × skill_factor × stamina_factor`.
4. Applies that rate to the Job's progress (build HP, craft completion, etc.).
5. On Job completion → triggers `skill_set.record_use(skill_id)` (Flow Trace above).

**End state:** Job progresses at the combined skill × Stamina rate; completion grants skill progress.

## Class Reference

### Class: SkillSet

**Extends:** Node
**Script:** `skill_set.gd` (in `subsystems/colonists/`)
**Description:** Per-entity skill progression. Holds level + progress for each of the 6 skills. Use-based leveling on successful job completions. Exposes work-speed multiplier per Labor.
**Used by:** Colonist AI (work-speed calc), Player (same), Job Board (L1 gating check), HUD (future Skills tab + notifications), Day Summary (skill-gain log).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `skills` | `Dictionary[String, SkillState]` | Per-skill state. Keyed by skill_id (`"medical"`, `"mechanical"`, etc.). `SkillState = { level: int, progress: int }`. |
| `skill_defs` | `SkillDefList` | Loaded from `data/skills/skills.tres` (shared) — use-curves + multipliers. |

**Signals:**

| Signal | Description |
|---|---|
| `skill_progressed(skill_id: String, progress: int)` | For UI (future Skills tab). Emitted on every `record_use`. |
| `skill_leveled_up(skill_id: String, new_level: int)` | For UI notification + Day Summary log. Emitted on threshold cross. |

**Functions:**

| Function | Description |
|---|---|
| `record_use(skill_id: String) -> void` | Increments progress; levels up if threshold crossed. Called by Job Board / labor AI on successful job completion. |
| `get_level(skill_id: String) -> int` | Returns 1–5. |
| `get_multiplier(labor: String) -> float` | Returns the work-speed multiplier for a Labor (maps Labor → skill_id → level → multiplier from `skills.tres`). L1=1.0 → L5=2.0. |
| `meets_requirement(skill_id: String, min_level: int) -> bool` | Gates regular jobs at L1; specialist gates (post-MVP) at higher levels. |
