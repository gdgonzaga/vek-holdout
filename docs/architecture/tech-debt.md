# Tracking

## Known Tech Debt

- [x] **Boot vs Main scene strategy decided** — `boot.tscn` is the `main_scene`; it instantiates `main.tscn`, then opens Splash → Main Menu. The menu gates gameplay (New Game loads the base map). See [Core](core.md) "Boot → Splash → Main Menu → New Game" flow.
- [~] **voxel_tool raycast reliability** — `VoxelTool.raycast()` is unreliable; the workaround uses a Godot physics raycast against voxel collision bodies. **Validated:** build mode has landed and `BuildController` uses a screen-center Godot physics raycast (player body excluded) for placement/deconstruct, so the workaround holds in practice.
- [~] **Colonist pathfinding split** — A* on voxel grid for colonists, NavigationAgent for enemies. Two pathfinding systems in one game is complexity; validate the split pays off vs. NavAgent-for-everything once both are prototyped. **Half prototyped:** the colonist A* (`voxel_pathfinder.gd`, injected walkability predicate) is wired end-to-end into `ColonistAI` (claim → path → arrive), including vertical routing — one-block climbs via the shared `StepClimber` hop, drops up to 3 cells, head-clearance-checked walkability. The enemy `NavigationAgent` half is still pending; the split-payoff verdict stays open until enemies land.
- [ ] **`combat/` accumulating shared character-stat components** — *(forward-looking; combat/ is currently empty).* The planned HealthComponent / BreathComponent components (plus StaminaComponent, which exists today as a 5-line stub in `colonists/`) are general-purpose character components (used by player/colonists/enemies), not combat-specific. When they land, consider a `core/components/` home if a fourth such component appears.
- [~] **Colony autoload accumulating run-state children** — *(forward-looking; none of the four children exist yet).* Memorial (deceased roster), KeyItemPool (once-per-playthrough enforcement), LoadoutManager (templates + assignments), and DiscoveredGear (item-possession tracking) are all intended to live on Colony because their state must persist across base↔POI scene swaps and be saved. **Resolved (in progress):** the `RunProgress` autoload has been created as the intended home for this run-state, and currently holds buildable unlocks. It is *growing* — additional run-earned state (and the eventual migration of Colony's four children, once they exist) lands here as subsystems come online.
- [ ] **Debug console release-stripping approach undecided** — the console is dev-only and must not ship in release builds. Options: (a) Godot export profile excludes the `debug/` folder, (b) `OS.is_debug_build()` gate around the autoload registration, (c) both. Decide before first export; document here.
- [ ] **Open-world migration path (deferred, forward-looking)** — the MVP uses loadable maps, but a future open-world streaming system is feasible. Full analysis (seams already in our favor + friction points) lives in [`open-world.md`](open-world.md). **Not current work** — recorded here as a tripwire: if `SceneManager`, `Map`, or `BlockyGrid` persistence are refactored, re-check that doc. Cost concentrates in the swap→stream world model and moving per-position runtime state (block HP, furniture, spawns) into chunk-keyed persistence.

## Unimplemented Subsystems

> GDD systems that have a design spec but **no architecture yet**. Each needs a subsystem section (Files + Signals + Flow Traces + Class Reference) before it can be built. Grouped by how much design work remains vs. how much is pure architecture coverage.

### Needs design decisions before architecting

**Companion + Day-1 incapacitated state** — GDD §6.6 + §9
The companion is a special colonist (+20% HP, fixed narrative identity, starts incapacitated in the ruined shelter). The Day-1 forced sequence is: scavenge → craft Clinic Bed → revive companion. **Missing:** no Companion class/subclass on Colonist, no "incapacitated" state machine, no revival flow at the Clinic Bed, no bootstrapping logic that places the companion + ruined shelter at New Game. The `+20% HP` is mentioned only as a parenthetical on Colonist.max_hp.
*Consumers:* §9 Starting Conditions (New Game bootstrap), Clinic Bed (revival interaction), permadeath (companion death is presumably game-relevant).
*Open design questions:* Is the companion a Colonist subclass or a flag? What does "incapacitated" mean mechanically (can't be targeted by enemies? invulnerable? just inactive?)? Does companion death end the game (separate from the all-colonists-dead rule)?

**Recruitment** — GDD §6.9
Two MVP recruitment sources: random world events (stranger at the gate) and radio contacts (via Command Desk). **Missing:** no recruitment subsystem, no event-source architecture (world-event spawner, radio-contact scheduler), no recruitment-event data, no "stranger arrives" notification flow. `Colony.add_colonist()` exists but has no caller.
*Consumers:* Colony roster growth (the path from solo+companion to the MVP cap of 5).
*Open design questions:* How are world events scheduled (timer-based? triggered by colony milestones?)? What does a "radio contact" look like mechanically (player-initiated at the Command Desk, or auto-offered)? Are recruits named or unnamed (ties to B12)?

**Named vs unnamed colonists** — GDD §6.5
Named colonists have backstories + may start with higher skill levels; unnamed are generic. The distinction controls memorial eligibility (per §17 Permadeath, named get entries; unnamed do not — though the GDD also says "permadeath applies equally to named and unnamed"). **Missing:** no `is_named` flag on Colonist, no narrative-identity field, no skill-level-bonus application for named recruits.
*Consumers:* Memorial roster (B1 stub currently appends all deaths equally — should it filter?), recruitment (B10 — are recruits named or unnamed?), Day Summary Fallen section.
*Open design questions:* Does "named vs unnamed" actually affect memorial eligibility, or was the GDD's "named get memorial entries; unnamed do not" superseded by "permadeath applies equally"? The two statements are in tension. Also: what fraction of recruits are named?

### Mostly specced — needs architecture coverage

**Encounter templates** — GDD §5 (MVP Encounter Templates)
Three ready-to-use configs for testing and scavenge missions: Template 1 Basic (2× Brawler), Template 2 Standard (2× Brawler + 1× Shooter), Template 3 Hard (3× Brawler + 2× Shooter). Each specifies enemy composition + positioning. **Missing:** no encounter-definition data file, no spawner that reads them, no link between templates and POI difficulty tiers. (Neither the `spawn_wave` debug command nor a SpawnManager exists yet — both land with the combat/encounter work.)
*Consumers:* Expeditions (scavenge missions need to spawn per-difficulty), playtesting (the templates are explicitly for testing).
*Open design questions:* Are templates the same data structure as raid waves, or separate? (Probably the same — both feed SpawnManager.) How do POI difficulty tiers (Easy/Normal/Hard per §17) map to templates?

**Demolition (as a Job)** — GDD §7.5
Block removal rate = 2× build rate (`tool repair amount × 2 × rate of fire`). Currently only the low-level `BlockyGrid.remove_block_at(pos)` primitive exists. **Missing:** no demolition-as-Job flow (a colonist paths to a marked block and removes it over time), no "mark for demolition" UI/placement, no Job-Board registration of demolition jobs. The player can presumably demolish instantly via build mode, but colonist-driven demolition isn't architected. The cell-targeted Job leg shape it needs (shared with colonist voxel mining/harvesting) is planned in [`job-extensions.md`](job-extensions.md).
*Consumers:* Base reorganization, breach repair (clearing destroyed-block debris).
*Open design questions:* Is demolition player-instant (RMB in build mode) AND colonist-Job (for larger demolitions), or one or the other? Does demolition produce reclaimed materials (partial refund) or just remove?

**Colonist capacity / bed-capping** — GDD §6.8
Max colony size is tied to Colonist Bed count (1 bed = 1 colonist slot; MVP cap 5, hard cap 10). **Missing:** no bed-count → cap enforcement logic, no signal when a bed is built/destroyed (which should raise/lower the cap). A hard-cap gate exists — `Colony.add_colonist` warns and rejects above `MVP_CAP = 5` — but it is a constant, not bed-derived.
*Consumers:* Recruitment (B10 — must check capacity before adding), Colony Management Roster tab (display cap), save system (persist bed count).
*Open design questions:* What happens if a bed is destroyed while a colonist is assigned to it (does the colonist leave? become "homeless"?). Already partially answered by Functional Rooms (bed is functional furniture, count tracked) but the cap-enforcement side isn't.

### Smaller improvements (D-items)

**New-Game reset flow** — GDD §8 (Game Over) + §17 Save — **Partially resolved.**
New game wipes all state including map reveal. `main_menu._start_new_game()` now owns the operation for the systems that exist: `SaveSystem.create_save` (fresh slot + clear `_parked`) → `RunProgress.reset_for_new_game` → `EventBus.run_started` (re-seed) → POI discovery → `SceneManager.wipe_map_cache` (clear `user://maps/`). **Still missing:** Colony's not-yet-shipped children (Memorial, KeyItemPool, LoadoutManager, DiscoveredGear) and anything tied to them — enumerate + zero those as each subsystem comes online.

**Game Over evaluator** — GDD §8
The `game_over()` EventBus signal exists, but nothing checks the "all colonists AND player dead" condition. **Missing:** an evaluator (probably on Colony or a dedicated component) that listens to `colonist_died` + `player_died` and emits `game_over()` when both rosters are empty.

**Structural weak-point targeting** — GDD §17 Raids
Brawlers attack the lowest-HP block in range; Shooters path through the lowest-resistance opening (open gates first, then Scrap blocks, then damaged blocks). **Missing:** the targeting logic / structural-analysis pass that evaluates the perimeter for weak points and is consumed by enemy AI. The low-level primitive it would build on now exists: `BlockyGrid` exposes `get_hp_at` / `has_block_at` / `apply_damage` and the `block_destroyed` signal — so per-block HP querying and damage are available; what's still needed is the perimeter-scoring + AI-consumption layer.

**Travel-time-proportional-to-distance** — GDD §17 Day/Night
"Travel time proportional to POI distance. Longer travel = more time passes = more Stamina drained." **Missing:** the proportional-distance calculation isn't specced (distance metric? time-per-unit-distance?).

**Save serializes voxel world** — ~~flagged in Tech Debt~~ **Resolved.** Zylann's `VoxelStreamSQLite` is reused as the binary terrain layer: SaveSystem snapshots each touched map's `map.sqlite` into the slot and keeps block HP / furniture / blueprints in JSON alongside it. Full design in [Save / Load](save.md) §State model + §Invariants.

**Player input map data file** — GDD §4 has a full key map; ARCH has no corresponding `data/input_map.tres` or similar. **Partially resolved:** player input reading is now centralized in `InputComponent` (`subsystems/player/input_component.gd`), but the action bindings themselves are still defined in `project.godot`'s `[input]` section. A data file would allow runtime rebinding.

### Data schemas still missing (C-items)

These data folders are *referenced* in Files tables but have no formal schema in the Data Schemas section. Low-decision work; mostly mechanical once the owning subsystem is settled:

- [~] **C1** `data/furniture/` — 16 buildables (Clinic Bed, Workbench, Forge, etc.). **Partially resolved:** the `FurnitureDef` class exists with `dimensions` + `action_options` (interaction) + capability params; 8 defs ship today (workbench, instant_workbench, storage_crate, growing_trough, shelf1, tree1, wood_block_dispenser, test_block_furniture_with_interaction). Still missing: the `is_functional` + `functional_area` fields the Functional Rooms subsystem needs to count placed furniture, plus defs for the remaining buildables. **Capability parameters** (crafting speed/tier, etc.) land as nullable sub-resources on `FurnitureDef` (seed: `test_params`), not subclass fields or a free-form dict — full rationale in [Data Schemas](data-schemas.md).
- **C6** `data/tools/` — Hammer, Nailgun (repair value, RoF, range).
- **C7** `data/starting_conditions.tres` — Day-1 resources/equipment/structure (GDD §9). Referenced in Core Files but never schema'd.
- **C8** ~~`data/pois/`~~ — **Resolved.** POI/map definitions now live in `data/maps/<id>/map_def.tres` as `MapDef` resources (schema'd below). `data/pois/` is no longer used.
- **C9** Schemas for already-referenced folders: `data/labors/`, `data/weapons/`, `data/armor/`. **Partially resolved:** `data/labors/` now has `labor_def.gd` + 7 `LaborDef` instances (schema in [Data Schemas](data-schemas.md)); `data/weapons/` + `data/armor/` are still pending (folders don't exist yet).
