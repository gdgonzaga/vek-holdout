# Architecture: Tech Debt & Unimplemented Subsystems

Tracking page for known architectural debt, incomplete features, missing schemas, and planned subsystems.

---

## AI Subsystem & LimboAI Behavior Tree Migration

**Status: Complete (Phases 1–5 Implemented, Legacy AI Dropped).**

- **Phase 1**: LimboAI GDExtension module integrated into `addons/limboai/`. Basic BT task suite (`BTActionNavigateTo`, `BTActionPerformWork`, `BTActionWander`, `BTConditionHasTool`, `BTConditionJobStillNeeded`, `BTConditionInGroup`) created.
- **Phase 2**: Fractional job system implemented (`JobInstance`, `WorkerClaim`, multi-worker claims, job blacklisting on `JobBoard`).
- **Phase 3**: Data-driven needs (`NeedDef`, `ColonistNeeds`) and Utility AI brain goal arbitration (`ColonistBrain`) with action commitment inertia (+0.30 bonus) implemented.
- **Phase 4**: Universal behavior trees (`colonist_root.tres`, `bt_generic_work.tres`, `bt_haul_single_trip.tres`, `enemy_swarmer.tres`) and programmatic tree factory (`BTTreeFactory`) created.
- **Phase 5**: Full SaveSystem persistence for `ColonistBrain`, `ColonistNeeds`, `JobBoard`, `JobInstance`, `WorkerClaim`, and LimboAI Blackboard state. Lazy tool retention and cleanup added.
- **Legacy AI Cleanup**: Legacy `ColonistAI` (`subsystems/colonists/colonist_ai.gd`) and procedural `JobLeg` (`data/jobs/job_leg.gd`) state machine methods have been **completely dropped and removed** from the codebase.

---

## Unimplemented Subsystems (Planned)

Combat, Equipment, and Raids have since moved from planned to implemented/in-progress — see
[Combat](combat.md), [Equipment](equipment.md), and [Raids](raids.md) for current status. What
remains genuinely unimplemented:

1. **Energy Subsystem** — no `BreathComponent` anywhere; `StaminaComponent` is a 5-line stub. See [Energy](energy.md).
2. **Permadeath & Memorial Subsystem** — no memorial registry, Day Summary, or Game Over screen. See [Permadeath & Memorial](permadeath-memorial.md).
3. **Loot Subsystem** — `subsystems/loot/` and `data/loot/` don't exist; no LootTable/LootRoller/KeyItemPool. See [Loot](loot.md).
4. **Functional Rooms** — no `functional_counts` state or listeners on `Colony`. See [Functional Rooms](functional-rooms.md).
5. **Debug Console** — `debug/` is empty; no console autoload or commands exist. See [Debug Console](debug-console.md).

---

## Furniture Capabilities & Pluggable Architecture

**Status: Complete.**
- `FurnitureDef` capability composition migrated from an ad-hoc if-ladder in `FurnitureLayer` to a static capability factory registry with property introspection.
- `FurnitureCapability` base resource established with virtual `collect_action_options()` hook.
- `ICapabilityComponent` protocol established for automatic per-component state serialization/deserialization.
- `TestParams` removed. `BedParams` added, introducing `BedComponent` and `colonist_bed.tres`.
- Farm plot capability expanded with `FarmPlotParams` (`crop_slots`, `growth_rate_multiplier`, `hydration_mode`).
