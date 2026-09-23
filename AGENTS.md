# AGENTS.md

Xeno Frontier: Colony Defense — Godot 4.7 (Forward Plus, Jolt) voxel colony-survival game. GDScript only. Work lands directly on `main`.

## Authoritative docs — read before designing

- `docs/architecture/overview.md` — entry point: directory map, autoload table, EventBus registry, signal-flow rules.
- `docs/architecture/<subsystem>.md` — one page per subsystem; keep in sync with code.
- `docs/GDD.md` — `[TBD]` sections are **not implementable**; `[DRAFT]` means expect change.
- `docs/TODO.md` + `docs/architecture/tech-debt.md` — check before inventing a system that may already be planned.
- `docs/HOWTO-*.md` — map authoring, interaction authoring, asset transfer.

## Layout

- `subsystems/` — one folder per gameplay subsystem; ambiguous ownership → `subsystems/core/`. Autoloads in `subsystems/autoloads/` (order in `project.godot` matters).
- `ui/` — one folder per screen/panel: `ui/<id>/<id>.tscn` + `<id>.gd`.
- `data/` — all game content as text `.tres`, schema scripts co-located.
- `assets/` — art only (provenance in `docs/art.md`). `addons/` — zylann.voxel, gdUnit4, voxel_paint.
- `test/` — gdUnit4 suites. `testing/` — manual playtest scenes (editor-run). `tests/` and `debug/` are vestigial placeholders — don't write in either.
- Generated/gitignored, never hand-edit or commit: `reports/`, `site/`, `.zcode/`, `.godot/`. `tmp/` is reserved for agent scratch/temporary task files (never commit). Authored map files (`data/maps/<id>/map.tscn`, `map_def.tres`, `map.sqlite`, `terrain.sqlite`) ARE committed content — regenerate them with the map editor or voxel_paint plugin instead of editing by hand.

## Hard rules

1. All gameplay content in `res://data/` as `.tres` — no hardcoded content values in scripts.
2. Only `subsystems/voxel/` touches `voxel_tool`; everything else uses `IBlockGrid` / `VoxelGridAdapter`.
3. No cross-subsystem coupling: never preload or path into another subsystem's folder; no `get_node("../../")` — use autoloads or EventBus.
4. `res://` is read-only at runtime; saves go to `user://` (SaveSystem invariant INV-1).
5. The EventBus registry is meant to be complete — prefer existing signals or direct refs over adding new ones.
6. Prototype art: capsule primitives until the art pass. Enemies extend `enemy_base.gd`, colonists extend `colonist.gd` — never from scratch.
7. Do not commit or edit previous automatically. Always wait for explicit commands before doing so.
8. No LaTeX math syntax (e.g. `$...$`, `\pm`, `\times`) in responses, docs, or code comments. Use plain text or code formatting (e.g. `+/- 3 Y`, `2x2`, `3x3`).
9. Only run tests when necessary. And only run relevant tests for changes made during the current coding session.
10. No backward compatibility yet: Early in development, do not write migration layers, legacy fallbacks, or compatibility shims. When schemas or data formats change, start over by updating or recreating resources and definitions directly. Always explicitly flag breaking or incompatible changes to the user.
11. Scratch & temporary work files: Use the `tmp/` folder for scratch or temporary work files. Always create a dedicated task-specific subfolder inside `tmp/` for the current task (e.g. `tmp/<task-name>/`) and store all temporary files there. Never place temporary files in the repository root or subsystem folders, and never commit files in `tmp/`.

## GDScript style

- Tabs; full static typing: explicit `-> ReturnType` on every function, typed params, `:=` inference.
- `snake_case` files (`.tscn` filename matches root node name), `PascalCase` classes/nodes, `_` private prefix, `SCREAMING_SNAKE_CASE` constants/enum members.
- `##` doc comments that explain the *why*, with ARCH/GDD cross-references where relevant.
- Autoload scripts omit `class_name` (referenced as `GameState`, `EventBus`, …).
- Signals describe events, not commands (`colonist_died`, not `kill_colonist`).
- Composition over inheritance: behavior as child nodes (`@onready var _x: Type = $Child`) or `Resource` subclasses with virtual methods. Panels expose `setup(...)` called right after `add_child`. `_init` is rare.
- Duck-typed contracts are `i_`-prefixed doc-only scripts; implementations do not extend them.

## Communication & persistence

- Same scene → direct refs. Cross-scene → EventBus (relay only, no state; connect/emit, don't grow the registry). GameState's own changes → GameState's own signals. Colonist/job state → `Colony` autoload; UI reads via its public methods.
- State-holding nodes expose `serialize() -> Dictionary` / `deserialize(data)` for SaveSystem.

## UI and UiGate

Preferences: prefer **scene files over dynamically created nodes** for any non-trivial UI element. Refer to UI nodes **by unique name (`%Name`, "Access as Unique Name") rather than paths** — `$Panel/VBox/Label` chains break when scenes are restructured.

`UiGate` (autoload, `subsystems/autoloads/ui_gate.gd`) is the single source of truth for "a modal UI is open" and the **sole owner of the cursor outside gameplay** — so input can't leak through open screens and screens can't stack. Full story: `docs/architecture/ui.md`.

- Every modal registers: freed panels call `UiGate.open_modal(self)` in `_ready` / `close_modal(self)` in `_exit_tree`; persistent panels in their open/close functions; full-screen screens are registered by SceneManager — no UiGate code in screen scripts.
- Never write `Input.mouse_mode` from a panel (only Player's initial capture and its gated recapture).
- Panels own their Esc/hotkeys in `_unhandled_input` + `set_input_as_handled()`.
- No stacking: global screen hotkeys fire only when `not UiGate.is_input_blocked()`; a toggle may *close its own* screen, never open over another (M/H pattern in `subsystems/core/main.gd`).
- Gameplay code that reads Input actions directly (outside InputComponent) must check `is_input_blocked()` itself before acting.
- Layers: HUDLayer = CanvasLayer 10, UILayer = 20 (SceneManager's screen slot). Ad-hoc panels mount on the CanvasLayer in group `"hud_layer"`.

## Data conventions

- `snake_case` filename matching the `id` field inside; **identity is the `id` string**, never the filename. Maps live in `data/maps/<id>/` with id == folder name.
- Capability params: nullable typed sub-resources in `data/capability_params/` — composition, not subclassing, not a flat Dictionary.
- Schemas marked "planned — does not exist yet" in `data-schemas.md` are designs, not code — don't create them silently; check TODO/tech-debt first.
- **No backward compatibility**: Early development prioritizes clean schema design over stability. Do not write data migration shims or fallback parsers for obsolete formats; update or recreate `.tres` resource definitions directly, and flag incompatible changes to the user.

## Testing & commits

- gdUnit4 suites in `test/`: `suite_<name>_test.gd`, `test_*` methods, `auto_free()` everything allocated, fluent asserts (`assert_int(x).is_equal(1)`). Autoloads persist across suites — clear or swap-and-restore global state (e.g. `GameLog.clear()`).
- **Do not test for content**: Tests must be content-agnostic. Do not assert specific game content IDs (e.g. `"wood"`), counts, or indices of active `.tres` data in `res://data/` as they are subject to design adjustments. Use in-memory or directory fixtures (via test helpers) to verify system logic invariants.
- Shared test helpers in `test/helpers/`: Colony-backed suites use `ColonySandbox` (swaps `Colony.storage_registry`/`job_board`, resets and restores Colony's map-wiring caches, plus actor/crate factories); content-backed suites use `ItemDbSandbox`/`BuildLibrarySandbox`; job-plumbing suites use `JobFixtures`. None of these helpers load `res://data/**/*.tres` — they build fixtures in memory. Common doubles (`SignalCounter`, `MockInventory`) live in `doubles.gd`. Plain scripts, never `extends GdUnitTestSuite` — the runner would scan them as suites.
- Run: `addons/gdUnit4/runtest.sh` (needs `GODOT_BIN`).
- Conventional Commits: `type(scope): lowercase imperative subject` — feat/fix/chore/refactor/docs/wip; scope = subsystem (`arch` for architecture docs). Detailed bodies explaining what/why; end with the test tally (e.g. "132/132 green").
- Architecture docs are updated **with** the code (`docs(arch):` commits); `mkdocs build --strict` must pass when arch pages change. New pages follow `docs/architecture/contributing.md`.

## Test Isolation & Anti-Patterns

Enforced by `tools/check_test_hygiene.sh` (run before finishing test work; exits non-zero on a violation; waive a single line with a trailing `# hygiene-ok: <reason>` comment) and `tools/run_test_orders.sh both <suites>` (a suite must pass alone, forward, and reversed alongside its neighbors).

- **`res://` is read-only outside one documented exception.** Scratch maps, defs, and files a test creates go under `user://`, never `res://data/` — except the map-editor sandbox (`test/helpers/map_editor_sandbox.gd`), which authors throwaway maps into `res://data/maps/zz_sandbox_*/` on purpose because the map editor's production code is hardcoded to that path (see `docs/architecture/tech-debt.md`, "Map Editor Sandbox Writes Into `res://data/maps`"); it sweeps its own leftovers with `sweep_stale()`. Any OTHER helper that writes into `res://` is a Hard rule 4 violation, not a pattern to copy.
- **No shipped content in assertions or setup.** Never `load`/`preload` a `.tres`/`.sqlite`/`.vox`/`.tscn` under `res://data/` (a schema *script*, `.gd`, is fine). Build in-memory fixtures instead — extend `test/helpers/*_fixtures.gd` / `*_sandbox.gd` before hand-rolling a new one.
- **Restore only what you touched, never a blanket reset.** A sandbox snapshots each id/field it changes and puts back exactly that (or erases it if absent); a broad clear can hide a leak instead of fixing it.
- **No wall-clock waits.** No `create_timer`, `OS.delay_msec`, or a busy `while Time.get_ticks_msec()...:` loop. Await `get_tree().physics_frame`/`process_frame` in a bounded loop tied to the real condition, or await the component's completion signal.
- **Drive physics-ticked components with `physics_frame`, never idle frames plus a manual tick call.** Idle-frame loops that also call `_physics_process()`/`_process()` by hand advance a different number of engine ticks depending on the renderer — a vsynced display and headless/software rendering are not interchangeable here, and this produced a real false failure.
- **No tautologies.** An assertion's expected value must be a literal you derived by hand, never the same formula the code under test uses to compute its own output.
- **Compare `Node`s with `is_same`, never `is_equal`** — `is_equal` on a mismatch recurses into `obj2dict` and can crash gdUnit instead of failing cleanly.
- **Break reference cycles before `after_test` ends.** A `RefCounted` cycle survives `auto_free()` and orphan-node checks; it only shows up as "N ObjectDB instances leaked at exit." Release or clear anything that holds a reference back.
- **Clean up every `user://` fixture directory in `after_test`**, not just at the end of the happy path — it must run even when an earlier assertion fails.
- **No tests that pin a legacy or back-compat shape** (Hard rule 10). Delete the test and the production fallback behind it together; flag the break, don't keep the shim to keep the test green.
- **Test the public contract, not private helpers.** A test that calls a `_`-prefixed method directly is usually pinning an implementation detail that can be refactored out from under it.
- **Own each scenario in exactly one suite.** Before adding a test, check whether an existing suite already exercises the same behavior at the same level; delete the weaker duplicate.
- **Split a suite before it becomes unreviewable.** A file mixing several unrelated features and growing past a few hundred lines is debt — split by feature into sibling suites sharing one sandbox/fixture helper.
- **Mutation-check anything HIGH-RISK**: save/serialize, job assignment, inventory accounting, damage math, walkability/pathing. Break the production line on purpose in a scratch worktree and confirm the test goes red — a test that stays green under a real behavior change is worse than none.

## LLM Execution & Code Generation Strategy

When writing or refactoring code for Xeno Frontier: Colony Defense, prioritize highly granular structures, strict typing, and defensive execution mapping over monolithic script blocks.

### Auxiliary Functions Preference
- **Granular Decomposition**: Break complex operations, data transformations, or logic branches into small, pure auxiliary functions. If an operation exceeds 15 lines or performs more than one single task (e.g., both parsing a resource and updating an array), it must be split into isolated helpers.
- **Pure Helpers**: Auxiliary functions should remain pure and deterministic where possible, relying solely on explicitly typed arguments rather than mutations of side-effect-heavy external states.
- **The Step-Down Rule (Narrative Flow)**: Code must read like a top-down story. Define high-level orchestrator or tool functions at the top of the file, and place auxiliary function definitions **after** the functions that call them. A reader should be able to scan down the script and encounter concepts in the exact order they are consumed. Do not specify "step down order" or "narrative order" in the code comment.

### Pre-Invocation Commenting
- **Mandatory Preface Comments**: Every time an auxiliary function is invoked within a primary orchestrating method, a clear, single-line preface comment must be placed directly above the execution line. 
- **Comment Structure**: Explain *what* the auxiliary function is processing and *why* it is necessary at that specific sequence of execution to fulfill system invariants.
- **Math Formatting**: Do not use LaTeX syntax inside these comments. Use plain text or code blocks (e.g., use `+/- 3 Y`, `2x2`, or `3x3` instead of mathematical symbols).

#### Structural Example (Narrative Flow):
```gdscript
# =================
# Primary Functions
# =================

func process_voxel_placement(target_pos: Vector3i) -> void:
	# 1. Bounds Evaluation: Resolving a 3x3 neighbor space to ensure alignment with IBlockGrid invariants.
	var area_bounds: Dictionary = _get_grid_bounds(target_pos)
	
	# Execute remaining orchestration using area_bounds...


# ===================
# Auxiliary Functions
# ===================

func _get_grid_bounds(voxel_position: Vector3i) -> Dictionary:
	## Auxiliary: Calculates boundaries for a 3x3 footprint chunk.
	return {
		"min": voxel_position + Vector3i(-1, -1, -1),
		"max": voxel_position + Vector3i(1, 1, 1)
	}
```

### Scratch & Temporary Files
- **Task Isolation**: Use the `tmp/` folder for any scratch scripts, probes, or temporary work files.
- **Dedicated Subfolders**: Always create a dedicated subfolder within `tmp/` for the current task (e.g. `tmp/<task_name>/`) and place all agent temporary files there. Never pollute the workspace root or subsystem directories with temporary files.
