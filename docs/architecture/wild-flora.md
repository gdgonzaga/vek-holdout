# Subsystem: Wild Flora

The **Wild Flora** subsystem governs naturally occurring non-domestic vegetation across the world: harvestable timber trees, perennial berry and fruit bushes, wild forageable root crops, and ambient foliage. Unlike domestic crops ([Farming](farming.md)) which require dedicated farm plots, soil hydration, and colonist tending, wild flora grows autonomously in nature, supports physical tool damage scaling (e.g. axe effectiveness vs timber), and integrates with the `FurnitureLayer` for spatial tracking, multi-stage visual growth, felling, and perennial fruit harvesting.

Authoring guide for creating new trees and plants: [`docs/HOWTO-author-wild-flora.md`](../HOWTO-author-wild-flora.md).

**Design notes:**
- **`Furniture` Specialization**: `WildFlora` extends `Furniture` directly, inheriting world-grid cell anchoring on `FurnitureLayer`, bounding box collision, and SaveSystem dictionary persistence, without inheriting domestic furniture action chains.
- **Independent Life-cycle**: Wild flora simulation advances via real-time frame deltas scaled to in-game hours (`TimeSystem`), independent of colonist labor or watering.
- **Progressive Stage Synchronization**: Growth progress (0.0 to 1.0) maps dynamically to `WildFloraStage` definitions, scaling HP, updating 3D visual scene instances, and toggling interaction capabilities.
- **Physical Damage & Tool Effectiveness**: Damage resolution routes through `HealthComponent`. Tool and weapon tags modulate damage dealt to solid timber (axes deal 100%, swords 25%, pickaxes 15%, bare hands 20%).

## Files

| File | Type | Responsibility |
|---|---|---|
| `data/furniture/wild_flora_def.gd` | Script (Resource) | Data schema for `WildFloraDef` (growth timing, collision policy, stage list, regrowth configuration). |
| `data/capability_params/wild_flora_stage.gd` | Script (Resource) | Data schema for `WildFloraStage` (HP thresholds, stage visual scenes/scale, fell yields, harvest yields). |
| `data/actions/forage_action.gd` | Script | Player context action for foraging ripe fruit via the E menu. |
| `data/furniture/tree1.tres` | Data | Mature harvestable timber tree definition. |
| `data/furniture/wild_berry_bush.tres` | Data | Perennial fruit bush definition with multi-stage growth and regrowth. |
| `subsystems/environment/wild_flora.gd` | Script | Runtime node managing growth progress, dynamic stage visual instantiation, tool damage scaling, felling, and the `IStatProvider` implementation feeding its moodlets. |
| `subsystems/environment/wild_flora_moodlet_visualizer.gd` | Script | In-world 3D billboard visualizer displaying active moodlet icons above a `WildFlora` entity. |
| `subsystems/environment/plant_spawner.gd` | Script | Map initialization node scattering wild flora across smooth terrain via Poisson-disc sampling. |
| `subsystems/environment/new_wild_flora_template.tscn` | Scene | Base scene template for wild flora visual instances (mounts `WildFloraMoodletVisualizer`). |
| `subsystems/map_authoring/tree_scatterer.gd` | Script | Editor utility for procedural tree scattering across map terrain. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
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

## Moodlet System

`WildFlora` implements `IStatProvider` (`subsystems/core/i_stat_provider.gd` — see [Colonists](colonists.md) "Moodlet System" for the full contract), so trees and plants can display the same kind of status billboard colonists and enemies do:

- **`get_stat_ratio`/`get_stat_value`**: `&"hp"`/`&"health"` reads the entity's own `HealthComponent`; `&"work_progress"` delegates to the sibling `Harvestable` capability component (`Harvestable.get_stat_ratio`/`get_stat_value`) rather than duplicating its ratio math — `Harvestable` is the single source of truth, `WildFlora` is the only call surface the moodlet pipeline actually reaches (`MoodletDef.evaluate_icon_index` is always called with the entity node, never a child component).
- **`get_current_activity`** (repurposed as interaction state): a priority chain, first match wins — `&"marked_for_harvest"` (currently inert; nothing can toggle a `WildFlora`'s harvest mark today since no tree content sets `harvest_params` — forward-looking scaffolding for the job-based chop flow `job-extensions.md` describes as not yet wired), `&"forageable"` (`can_forage()`), `&"depleted"` (sitting at the def's `regrowth_stage_index` stage and not currently ripe — covers both "just picked, regrowing" and a young plant naturally passing through its mature-unfruited stage), `&"choppable"` (tagged `"tree"`/`"timber"`/`"wood"` and not dead), else `&""`.
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
| `take_damage(raw_amount: int, source: Node = null) -> void` | Applies tool-scaled damage to the plant's `HealthComponent`. |
| `get_current_stage() -> WildFloraStage` | Returns the currently active growth stage definition. |
| `get_stat_ratio(stat_name: StringName) -> float` | `IStatProvider`: normalized ratio for `&"hp"`/`&"health"` or delegated `&"work_progress"`, else -1.0. |
| `get_stat_value(stat_name: StringName) -> float` | `IStatProvider`: raw value for `&"hp"`/`&"health"` or delegated `&"work_progress"`, else -1.0. |
| `get_current_activity() -> StringName` | `IStatProvider`: current interaction-state identifier (see "Moodlet System" above). |
| `get_active_moodlets() -> Array[Dictionary]` | Evaluates `moodlet_defs` via `MoodletLayoutResolver`, returning the active, texture-bearing list. |
