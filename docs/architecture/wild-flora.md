# Subsystem: Wild Flora

The **Wild Flora** subsystem governs naturally occurring non-domestic vegetation across the world: harvestable timber trees, perennial berry and fruit bushes, wild forageable root crops, and ambient foliage. Unlike domestic crops ([Farming](farming.md)) which require dedicated farm plots, soil hydration, and colonist tending, wild flora grows autonomously in nature, supports physical tool damage scaling (e.g. axe effectiveness vs timber), and integrates with the `FurnitureLayer` for spatial tracking, multi-stage visual growth, felling, and perennial fruit harvesting.

Authoring guide for creating new trees and plants: [`docs/HOWTO-author-wild-flora.md`](../HOWTO-author-wild-flora.md).

**Design notes:**
- **`Furniture` Specialization**: `WildFlora` extends `Furniture` directly, inheriting world-grid cell anchoring on `FurnitureLayer`, bounding box collision, and SaveSystem dictionary persistence, without inheriting domestic furniture action chains.
- **Independent Life-cycle**: Wild flora simulation advances via real-time frame deltas scaled to in-game hours (`TimeSystem`), independent of colonist labor or watering.
- **Progressive Stage Synchronization**: Growth progress (0.0 to 1.0) maps dynamically to `WildFloraStage` definitions, scaling HP, updating 3D visual scene instances, and toggling interaction capabilities.
- **Physical Damage & Tool Effectiveness**: Damage resolution routes through `HealthComponent`. Tool and weapon tags modulate damage dealt to solid timber (axes deal 100%, swords 25%, pickaxes 15%, bare hands 20%).
- **Colonist Chop/Removal Job**: A `Harvestable` capability component is attached to every `WildFlora` instance (mirroring domestic furniture harvesting, [Jobs & Fractional Work System](job-extensions.md#harvesting-furniture-nodes-marking-and-manual-chop)). Marking (via the area-designation tool below, or programmatically) registers a `harvest`/`chop` `JobDef` on the colony job board — `chop.tres` (requires `WildFloraDef.required_tool_tag`, e.g. an axe for timber) or `harvest.tres` (no tool, for plant removal), chosen per-def. Completion deals a direct lethal `HealthComponent` hit, reusing the real-time felling pipeline below unchanged.

## Files

| File | Type | Responsibility |
|---|---|---|
| `data/furniture/wild_flora_def.gd` | Script (Resource) | Data schema for `WildFloraDef` (growth timing, collision policy, stage list, regrowth configuration). |
| `data/capability_params/wild_flora_stage.gd` | Script (Resource) | Data schema for `WildFloraStage` (HP thresholds, stage visual scenes/scale, fell yields, harvest yields). |
| `data/actions/forage_action.gd` | Script | Player context action for foraging ripe fruit via the E menu. |
| `data/furniture/tree1.tres` | Data | Mature harvestable timber tree definition (`required_tool_tag = "axe"`). |
| `data/furniture/apple.tres` | Data | Fruit-bearing timber tree — both choppable (`required_tool_tag = "axe"`) and forageable. |
| `data/furniture/wild_berry_bush.tres` | Data | Perennial fruit bush definition with multi-stage growth and regrowth (no tool required to remove). |
| `subsystems/harvesting/harvestable.gd` | Script | Capability component (shared with domestic furniture harvesting) tracking the harvest mark and driving `HarvestJobDef`; its `WildFlora` branch resolves work time from `chop_work_time` and fells via a direct `HealthComponent` hit on completion. |
| `data/jobs/chop.tres` / `data/jobs/harvest.tres` | Data | `HarvestJobDef` instances on the `harvesting` labor — `chop.tres` requires an equipped `axe` tag, `harvest.tres` requires no tool. `Colony._harvest_job_def_for` picks between them per `WildFloraDef.required_tool_tag`. |
| `subsystems/harvesting/harvest_box_controller.gd` | Script | Player area-designation tool (key **T**): raycasts the ground, resizes a flat footprint with the scroll wheel, and marks/unmarks every `WildFlora` in it via `FurnitureLayer.get_wild_flora_in_box` + `Harvestable.set_marked`. |
| `subsystems/environment/wild_flora.gd` | Script | Runtime node managing growth progress, dynamic stage visual instantiation, tool damage scaling, felling, and the `IStatProvider` implementation feeding its moodlets. |
| `subsystems/environment/wild_flora_moodlet_visualizer.gd` | Script | In-world 3D billboard visualizer displaying active moodlet icons above a `WildFlora` entity. |
| `subsystems/environment/plant_spawner.gd` | Script | Map initialization node scattering wild flora across smooth terrain via Poisson-disc sampling. |
| `subsystems/environment/new_wild_flora_template.tscn` | Scene | Base scene template for wild flora visual instances (mounts `WildFloraMoodletVisualizer`). |
| `subsystems/map_authoring/tree_scatterer.gd` | Script | Editor utility for procedural tree scattering across map terrain. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `harvest_box_toggled(active)` | `Player` | `HarvestBoxController`, HUD | Yes | Area designation toggle (**T**) |
| `furniture_removed(def_id, anchor)` | `FurnitureLayer` / `WildFlora` | BuildController, Map, Colony | Yes | Felling / Uprooting |

*(Wild flora instances communicate primarily via `HealthComponent` signals (`damaged`, `entity_died`) and direct `FurnitureLayer` queries.)*

## Flow Trace: Real-Time Chopping and Felling

**Trigger:** Player swings a weapon/axe at a wild tree, or a colonist/enemy attacks the tree entity.

1. **Hit Detection & Routing**: Weapon raycast or melee sweep strikes the tree's `Layer 5` (Interactable) collider, calling `WildFlora.take_damage(raw_amount, source)`.
2. **Damage Scaling**: `_calculate_effective_damage()` checks source equipment tags. If the target has `"tree"` or `"timber"` tags:
   - Axes (`"axe"`, `"tool_axe"`) deal full `100%` damage.
   - Swords/Blades deal `25%` damage.
   - Pickaxes deal `15%` damage.
   - Unarmed / bare hands deal `20%` damage.
3. **Particle & Audio Feedback**: `_spawn_splinter_particles()` emits directional wood/leaf particles at the hit coordinate with `hit_particles_color`.
4. **Durability Reduction**: `HealthComponent.take_damage()` reduces current HP.
5. **Felling & Removal**: When HP reaches `0`, `HealthComponent.entity_died` fires:
   - `_on_felled()` queries the active `WildFloraStage.fell_yields` (and ripe `harvest_yields` if fruiting).
   - `WorldItem.spawn_at()` instantiates physical item drops at the entity origin.
   - `FurnitureLayer.remove_at(anchor)` unregisters the cell and frees the node.

**End state:** The tree is removed from the world grid and physical item drops land on the ground.

## Flow Trace: Perennial Fruit Foraging & Regrowth

**Trigger:** Player approaches a ripe bush and presses **E** -> **Forage** (or triggers LMB foraging).

1. **Readiness Check**: `ForageAction` checks `WildFlora.can_forage()`, confirming `stage.can_harvest_fruit == true` and `harvest_yields` is non-empty.
2. **Harvest Spawning**: `WildFlora.forage(actor)` spawns `harvest_yields` items into the world via `WorldItem.spawn_at()`.
3. **Lifecycle Branching**:
   - **Single-Harvest (e.g. wild carrot)**: If `destroy_on_fruit_harvest == true`, `_destroy_flora()` removes the plant.
   - **Perennial Bush (e.g. berry bush, apple tree)**: If `destroy_on_fruit_harvest == false`, growth progress resets to `regrowth_stage_index` (e.g. stage 1 mature unfruited).
4. **Visual Re-synchronization**: `_sync_to_current_stage()` swaps or scales the visual scene back to the defruited stage and resets the interaction state.

**End state:** Fruit items are dropped, the bush remains alive in the defruited state, and growth simulation resumes toward the next harvest.

## Flow Trace: Colonist Chop/Removal Job

**Trigger:** Player designates an area with `HarvestBoxController` (key **T**), or marks a single flora's `Harvestable` directly.

1. **Area Designation**: LMB raycasts the ground to a cell, sizes a flat width x depth footprint (scroll wheel; Shift+scroll for depth) around it, and calls `FurnitureLayer.get_wild_flora_in_box` for every `WildFlora` whose footprint falls inside. Each result's `Harvestable.set_marked(true)` fires `EventBus.harvest_mark_toggled`, the same signal single-tree E-menu marking uses. RMB un-marks the footprint instead.
2. **Job Routing**: `Colony._on_harvest_mark_toggled` -> `_spawn_harvest_job` -> `_harvest_job_def_for` picks `chop.tres` when the flora's `WildFloraDef.required_tool_tag` is set (e.g. `"axe"` for timber), else `harvest.tres` (no tool — plant removal). Both are `HarvestJobDef` on the `harvesting` labor; only the tool requirement and job `id` differ.
3. **Claim & Work**: `BTActionClaimJob` claims the job (equipping the required tool first, if any); `begin()` reads `Harvestable.effective_work_time()`, which for a `WildFlora` target returns `WildFloraDef.chop_work_time` (skill-scaled like any other harvest job). `is_available`/`should_close` additionally gate on `Harvestable.is_claimable()`, which requires the flora's *current* growth stage to have `can_chop == true` — a stage change after marking (e.g. growing into/out of a non-choppable stage) self-closes the job instead of a claim silently no-oping.
4. **Completion**: `HarvestJobDef.complete()` -> `Harvestable.complete()`'s `WildFlora` branch deals a direct lethal hit to `health_component` (bypassing the real-time weapon-tag damage scaling in `_calculate_effective_damage` — the job's own duration and tool-gate already model effort/equipment), reusing the `entity_died` -> `_on_felled()` pipeline from the real-time chopping flow above unchanged: stage `fell_yields` (+ ripe `harvest_yields` if fruiting) spawn as world items and the node is removed via `FurnitureLayer`.

**End state:** Same as real-time felling — the flora is removed and its stage-authored yields land on the ground — but driven by the colonist job system instead of a weapon swing.

## Moodlet System

`WildFlora` implements `IStatProvider` (`subsystems/core/i_stat_provider.gd` — see [Colonists](colonists.md) "Moodlet System" for the full contract), so trees and plants can display the same kind of status billboard colonists and enemies do:

- **`get_stat_ratio`/`get_stat_value`**: `&"hp"`/`&"health"` reads the entity's own `HealthComponent`; `&"work_progress"` delegates to the sibling `Harvestable` capability component (`Harvestable.get_stat_ratio`/`get_stat_value`) rather than duplicating its ratio math — `Harvestable` is the single source of truth, `WildFlora` is the only call surface the moodlet pipeline actually reaches (`MoodletDef.evaluate_icon_index` is always called with the entity node, never a child component).
- **`get_current_activity`** (repurposed as interaction state): a priority chain, first match wins — `&"marked_for_harvest"` (`Harvestable.is_marked_for_harvest()` — set by the area-designation tool or a single-tree toggle, see "Flow Trace: Colonist Chop/Removal Job" above), `&"forageable"` (`can_forage()`), `&"depleted"` (sitting at the def's `regrowth_stage_index` stage and not currently ripe — covers both "just picked, regrowing" and a young plant naturally passing through its mature-unfruited stage), `&"choppable"` (`WildFlora.can_be_felled()` — the current `WildFloraStage.can_chop` flag and not dead; the parallel eligibility check to `can_forage()`'s `can_harvest_fruit`, independent of the `"tree"`/`"timber"`/`"wood"` tags which only drive `_calculate_effective_damage`'s axe-vs-bare-hands scaling), else `&""`.
- **`WildFloraDef.moodlet_defs`**: per-def list of `MoodletDef` resources, same shape and authoring pattern as `ColonistDef.moodlet_defs`. Shipped content (`flora_hp_moodlet.tres`, `flora_interaction_moodlet.tres` in `data/moodlets/`) ships with empty icon arrays pending art — the code/data pipeline is wired end-to-end, icon textures are a separate follow-up.
- **`WildFloraMoodletVisualizer`**: structurally identical to `ColonistMoodletVisualizer`/`EnemyMoodletVisualizer`, delegating row grouping/capping to the shared `MoodletLayoutResolver`. Declared in `new_wild_flora_template.tscn`; `WildFlora._setup_moodlet_visualizer()` self-heals a missing node for any future alternate template.

## Class Reference

### Class: `WildFloraDef`

**Extends:** `BuildableDef`  
**Script:** `data/furniture/wild_flora_def.gd`  
**Description:** Definition resource specifying growth duration, physical movement blocking, stage configurations, and fruit harvest behavior.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `dimensions` | `Vector3i` | Grid footprint occupied on `FurnitureLayer` (default `1x1x1`). |
| `default_scene` | `PackedScene` | Default 3D visual scene fallback across stages. |
| `blocks_movement` | `bool` | `true` for solid tree trunks (Layer 1 physics collider); `false` for pass-through bushes and shrubs. |
| `growth_time_hours` | `float` | In-game hours to grow from 0.0 to 1.0 (0.0 = static). |
| `destroy_on_fruit_harvest` | `bool` | If `true`, harvesting fruit destroys the plant. |
| `regrowth_stage_index` | `int` | Stage index to revert to upon harvesting fruit. |
| `initial_growth_min` | `float` | Minimum randomized starting growth progress (0.0 to 1.0). |
| `initial_growth_max` | `float` | Maximum randomized starting growth progress (0.0 to 1.0). |
| `impact_audio_event` | `String` | Audio event string on weapon impact. |
| `hit_particles_color` | `Color` | Color of particle burst on weapon strike. |
| `required_tool_tag` | `String` | Equipped item tag a colonist must hold to claim the chop/removal job (e.g. `"axe"`); empty = no tool required, plain plant removal. Routes the marked job to `chop.tres` vs `harvest.tres` (see "Flow Trace: Colonist Chop/Removal Job"). |
| `chop_work_time` | `float` | Unskilled seconds of colonist work to fell/remove via the harvest labor job, mirroring `HarvestParams.work_time`. |
| `stages` | `Array[WildFloraStage]` | Ordered growth milestones and per-stage configurations. |
| `moodlet_defs` | `Array[MoodletDef]` | Configured status/interaction moodlets to evaluate and display, in order (see "Moodlet System" above). |

**Functions:**

| Function | Description |
|---|---|
| `get_effective_stages() -> Array[WildFloraStage]` | Returns authored stages or synthesizes a default mature stage if empty. |
| `get_stage_for_progress(progress: float) -> WildFloraStage` | Resolves the active `WildFloraStage` for a given growth value (0.0 to 1.0). |
| `get_stage_index_for_progress(progress: float) -> int` | Resolves the active stage index for a given growth value. |

---

### Class: `WildFlora`

**Extends:** `Furniture`  
**Script:** `subsystems/environment/wild_flora.gd`  
**Description:** Runtime entity representing a live tree, bush, or harvestable wild plant in the world.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `growth_progress` | `float` | Current growth progress (0.0 to 1.0), persisted in state dictionary. |
| `health_component` | `HealthComponent` | Manages entity durability, damage signals, and felling. |

**Functions:**

| Function | Description |
|---|---|
| `set_growth_progress(val: float) -> void` | Sets growth progress and triggers visual/HP stage synchronization if threshold crossed. |
| `can_forage() -> bool` | Returns whether the active stage has ripe fruit available for harvest. |
| `forage(actor: Node) -> bool` | Gathers ripe fruit, drops items, and resets progress to `regrowth_stage_index`. |
| `can_be_felled() -> bool` | Returns whether the current growth stage allows felling/removal (`WildFloraStage.can_chop`) and the plant isn't already dead — gates both real-time `take_damage` and the colonist chop/removal job uniformly. |
| `take_damage(raw_amount: int, source: Node = null) -> void` | No-ops if `can_be_felled()` is false; otherwise applies tool-scaled damage to the plant's `HealthComponent`. |
| `get_current_stage() -> WildFloraStage` | Returns the currently active growth stage definition. |
| `get_stat_ratio(stat_name: StringName) -> float` | `IStatProvider`: normalized ratio for `&"hp"`/`&"health"` or delegated `&"work_progress"`, else -1.0. |
| `get_stat_value(stat_name: StringName) -> float` | `IStatProvider`: raw value for `&"hp"`/`&"health"` or delegated `&"work_progress"`, else -1.0. |
| `get_current_activity() -> StringName` | `IStatProvider`: current interaction-state identifier (see "Moodlet System" above). |
| `get_active_moodlets() -> Array[Dictionary]` | Evaluates `moodlet_defs` via `MoodletLayoutResolver`, returning the active, texture-bearing list. |
