# AGENTS.md

Vek Holdout — Godot 4.7 (Forward Plus, Jolt) voxel colony-survival game. GDScript only. Work lands directly on `main`.

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
- Generated/gitignored, never hand-edit or commit: `reports/`, `site/`, `tmp/`, `.zcode/`, `.godot/`, and `data/maps/<id>/map.tscn` (stamped by the voxel_paint plugin).

## Hard rules

1. All gameplay content in `res://data/` as `.tres` — no hardcoded content values in scripts.
2. Only `subsystems/voxel/` touches `voxel_tool`; everything else uses `IBlockGrid` / `VoxelGridAdapter`.
3. No cross-subsystem coupling: never preload or path into another subsystem's folder; no `get_node("../../")` — use autoloads or EventBus.
4. `res://` is read-only at runtime; saves go to `user://` (SaveSystem invariant INV-1).
5. The EventBus registry is meant to be complete — prefer existing signals or direct refs over adding new ones.
6. Prototype art: capsule primitives until the art pass. Enemies extend `enemy_base.gd`, colonists extend `colonist.gd` — never from scratch.

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

## Testing & commits

- gdUnit4 suites in `test/`: `suite_<name>_test.gd`, `test_*` methods, `auto_free()` everything allocated, fluent asserts (`assert_int(x).is_equal(1)`). Autoloads persist across suites — clear or swap-and-restore global state (e.g. `GameLog.clear()`).
- Run: `addons/gdUnit4/runtest.sh` (needs `GODOT_BIN`).
- Conventional Commits: `type(scope): lowercase imperative subject` — feat/fix/chore/refactor/docs/wip; scope = subsystem (`arch` for architecture docs). Detailed bodies explaining what/why; end with the test tally (e.g. "132/132 green").
- Architecture docs are updated **with** the code (`docs(arch):` commits); `mkdocs build --strict` must pass when arch pages change. New pages follow `docs/architecture/contributing.md`.
