# Subsystem: Farming

The **Farming** subsystem governs the full crop life-cycle: farm plot furniture placement, seed sowing, hydration decay and watering, milestone & decay tending, early harvesting via progressive yield tiers, automated job dispatch (`Sow`, `Water`, `Tend`, and `Harvest`), and context-sensitive player LMB interaction.

## Core Concepts

- **Farm Plots as Furniture**: Farm plots (e.g. `Growing Trough`) are authored as `FurnitureDef` resources carrying a `FarmPlotParams` sub-resource.
- **Component Pairing**: Placed farm plots attach both `Growable` and `Harvestable` components. `Growable` manages time-based simulation (hydration, tending, growth stages), while `Harvestable` provides unified interaction with the colony's `JobBoard` and player harvesting.
- **Dynamic Yields & Early Harvesting**: Crops define `CropYieldTier`s. When harvested (early by player command or automatically at 100% maturity), yields are scaled based on achieved milestones and any neglect penalties.
- **Context-Sensitive LMB Interaction**: Pointing at a farm plot and holding LMB automatically resolves the required action (Plant -> Tend -> Water -> Harvest).

## Architecture & Layout

| File | Type | Purpose |
|---|---|---|
| `data/crops/crop_def.gd` | Script | Schema for `CropDef` resources. |
| `data/crops/crop_yield_tier.gd` | Script | Schema for `CropYieldTier` milestone yields. |
| `data/crops/*.tres` | Data | Crop definitions (`cave_spud`, `holdout_wheat`, `bio_gel_orchid`). |
| `data/capability_params/farm_plot_params.gd` | Script | Sub-resource on `FurnitureDef` defining allowed crops. |
| `data/labors/farming.tres` | Data | Farming labor definition (`id = "farming"`). |
| `data/jobs/sow_job_def.gd` / `sow.tres` | Script/Data | Sowing job for empty farm plots. |
| `data/jobs/water_job_def.gd` / `water.tres` | Script/Data | Watering job for thirsty crops. |
| `data/jobs/tend_job_def.gd` / `tend.tres` | Script/Data | Tending job for crops needing maintenance. |
| `subsystems/farming/crop_library.gd` | Script | Static catalog loader for all crop definitions. |
| `subsystems/farming/growable.gd` | Script | Node component managing growth, hydration, tending, and visuals. |
| `subsystems/harvesting/harvestable.gd` | Script | Extended to query `Growable` dynamic yields and reset plots on harvest. |
| `data/actions/farm_manual_action.gd` | Script | Context-sensitive player LMB action. |
| `data/actions/inspect_crop_action.gd` | Script | Opens crop inspection UI panel via E menu. |
| `data/actions/select_crop_action.gd` | Script | Opens crop picker dialog via E menu. |
| `ui/crop_inspect/` | UI | Crop inspection modal (`crop_inspect.tscn` + `.gd`). |
| `ui/crop_picker/` | UI | Crop selection modal (`crop_picker.tscn` + `.gd`). |

## EventBus Signals

| Signal | Emitted by | Listeners | Purpose |
|---|---|---|---|
| `plot_needs_sowing(growable, anchor, crop_id, needed)` | `Growable` | Colony | Spawns or removes `SowJobDef` on `JobBoard`. |
| `plot_needs_water(growable, anchor, needed)` | `Growable` | Colony | Spawns or removes `WaterJobDef` on `JobBoard`. |
| `plot_needs_tending(growable, anchor, needed)` | `Growable` | Colony | Spawns or removes `TendJobDef` on `JobBoard`. |
| `harvest_mark_toggled(furniture, anchor, marked)` | `Harvestable` | Colony | Spawns or removes `HarvestJobDef` on `JobBoard`. |

## Job Lifecycle & Dispatch

1. **Sowing**: When a plot is `EMPTY` and has a `selected_crop_id`, `Growable` emits `plot_needs_sowing(..., true)`. Colony registers a `SowJobDef` (Priority 4). A colonist satisfying `CropDef.plant_conditions` plants the crop, advancing state to `GROWING`.
2. **Watering**: As in-game time advances, `water_level` decays. When `water_level <= thirsty_threshold`, `Growable` emits `plot_needs_water(..., true)`. Colony registers `WaterJobDef` (Priority 3). Colonists restore hydration to 100%. If water hits 0%, growth halts until watered.
3. **Tending**:
   - **Milestone Mode**: Tending is triggered at specific growth progress thresholds (e.g. 50%).
   - **Decay Mode**: Tended timer decays; when expired, tending is required.
   - While untended, growth rate scales by `untended_growth_mult` (default 0.0) and `neglect_time` accumulates.
   - Colony registers `TendJobDef` (Priority 2), gated by `CropDef.tend_conditions` (skill & tool requirements).
4. **Harvesting**:
   - At 100% maturity, `Growable` transitions to `MATURE` and auto-marks `Harvestable.set_marked(true)`, generating a `HarvestJobDef` (Priority 1).
   - Early harvest can also be manually marked via E menu or inspection panel.
   - On completion, yields are awarded from `Growable.get_harvest_yields()` (applying neglect penalties if untended beyond `neglect_hours`), and `Growable.on_harvested()` resets the plot to `EMPTY` without destroying the furniture.
