# Architecture: Tech Debt & Unimplemented Subsystems

Tracking page for known architectural debt, incomplete features, missing schemas, and planned subsystems.

---

## AI Subsystem & LimboAI Behavior Tree Migration

**Status: Complete (Phases 1–5 Implemented).**

- **Phase 1**: LimboAI GDExtension module integrated into `addons/limboai/`. Basic BT task suite (`BTActionNavigateTo`, `BTActionPerformWork`, `BTActionWander`, `BTConditionHasTool`, `BTConditionJobStillNeeded`, `BTConditionInGroup`) created.
- **Phase 2**: Fractional job system implemented (`JobInstance`, `WorkerClaim`, multi-worker claims, job blacklisting on `JobBoard`).
- **Phase 3**: Data-driven needs (`NeedDef`, `ColonistNeeds`) and Utility AI brain goal arbitration (`ColonistBrain`) with action commitment inertia (+0.30 bonus) implemented.
- **Phase 4**: Universal behavior trees (`colonist_root.tres`, `bt_generic_work.tres`, `bt_haul_single_trip.tres`, `enemy_swarmer.tres`) and programmatic tree factory (`BTTreeFactory`) created.
- **Phase 5**: Full SaveSystem persistence for `ColonistBrain`, `ColonistNeeds`, `JobBoard`, `JobInstance`, `WorkerClaim`, and LimboAI Blackboard state. Lazy tool retention and cleanup added.

**Deprecated Components**:
- Legacy `ColonistAI` (`subsystems/colonists/colonist_ai.gd`) and procedural `JobLeg` state machine methods on `JobDef` are marked `@deprecated` and superseded by LimboAI behavior trees and `JobInstance`.

---

## Unimplemented Subsystems (Planned)

1. **Combat Subsystem** (`subsystems/combat/`) — DamageResolver, HealthComponent, BreathComponent, WeaponBase.
2. **Equipment Subsystem** (`subsystems/equipment/`) — 8-slot loadouts, auto-equip logic.
3. **Energy Subsystem** (`subsystems/energy/`) — Daily stamina pool and breath resource management.
4. **Raids Subsystem** (`subsystems/raids/`) — Raid scheduler, threat direction, wave spawning.
5. **Permadeath & Memorial Subsystem** (`subsystems/permadeath/`) — Memorial registry and colony loss handling.
