# TODO — Vek: Holdout

Master register of unimplemented systems, deferred work, and known gaps.
Consolidates ARCHITECTURE.md's "Unimplemented Subsystems", "Known Tech Debt",
and missing data schemas, plus implementation decisions and gaps surfaced during
build-out. Reference ARCH for spec detail; this file tracks *what's left*.

Last updated: 2026-08-17

---

## Dual-voxel conversion — smooth terrain + blocky structures (2026-08-17)

Natural ground becomes a smooth zylann terrain (`VoxelMesherTransvoxel`,
diggable + placeable — a full gameplay surface); player structures stay on the
blocky terrain (`VoxelMesherBlocky`). Two `VoxelTerrain` nodes per map,
separated by collision layers. Feasibility is proven by the runtime spike
(`testing/zylann/smooth_terrain_spike.tscn`, verdict F7 in
`docs/VOXEL-TOOL-NOTES.md`). Condensed from the working plan in `tmp/`
(gitignored); this section is the in-repo plan of record.

### Decisions locked (2026-08-17) — do not re-litigate without explicit reason

- **D1 Mirrored grids.** `voxel_grid.gd` evolves into `blocky_grid.gd`; a
  sibling `smooth_grid.gd` mirrors its public surface (`get_block_at` ↔
  `get_material_at`, `set/remove_block_at` ↔ `add_material/carve`, `height_at`
  both, mirrored signals). Both are the only touchers of `voxel_tool` (hard
  rule 2). Blocky keeps per-block HP; smooth has none in v1.
- **D2 Smooth terrain is editable.** Mining digs (sphere carve via
  `VoxelTool.do_sphere`); players place smooth materials (dirt/rock). Edits
  persist via a second sqlite stream (`terrain.sqlite` beside `map.sqlite`) —
  stream-saved blocks override the generator.
- **D3 Collision layers.** 1 World (furniture statics, unchanged), 2
  TerrainBlocky, 3 TerrainSmooth (reserved until Phase 2), 4 Player, 5 Build,
  6 Colonist. Body + spring-arm masks 7; the build/deconstruct ray mask is
  1|2|16 now and 1|2|4|16 once smooth exists. Multi-terrain hit
  disambiguation is a `surface` tag on the ray result — never terrain-only
  masking (deconstruct depends on hitting furniture/blueprint BuildBody boxes).
- **D4 Hybrid walkability.** Today's blocky column predicate OR smooth-column
  stand cells from a cached heightfield (slope gate ≤ 45°); the A* step model
  is unchanged. All smooth writes evict cached columns synchronously; both
  invariants (no-regression, edits-keep-pathing-honest) get gdUnit suites.
- **D5 `VoxelTerrain` first.** Plain terrain node for the conversion;
  `VoxelLodTerrain` is a Phase 6 perf trial isolated to the smooth grid.

### Phases

- [x] **1 Foundations** (single-terrain world, no gameplay-visible change):
      atomic collision-layer remap + explicit masks everywhere; `height_at`
      ground query on the blocky grid (via `IBlockGrid`); injectable
      ground-probe seam in `MapWiring._compose_walkability`.
- [x] **2 Mirrored grids + editable smooth terrain**: `blocky_grid.gd` rename
      (consumers updated, no behavior change); extended spike proving carve/add
      + sqlite-override semantics + material representation + block-loaded
      signal names (record as F8); `data/terrain/` schema + `map_def.terrain_gen`
      (null → no smooth grid at all); `smooth_grid.gd`; map template gains the
      smooth node + second stream slot; paint tool binds the blocky terrain
      only; dev map with generator hills overlapping the blocky plate. Done —
      F8 recorded (carve/add + sqlite override + no material API + signal
      names); dev map smoke: 421 smooth-first / 20 blocky-first columns.
- [ ] **3 Gameplay reads on smooth ground**: walkability smooth source wired
      into the seam; pathfinder stand-cell fallbacks; combined
      TerrainBlocky|TerrainSmooth spawn ground query; build support on slopes;
      D4 invariant regression suites.
- [ ] **4 Two-stream persistence**: one shared helper over the two optional
      streams, applied at the four single-`map.sqlite` sites (paint stamp,
      SceneManager redirect, SaveSystem park flush, slot snapshot/restore).
      `map.sqlite` keeps its name.
- [ ] **5 Player-facing editing**: mining dig mode (yields via the harvesting
      pattern) + smooth placement mode (add-sphere, blob ghost) through the
      existing placement-strategy shape; HUD/UX respects `UiGate`.
- [ ] **6 Perf & docs**: `VoxelLodTerrain` trial, viewer/collision tuning,
      height-cache soak, HOWTO + arch sweep.

Standing gotchas: F5 (editor viewport cannot render Transvoxel — no in-editor
smooth authoring), F7 (terrains pinned at origin; layer and mask must move
together; smooth normals are non-axis), `PackedScene.pack()` drops
GDExtension properties (template text-patch pattern) — see
`docs/VOXEL-TOOL-NOTES.md`.

---

## Core subsystem — skeleton scope (next implementation pass)

Build the structural skeleton so the architecture is loadable + testable. Real
bodies for GameState/TimeSystem; stubs with real APIs for the rest.

- [ ] **Data:** `data/game_config.gd` + `data/game_config.tres` (gravity, target_fps, loop_length_minutes, max_enemies_on_screen — ARCH lines 1733–1736). Use the `uid://` `_custom_type_script` form.
- [ ] **Autoload `event_bus.gd`** — declare the full 11-signal registry (ARCH lines 97–107); no state, relay only.
- [ ] **Autoload `game_state.gd`** — properties (current_day, current_scene_id, paused, save_slot), signals (day_changed, scene_changed, pause_state_changed, save_slot_changed), `set_paused()` (toggles process_mode on sim nodes), `advance_day()`. Add `set_scene_id()` (gap — see "Known gaps").
- [ ] **Autoload `time_system.gd`** — continuous advance (loop_length_minutes from game_config), midnight → `GameState.advance_day()` + emit `day_rolled_over`, `advance_to_midnight()` for sleep.
- [ ] **Autoload `scene_manager.gd`** — stub: real API (`swap_world`, `open_screen`, `close_screen`), bodies are TODOs + `push_warning`.
- [ ] **Autoload `save_system.gd`** — stub: real API (`save_game`, `load_game`, `list_saves`, `has_save`, `create_save`), bodies TODO. Wire `day_rolled_over` listener even though body is stub.
- [ ] **Autoload `colony.gd`** — stub only (belongs to Colonists subsystem); exists so autoload table is complete.
- [ ] **`core/main.tscn` + `main.gd`** — CanvasLayer(10) HUD slot, CanvasLayer(20) UI slot, WorldRoot placeholder. Thin script, no gameplay logic.
- [ ] **`core/boot.tscn` + `boot.gd`** — project entry; instances main.tscn, (TODO) opens Main Menu.
- [ ] **Register autoloads** in `project.godot` `[autoload]` (order: GameState, EventBus, SceneManager, SaveSystem, Colony, TimeSystem).
- [ ] **Set `run/main_scene`** to `boot.tscn` (currently points at the player test scene).
- [ ] **Pause wiring** — Esc → `GameState.set_paused(true)`. Reconcile with Player's existing Esc handler.
- [ ] **Test scene** `testing/core/core_test.tscn` — instances main.tscn, drops player in WorldRoot, on-screen label shows day + paused state, key to force midnight.

---

## Decisions locked (2026-07-28, Core planning)

Do not re-litigate without explicit reason.

- **Core scope:** skeleton + stubs. Real bodies for GameState/TimeSystem; stub APIs elsewhere. No UI content scenes this pass.
- **Boot vs Main (resolves ARCH Tech Debt line 147):** `boot.tscn` is the project entry point and loads `main.tscn` + opens Main Menu on the UI layer. Matches ARCH Scene Tree line 69.
- **SaveSystem format:** deferred. Stub only; no JSON-vs-binary commitment until voxel-world save integration is decided (Tech Debt line 206).

---

## Unimplemented subsystems (need design or architecture coverage)

### Needs design decisions before architecting

- [ ] **Companion + Day-1 incapacitated state** (GDD §6.6 + §9) — no Companion class/subclass on ColonistBase, no "incapacitated" state machine, no revival flow at Clinic Bed, no New-Game bootstrap placing companion + ruined shelter. `+20% HP` only a parenthetical on ColonistBase.max_hp.
  - *Open Q:* companion = ColonistBase subclass or flag? What does "incapacitated" mean mechanically? Does companion death end the game?
- [ ] **Recruitment** (GDD §6.9) — no recruitment subsystem, no event-source architecture (world-event spawner, radio-contact scheduler), no recruitment-event data, no "stranger arrives" flow. `Colony.add_colonist()` has no caller.
  - *Open Q:* how are world events scheduled? Radio contact = player-initiated or auto-offered? Are recruits named or unnamed?
- [ ] **Named vs unnamed colonists** (GDD §6.5) — no `is_named` flag on ColonistBase, no narrative-identity field, no skill-level bonus for named recruits.
  - *Open Q:* does named/unnamed actually affect memorial eligibility? GDD's two statements are in tension ("named get entries" vs "permadeath applies equally").

### Mostly specced — needs architecture coverage

- [ ] **Crop Irrigation Tier 2 (Water Physics & Automation)** — Voxel hydration, trench/aqueduct water flow, or piped sprinkler network to automate soil hydration without manual colonist watering. Requires voxel fluid/water simulation pass.
- [ ] **Encounter templates** (GDD §5) — no encounter-definition data file, no spawner reading them, no link to POI difficulty tiers. Three templates specced: Basic (2× Brawler), Standard (2× Brawler + 1× Shooter), Hard (3× Brawler + 2× Shooter).
  - *Open Q:* are templates the same data structure as raid waves (probably — both feed SpawnManager)? How do POI difficulty tiers map to templates?
- [ ] **Demolition as a Job** (GDD §7.5) — only the low-level `BlockyGrid.remove_block_at()` exists. No demolition-as-Job flow, no "mark for demolition" UI, no Job-Board registration. Removal rate = 2× build rate.
  - *Open Q:* player-instant AND colonist-Job, or one or the other? Does demolition refund materials?
- [ ] **Colonist capacity / bed-capping** (GDD §6.8) — no bed-count → cap enforcement, `Colony.add_colonist` doesn't check capacity, no signal on bed built/destroyed. MVP cap 5, hard cap 10.
  - *Open Q:* what happens if a bed is destroyed while a colonist is assigned?

---

## Smaller improvements (D-items)

- [ ] **New-Game reset flow** (GDD §8 + §17) — no reset class/flow owns "clear everything for a fresh run". Enumerate all run-state (GameState, Colony + 4 children, voxel world, map reveal, inventories, skills, loadouts, raid stances) and zero it.
- [ ] **Game Over evaluator** (GDD §8) — nothing checks "all colonists AND player dead". Evaluator (on Colony or a component) listens to `colonist_died` + `player_died`, emits `game_over()` when both rosters empty.
- [ ] **Structural weak-point targeting** (GDD §17 Raids) — Brawlers attack lowest-HP block in range; Shooters path through lowest-resistance opening (gates → Scrap → damaged). No targeting logic; only `block_destroyed` signal exists. Needs structural-analysis pass for enemy AI.
- [ ] **Travel-time-proportional-to-distance** (GDD §17 Day/Night) — "longer travel = more time = more Stamina drained" but the proportional calc isn't specced (distance metric? time-per-unit-distance?).
- [ ] **Save serializes voxel world** (Tech Debt line 206) — Zylann's `voxel_tool` has its own save format; integration with game save slots needs design. Elevate to a real decision before SaveSystem is built.
- [ ] **Player input map data file** (GDD §4) — ARCH has no `data/input_map.tres`. Minor — could be hardcoded in Godot's InputMap at project level, but GDD implies it's data.

---

## Missing data schemas (C-items)

Data folders *referenced* in Files tables but with no formal schema in the Data
Schemas section. Mostly mechanical once the owning subsystem settles.

- [ ] **C1** `data/furniture/` — 16 buildables (Clinic Bed, Workbench, Forge, etc.). Needs `is_functional` + `functional_area` fields (Functional Rooms subsystem).
- [ ] **C6** `data/tools/` — Hammer, Nailgun (repair value, RoF, range).
- [ ] **C7** `data/starting_conditions.tres` — Day-1 resources/equipment/structure (GDD §9). Referenced in Core Files, never schema'd.
- [ ] **C8** `data/pois/` — POI definitions (1 for MVP). Referenced in Expeditions Files.
- [ ] **C9** Schemas for already-referenced folders: `data/labors/`, `data/weapons/`, `data/armor/`.

---

## Core deferred items (from skeleton pass)

- [ ] SaveSystem bodies + save-file format (depends on voxel-world save decision above).
- [ ] SceneManager bodies — real base↔POI WorldRoot swap + layer-20 UI screen management.
- [ ] Colony logic — roster + Job Board (Colonists subsystem owns this).
- [ ] UI scenes: Main Menu, Pause Menu, Day Summary (UI subsystem). Main Menu items: New Game / Continue / Load / Settings / Quit (GDD §12 line 964).
- [ ] Continuous time-of-day value / clock (unspecified — ARCH has no field; game_config has only `loop_length_minutes`).
- [ ] Sleep flow — bed interaction → midnight → save → Day Summary (needs bed + Day Summary scene).
- [ ] **Player Esc-handler reconciliation** — `player.gd` currently releases the mouse cursor on Esc; once Core owns pause, route Esc through GameState and make Player defer.

---

## Open ARCH Tech Debt (all subsystems)

- [x] **Boot vs Main scene strategy** (line 147) — **resolved:** boot.tscn loads Main + Menu. Update ARCH line 147 when implemented.
- [ ] **voxel_tool raycast reliability** (line 148) — `VoxelTool.raycast()` unreliable; workaround uses Godot physics raycast against voxel collision bodies (see `gotchas/voxel_tool_raycast.md`). Validate when build mode lands.
- [ ] **Colonist pathfinding split** (line 149) — A* on voxel grid for colonists, NavigationAgent for enemies. Two pathfinding systems; validate the split pays off vs NavAgent-for-everything once both prototyped.
- [ ] **`combat/` accumulating shared character-stat components** (line 150) — HealthComponent/BreathComponent/StaminaComponent live in `combat/` but are general-purpose. Consider `core/components/` home if a fourth such component appears.
- [ ] **Colony autoload accumulating run-state children** (line 151) — Memorial, KeyItemPool, LoadoutManager, DiscoveredGear all on Colony (4 children). Consider dedicated `RunProgress` autoload before adding a fifth.
- [ ] **Debug console release-stripping** (line 152) — decide before first export: (a) export profile excludes `debug/`, (b) `OS.is_debug_build()` gate, (c) both.

---

## Known gaps (ARCHITECTURE.md inconsistencies to resolve)

- **No Class Reference sections** for SceneManager, SaveSystem, TimeSystem, EventBus — only responsibility prose + emitted/listened signals. Public methods mostly undocumented (only `SceneManager.open_screen()` and `TimeSystem.advance_to_midnight()` appear in flow traces).
- **`game_over()` emitter mismatch** — EventBus registry (line 105) credits GameState as emitter, but GameState's class-reference signals table (lines 294–301) does not list it. Reconcile.
- **GameState "time-of-day" stale entry** — autoloads table (line 79) says GameState owns time-of-day, but the class reference (lines 285–292) has no such property. Time-of-day lives in TimeSystem (or nowhere).
- **`current_scene_id` has no documented setter** — `scene_changed` fires on "SceneManager swap completed" (line 299) but no GameState function writes it. Skeleton adds `set_scene_id()`; document in ARCH.
- **`starting_conditions.tres` has no schema** (C7, line 217) — Core Files table says "See Data Schema" but none exists.
