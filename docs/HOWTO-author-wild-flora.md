# How To: Author Wild Flora

> End-to-end guide for creating, configuring, texturing, and placing wild trees, fruit-bearing bushes, and forageable plants in *Vek: Holdout*.
> Covers `WildFloraDef` resource setup, multi-stage growth (`WildFloraStage`), perennial fruit foraging, weapon impact/felling tuning, collision policies, and map scattering.
>
> **Prerequisites:** Familiarity with Godot `.tres` Resource creation and 3D scene imports (`.glb`).
> Read [`docs/architecture/wild-flora.md`](architecture/wild-flora.md) and [`docs/architecture/data-schemas.md`](architecture/data-schemas.md) for subsystem architecture details.

---

## 1. Overview & Architectural Role

Wild flora in *Vek: Holdout* encompasses all naturally occurring vegetation across the world:
- **Harvestable / Felled Trees**: Solid trunks that yield logs and branches when chopped down with axes.
- **Perennial Fruit Bushes**: Forageable berry bushes or fruit trees that yield edible food on interaction without destroying the plant, regrowing fruit over time.
- **Single-Harvest Wild Herbs & Plants**: Uprooted entirely upon harvesting (e.g. wild roots, wild fiber).
- **Decorative Foliage & Shrubs**: Non-blocking vegetation adding aesthetic density to biomes.

### Wild Flora (`WildFloraDef`) vs. Domestic Crops (`CropDef`)

| Feature | Wild Flora (`WildFloraDef`) | Domestic Crops (`CropDef`) |
|---|---|---|
| **Placement Target** | Open world terrain / `FurnitureLayer` / Map Spawners | Authored farm plots / troughs (`FarmPlotParams`) |
| **Hydration / Tending** | None (grows independently in nature) | Strict water decay, tending milestones, neglect penalties |
| **Destruction / Felling** | Real-time weapon combat / tool chopping via `HealthComponent` | Cleared via Job Board or plot reset |
| **Foraging Interaction** | Direct player context action (`ForageAction`) / LMB | Farming action chain (`FarmManualAction`) / `HarvestJobDef` |

---

## 2. Resource Hierarchy

A complete wild flora definition is organized as:

```
WildFloraDef (res://data/furniture/<id>.tres)
├── stages: Array[WildFloraStage]
│   ├── [0] WildFloraStage (Sprout / Sapling)
│   │   ├── scene: PackedScene (optional .glb / .tscn)
│   │   ├── fell_yields: Array[ItemAmount]
│   │   └── visual_scale: Vector3
│   ├── [1] WildFloraStage (Mature Bush / Tree)
│   │   ├── scene: PackedScene
│   │   ├── fell_yields: Array[ItemAmount]
│   │   └── visual_scale: Vector3
│   └── [2] WildFloraStage (Fruiting / Ripe)
│       ├── scene: PackedScene
│       ├── can_harvest_fruit: true
│       ├── harvest_yields: Array[ItemAmount] -> e.g. 3x berry
│       └── fell_yields: Array[ItemAmount] -> e.g. wood + berries
└── default_scene: PackedScene (.glb fallback if stage scene is omitted)
```

---

## 3. Step-by-Step Authoring Guide

### Step 1: Ensure Drop Items Exist
Ensure all dropped items (wood, branches, berries, fiber, saplings) exist as `ItemDef` resources in `res://data/items/` (e.g. `data/items/wood.tres`, `data/items/wild_berries.tres`).

---

### Step 2: Prepare 3D Models & Scenes
1. Save your 3D models (`.glb`) into `assets/furniture/` or `assets/art/`.
2. **Pivot & Origin Convention**:
   - Unlike voxel blocks which occupy positive `[0, 1]³` space, **wild flora models must have their pivot centered at (0, 0, 0) on the bottom floor plane** (matching furniture and world items).
3. If you have distinct visual models for different growth stages (e.g. sapling vs mature tree vs fruit-laden tree), prepare each `.glb` scene.
4. If using a single mesh that scales dynamically, you can assign it once to `default_scene` and adjust `visual_scale` per stage in Step 4.

---

### Step 3: Create the `WildFloraDef` Resource
1. In the FileSystem dock, right-click in `res://data/furniture/` -> **Create New Resource...** -> select `WildFloraDef` (script: `res://data/furniture/wild_flora_def.gd`).
2. Save the file as `data/furniture/<flora_id>.tres` (e.g. `data/furniture/elder_berry_bush.tres`).
3. Set the core properties:

| Property | Example Value | Description |
|---|---|---|
| `id` | `"elder_berry_bush"` | Unique ID string (must match filename). |
| `display_name` | `"Elder Berry Bush"` | In-game UI label for inspection and logs. |
| `dimensions` | `Vector3i(1, 1, 1)` | Voxel footprint occupied on the `FurnitureLayer`. |
| `default_scene` | `res://assets/furniture/berry_bush.glb` | Default 3D visual fallback. |
| `blocks_movement` | `false` | `true` for solid tree trunks; `false` for shrubs/bushes so entities can walk through. |
| `growth_time_hours` | `18.0` | In-game hours to grow from 0.0 to 1.0 (0.0 = static / mature). |
| `destroy_on_fruit_harvest` | `false` | `false` for perennial bushes/trees; `true` for single-harvest roots. |
| `regrowth_stage_index` | `1` | Stage index to revert to when picked (`1` = mature bush without fruit). |
| `initial_growth_min` | `0.4` | Minimum randomized growth progress on fresh world generation. |
| `initial_growth_max` | `1.0` | Maximum randomized growth progress on fresh world generation. |
| `impact_audio_event` | `"foliage_rustle"` | Audio event on weapon hit (`"wood_chop"`, `"foliage_rustle"`). |
| `hit_particles_color` | `Color(0.3, 0.6, 0.2)` | Particle color burst on weapon impact. |
| `tags` | `["live_flora", "bush", "forageable"]` | Gameplay query tags (`"tree"`, `"timber"`, `"bush"`). |

---

### Step 4: Configure Growth Stages (`WildFloraStage`)

Add elements to the `stages` array in ascending order of `min_progress` (from `0.0` to `1.0`):

#### Stage 0: Sprout / Sapling (`min_progress = 0.0`)
- `min_progress`: `0.0`
- `max_hp`: `30`
- `visual_scale`: `Vector3(0.4, 0.4, 0.4)`
- `can_harvest_fruit`: `false`
- `fell_yields`: `[1 x fiber]`

#### Stage 1: Mature Unfruited Bush (`min_progress = 0.6`)
- `min_progress`: `0.6`
- `max_hp`: `80`
- `visual_scale`: `Vector3(0.85, 0.85, 0.85)`
- `can_harvest_fruit`: `false`
- `fell_yields`: `[2 x branches, 1 x fiber]`

#### Stage 2: Ripe / Fruiting Bush (`min_progress = 1.0`)
- `min_progress`: `1.0`
- `max_hp`: `100`
- `visual_scale`: `Vector3(1.0, 1.0, 1.0)`
- `can_harvest_fruit`: `true`
- `harvest_yields`: `[4 x elder_berries]`
- `fell_yields`: `[2 x branches, 4 x elder_berries]` (drops fruit if chopped down while ripe!)

---

### Step 5: Weapon & Tool Damage Scaling (Built-In)

When a tree or plant is attacked by a player, colonist, or enemy:
- **Trees (`tags` contains `"tree"`, `"timber"`, or `"wood"`)**:
  - **Axe (`tool_axe`, `axe`)**: `100%` damage.
  - **Blades (`sword`, `dagger`, `blade`)**: `25%` damage.
  - **Pickaxes (`pickaxe`, `pick`)**: `15%` damage.
  - **Bare Hands / Unarmed**: `20%` damage.
- **Foliage / Bushes (non-tree tags)**:
  - Take `100%` damage from all sources.
- **Lethal Damage (0 HP)**: Triggers felling, awards `fell_yields`, and frees the entity from `FurnitureLayer`.

---

## 6. Spawning & World Placement

### Option A: World Generation / Map Authoring (`PlantSpawner`)
Attach a `PlantSpawner` or `TreeScatterer` node in your map scene (`data/maps/<map_id>/map.tscn`):
- Assign your `WildFloraDef` to the spawner's flora list.
- Set Poisson-disc radius, density, and allowed slope angles.
- On map load, `PlantSpawner` raycasts the smooth terrain surface and registers plants via `FurnitureLayer.spawn(def, cell, 0)`.

### Option B: Hand-Placement via Map Editor
1. Launch the Map Editor (`tools/map_editor/map_editor.tscn`).
2. Switch to **Furniture / Flora Mode**.
3. Select your flora from the palette and click on the terrain to place it.
4. Placed instances persist directly into the map definition.

---

## 7. Verification & Testing Checklist

- [ ] **Data Check**: Verify `def.get_effective_stages()` returns your configured stages.
- [ ] **Unit Tests**: Run `test/suite_wild_flora_test.gd` via gdUnit4 to verify stage resolution, damage scaling, felling, and foraging logic.
- [ ] **Movement Collision**: Confirm that characters pass through bushes (`blocks_movement = false`) and collide with trees (`blocks_movement = true`).
- [ ] **Fruit Harvest**: Press **E** on a mature plant to confirm the "Forage" action appears, drops fruit, and reverts progress to `regrowth_stage_index`.
- [ ] **Chop & Fell**: Hit the plant with an axe to confirm particle bursts, HP loss, and fell item drops upon destruction.
