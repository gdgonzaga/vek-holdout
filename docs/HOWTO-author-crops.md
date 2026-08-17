# How To: Author a Crop

> End-to-end guide for creating and configuring new crops in Vek Holdout —
> covering visual growth stages, hydration decay, tending modes, skill & tool gating,
> dynamic milestone yield tiers, and registering crops with farm plots.
>
> **Prerequisites:** Familiar with Godot `.tres` Resource creation.
> Read [`docs/architecture/farming.md`](architecture/farming.md) for the subsystem overview.

---

## Overview of Crop Resources

A crop in Vek Holdout is defined via data resources located in `res://data/crops/`:

```
CropDef (data/crops/<id>.tres)
├── yield_tiers: Array[CropYieldTier]
│   └── CropYieldTier (sub-resource)
│       └── yields: Array[ItemAmount]
│           └── ItemAmount (sub-resource -> ItemDef in data/items/)
├── plant_conditions: Array[Condition] (sub-resources -> MinSkillCondition / HasItemCondition)
├── tend_conditions: Array[Condition]  (sub-resources -> MinSkillCondition / HasItemCondition)
└── stage_meshes: Array[Mesh]          (optional custom 3D models per growth stage)
```

---

## Step-by-Step Authoring Guide

### Step 1: Create the Harvest Item

Ensure the crop harvest product exists in `data/items/<id>.tres` (e.g. `data/items/cave_spud.tres`).
The harvest product must be an `ItemDef` resource defining `id`, `weight`, `icon`, and `tags` (see `data/items/item_def.gd` — there is no `display_name` or `stack_limit` field).

---

### Step 2: Create the `CropDef` Resource

Create a new file `data/crops/<crop_id>.tres` (matching its `id` string). Set its script to `res://data/crops/crop_def.gd`.

#### Basic Identification & Growth Timing
```ini
id = "sweet_maize"
display_name = "Sweet Maize"
growth_time_hours = 18.0      # Total in-game hours from seed to 100% maturity
growth_stages = 3             # Number of visual stages (1: Sprout, 2: Growing, 3: Mature)
base_harvest_time = 3.0       # Base seconds to harvest (scaled by Harvesting skill)
wither_hours = 24.0           # Hours mature crop can sit unharvested before withering (0.0 = never)
```

---

### Step 3: Configure Hydration

Set the water consumption profile:

```ini
max_water = 100.0             # Water capacity (starts at 100% upon watering)
water_decay_per_hour = 4.0    # Consumes 4% water per in-game hour (lasts 25 hours per watering)
thirsty_threshold = 30.0      # Triggers a Water job when water drops <= 30%
```

- If `water_level == 0%`, crop growth **halts immediately** (0× multiplier) until watered.

---

### Step 4: Configure Tending & Gating

Choose a tending mode (`TendingMode.NONE = 0`, `TendingMode.MILESTONE = 1`, `TendingMode.DECAY = 2`):

#### Option A: No Tending Required (`tending_mode = 0`)
```ini
tending_mode = 0
```
*Best for starter, hardy crops like `cave_spud`.*

#### Option B: Milestone Tending (`tending_mode = 1`)
Triggers tending at specific growth milestones (0.0 to 1.0):
```ini
tending_mode = 1
tending_milestones = [0.5]          # Requires tending once at 50% growth
untended_growth_mult = 0.0          # Growth freezes while untended (0.1 = grows at 10% speed)
neglect_hours = 6.0                 # Safe buffer before neglect penalties accumulate
neglect_yield_penalty = 0.25        # Loses 25% yield per neglect_hours untended
```

#### Option C: Decay-Based Tending (`tending_mode = 2`)
Requires recurring maintenance every $N$ in-game hours:
```ini
tending_mode = 2
tending_decay_hours = 6.0           # Needs tending every 6 in-game hours
untended_growth_mult = 0.0
neglect_hours = 4.0
neglect_yield_penalty = 0.5         # High penalty for delicate luxury/medicinal crops
```

#### Gating with Conditions (Skills & Equipment)
Attach `plant_conditions` and/or `tend_conditions` sub-resources:

```ini
# Require Farming skill level >= 2:
[sub_resource type="Resource" id="skill_gate"]
script = ExtResource("res://data/conditions/min_skill_condition.gd")
skill_id = "farming"
min_level = 2

# Require gardening tool equipped/in inventory:
[sub_resource type="Resource" id="tool_gate"]
script = ExtResource("res://data/conditions/has_item_condition.gd")
item_tag = "gardening_tool"
count = 1

# Inside [resource]:
tend_conditions = [SubResource("skill_gate"), SubResource("tool_gate")]
```

---

### Step 5: Configure Dynamic Yield Tiers

Crops support progressive harvesting at different growth thresholds:

```ini
[sub_resource type="Resource" id="yield_item_half"]
script = ExtResource("res://data/items/item_amount.gd")
item_def = ExtResource("res://data/items/sweet_maize.tres")
count = 3

[sub_resource type="Resource" id="yield_item_full"]
script = ExtResource("res://data/items/item_amount.gd")
item_def = ExtResource("res://data/items/sweet_maize.tres")
count = 8

[sub_resource type="Resource" id="tier_50pct"]
script = ExtResource("res://data/crops/crop_yield_tier.gd")
min_growth_progress = 0.5
yields = [SubResource("yield_item_half")]

[sub_resource type="Resource" id="tier_100pct"]
script = ExtResource("res://data/crops/crop_yield_tier.gd")
min_growth_progress = 1.0
yields = [SubResource("yield_item_full")]

# Inside [resource]:
yield_tiers = [SubResource("tier_50pct"), SubResource("tier_100pct")]
```

- When harvested early (e.g. at 70% growth), the player receives the highest satisfied tier (`tier_50pct` $	o$ 3 maize).
- At 100% maturity, the player receives `tier_100pct` (8 maize, minus any neglect penalties).

---

### Step 6: Growth Stage Meshes (Visuals)

`Growable` renders visual stages based on `growth_progress`:
- **Stage 0 (Sprout):** `< 40%` progress
- **Stage 1 (Growing):** `40% - 99%` progress
- **Stage 2 (Mature):** `100%` progress
- **Stage 3 (Withered):** `wither_hours` exceeded

You can provide custom meshes in `stage_meshes = [mesh_sprout, mesh_growing, mesh_mature]`. If left empty, `Growable` automatically renders colored procedural cylinder meshes.

---

### Step 7: Restrict to Specific Farm Plots (Optional)

By default, farm plot furniture (`Growing Trough` — the only farm plot shipped today) accepts all crops in `CropLibrary`.
To restrict a specific plot type to certain crops, edit the plot's `FurnitureDef` and set `FarmPlotParams.allowed_crops`:

```ini
[sub_resource type="Resource" id="farm_params"]
script = ExtResource("res://data/capability_params/farm_plot_params.gd")
allowed_crops = ["sweet_maize", "cave_spud"]
```

---

## Testing & Verification

1. **Static Catalog Check:** Ensure `CropLibrary.get_crop("<crop_id>")` resolves your resource.
2. **Player Interaction Check:**
   - Place a farm plot in build mode.
   - Press **E** to open the context menu $	o$ choose **Select Crop** $	o$ pick your new crop.
   - Hold **LMB** to plant, water, tend, and harvest.
3. **Colonist JobBoard Check:**
   - Set a plot to your crop with no player intervention.
   - Verify that `SowJobDef`, `WaterJobDef`, and `TendJobDef` are claimed and executed by qualified colonists on the Job Board.
