# Mining

Digging the natural (smooth) terrain yields **position-dependent materials** — a dirt cap, a rock body, iron and gold veins — driven entirely by authored `TerrainMaterialDef` defs in `data/terrain/materials/`. This page consolidates the feature; it is deliberately **not a subsystem** (see [Future work](#future-work-and-when-mining-becomes-a-subsystem)).

> **Design notes**
> - The mesher has no material API (F8/F11) and its per-voxel texturing system is verified non-functional (F14) — so visuals are **indirect**: a terrain shader bands the two band endpoints' triplanar textures by depth (F11 shader rules), and authored blobs each get a Decal marker tinted `TerrainMaterialDef.color`. Material *identity* lives outside the renderer — a per-block voxel-metadata sidecar for authored blobs (F12) and deterministic depth rules for natural ground (F13). See `docs/VOXEL-TOOL-NOTES.md`.
> - Equipment gating (planned) matches on the material's **`id`** — no type enum. Identity-is-id is the project's def convention; `ItemDef.tags` is the escape hatch if id-listing ever gets tedious.
> - `hp` is one concept for two eras: today it scales dig duration (`work_time × hp / 100`); the future tool-damage model consumes the same pool per swing.

## Files

| File | Type | Responsibility |
|---|---|---|
| `subsystems/voxel/smooth_grid.gd` | Script | Identity representation: F12 sidecar writes/reads, `get_material_at` / `get_material_def_at` resolution chain, `set_material_catalog` injection, `_pristine_height` (the F13 generator mirror). Also the visuals: terrain shader + height bake on `material_override`, Decal markers for authored blobs. |
| `subsystems/voxel/terrain_strata.gd` | Script (RefCounted) | Deterministic natural-material selection: depth band + per-material coherent noise in a softmax with `spawn_weight`. No storage. |
| `assets/terrain/terrain_shader.gdshader` | Shader | The one terrain look (F11/F14): triplanar ground/rock textures blended by depth below the pristine surface. Placeholder textures from `tools/terrain_texture_generator.gd`. |
| `data/terrain/materials/*.tres` | Data | `TerrainMaterialDef` content: `ground` (dirt, band 0–3), `rock` (3+, weight 10, province-scale veins), `iron_ore` (12+), `gold_ore` (24+); `color` tints markers, band endpoints carry `texture`. |
| `data/actions/dig_action.gd` | Script | The timed dig interaction: resolve-before-carve, hp-scaled gauge, yields to the digger's inventory, mining skill use. Trigger-agnostic `begin()` — the equipped-tool LMB later reuses it. |
| `data/mining/dig_tool.tres` (`dig_tool_params.gd`) | Data | `DigToolParams`: `work_time`, `carve_radius`. Preloaded as `BuildLibrary.DIG_TOOL`. |
| `data/items/iron_ore.tres`, `data/items/gold_ore.tres` | Data | Ore drops (`ItemDef`). |
| `subsystems/build/build_controller.gd` | Script | Tool routing: the `BuildLibrary.DIG_ID` sentinel, dig ghost, `_try_dig()`. |
| `testing/zylann/voxel_metadata_spike.tscn`, `testing/zylann/voxel_texturing_spike.tscn` | Scenes (editor-run) | The F12/F13 and F14 probes. The texturing spike is the harness to re-run if a future addon bump should ever revive per-voxel texturing. |
| `test/suite_terrain_strata_test.gd`, `test/suite_mining_test.gd`, `test/suite_terrain_visuals_test.gd` | Tests | Bands, determinism, seed sensitivity, weight mix, vein coherence; per-position yields; band picks, tint fallbacks, marker math. |

## Identity model: what material is this position?

`SmoothGrid.get_material_at(pos)` resolves in strict order:

1. **Air** (`get_voxel_f > 0`) → `""`. Always checked first — carved cells keep stale sidecar entries (F12), and an air-checkless reader would resurrect material out of holes.
2. **Authored sidecar** → the F12 per-block Dictionary (anchored at the 16³ block origin, riding `terrain.sqlite` with the normal block saves). Every smooth add routes through `SmoothGrid.add_material(material_id)` — editor sculpts, `SmoothPlacementStrategy`, `StructureStamper` — so non-generated terrain always carries authored identity.
3. **Strata** → `TerrainStrata.material_id_at`: depth below the **pristine generated surface** (surface row = 0, stable under digging — F13's closed form mirrors the generator), filtered by `min_depth`/`max_depth` bands, scored `argmax(log(spawn_weight) + 4·noise)` over per-material coherent noise at wavelength `vein_size`. Deterministic: same position + seed answers the same material forever — which is why strata needs no storage and survives streaming, saves and reloads.
4. **Fallback** → `default_material` (maps without an injected catalog behave exactly pre-mining).

Two load-bearing invariants keep the sources from disagreeing: `_pristine_height` reads the *same saved `TerrainGenDef`* the generator consumes (editor regeneration moves both in lockstep), and `add_material` is the *only* smooth-add path (no rogue `do_sphere` adds — a painted mound sits above the pristine surface and matches no band anyway).

## Flow Trace: player digs

1. **B** opens the build menu; the **Dig** entry (`BuildLibrary.DIG_ID` sentinel, not a `BuildableDef`) arms dig mode.
2. `_physics_process` raycasts; a smooth-surface hit shows the green sphere ghost of exactly the carve volume (half a radius sunk so it bites a bowl).
3. **LMB** → `BuildController._try_dig()` → `DigAction.begin(actor, grid, center, BuildLibrary.DIG_TOOL)`.
4. The gauge duration is `work_time × hp(at center) / 100 ÷ mining-skill multiplier`; the label reads **"Digging <display_name>"** from the def at the dig position — the in-game oracle for the whole chain.
5. On completion `_apply` resolves the def **before** carving (after the carve the center is air), carves the sphere, grants the def's `yields` to the digger's pocket inventory, and records a `mining` skill use.
6. A cancelled dig banks nothing (v1 semantics — no partial-HP state on smooth terrain).

## Visuals: how a material becomes visible

The renderer can't carry material identity (F8/F14), so looks are indirect and ride the identity system:

- **Natural terrain** — `SmoothGrid._apply_visuals` puts one `ShaderMaterial` (`assets/terrain/terrain_shader.gdshader`) on `VoxelTerrain.material_override` (F11). The shader blends the two **band endpoints**' triplanar textures by depth below the pristine surface: `_pick_band_materials` picks the surface material (smallest `min_depth`) and the dominant deep material (highest `spawn_weight` starting at/below the surface material's `max_depth`) — today `ground` → `rock`, so the world reads dirt-over-stone exactly where the strata say it is. The depth basis is a 512² RF height bake written from `_pristine_height` (same F13 math as strata, no per-column cache).
- **Authored blobs** — every smooth add through `add_material` spawns one **Decal** per (block, material), a radial disc tinted the def's `color` (iron rust, gold yellow), reconstructed from the F12 sidecar as blocks load — so markers survive reloads with zero extra save state. The surface material skips marking (its blobs match the terrain's own top band).
- **Known limits (v1):** a marker goes stale if its blob is fully carved away, markers are projectors (a cap may be wanted for heavy editor painting), and the height bake repeats past ±256 m — far terrain band drift only.

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `material_placed(pos: Vector3, material_id: String)` | `smooth_grid.gd` | (none yet — future sound/particles hook; persistence is the sidecar's job, not the signal's) | No | Smooth placement, editor sculpt, structure stamp |
| `material_carved(pos: Vector3)` | `smooth_grid.gd` | (none yet — future dig feedback hook) | No | Dig completion |

## Authoring & verification

- All tunables live in the defs — see [Data Schemas](data-schemas.md) `TerrainMaterialDef` row (hp, depth band, vein_size, spawn_weight, `color`, band `texture`) and `DigToolParams`. Note `rock`'s `vein_size` 60 is province-scale on purpose; minority ores occur as contiguous veins via the softmax scoring.
- The map editor's Terrain mode cycles materials with **M**; sculpted blobs carry the id persistently and show their colored marker immediately (see [Map Editor](map-editor.md)).
- The generator pipeline that produces the ground mining digs into is documented in [Voxel World](voxel-world.md) "Terrain generation when a map opens".
- Manual test recipe and the design history live in `terrain_mining/plan.md`; addon-behavior facts in `docs/VOXEL-TOOL-NOTES.md` (F12, F13, F14).

## Future work — and when mining becomes a subsystem

Mining is currently a **feature woven through three homes, each correct**: representation in `subsystems/voxel/` (hard rule 2 isolates `voxel_tool` there; strata is grid representation), the interaction in `data/actions/` (the GameAction pattern — same home as harvesting), tool routing in `subsystems/build/`. It owns no state, no autoload, no loop — nothing subsystem-shaped.

Planned additions: **equipment gating** (tool damage per swing against `hp`, id-matched buffs/penalties, wrong-tool penalties, LMB-while-equipped trigger — `DigAction.begin` already accepts any actor/tool), **colonist mining jobs**, and **ore processing/smelting**. Visual upgrades that would need the renderer (per-voxel textures, dig-UI texture feedback) wait on a working mesher — re-run `testing/zylann/voxel_texturing_spike.tscn` on any addon bump (F14).

**Promotion threshold:** when the job/processing work lands — code with its own state and loops — a `subsystems/mining/` folder is created for it. `dig_action.gd` stays with the actions (trigger-agnostic by design), and representation stays in voxel; the move is additive, not a migration.
