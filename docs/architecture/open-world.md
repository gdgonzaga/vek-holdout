# Open-World Migration Notes

A forward-looking, non-binding analysis of what an MVP→open-world transition
would cost. This is **not** a current design or a planned feature — it records
the seams already in our favor and the friction points to expect, so the
context isn't lost once the MVP map system ships.

> Scope: feasibility only. No implementation work is implied or scheduled.

## Verdict

Feasible. The engine layer is ready; the cost is concentrated in the top-level
world/session model (loadable map → streaming world) and in moving per-position
runtime state out of scene nodes and an in-memory dictionary into chunk-keyed
persistence. A meaningful refactor of `SceneManager`, `Map`, and `VoxelGrid`'s
persistence — not a rewrite — but real work, correctly deferred past MVP.

## What's Already in Our Favor

| Asset | Where | Why it matters |
|---|---|---|
| `IBlockGrid` interface | `build/i_block_grd.gd` (see [Voxel/World](voxel-world.md)) | Build and gameplay talk to the interface, not `voxel_tool` directly. The voxel *backend* can be swapped without rewiring gameplay. The single most important seam for open-world. |
| Global `BlockLibrary` | `block_library.gd` | Block definitions are not per-map — they carry over unchanged. |
| `VoxelGeneratorFlat` base terrain | `map.tscn` | voxel_tool's `VoxelGenerator` family is exactly the mechanism open-world games use (noise generators → infinite terrain). The tech stack supports it natively; we already use it for the base colony. |
| Persistent Player reparent + VoxelViewer reuse | `MapWiring.wire_player` ([Maps](maps.md)) | The Player already survives transitions and the viewer doesn't stack on repeated swaps. |

voxel_tool (Zylann) also natively supports chunk paging and LOD streaming for
large/infinite worlds. The plugin is not the blocker.

## Friction Points (the real cost)

Every item below maps to a well-understood voxel-game pattern. None are dead
ends; all are deferred work.

### 1. World/session model: swap vs. stream

Today `Map` is the current world node and `SceneManager.swap_map()` loads/unloads
entire scenes (see [Voxel/World](voxel-world.md), [Maps](maps.md)).
`EventBus` carries `map_loading` / `map_loaded` / `map_unloading`.

Open world is the inverse: **one persistent world that streams chunks in/out
around the viewer.** The swap lifecycle and its signals would need to become
"chunk region" events, not whole-map events. This is the largest conceptual
change.

### 2. Containers are children of the current Map

Colonists, enemies, and furniture parent into Map-owned containers
(`colonist_container`, `enemy_container`, `furniture_container` — see
[Voxel/World](voxel-world.md)). In an open world they'd need a
persistent world root plus spatial activation/deactivation — not "loaded with
the map." Furniture isolation today is per-scene authored markers; that authoring
model doesn't extend to a continuous world.

### 3. Block HP is an in-memory, per-VoxelGrid Dictionary

`VoxelGrid._hp_by_pos` (`Vector3i -> int`) works for MVP but grows unbounded and
doesn't survive area unload (see [Voxel/World](voxel-world.md)).
Open world needs block HP **chunk-keyed and persisted** — ideally into/alongside
the voxel stream so damage survives paging out and back in.

### 4. Furniture is stored as scene markers, not spatial data

Authored POIs accumulate `Furniture_*` Marker3Ds under `SpawnPoints`
(see [Maps](maps.md)). An open world needs furniture keyed by
**world position in a spatial store**, not authored `.tscn` nodes.

### 5. Spawn model is authored points

`SpawnHelpers.read_spawns` reads authored `Marker3D`s. Open world spawns
**dynamically** by region/biome/density, not authored points.

### 6. Copy-on-load sqlite pattern assumes a bounded world

`SceneManager` copies each map's `map.sqlite` to `user://` at runtime to preserve
authored data (see [Maps](maps.md)). A huge open world wouldn't copy
wholesale — it would **stream chunks on demand**. voxel_tool supports this, but
the copy-on-load plumbing would be removed.

## Where the Cost Concentrates

- **`SceneManager`** — swap lifecycle → streaming/region lifecycle.
- **`Map`** — current-world node → persistent world root with spatial activation.
- **`VoxelGrid`** persistence — in-memory `_hp_by_pos` → chunk-keyed, persistent.
- **Furniture / spawns** — authored scene nodes → spatial stores + dynamic
  generation.

The hard-won `IBlockGrid` seam plus voxel_tool's native streaming mean the engine
layer is ready. The migration is a refactor of the above, not a rewrite.
