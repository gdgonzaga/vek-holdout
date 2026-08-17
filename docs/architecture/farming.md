# Subsystem: Farming

The **Farming** subsystem governs the full crop life-cycle: farm plot furniture placement, seed selection, hydration decay and watering, milestone & decay tending, early harvesting via progressive yield tiers, automated job dispatch (`Sow`, `Water`, `Tend`, and `Harvest`), and context-sensitive player LMB interaction.

Authoring guide for creating new crops: `docs/HOWTO-author-crops.md`.

---

## Core Concepts

- **Farm Plots as Furniture**: Farm plots (e.g. `Growing Trough`) are authored as `FurnitureDef` resources carrying a `FarmPlotParams` sub-resource.
- **Component Pairing**: Placed farm plots attach both `Growable` and `Harvestable` components. `Growable` manages time-based simulation (hydration, tending, growth stages), while `Harvestable` provides unified interaction with the colony's `JobBoard` and player harvesting.
- **Dynamic Yields & Early Harvesting**: Crops define `CropYieldTier`s. When harvested (early by player command or automatically at 100% maturity), yields are scaled based on achieved milestones and any neglect penalties.
- **Context-Sensitive LMB Interaction**: Pointing at a farm plot and holding LMB automatically resolves the required action (`Plant` -> `Tend` -> `Water` -> `Harvest`).
- **Two-Tier Hydration Progression**:
  - **Tier 1 (Manual Hydration - Current):** Colonists and player manually fetch water to top off crop hydration.
  - **Tier 2 (Automated Irrigation - Future):** Voxel fluid hydration, trenches, and piped sprinkler networks automate watering.

---

## Architecture & Layout

| File | Type | Purpose |
|---|---|---|
| `data/crops/crop_def.gd` | Script | Schema for `CropDef` resources (growth parameters, hydration, tending modes, gating). |
| `data/crops/crop_yield_tier.gd` | Script | Schema for `CropYieldTier` milestone yields. |
| `data/crops/*.tres` | Data | Crop definitions (`cave_spud`, `holdout_wheat`, `bio_gel_orchid`). |
| `data/capability_params/farm_plot_params.gd` | Script | Sub-resource on `FurnitureDef` defining allowed crops for the plot. |
| `data/labors/farming.tres` | Data | Farming labor definition (`id = "farming"`). |
| `data/jobs/farming_job_def.gd` | Script (Resource) | Shared skeleton for the three plot labors: one WORK leg against the plot's `Growable`, skill-scaled `begin` over `work_time` (authored per `.tres`). Subclasses override `_needs(growable)` / `_apply(growable, actor)` — a future FertilizeJobDef drops in the same way. |
| `data/jobs/sow_job_def.gd` / `sow.tres` | Script/Data | Sowing job for empty farm plots (`_needs`: EMPTY + crop selected; `_apply`: `plant`). Also gates on the crop's `plant_conditions`. |
| `data/jobs/water_job_def.gd` / `water.tres` | Script/Data | Watering job for thirsty crops (`_needs`: `needs_water()`; `_apply`: `water`). |
| `data/jobs/tend_job_def.gd` / `tend.tres` | Script/Data | Tending job for crops needing maintenance (`_needs`: `needs_tending()`; `_apply`: `tend`). Also gates on the crop's `tend_conditions`. |
| `subsystems/farming/crop_library.gd` | Script | Static catalog loader for all crop definitions in `res://data/crops/`. |
| `subsystems/farming/growable.gd` | Script | Node component managing growth simulation, hydration, tending, and visuals. |
| `subsystems/harvesting/harvestable.gd` | Script | Extended to query `Growable` dynamic yields and reset plots on harvest. |
| `data/actions/farm_manual_action.gd` | Script | Context-sensitive player LMB action. |
| `data/actions/inspect_crop_action.gd` | Script | Opens crop inspection UI panel via E menu. |
| `data/actions/select_crop_action.gd` | Script | Opens crop picker dialog via E menu. |
| `ui/crop_inspect/` | UI | Crop inspection modal (`crop_inspect.tscn` + `.gd`). |
| `ui/crop_picker/` | UI | Crop selection modal (`crop_picker.tscn` + `.gd`). |

---

## EventBus Signals

| Signal | Emitted by | Listeners | Purpose |
|---|---|---|---|
| `plot_needs_sowing(growable, anchor, crop_id, needed)` | `Growable` | Colony (`JobBoard`) | Spawns or removes `SowJobDef` on `JobBoard`. |
| `plot_needs_water(growable, anchor, needed)` | `Growable` | Colony (`JobBoard`) | Spawns or removes `WaterJobDef` on `JobBoard`. |
| `plot_needs_tending(growable, anchor, needed)` | `Growable` | Colony (`JobBoard`) | Spawns or removes `TendJobDef` on `JobBoard`. |
| `harvest_mark_toggled(furniture, anchor, marked)` | `Harvestable` | Colony (`JobBoard`) | Spawns or removes `HarvestJobDef` on `JobBoard`. |

---

## Crop Lifecycle & State Machine

```mermaid
stateDiagram-v2
    [*] --> EMPTY: Furniture Placed / Harvested
    EMPTY --> GROWING: Plant / Sow (Crop Selected)
    
    state GROWING {
        [*] --> Hydrated_Tended
        Hydrated_Tended --> Thirsty: Water <= thirsty_threshold
        Thirsty --> Hydrated_Tended: Watered (100%)
        Thirsty --> Growth_Paused: Water == 0%
        Growth_Paused --> Hydrated_Tended: Watered (100%)
        
        Hydrated_Tended --> Needs_Tending: Milestone reached / Timer expired
        Needs_Tended --> Hydrated_Tended: Tended (Colonist / Player)
    }
    
    GROWING --> MATURE: Growth Progress == 1.0 (Auto-mark Harvest)
    MATURE --> WITHERED: Unharvested >= wither_hours
    MATURE --> EMPTY: Harvested (Yields Awarded)
    GROWING --> EMPTY: Early Harvest (Partial Yields Awarded)
    WITHERED --> EMPTY: Cleared
```

---

## End-to-End Flow Traces

### 1. Sowing Flow (Player Manual vs. Colonist JobBoard)

```mermaid
sequenceDiagram
    autonumber
    actor Player
    participant UI as CropPickerUI
    participant Plot as FarmPlot (Growable)
    participant Bus as EventBus
    participant Board as Colony (JobBoard)
    actor Colonist

    Note over Player,Plot: 1. Crop Selection
    Player->>Plot: Press E -> "Select Crop"
    Plot->>UI: Open CropPicker (Filtered by FarmPlotParams)
    Player->>UI: Selects "Sweet Maize"
    UI->>Plot: set_selected_crop_id("sweet_maize")
    Plot->>Bus: plot_needs_sowing(self, anchor, "sweet_maize", true)
    Bus->>Board: Register SowJobDef (Priority 4, Gates: plant_conditions)

    alt Player Plants Directly (LMB)
        Player->>Plot: Hold LMB (FarmManualAction)
        Plot->>Plot: plant_crop("sweet_maize")
        Plot->>Bus: plot_needs_sowing(..., false)
        Bus->>Board: Cancel SowJobDef
    else Colonist Auto-Sows via JobBoard
        Colonist->>Board: Poll available jobs
        Board->>Colonist: Assign SowJobDef (Evaluates skill/equipment)
        Colonist->>Plot: Pathfind to Plot & Perform Work
        Colonist->>Plot: plant_crop("sweet_maize")
        Plot->>Bus: plot_needs_sowing(..., false)
        Bus->>Board: Complete SowJobDef
    end

    Plot->>Plot: State = GROWING, Water = 100%, Growth = 0%
```

---

### 2. Hydration & Watering Flow

```mermaid
sequenceDiagram
    autonumber
    participant Time as TimeSystem
    participant Plot as FarmPlot (Growable)
    participant Bus as EventBus
    participant Board as Colony (JobBoard)
    actor Colonist

    Time->>Plot: _process(delta) -> Advance hours_delta
    Plot->>Plot: water_level -= water_decay_per_hour * hours_delta

    opt water_level <= thirsty_threshold (e.g. 30%)
        Plot->>Bus: plot_needs_water(self, anchor, true)
        Bus->>Board: Register WaterJobDef (Priority 3)
    end

    opt water_level == 0.0%
        Plot->>Plot: growth_mult = 0.0 (Growth Frozen)
    end

    alt Colonist Waters Plot
        Colonist->>Board: Claim WaterJobDef
        Colonist->>Plot: Walk to Plot & Water
        Colonist->>Plot: water_crop()
    else Player Waters Plot
        actor Player
        Player->>Plot: Hold LMB (FarmManualAction)
        Player->>Plot: water_crop()
    end

    Plot->>Plot: water_level = 100.0%
    Plot->>Bus: plot_needs_water(self, anchor, false)
    Bus->>Board: Complete / Cancel WaterJobDef
```

---

### 3. Tending & Neglect Flow (Gated Maintenance)

```mermaid
sequenceDiagram
    autonumber
    participant Plot as FarmPlot (Growable)
    participant Bus as EventBus
    participant Board as Colony (JobBoard)
    actor Colonist

    Note over Plot: Milestone reached (e.g. 50%) OR Decay Timer expired
    Plot->>Plot: is_tended = false, growth_mult = untended_growth_mult (0.0)
    Plot->>Bus: plot_needs_tending(self, anchor, true)
    Bus->>Board: Register TendJobDef (Priority 2, Gates: tend_conditions)

    loop While Untended
        Plot->>Plot: neglect_time += hours_delta
    end

    Colonist->>Board: Poll jobs
    Board->>Board: Validate Colonist satisfies tend_conditions (Farming Skill + Tool)
    Board->>Colonist: Assign TendJobDef
    Colonist->>Plot: Walk to Plot & Tend
    Colonist->>Plot: tend_crop()

    Plot->>Plot: is_tended = true, reset timer / advance milestone index
    Plot->>Plot: growth_mult = 1.0 (Resume normal growth)
    Plot->>Bus: plot_needs_tending(self, anchor, false)
    Bus->>Board: Complete TendJobDef
```

---

### 4. Harvesting & Dynamic Yield Evaluation Flow

```mermaid
sequenceDiagram
    autonumber
    participant Plot as FarmPlot (Growable)
    participant Harv as Harvestable
    participant Bus as EventBus
    participant Board as Colony (JobBoard)
    actor Colonist

    alt Reaches 100% Maturity
        Plot->>Plot: State = MATURE, growth_progress = 1.0
        Plot->>Harv: set_marked(true)
        Harv->>Bus: harvest_mark_toggled(furniture, anchor, true)
        Bus->>Board: Register HarvestJobDef (Priority 1)
    else Early Harvest Triggered (Player LMB / E-menu)
        actor Player
        Player->>Harv: Mark Harvest / Hold LMB
    end

    Colonist->>Board: Claim HarvestJobDef
    Colonist->>Harv: Perform harvest work (base_harvest_time)
    Harv->>Plot: Query get_harvest_yields()

    Note over Plot: Calculates highest satisfied CropYieldTier<br/>Applies penalty: yield * (1.0 - (neglect_time / neglect_hours) * penalty)
    Plot-->>Harv: Return Array[ItemAmount]
    Harv->>Colonist: Spawn / Transfer Harvest Items to Inventory
    Harv->>Plot: on_harvested()

    Plot->>Plot: Reset to EMPTY, clear growth/timers
    Harv->>Harv: set_marked(false), work_done = 0.0
    
    opt Has selected_crop_id
        Plot->>Bus: plot_needs_sowing(self, anchor, selected_crop_id, true)
        Bus->>Board: Register SowJobDef for next cycle
    end
```

---

## Player UI & Interaction

1. **Context-Sensitive LMB (`FarmManualAction`):**
   - Raycast detects `Growable` via `InteractionComponent`.
   - Single continuous LMB hold evaluates state in priority order:
     - `EMPTY` $	o$ Plants `selected_crop_id`.
     - `Needs Tending` $	o$ Performs tending action.
     - `Thirsty / Dry` $	o$ Waters plot to 100%.
     - `MATURE / Harvestable` $	o$ Completes harvest work.
2. **Context Menu (E Key):**
   - **Inspect Crop (`InspectCropAction`):** Opens `ui/crop_inspect/crop_inspect.tscn`, displaying current growth %, water level %, tending countdown, neglect time, and projected harvest yields.
   - **Select Crop (`SelectCropAction`):** Opens `ui/crop_picker/crop_picker.tscn` displaying a grid of available crops from `CropLibrary` (filtered by `FarmPlotParams.allowed_crops`).
