# Terrain Mining — Per-Position Material Identity (Rev 2)

Status: planned (2026-08-21). Rev 2 folds in external review: binary sidecar fallback,
identity invariants, strata tuning pivot, metadata-write perf ceiling. Companion notes:
`docs/VOXEL-TOOL-NOTES.md` (F3, F8, F9, F10, F11), `docs/architecture/voxel-world.md`,
`docs/architecture/data-schemas.md`. Repo copy: `terrain_mining/plan.md` (rev 1).

## Goals

1. **Per-position material identity on the smooth terrain.** `SmoothGrid.get_material_at()` stops
   being dead code that returns `default_material` for every solid cell; a dig at depth 30 answers
   "rock", a dig at depth 2 answers "dirt".
2. **A real mining loop.** Depth progression (dirt cap → rock → iron ore → gold ore) driven entirely
   by authored `TerrainMaterialDef` `.tres` files — bands, rarity, veins, HP, yields.
3. **Authored material persists.** Map-editor terrain blobs and structure stamps carry their
   material identity across save/load — today the id rides a signal nobody listens to
   (`material_placed` has zero consumers) and evaporates.
4. **All tunables in data.** Depth bands, vein size, spawn weight, HP, yields, textures live in
   `data/terrain/materials/*.tres` (AGENTS.md rule 1 — no gameplay values in scripts).
5. **Keep zylann.** No custom voxel backend. The one thing it can't do (per-voxel *visuals*) stays
   out of scope; the thing we need (per-voxel *identity*) is achievable without touching it.

## Non-goals (later phases)

- Equipment wiring: wrong-tool penalties / tool-gated HP reduction. The `hp` field lands now; the
  damage-per-swing model and LMB-while-equipped interaction come later and will match on material
  `id`s (decision below).
- Per-voxel painted terrain *visuals* — mesher ceiling (F8/F11). The `texture` field is reserved
  data only.
- Blocky-side mining changes, colonist mining jobs, dig UI material feedback.

## Background & rationale

**Where we start.** F8 established that the smooth terrain's single channel is pure float SDF
density — no material channel exists — so v1 reports one material for the whole map:
`DigAction` reads `grid.default_material` wholesale (`data/actions/dig_action.gd:30,58`), and
`get_material_at` (`subsystems/voxel/smooth_grid.gd:159-171`) is its default-fallback twin with zero
callers. The old design fork ("depth lookup vs second channel vs single material") existed *only*
because of that ceiling.

**Why not write our own voxel system** (decided upstream of this plan): the feature surface we'd
need is smaller than zylann, but the problems are the same hard ones — multithreaded remeshing,
transvoxel seams, server-side collision, sqlite streaming/persistence (F2, F9) — and in GDScript
they'd be frame-budget killers exactly during raids. The identity gap has a much cheaper fix, which
is this plan.

**Why a sidecar built on voxel metadata.** The addon's `VoxelTool` exposes per-voxel
`set/get_voxel_metadata` (verified in the API surface, F8). If metadata persists through
`save_modified_blocks()` into `terrain.sqlite` (probe P1 below), we get authored-material
persistence with **zero new plumbing**: no new addon (the project has no plain-sqlite binding), no
new per-map file, no `Map.stream_dbs()`/SaveSystem/SceneManager changes — metadata rides the block
saves that already work, and the map editor already calls `save_modified_blocks()` after every
sculpt (`tools/map_editor/map_editor.gd:1381-1385`).

**Why natural materials are computed, not stored.** Depth bands, vein size and spawn weight are
*rules*, not per-cell facts anyone authors. Computing them deterministically at query time (seeded
3D noise shaped by the def fields) means: no storage growth, infinite/streaming terrain just works
(strata answers even for unloaded blocks — only the air check needs streamed data), and the same
position answers the same material across saves and reloads forever. The sidecar then only stores
what genuinely is per-cell authored state: painted blobs. `get_material_at` composes:
air → `""`; metadata → authored id; strata → natural id; else `default_material`.

**Why depth is measured from the pristine generated surface.** Current-surface depth is
self-defeating for a mining game: dig 10 deep and the hole's floor is depth 0 again — dirt
re-appears at the bottom of every shaft, ores unreachable. Pristine-surface depth means the deeper
you dig, the deeper the materials (7DtD/Minecraft feel). Cost: replicating the generator's height
formula in GDScript (probe P2).

## Locked decisions (user, 2026-08-21)

| Question | Decision |
| --- | --- |
| Depth basis | **Original generated surface** (stable under digging; surface row = depth 0) |
| "Chance to appear" field | **`spawn_weight: float = 1.0`** — relative weight, any value ≥ 0, normalized across candidates sharing a depth band; 0 = never generates |
| Material type re: mining | **No type field.** Equipment will match the material's `id` for buffs/penalties (identity-is-id is the project convention; `ItemDef.tags` is the escape hatch if id-listing gets tedious) |
| HP vs hardness | **`hp: int = 100` replaces `hardness`** — one concept, forward-compatible with the future tool-damage model; dig time today = `work_time × hp / 100` (dirt 100 keeps today's feel; old hardness 3 ≡ hp 300) |

## Design

New `TerrainMaterialDef` fields (identity/stats only — mesher ceiling unchanged):

| Field | Type | Meaning |
| --- | --- | --- |
| `hp` | `int = 100` | break pool; scales dig time today, tool damage later |
| `min_depth` / `max_depth` | `int` `0` / `0x7FFFFFFF` | inclusive band in voxel rows below the pristine surface |
| `vein_size` | `int = 8` | approx blocks per vein cluster → strata noise wavelength |
| `spawn_weight` | `float = 1.0` | relative frequency within a band, normalized; 0 = never |
| `texture` | `Texture2D = null` | **reserved, not rendered in v1** (F8/F11) — dig-UI feedback / future visuals |

Kept: `id`, `display_name`, `yields: Array[ItemAmount]` (the drop table — the yield field already
existed), `place_radius`, `icon`. Removed: `hardness`.

**`TerrainStrata`** (new, `subsystems/voxel/terrain_strata.gd`, `RefCounted`, pure/headless-testable):
`material_id_at(pos)` = pick from band candidates by per-material coherent 3D noise
(`FastNoiseLite`, seed + index, frequency ≈ `1/vein_size`) biased by normalized weight share
(additive), argmax wins. Coherent noise makes adjacent cells correlate → veins of ≈ `vein_size`;
weights tune the mix. Deterministic heuristic, tunable — documented as such, not exact share math.
Tuning pivot if playtesting shows high-frequency fields fracturing big low-frequency veins: switch
to a single shared noise field partitioned into weight-proportional ranges (clean contiguous
boundaries) — at the cost of one shared vein scale, i.e. losing per-material `vein_size`.

**Resolution order** in `SmoothGrid.get_material_at(pos)` / new `get_material_def_at(pos)`:

```
air (get_voxel_f > 0)      → "" / null
voxel metadata set          → authored/placed material id
strata band + noise         → natural material id
no candidate                → default_material (today's behavior)
```

**Why the two identity sources can't disagree** (load-bearing invariants):

- `_pristine_height` is derived from the *same saved `TerrainGenDef`* the generator consumes —
  when the map editor regenerates terrain from an edited heightmap/seed, def and pristine height
  move together, so strata always describes exactly the ground the generator produces. It can
  never describe editor-painted terrain, because…
- …every smooth terrain add in the codebase routes through `add_material(material_id)` — editor
  sculpts, `SmoothPlacementStrategy`, `StructureStamper` — so non-generated terrain always carries
  authored metadata and depth rules are never consulted for it. A painted mountain is never
  "misread" by depth rules (it sits above the pristine surface anyway: negative depth matches no
  band). Preserve the invariant: no rogue `do_sphere` adds outside `add_material`.

## Implementation steps

### 0. Probes (gate everything) — windowed auto-quit spikes in `testing/zylann/`, F8 style
(headless `--script` instantiation hangs, F11 gotcha)

- **P1 — metadata persistence** (`voxel_metadata_spike.tscn`): terrain + `VoxelStreamSQLite`
  (tmp db) + `VoxelViewer` → sphere edit, `set_voxel_metadata(pos, "rock")` →
  `save_modified_blocks()` + flush → teardown → rebuild from db → `get_voxel_metadata(pos)`.
  Also: what carve leaves behind; Variant/String value shape. → **F12** in VOXEL-TOOL-NOTES.
- **P2 — `VoxelGeneratorNoise2D` height formula**: raycast real columns vs candidate
  `h = height_start + (noise2d(x,z) × 0.5 + 0.5) × height_range` with
  `FastNoiseLite(noise_seed, noise_frequency)`. Needed for pristine height on noise maps (dev);
  heightmap maps (base) sample the def's image directly (reuse `_prepare_heightmap_image` math,
  incl. offset + F10 repeat). → **F13**.

### 1. Schema — `data/terrain/materials/terrain_material_def.gd`
Field changes per table above; rewrite the class docstring (per-position semantics, F8/F11 stay as
the *mesher* ceiling).

### 2. Content
- `ground.tres`: `display_name = "Dirt"`, `hp = 100`, band 0–3, `spawn_weight = 1`,
  `vein_size = 16` (id stays `"ground"` — map template stamping, editor fallback, tests use it).
- New: `rock.tres` (hp 300, band 3–∞, weight 10, vein 60, yields `stone_block ×2`),
  `iron_ore.tres` (hp 400, band 12–∞, weight 2, vein 8, yields `iron_ore ×1`),
  `gold_ore.tres` (hp 400, band 24–∞, weight 1, vein 6, yields `gold_ore ×1`).
- New items `data/items/iron_ore.tres`, `gold_ore.tres` (`ItemDef`; icon null — prototype-art rule).

### 3. `TerrainStrata` — new `subsystems/voxel/terrain_strata.gd`
Per Design above. `setup(materials, seed, pristine_height: Callable)` — composition, no `_init`.

### 4. `SmoothGrid` — `subsystems/voxel/smooth_grid.gd`
- `add_material`: after `do_sphere`, write `set_voxel_metadata(p, material_id)` for every solid
  voxel in the sphere's integer bbox (≈65 voxels at r 2.5). Editor sculpts,
  `SmoothPlacementStrategy`, `StructureStamper` inherit persistence free — they all call this.
  Perf ceiling (review): the editor brush is clamped to r 5.0 (~523 voxels) today, so the
  GDScript bbox pass stays trivial; revisit only if brush maxes grow — this build exposes no bulk
  metadata setter. This method is also the single choke point for smooth adds (invariant above).
- `carve`: unchanged (the air check makes stale metadata harmless; P1 decides whether a proactive
  bbox clear is worth it for tidiness).
- `get_material_at` real per Design; new `get_material_def_at(pos) -> TerrainMaterialDef`
  (null for air) — what DigAction consumes.
- Catalog injection — voxel subsystem must not call `BuildLibrary` (no precedent, wrong layering):
  `set_material_catalog(materials: Array)` builds the strata; wired where `terrain_gen` already
  flows — `SceneManager` swap (`subsystems/autoloads/scene_manager.gd:69-75`, source
  `BuildLibrary.get_terrain_materials()`) and map editor `_inject_terrain_gen`
  (`tools/map_editor/map_editor.gd:1063`). No injection → empty catalog → natural ground answers
  `default_material` (back-compat).
- `_pristine_height(x, z)` + never-evicted cache (pristine never changes; bounded by visited
  columns like `_height_cache`).

### 5. `DigAction` — `data/actions/dig_action.gd`
- `begin` + `_apply` switch from `default_material` to `get_material_def_at(center.round())`.
- **Ordering trap:** `_apply` must read the def *before* `grid.carve(...)` — after the carve the
  center is air.
- Duration `work_time × hp / 100.0` (const `HP_SCALE := 100.0`); mining-skill multiplier unchanged.
- `Doubles.RecordingSmoothGrid` (test/helpers/doubles.gd): add configurable `get_material_def_at`.

### 6. Docs (with code; `mkdocs build --strict` must pass)
`data-schemas.md` (TerrainMaterialDef rewrite), `voxel-world.md` (SmoothGrid reference: real
`get_material_at`, strata + catalog injection + pristine height, add_material persists identity),
`build.md` (dig flow: per-position material, hp formula), `map-editor.md` (painted blobs now carry
persistent identity), `VOXEL-TOOL-NOTES.md` (F12, F13, TL;DR rule 7 addendum), `docs/TODO.md`
Phase 5 note; sync `terrain_mining/plan.md` to this rev.

### 7. Tests
- New `test/suite_terrain_strata_test.gd`: band gating (depth 1 → dirt only; depth 30 → no dirt),
  determinism, `spawn_weight = 0` never appears, statistical mix at depth 30 (rock > iron > gold,
  ~2000 samples), vein coherence (adjacent positions same-material more often than distant ones),
  empty catalog → `""`.
- `test/suite_mining_test.gd`: hp-based duration; yields come from the def **at the dig position**
  (via double), not `default_material`.
- `suite_smooth_grid_test.gd`, `suite_map_editor_test.gd`, `suite_smooth_placement_test.gd`:
  hardness → hp adjustments; keep green.
- Constraint: gdUnit can't stream-write voxels without a viewer (F3) — metadata round-trip stays a
  spike unless P1 shows a viewer works inside a suite; strata/mining logic is pure and suite-tested.

## Risks & fallbacks

- **P1 fails (metadata doesn't persist):** fallback = per-map binary sidecar
  `data/maps/<id>/terrain_materials.bin` written with `FileAccess.store_var()` (native Variant
  serialization — real `Vector3i` keys, none of JSON's string-key bloat on heavily-modified maps);
  SceneManager copy-on-load hook; append filename to `Map.stream_dbs()`
  (`subsystems/voxel/map.gd:49-55`) so SaveSystem snapshot/restore covers it automatically
  (journal quiescing F9 is sqlite-specific and not needed for the binary file). Build only if the
  probe fails.
- **P2 formula mismatch:** fall back to capturing pristine height on first `height_at` query per
  column (documented caveat: columns first queried after a nearby dig may read slightly low).
- **Behavior change, accepted:** deep digs that used to yield ground now yield rock/ore — that is
  the feature. No save migration: `terrain.sqlite` schema unchanged, metadata is additive.
- **Cost profile:** strata = a few FastNoiseLite samples per query (cheap; pristine height cached);
  metadata writes = one bbox pass per sculpt/stamp. Neither touches the hot path (remesh stays C++).

## Verification & commits

Order: P1/P2 spikes (+F12/F13) → schema + content → TerrainStrata + suite → SmoothGrid + DigAction
+ suites → docs → full run `addons/gdUnit4/runtest.sh`, tally in the commit body.

1. `feat(voxel): per-position terrain materials via voxel metadata and depth strata`
2. `feat(data): rock, iron and gold terrain materials with depth bands and ore items`

## Follow-ups (future phases, not this plan)

- Equipment gating: tool damage per swing vs `hp`, id-matched buffs/penalties, LMB-while-equipped.
- Dig UI feedback showing the material being hit (uses the reserved `texture`).
- Per-material terrain visuals — only via a custom/forked mesher; revisit if it ever becomes a
  hard requirement.

## As-built outcomes (2026-08-21, implementation)

Implemented on top of savepoint commits `52f06cb..13da92e`. Verdicts and deviations:

- **P1/F12 — metadata persistence is one-entry-per-block, not per-voxel.** The
  spike (`testing/zylann/voxel_metadata_spike.tscn`, 7 runs) proved only the
  LOWEST-position entry per 16^3 block survives `save_modified_blocks()`
  (set order irrelevant). As-built sidecar: ONE Dictionary per block, anchored
  at the block origin (nothing in a block can outrank the origin), holding
  `{Vector3i pos: String material_id}`; `add_material` read-modify-writes one
  dict per touched block. The plan's per-voxel String tags would have silently
  lost N-1 entries per block — the binary-file fallback was NOT needed.
  Also pinned: `mesh_block_size` = 16 (runtime property), carve leaves stale
  entries in air (readers air-check first), Variant values round-trip.
- **P2/F13 — noise formula exact** (`start + (n×0.5+0.5)×range`, MAE 0.005);
  **heightmap formula verified** too (`pixel(x + size/2)` wrapped, MAE 0.004 —
  offset sign indistinguishable from minus since they coincide mod size).
- **Strata scoring is a softmax, not additive/multiplicative.** Additive
  noise + weight-share degenerates (a 10:2:1 bias dominates [0,1] noise —
  heaviest material wins every cell, seed-invariant); multiplicative
  argmax(n×w) needs noise RATIO > weight ratio, impossible for 10:1 with
  OpenSimplex2's practical ±0.5 range. As-built:
  `argmax(log(spawn_weight) + 4.0 × n)` with `n = clamp(raw + 0.5)` — a 10:1
  upset needs only a ~0.57 noise gap; the long-run mix tracks the weights
  (measured 87/11/2.5 for the 10:2:1 fixture band).
- **Tests: 360/360 green** (from a 351 baseline; +8 `suite_terrain_strata_test`,
  +1 per-position yields case in `suite_mining_test`; the map-editor cycling
  test's catalog fixture made hermetic — the shipped rock/iron/gold defs
  changed the cycle count).
- Shipped bands: ground (dirt) 0-3, rock 3+ (w10, province-scale vein 60),
  iron_ore 12+ (w2), gold_ore 24+ (w1); hp 100/300/400/400; ore items added to
  `data/items/`. Equipment-gated HP damage, dig-UI texture feedback, and
  per-material visuals remain future phases (unchanged).
