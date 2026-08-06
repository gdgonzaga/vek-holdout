# Subsystem: Energy

Two personal-energy pools on each character, both framed as depleting resources (100% fresh → 0% empty). Split from the original single "Fatigue" pool so burst costs (sprint/jump/melee/ranged) and daily grind (time + work) evolve independently. See GDD §17 Energy subsystem for the full mechanic spec.

**Entity attachment matrix** (key architectural fact — component presence IS capability):

| Entity | BreathComponent | StaminaComponent | MVP usage |
|---|---|---|---|
| Player | ✅ | ✅ | Sprint/jump/melee/ranged (Breath); daily collapse (Stamina) |
| Colonist | ✅ | ✅ | Breath unused in MVP (future special actions); daily collapse (Stamina) |
| Enemy (Brawler/Shooter) | ✅ | ❌ | Breath unused in MVP (future windup/heavy attacks); Stamina is a future addition |

BreathComponent is attached to enemies now so future Breath-consuming features don't require architectural change.

## Files

| File | Type | Responsibility |
|---|---|---|
| `../combat/breath_component.gd` | Script (component) | Breath pool (burst energy). Self-ticking in `_process`. Owns sprint drain + jump/melee/ranged costs + regen. Does NOT cause collapse (that's Stamina). |
| `../combat/stamina_component.gd` | Script (component) | Stamina pool (daily energy). Self-ticking in `_process`. Owns ambient drain + work multiplier + bands + collapse. Does NOT gate burst actions (that's Breath). |
| `../data/energy_config.tres` | Data | Global Stamina thresholds/floors + work multiplier. See [Data Schemas](data-schemas.md). |
| character defs (in `../data/characters/`) | Data | Per-character Stamina drain rate + Breath costs. See [Data Schemas](data-schemas.md). |

*Component scripts live in `combat/` alongside HealthComponent (all three are paired character-stat components). See [Tech Debt & Unimplemented](tech-debt.md) on a possible future `core/components/` home.*

## Signals

All same-scene (No EventBus) — Energy is per-entity, consumed locally by the owning character + HUD.

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `breath_changed(value)` | `breath_component.gd` | HUD (Breath bar) | No | Sprint/Burst drain |
| `sprint_available(available)` | `breath_component.gd` | Player (sprint gate) | No | Sprint/Burst drain |
| `stamina_changed(value)` | `stamina_component.gd` | HUD (Stamina bar) | No | Daily Stamina drain |
| `stamina_band_changed(band)` | `stamina_component.gd` | HUD (status icon), Player (move floor), Colonist AI (work floor / collapse) | No | Daily Stamina drain, Active work, Sleep reset |

## Flow Trace: Sprint and burst actions drain Breath, regenerates when idle

**Trigger:** Player sprints, jumps, melee-swings, or fires a ranged weapon.

1. Player queries `breath_component.can_sprint()` before entering SPRINT state (requires breath > 20%).
2. On SPRINT entry: Player calls `breath_component.set_sprinting(true)`.
3. BreathComponent._process: `breath -= sprint_drain_rate × delta`; emits `breath_changed`.
4. If `breath ≤ 0`: emit `sprint_available(false)` → Player forced to WALK.
5. Other burst actions call `breath_component.spend(cost)` — returns false (blocked) if `breath < cost`.
6. When not sprinting (or not spending): `breath += regen_rate × delta` (capped 100); emits `breath_changed`.

**End state:** Breath cycles between drain (burst) and regen (idle). Never causes collapse. Player-only in MVP (colonists/enemies don't sprint in MVP, but BreathComponent is attached for future use).

## Flow Trace: Daily Stamina drain + collapse at 0%

**Trigger:** Time passes (always, while awake). Applies to Player + Colonists.

1. StaminaComponent._process: `stamina -= drain_rate × delta` (drain_rate from character def).
2. Emits `stamina_changed`.
3. On crossing thresholds, emits `stamina_band_changed(band)`:
   - < 45% → Tired band → work-speed penalty active (floor 60% at collapse).
   - < 25% → Exhausted band → movement penalty also active (floor 40% at collapse).
   - = 0% → Collapsed band → owner enters collapse state (Player forced IDLE; colonist AI hard-stopped).
4. Listeners react: HUD updates status icon; Player applies movement floor; colonist_ai halts job-seeking.

**End state:** Stamina depletes over the day; character collapses at 0% until sleep. Sleep is the only recovery (Player action — collapsed colonists simply stay down until the next day).

## Flow Trace: Active work doubles Stamina drain

**Trigger:** Player or Colonist starts/stops an active work Job (craft/build/smelt/haul).

1. Colonist AI (or Player, for manual build) calls `stamina_component.set_working(true)` on Job start.
2. StaminaComponent applies `work_multiplier (×2)` to its drain in `_process`.
3. On Job completion/failure: `set_working(false)` → drain returns to ambient.

**End state:** Working burns the daily budget faster; choosing to work is choosing to spend Stamina. Interleaves with ambient drain (always-on) and the collapse rule.

## Flow Trace: Sleep resets Stamina to 100%

**Trigger:** Player interacts with bed (E) at base → triggers Core's Sleep→Day Summary flow.

1. Core's Sleep flow calls `time_system.advance_to_midnight()` → `day_rolled_over`.
2. For each entity with StaminaComponent (Player + all colonists): `stamina_component.reset()` → sets `stamina = 100`, emits `stamina_changed` + `stamina_band_changed(FRESH)`.
3. BreathComponent.reset() also called (top up Breath to 100 for consistency).
4. Collapse state clears; colonist AI resumes job-seeking next morning.

**End state:** All characters at full Stamina + Breath at start of new day. Collapse lifted.

## Class Reference

### Class: BreathComponent

**Extends:** Node
**Script:** `breath_component.gd` (in `combat/`)
**Description:** Short-term burst energy pool. Self-ticking. Drains on sprint/jump/melee/ranged; regenerates when idle. Gates sprinting. Does NOT cause collapse.
**Used by:** Player (sprint gating + burst-action spending), Colonists (future), Enemies (future). HUD (Breath bar).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `breath` | `float` | Current value, 0–100. |
| `max_breath` | `float` | [export] 100. |
| `sprint_drain_rate` | `float` | [export] 20/sec while sprinting. |
| `regen_rate` | `float` | [export] 10/sec when not exerting. |
| `jump_cost` / `melee_cost` / `ranged_cost` | `float` | [export] 10 / 5 / 2 per action. |
| `sprint_gate` | `float` | [export] 20 — below this, sprint is blocked. |

**Signals:**

| Signal | Description |
|---|---|
| `breath_changed(value: float)` | For HUD Breath bar. |
| `sprint_available(available: bool)` | For Player sprint gating; false when breath < sprint_gate. |

**Functions:**

| Function | Description |
|---|---|
| `set_sprinting(active: bool) -> void` | Toggles continuous sprint drain. |
| `spend(amount: float) -> bool` | Deducts a burst-action cost; returns false if `breath < amount` (action blocked). |
| `can_sprint() -> bool` | Returns `breath > sprint_gate`. |
| `reset() -> void` | Sets breath to max_breath (called on sleep). |

### Class: StaminaComponent

**Extends:** Node
**Script:** `stamina_component.gd` (in `combat/`)
**Description:** Long-term daily energy pool. Self-ticking. Ambient drain (×2 while working). Sleep-only recovery. Causes collapse at 0%. Applies work/movement penalties via bands.
**Used by:** Player (movement floor + work multiplier), Colonists (work multiplier + collapse). HUD (Stamina bar + status icon). Colonist AI (collapse halt).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `stamina` | `float` | Current value, 0–100. |
| `max_stamina` | `float` | [export] 100. |
| `drain_rate` | `float` | [export] 0.21/min (ambient, per-character from CharacterDef). |
| `work_multiplier` | `float` | [export] 2.0 — drain is multiplied by this while `working` is true. |
| `working` | `bool` | Set true during active work Jobs. |
| `band` | `StaminaBand` enum | FRESH / TIRED / EXHAUSTED / COLLAPSED. Derived from stamina. |

**Signals:**

| Signal | Description |
|---|---|
| `stamina_changed(value: float)` | For HUD Stamina bar. |
| `stamina_band_changed(band: StaminaBand)` | For HUD status icon, Player movement floor, colonist AI collapse halt. |

**Functions:**

| Function | Description |
|---|---|
| `set_working(active: bool) -> void` | Toggles the `work_multiplier` on the drain. |
| `reset() -> void` | Sets stamina to max_stamina + band to FRESH (called on sleep). |
| `get_work_multiplier() -> float` | Returns the effective work-speed multiplier (1.0 fresh → 0.6 at collapse). |
| `get_move_multiplier() -> float` | Returns the effective movement-speed multiplier (1.0 fresh → 0.4 at collapse). |
