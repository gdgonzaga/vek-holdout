# How To: Author Enemies & Loot Tables

> End-to-end guide for adding a hostile enemy archetype to *Xeno Frontier: Colony Defense*: the `EnemyDef` resource, its attack parameters, its scene, getting it into night raids, and giving it drops with a `LootTable`.
> Covers `EnemyDef`, `MeleeActionParams` / `RangedActionParams`, the enemy scene layout, `RaidSpawnEntry` pool wiring, `LootTable`, and `LootEntry`.
>
> **Prerequisites:** Familiarity with Godot `.tres` Resource creation and scene editing.
> Read [`docs/architecture/combat.md`](architecture/combat.md), [`docs/architecture/loot.md`](architecture/loot.md) and [`docs/architecture/data-schemas.md`](architecture/data-schemas.md) for subsystem details.

---

## 1. Overview & Architectural Role

An enemy is data plus a thin scene. All numbers (HP, speed, damage, drops) live in `.tres` resources under `data/`; the scene only supplies the body and components, and the behavior tree supplies the decision-making. There is no per-enemy combat code.

```
EnemyDef (res://data/enemies/<id>.tres)
├── id, display_name
├── max_hp, max_durability, base_move_speed
├── detect_range, los_loss_timeout     (not consumed by AI yet, see Step 3)
├── behavior_tree: BehaviorTree        (shared trees in data/ai/trees/)
├── attack_params: CombatActionParams  (MeleeActionParams | RangedActionParams | null)
├── loot_table: LootTable              (optional, res://data/loot/<id>.tres)
└── moodlet_defs: Array[MoodletDef]    (e.g. the HP heart gauge)

Enemy scene (res://subsystems/combat/enemies/enemy_<id>/enemy_<id>.tscn)
├── root: CharacterBody3D + thin EnemyBase subclass, enemy_def = the .tres above
├── CollisionShape3D, MeshInstance3D   (capsule prototype art)
├── HealthComponent                    (required)
└── GroundSafetyGuard, VoxelPathfinder, StepClimber
```

At `_ready()`, `EnemyBase` applies the assigned `enemy_def`: HP and durability go to the `HealthComponent`, the behavior tree goes to a runtime-created `BTPlayer`, and the moodlets go to a runtime-created `EnemyMoodletVisualizer`. When the `HealthComponent` reports death, `EnemyBase` rolls `loot_table` and spawns the drops.

`EnemyLibrary` (autoload) indexes every `EnemyDef` under `data/enemies/` by its `id` string. Identity is the `id`, never the filename, but keep them equal (data convention).

---

## 2. Step-by-Step: Add an Enemy

The examples below author a fictional melee enemy called `lurker`. Substitute your own id.

### Step 1: Pick a Behavior Tree

Reuse an existing tree unless your enemy needs genuinely new behavior:

| Tree | Behavior | Pair with |
|---|---|---|
| `data/ai/trees/enemy_melee.tres` | Scan for threats, path to the target (breaching voxels that block the way), and swing when in range | `MeleeActionParams` |
| `data/ai/trees/enemy_ranged_kiter.tres` | Scan for threats, close in until within firing range, and fire. Despite the name it does not back-pedal (see Ranged Kiting in [Combat](architecture/combat.md)) | `RangedActionParams` |

One tree resource is shared by every archetype that uses it. The trees read their numbers from the agent's `EnemyDef.attack_params`, so two melee enemies differ only in their data. To build a new tree, follow [Authoring Behavior Trees](HOWTO-author-behavior-trees.md).

---

### Step 2: Author the Attack Parameters

`attack_params` is a polymorphic sub-resource. In the Inspector's **Attack Params** field choose **New MeleeActionParams** or **New RangedActionParams**; it is saved inline inside the `EnemyDef` file. Leave it empty for an enemy that never attacks.

**What the enemy AI reads:**

| Field | Melee (`MeleeActionParams`) | Ranged (`RangedActionParams`) |
|---|---|---|
| `damage` | Damage per hit (truncated to an int) | Damage per shot (truncated to an int) |
| `range_meters` | Distance at which the swing starts | Distance the enemy closes to before it fires (and fires at) |
| `windup_seconds` | Delay before the damage lands | Not used |
| `active_seconds` | Added to the recovery time after the hit | Not used |
| `cooldown_seconds` | Recovery time after the hit | Full time between shots |

For melee, one full attack cycle is `windup_seconds + active_seconds + cooldown_seconds`.

**What enemies ignore:** enemy attacks apply damage straight to their locked target rather than going through the weapon hitscan or projectile path (see the Ranged Attack note in [Combat](architecture/combat.md)). Ranged fields such as `is_hitscan`, `ammo_item_id`, `spread_angle_degrees`, `projectile_*` and `show_tracer`, and audio-event fields, have no effect on enemies today.

---

### Step 3: Create the `EnemyDef` Resource

1. In the FileSystem dock, right-click `res://data/enemies/` -> **Create New Resource...** -> select `EnemyDef` (script: `res://data/enemies/enemy_def.gd`).
2. Save it as `data/enemies/enemy_lurker.tres`.
3. Set the fields:

| Property | Example | Description |
|---|---|---|
| `id` | `"enemy_lurker"` | Identity string `EnemyLibrary` indexes by. Must be non-empty (an empty id is skipped on load) and should match the filename. |
| `display_name` | `"Lurker"` | UI label. Default `"Enemy"`. |
| `max_hp` | `80` | Hit points. Default `100`. |
| `max_durability` | `0` | Durability absorbs damage before HP (shared with Player and Colonist). Default `0`. |
| `base_move_speed` | `2.5` | Meters per second along the path. Default `5.0`, which is faster than the GDD's 3.5 m/s player base speed, so always set it. Check GDD §5 for design targets. |
| `detect_range` | `12.0` | **Not consumed by any AI task yet.** The scan node in the behavior tree authors its own radius. Set it for forward compatibility. |
| `los_loss_timeout` | `5.0` | **Not consumed yet** (no line-of-sight tracking exists). Forward-compatible data only. |
| `behavior_tree` | `enemy_melee.tres` | The tree from Step 1. Without it the enemy stands still. |
| `attack_params` | `MeleeActionParams` | From Step 2. |
| `loot_table` | `lurker_drops.tres` | Optional. See [Section 4](#4-author-a-loot-table). Empty means no drops. |
| `moodlet_defs` | `[heart_hp_gauge.tres]` | Billboard icons above the enemy. Add `data/moodlets/heart_hp_gauge.tres` for the standard HP heart. See [Authoring Moodlet Definitions](HOWTO-author-moodlet-defs.md). |

Reference: the shipped defs in `data/enemies/` (`enemy_swarmer`, `enemy_brawler`, `enemy_shooter`) show a melee and a ranged setup end to end.

> **Rule 1 reminder:** put stat and content values in the `.tres`, never in the enemy script.

---

### Step 4: Create the Enemy Scene

Follow the shipped scenes (for example `subsystems/combat/enemies/enemy_brawler/enemy_brawler.tscn`).

1. Create the folder `subsystems/combat/enemies/enemy_lurker/`.
2. Add a thin script `enemy_lurker.gd`. Enemies extend `EnemyBase`, never `CharacterBody3D` directly. Numbers belong in the `EnemyDef`; only add code for genuinely archetype-specific behavior:

```gdscript
class_name EnemyLurker
extends EnemyBase


func _ready() -> void:
	super._ready()
```

3. Build the scene with root node `EnemyLurker` (`CharacterBody3D`, script above) and save it as `enemy_lurker.tscn`. The filename matches the root node name in snake_case.
4. On the root set `enemy_def` to `enemy_lurker.tres`, `collision_layer = 64`, `collision_mask = 7`, `floor_snap_length = 0.5` (matches the shipped scenes).
5. Add children:

| Node | Notes |
|---|---|
| `CollisionShape3D` | `CapsuleShape3D`, offset `y = 1` so the capsule stands on the origin |
| `MeshInstance3D` | `CapsuleMesh` with the same offset. Prototype art is capsules until the art pass |
| `HealthComponent` | Script `subsystems/combat/components/health_component.gd`. **Required**: without it `EnemyBase` warns and the enemy cannot take damage or die |
| `GroundSafetyGuard` | Script `subsystems/core/ground_safety_guard.gd` |
| `VoxelPathfinder` | Script `subsystems/colonists/voxel_pathfinder.gd` |
| `StepClimber` | Script `subsystems/core/step_climber.gd`, `hop_height = 1.3` |

Do **not** place a `BTPlayer` or `EnemyMoodletVisualizer`. `EnemyBase` creates them at runtime from the `EnemyDef`. It will also create a `VoxelPathfinder` and `StepClimber` if missing, but the shipped scenes place them explicitly so their settings show in the editor.

---

### Step 5: Get the Enemy Into the Game

**Night raids (works today).** `NightRaidController` picks an enemy per spawn by weighted random selection over `GameConfig.enemy_pool`.

1. Open `data/game_config.tres`.
2. In the **Night Raid Spawning** group, expand **Enemy Pool** and add an element -> **New RaidSpawnEntry**.
3. Set `enemy_scene` to `enemy_lurker.tscn` and `weight` (default `1.0`).

An entry's chance of being picked is its `weight` divided by the sum of all weights. With the current pool, an entry of weight `5.0` next to weights of `2.0` and `1.0` is chosen five times out of eight. Adding an enemy with a high weight makes it easy to see during testing; lower it before you finish. See [Raids](architecture/raids.md).

**Authored map spawn markers (not wired).** `MapWiring.wire_enemies` still instantiates only the swarmer for markers placed in a map. A new archetype will not appear there until that path is generalized (tracked in [Tech Debt](architecture/tech-debt.md)).

---

## 3. What Happens When an Enemy Dies

1. The `HealthComponent` emits `entity_died`.
2. `EnemyBase` rolls `enemy_def.loot_table` (skipped if there is no def or no table).
3. Each resulting stack spawns as a `WorldItem` on its own slice of a circle around the death position, with a small outward and upward impulse, so drops never share a spawn point.
4. The enemy frees itself. The drops are parented to the scene, not the enemy, so they stay.

Drops are ordinary `WorldItem`s: the player picks them up with the interact key and colonists haul them like any other loose item. Only death drops loot. Enemies removed directly by code, such as raid cleanup, do not.

---

## 4. Author a Loot Table

### Concepts

A `LootTable` has two lists:

| Field | Meaning |
|---|---|
| `guaranteed` (`Array[ItemAmount]`) | Always dropped, with the exact count. Uses the same `ItemAmount` type as recipes and harvest yields. |
| `entries` (`Array[LootEntry]`) | Each entry rolls **independently**. |

A `LootEntry` has four fields:

| Field | Default | Meaning |
|---|---|---|
| `item_def` | none | The item to drop. An entry with no item is skipped. |
| `chance` | `1.0` | Probability from `0.0` to `1.0` (the Inspector shows a slider). `0.5` is 50%. |
| `min_count` | `1` | Lowest stack size. Values below `1` are raised to `1`. |
| `max_count` | `1` | Highest stack size. A value below `min_count` is raised to `min_count`. |

An entry first rolls `chance`. If it passes, the stack size is picked uniformly between `min_count` and `max_count`, inclusive. Chance controls how often something drops; count controls how much.

### Rules to design around

- **Every entry that passes drops.** There is no cap and no pick-one behavior. Ten entries at `0.9` will nearly all drop on every kill.
- **The same item stacks.** Amounts for one item from `guaranteed` and from any number of entries are summed into a single stack and spawn as one `WorldItem`. A second, low-chance entry for an item you already drop is a bonus on top of the base drop, not a replacement for it.
- **Author quantity as a range, not as extra entries.** "50% chance of 3 to 7" is one entry. Use a second entry only for a deliberate rare bonus, for example a `0.05` chance of `10`.
- **Tune with expected value.** Average drops per kill is `chance x average count`. An entry of `0.5` chance and `3` to `7` count averages `0.5 x 5 = 2.5` per kill. Bulk materials usually want a high chance with a count range; rare items want a low chance with a count of `1`.
- **Each distinct item is a physics body.** Keep the number of distinct items per table modest. Counts are cheap because they share one stack.

### Create the table

1. Make sure every dropped item exists as an `ItemDef` in `res://data/items/`. Monster materials already carry the `monster_drop` tag (`monster_chitin`, `monster_sinew`); follow that convention for new ones.
2. In the FileSystem dock, right-click `res://data/loot/` -> **Create New Resource...** -> select `LootTable`.
3. Save it as `data/loot/lurker_drops.tres` and set `id` to `"lurker_drops"` (matching the filename).
4. Expand **Guaranteed** and add an element -> **New ItemAmount** for each always-drop item, then set its `item_def` and `count`.
5. Expand **Entries** and add an element -> **New LootEntry** for each random drop, then set `item_def`, `chance`, `min_count` and `max_count`.
6. Open your `EnemyDef` and drag the table into **Loot Table**.

A table is a shared resource, so several `EnemyDef`s can point at the same file, for example a common "monster remains" table with per-enemy extras in their own tables.

### Worked example

Two scraps every time, chitin half the time in stacks of 3 to 7, and a 10% chance of one sinew:

```
[gd_resource type="Resource" script_class="LootTable" format=3]

[ext_resource type="Script" path="res://data/loot/loot_table.gd" id="1_table"]
[ext_resource type="Script" path="res://data/loot/loot_entry.gd" id="2_entry"]
[ext_resource type="Script" path="res://data/items/item_amount.gd" id="3_amount"]
[ext_resource type="Resource" path="res://data/items/materials/salvaged_scraps.tres" id="4_scraps"]
[ext_resource type="Resource" path="res://data/items/materials/monster_chitin.tres" id="5_chitin"]
[ext_resource type="Resource" path="res://data/items/materials/monster_sinew.tres" id="6_sinew"]

[sub_resource type="Resource" id="Resource_scraps"]
script = ExtResource("3_amount")
item_def = ExtResource("4_scraps")
count = 2

[sub_resource type="Resource" id="Resource_chitin"]
script = ExtResource("2_entry")
item_def = ExtResource("5_chitin")
chance = 0.5
min_count = 3
max_count = 7

[sub_resource type="Resource" id="Resource_sinew"]
script = ExtResource("2_entry")
item_def = ExtResource("6_sinew")
chance = 0.1
min_count = 1
max_count = 1

[resource]
script = ExtResource("1_table")
id = "lurker_drops"
guaranteed = Array[ExtResource("3_amount")]([SubResource("Resource_scraps")])
entries = Array[ExtResource("2_entry")]([SubResource("Resource_chitin"), SubResource("Resource_sinew")])
```

Rolled 1000 times with a fixed seed, this table gave scraps every time, chitin 522 times with stack sizes between 3 and 7, and sinew 99 times. You will normally build this in the Inspector; the text form is shown so you can read and diff the files.

### Not supported yet

Mutually exclusive pools ("exactly one of these three"), luck or quantity modifiers, per-difficulty tables, loot containers, and Key Items. These are planned; see [Loot](architecture/loot.md). Do not work around them with scripts. If an enemy needs one of them, extend the loot system instead.

---

## 5. Verification & Testing Checklist

- [ ] **Loads cleanly**: run `test/suite_enemy_def_test.gd`. Its real-library check loads every authored `EnemyDef` and catches bad `ext_resource` paths and empty ids.
- [ ] **Enemy behavior**: the enemy pathfinds toward a target, attacks when in range, and its HP heart appears above its head and drains as it takes damage.
- [ ] **Raid spawning**: with your entry temporarily at a high `weight`, the enemy appears during the night raid. Restore a sensible weight afterwards.
- [ ] **Drops**: kill it. Expect one `WorldItem` per distinct item, spread around where it fell, with counts inside your `min_count` to `max_count` ranges. Guaranteed items appear every kill. Kill several to see the chances play out.
- [ ] **No drops when null**: an enemy without a `loot_table` dies without spawning anything and without errors.
- [ ] **Loot tests**: if you changed `LootRoller` or `EnemyBase`, run `test/suite_loot_roller_test.gd` and `test/suite_enemy_loot_test.gd`. There is no dedicated enemy playtest scene under `testing/` yet, so kill-and-inspect checks are done in a running map.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Enemy stands still | `behavior_tree` is empty on the `EnemyDef` |
| Enemy chases but never attacks | `attack_params` is empty, or its type does not match the tree (melee params with the ranged tree, or the reverse) |
| Enemy is immortal or warns about `HealthComponent` | The scene has no `HealthComponent` child |
| Enemy is far too fast | `base_move_speed` was left at the default `5.0` (faster than the player's base speed) |
| Enemy never shows up in raids | Not in `GameConfig.enemy_pool`, or its `weight` is tiny compared with the others |
| Nothing drops | `loot_table` is empty, every entry has `chance = 0` or no `item_def`, or the enemy was removed by code instead of killed |
| A drop appears as a plain box | The `ItemDef` has no `scene` or `mesh`, so `WorldItem` uses its prototype box |
| An item you expected is missing | Its `chance` did not pass that roll, or it is a duplicate of another entry and merged into that stack |

---

## 6. Related Docs

- [Combat](architecture/combat.md): enemy AI, behavior trees, health and death.
- [Loot](architecture/loot.md): the loot system design, roll rules and drop flow.
- [Data Schemas](architecture/data-schemas.md): `EnemyDef`, `LootTable` and `LootEntry` field reference.
- [Raids](architecture/raids.md): night raid pacing and the enemy pool.
- [Authoring Behavior Trees](HOWTO-author-behavior-trees.md) and [Authoring Moodlet Definitions](HOWTO-author-moodlet-defs.md).
