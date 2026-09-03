---
title: Game Design Document — Rust Frontier: Colony Defense
tags: [gdd, design, godot]
area: Projects
created: 2026-06-19
updated: 2026-07-04
status: DRAFT
version: v2.6 (decisions fold; audit trail in `.archive/v2.6-decisions/`)
---

# Rust Frontier: Colony Defense — Game Design Document

_3D Voxel Colony Survival — Godot 4 (GDScript)_

> **How to use this document:**
> - Fill in every section before starting development. Sections marked `[TBD]` are placeholders — do not ask an agent to implement anything still marked `[TBD]`.
> - Mark each section with a stability tag: `[FINAL]`, `[DRAFT]`, or `[TBD]`.
> - Keep the Decisions Log updated as design choices are made or changed.
> - When briefing an AI agent, paste the relevant section(s) directly into the prompt.

> **Structural adaptation notes (how this doc differs from the stock template):**
> The stock template targets a mobile/Android action game. Rust Frontier: Colony Defense is a PC 3D voxel colony survival sim. The following adaptations were made:
> - **Platform/Technical fields** were rewritten for PC (orientation, min specs, perf targets) instead of Android (ads, UMP/TCF, portrait).
> - **Three core sections were added** that the template lacks but this game requires as core design (not subsystems): **Colonists** (§6), **Base Building** (§7), and **Starting Conditions** (§9). Per playbook guidance, subsystems must be removable without breaking the core loop; colonists and the voxel base *are* the core loop, so they live in the core, not in Subsystems.
> - Most of the game's modular systems (Energy, Raids, Expeditions, Equipment, Skills/labor, Time, Save, Mods, Debug) live in **Subsystems (§17)** using the template's structured schema (What it does / Triggers / Inputs / Outputs / States / Fixed values / Does NOT / Dependencies).
> - The Brawler/Shooter state machines (§5) and all other originally-placeholder values were resolved in v2.6 via the decisions-fold pass — see `.archive/v2.6-decisions/` for the original question/answer/rationale trail.

---

## 1. Overview `[FINAL]`

| Field | Value |
| --- | --- |
| **Game title** | Rust Frontier: Colony Defense |
| **Genre** | Steampunk / low-fantasy voxel colony survival & horde defense (mechanical/frontier theme) |
| **Engine** | Godot 4 (GDScript) |
| **Platform** | PC (initial) — consoles later |
| **Perspective** | Third-person (player character) with colony management overlay |
| **Colony size** | Up to 10 colonists + the player character (MVP cap: 5) |
| **World** | Separate maps per location — base and POIs are distinct scenes |
| **Target audience** | Fans of 7 Days to Die's defense/scavenging loop and RimWorld-style colony management, comfortable with systemic depth (DF-adjacent) but presented in a Minecraft-accessible voxel sandbox. Hardcore-adjacent but not punitive. |
| **One-sentence description** | Rust Frontier: Colony Defense is a survival colony-sim & horde defense game where you lead a frontier stronghold on the realm's border during a wartime stalemate, fortifying with mechanical traps and brass/iron defenses by day and holding off regular monster horde assaults by night. |
| **Core fantasy** | The frontier engineer-commander: constructing mechanical fortifications and traps in a buildable voxel world, managing colonist logistics and ammunition economy, holding the line against regular, massive monster hordes sent crashing into the border stronghold. |

**Theme notes:** Steampunk / low-fantasy mechanical frontier. Sent by the crown to establish a border stronghold during a wartime stalemate. Technology is purely mechanical (steam, clockwork, gears, iron/brass, blackpowder — no magic). Threat is massive regular horde waves of monsters/orcs/beasts testing the colony's defensive perimeter.

**Audience scope bounds (what we're NOT taking from the reference games):** DF's individual-mood-simulation depth; Minecraft's minute-by-minute block-mining cadence (building here is faster, blueprint-driven).

---

## 2. Scope `[DRAFT]`

> This section is the most important for AI-assisted development. Be explicit about what is NOT in the game. The "Out of Scope" list below was derived from the v2.5 "Post-MVP" list plus standard systems the design intentionally omits in MVP.

### In Scope (MVP)

- Functional voxel base building with manual construction by colonists and player
- Solo start — player begins alone with one named companion (incapacitated) in a ruined 3×3m shelter. Starting resources: 80 scrap, 15 components, 20 fuel, knife + armor equipped, pistol in storage. Colony grows to max 5 colonists via recruitment (bed-capped). Full 10-colonist cap is post-MVP.
- Skill system: 6 skills (Medical, Mechanical, Construction, Crafting, Combat, Farming), use-based leveling (L1–L5), regular jobs gated at Level 1; per-colonist labor management
- Energy system (Breath + Stamina) with status icons across all colonists
- Full permadeath — named and unnamed resolution
- Raid stance system (Fight / Fight Post / Shelter) with basic colonist AI
- Two enemy archetypes (Brawler + Shooter) with structural weak-point targeting
- One expedition type: Scavenge (timed extraction format, fully specced)
- 5 core functional furniture items: Command Desk, Clinic Bed, Workbench, Forge, Colonist Bed. Growing Trough exists in the furniture list but is non-functional in MVP — food and hunger are post-MVP systems.
- World map with fog-of-war (visit to reveal)
- Persistent save on sleep including voxel world state
- Day Summary screen
- Debug console with all listed commands
- Data-driven architecture (block types, enemy stats, furniture, loot tables, skills, raid curves, starting conditions externalised as resource files) — prerequisite for Tier 1 mod support

### Out of Scope (do not implement, do not design for — MVP)

> Items the design intentionally does NOT include in MVP. The agent must not add these "because most games have them."

- Multiplayer implementation (networking/RPCs deferred to post-MVP; codebase follows multiplayer-ready architectural constraints)
- Procedural generation of the voxel world (MVP uses discrete pre-built scenes per map; true open world with chunking is future)
- True open world / Zylann's voxel plugin streaming (MVP: separate scenes per location)
- Structural support / gravity for voxel blocks (blocks may float freely in MVP)
- Food, hunger, and crop farming loop (Growing Trough is a non-functional placeholder)
- **Water system** (deferred with food/hunger; remove the "needs water nearby" reference from Growing Trough)
- **Power system** (was referenced by Turrets; both deferred)
- **Turret** (automated defense; deferred with Power)
- **Medical Fridge** (deferred with the medical-system work)
- **Audio** — SFX, music, voice/radio cues all deferred (game ships silent for MVP; Settings Audio tab stays wired-but-silent)
- Trading system with NPC factions
- Morale system
- Night visibility / atmospheric tension mechanics
- Story POIs and overarching narrative
- Megaproject goals
- Underground mining / ore veins / tunnels (ore exists as a post-MVP resource item only)
- Advanced enemy types and siege mechanics beyond Brawler/Shooter
- Durability wear-and-repair loop *(note: the Durability stat itself is in MVP as the damage-absorption buffer — see §6.11. What's deferred is the **wear-and-repair loop**: armor degrading through use and requiring Workbench repair with materials. In MVP, Durability functions as the ablative hit pool; the wear aspect activates when the repair loop is built.)* Ammo types are consumed but ammo scarcity/scarcity-Durability is out of scope.
- Specialist slots and advanced operations gated behind them
- In-game mod browser / mod.io / Steam Workshop integration (manual /mods install + Nexus only at launch)
- Configurable game start / difficulty selection screen (Survivor / Brutal / Custom)
- Additional expedition types beyond Scavenge (Mining, Rescue, Recon, Story)
- **In-app purchases / microtransactions** (no IAP for MVP or full release — PC premium title)
- **Skills tab content** (tab reserved in Player screen; skill tree is post-MVP)
- **Crouch** (key **C** reserved; mechanic is post-MVP)
- **Colonist Groups** (assign loadouts/priorities/away-teams by group — pinned post-MVP concept)
- **Additional weapons** beyond Knife + Pistol — Club (melee), Bow (ranged), and their ammo (arrows) are post-MVP. MVP weapon set is Knife + Pistol only.
- Mod loader integration itself (godot-mod-loader wiring is a short post-MVP task once data layer is stable)
- Relationship / romance system for the companion
- Stimpack consumable

### Deferred to Later Versions (post-MVP, planned)

- Configurable game start (difficulty modes: Survivor / Brutal / Custom — exposes starting resources, equipment, and pre-built structure)
- Mining expeditions, Rescue expeditions, Recon expeditions
- Food and hunger system: Growing Trough (crop farming), colonist hunger meter, food consumption loop, foraging on expeditions
- Colony cap expansion to 10 via additional beds
- Trading system with NPC factions via Command Desk radio
- Morale system
- Night visibility mechanics and atmospheric tension layer
- Story POIs and overarching narrative
- Megaproject goals for advanced players
- Resource mining — ore veins, underground tunnels
- Advanced enemy types, siege mechanics
- Durability wear-and-repair loop (armor degrades through use; repair at Workbench with materials). The Durability stat is in MVP as the damage-absorption buffer — this entry covers the wear/repair *loop*, post-MVP.
- Specialist colonist tier (one per functional area, colony-wide buff + advanced operations)
- Companion relationship system (lover, sibling, close friend, former rival)
- Stimpack consumable (temporarily suppresses Stamina penalties during a mission)
- Structural support and gravity for voxel blocks
- True open world with Zylann's voxel Godot plugin
- Autoplay / autosave on expedition return; manual save
- mod.io in-game browser; Steam Workshop
- Future moodlets: Injured, Well-Fed, Morale Boost, Morale Penalty, Well-Rested, Hungry
- Future consumables, "Armored Brawler" / "Vested Shooter" / "Sniper" enemy variants

---

## 3. Core Loop `[DRAFT]`

The loop has no hard daily structure. Time advances continuously. The player and colonists decide how to spend it.

| Phase | Player activity | Colony activity |
| --- | --- | --- |
| **Base time** | Build, craft, assign tasks, manage colonists, sleep | Work assigned jobs, build, eat, rest, socialise |
| **Expedition** | Lead a crew to a POI — scavenge, mine, rescue, explore | Hold the base — work continues, raids may hit |
| **Raid** | Fight alongside colonists, direct defense, repair breaches | Execute assigned stance (fight / fight post / shelter) |
| **Recovery** | Tend to wounded, assess damage, restock supplies | Repair structures, recover Stamina (sleep), resume jobs |

Expressed as a concrete repeated cycle:

1. At base, the player builds/crafts, assigns colonist labor, and manages the colony.
2. The player leads a crew on an expedition to a POI (scavenge) — fuel and time are spent, the base is left under-defended.
3. Enemies (raid or expedition waves) apply pressure; the player and colonists fight, defend the perimeter, and repair breaches.
4. The player returns / recovers — tend wounded, assess damage, restock, sleep to resolve the Day Summary and save.

**Loop length:** 1 in-game day ≈ 30 min real time. A day contains the full cycle (build morning → scavenge/expedition midday → raid at night → recover).
**Session length:** Open-ended (no fixed target). Players stay for as many days as they want; autosave fires at in-game midnight and on quit-to-menu so quitting mid-loop is safe (see §17 Save & Reset).

---

## 4. Player `[DRAFT]`

> The player character is a physical third-person avatar who lives alongside colonists. They use the same skill system as colonists (see §6 Colonists). They cannot hold a specialist slot (specialists are NPC-only, post-MVP).

### States `[DRAFT]`

Two-layer model: a **Mode** flag (Normal | Blueprint) layered over a **movement/action State**. Blueprint is a *mode*, not a mutually-exclusive state — you can walk/sprint while in Blueprint.

```
Modes:  Normal | Blueprint

States: Idle | Walk | Sprint | Attack | Interact | Sleep | Dead

Movement transitions (apply in both modes):
  Idle    → Walk        (movement input)
  Walk    → Sprint      (Shift held)
  Sprint  → Walk        (Shift released)
  Walk/Sprint → Idle    (no input)
  Any non-Dead → Attack     (LMB/RMB while item equipped; does NOT change movement
                             state — you keep walking/sprinting while attacking)
  Any non-Dead → Interact  (E; brief locked animation; does NOT cancel on damage —
                            interrupting is a player choice, see note below)
  Any → Sleep    (use bed)
  Any → Dead     (HP 0)
  Sleep → Idle    (wake)

Blueprint mode (toggled with B):
  - While active, LMB/RMB place/demolish blueprints instead of attacking.
  - Movement states still apply (Walk/Sprint) — building while moving is allowed.
  - Interact still works.
  - Rotation/selection keys route to the build cursor (see Actions table).
```

**Single merged Attack state:** the equipped item decides melee vs ranged (one transition table, not two). Confirmed.

**Interaction interrupt rule:** interactions do **not** cancel on damage. A player looting/building can tank hits to finish the action — interrupting is a *player choice* (walk away to cancel), not enemy-enforced. Implication: a Brawler doing 25 dmg/s chunks ~75 HP during a 3s loot. This is intentional risk-reward.

### Actions and Controls `[DRAFT]`

| Action | Input | Notes |
| --- | --- | --- |
| Move | **WASD** | Third-person movement |
| Sprint | **Left Shift** (hold) | Drains Breath (−20/sec); blocks sprint when Breath empty (see Energy subsystem) |
| Jump | **Space** | |
| Interact (loot / door / furniture / vehicle / bed) | **E** | Looting takes 3s; does NOT cancel on damage |
| Reload | **R** | No-op if equipped item isn't reloadable |
| Toggle Blueprint mode | **B** | Enters/exits build mode |
| Rotate block (active axis) | Mouse wheel up/down | 90° increments |
| Cycle rotation axis | **R** | Z → X → Y → Z (default axis Z / vertical). *Note: R is reload in Normal mode, cycle-axis in Blueprint mode — context-dependent.* |
| Place blueprint | **Left-click** | Blueprint mode only |
| Remove blueprint | **Right-click** | Blueprint mode only |
| Select blueprint block | **Middle-click** | Blueprint mode only |
| Primary item action (melee swing / ranged fire) | **LMB** | Equipped item decides melee vs ranged |
| Secondary item action (aim / alt-fire / block) | **RMB** | |
| Open Player screen | **Z** | Tabbed: Player Info / Inventory / Gear / Skills(post-MVP reserved) |
| Player screen → Inventory tab shortcut | **I** | Opens Player screen on Inventory tab |
| Open Colony screen | **X** | Tabbed: Roster / Labor / Defense / Loadouts / Expeditions |
| Open World Map | **M** | Standalone overlay; also accessible via Command Desk |
| Pause Menu | **Esc** | Full pause (see §12 Pause Menu) |
| Crouch (toggle) | **C** | **Reserved — post-MVP only.** Do not implement in MVP. |
| Debug console | **~** or **F1** | Dev only |

### Movement `[DRAFT]`

| Property | Value | Notes |
| --- | --- | --- |
| Move speed (base walk) | **3.5 m/s** | Godot 3rd-person default; reference for enemy speeds |
| Sprint multiplier | **1.6×** | → 5.6 m/s sprint |
| Sprint breath drain | **−20/sec** while sprinting | ≈5s of continuous sprint (see Energy subsystem) |
| Walk breath drain | **0** | only burst actions cost Breath |
| Gravity | **9.8 m/s²** (Y) | Godot default 3D gravity; affects player + NPC physics only — blocks are static in MVP |

**Breath costs (burst actions):** sprint −20/sec (held), jump −10, melee swing −5, ranged fire −2. Breath regenerates **+10/sec** when not doing any of these. Empty Breath (< 20%) blocks sprint but does NOT collapse — player can always walk. Full Breath cost table in §17 Energy subsystem.

**Derived enemy speeds** (from base 3.5 m/s): Brawler = 60% → **2.1 m/s** (slower than walk — kiting is viable); Shooter = 85% → **2.98 m/s** (faster than walk, slower than sprint — sprint is the escape tool).

All movement values are designer-configurable; flag for first-playtest tuning alongside Stamina thresholds.

### Abilities `[DRAFT]`

> **Note:** This game has no ability framework (dash, slam, etc.) in the style the stock template assumes. Combat actions are resolved through equipped weapons (see *Subsystem: Equipment*). There are no cooldown-based player abilities in MVP.

- **Melee attack:** via equipped melee weapon. **MVP: Knife** (25 dmg/1s). Bound to **LMB** (primary item action).
- **Ranged attack:** via equipped ranged weapon + ammo. **MVP: Pistol.** Bound to **LMB** (primary item action — same as melee; the equipped item decides). Consumes ammo.
- **No dash, no dodge roll, no active skills in MVP.**

### Health and Death `[DRAFT]`

Uses the shared Durability-before-HP damage model (see §6.11 Damage Resolution).

- **Max health:** **200 HP** (player). Colonist baseline: **100 HP** (before the companion's +20% — see §6.6). All HP values exposed as `@export` for designer tuning without recompiling.
- **Health type:** Integer HP with Durability buffer
- **Armor:** provided by equipped armor (6 slots × 3 material sets, see Equipment subsystem)
- **On player death (HP ≤ 0 during an expedition):** Mission Failed. Player respawns at base with 50% HP. All loot from the mission is lost. 1 day of recovery time. Colonist crew outcomes resolve normally (permadeath rules apply to them).
- **On player death (outside expedition):** Respawn at base. Recovery time/penalty to be tuned in playtest (MVP: minimal — respawn at base, no extra penalty beyond the death itself; the colony continues).
- **Lives system:** No
- **Respawn / continue:** Yes — player respawns at base. Player death alone does **not** end the game; the colony continues. Game Over only when all colonists **and** the player are dead (see §8).

---

## 5. Enemies `[DRAFT]`

> Define a state machine for every enemy type. Do not leave behavior as prose. The Brawler/Shooter stat tables below are from GDD v2.5 §12; the state machines were converted from the prose "Behavior (stub)" and need confirmation (bracketed values are inferred).

### Enemy — Brawler `[DRAFT]`

A heavily built scavenger in improvised armor. Rushes the player on sight. High HP, no ranged capability. Intended to absorb damage and force the player into a positional decision.

**Role:** Resource sink / melee pressure. A single Brawler tests whether the player can out-DPS incoming damage; two test positioning and retreat.

```
States: Idle, Chase, Attack, Dead

Transitions:
- Idle → Chase: player/colonist within Detection Range (10m) AND line_of_sight == true,
                 OR player fires any weapon anywhere in the room
- Chase → Attack: target within Attack Range (1.5m)
- Attack → Chase: target leaves 1.5m OR target dies
- Chase → Idle: loses line of sight for 5 seconds
- Attack → Attack: (target still within 1.5m) re-attack at Attack Rate (1/sec)
- Any → Dead: HP <= 0

Re-target rule: every 0.5s while in Chase, pick the nearest reachable
colonist/player as the current target.

Notes:
- Uses NavigationAgent + navmesh for movement (see §6.10 colonist AI for the
  enemies-use-NavAgent / colonists-use-A* split rationale)
- Paths around obstacles, not through them
- Windup 0.4s before damage is applied
- No stun state in MVP
```

| Property | Value |
| --- | --- |
| Health | 140 |
| Durability | 0 (no armor) |
| Melee Damage | 25 per hit |
| Attack Rate | 1 hit / sec |
| Move Speed | 2.1 m/s (60% of player base 3.5 m/s) |
| Detection Range | 10m line of sight |
| Attack Range | **1.5m** |
| LOS-loss timeout | 5s (returns to Idle if no sight) |
| XP / Loot | — (placeholder for MVP; drops nothing) |

**Design intent:** A Brawler is a resource sink. 140 HP at Pistol rate (15 damage × 4/sec = 60 DPS) means ~2.3 seconds to kill if every shot lands. It is not meant to be killed quickly.

**Scaling notes:**
- Early missions: 1–2 Brawlers. Mid-game: 3–4. Scale by count, not stats, for MVP.
- Future: add a Durability value (e.g. +25) for an "Armored Brawler" variant without new AI.

**Cannot do:** ranged attacks, path around obstacles, open doors/gates intelligently, drop loot in MVP.

### Enemy — Shooter `[DRAFT]`

A lightly armed scavenger holding a scavenged pistol. Stays at range and fires at the player. Low HP — fragile if reached. Intended to punish players who stand still and reward players who close the gap.

**Role:** Lateral pressure / ranged threat. Forces the player to decide: push through a Brawler to silence the Shooter, or kite the Brawler while absorbing Shooter damage.

```
States: Idle, Reposition, RangedAttack, MeleeFallback, Dead

Transitions:
- Idle → Reposition: target within Detection Range (16m) AND LOS,
                     OR player fires any weapon
- Reposition → RangedAttack: target within holding range (10m) AND LOS
- Reposition → MeleeFallback: target within 6m AND unable to retreat (wall/obstacle behind)
- RangedAttack → Reposition: target leaves 10m holding range OR LOS broken
- RangedAttack → RangedAttack: fires every 1.5s while target in LOS and within 16m
- MeleeFallback → Reposition: retreat path becomes available
- Any → Dead: HP <= 0

Notes:
- Never advances toward target — only holds range or back-pedals to re-establish it
- Uses NavigationAgent + navmesh (paths around obstacles, not through them)
- Only melees when a colonist/player closes within melee range and it cannot retreat
- No spread / accuracy modifier in MVP
- Ranged damage 12/shot; melee fallback 8 damage/hit at 1/sec
```

| Property | Value |
| --- | --- |
| Health | 60 |
| Durability | 0 (no armor) |
| Ranged Damage | 12 per shot |
| Attack Rate | 1 shot / 1.5 sec (~0.67/sec) |
| Holding Range | **10m** (single value, not a band) |
| Melee fallback damage | 8 per hit at 1/sec (when cornered) |
| Move Speed | 2.98 m/s (85% of player base 3.5 m/s; repositions, does not rush) |
| Detection Range | 16m line of sight |
| XP / Loot | — (placeholder for MVP; drops nothing) |

**Design intent:** At 12 damage / 1.5s the player takes ~8 DPS at range — survivable, but punishing if ignored. The Shooter is fragile by design at 60 HP; reaching it ends the ranged threat immediately, rewarding aggressive play.

**Scaling notes:**
- Pair with 1 Brawler for a basic encounter. Pair with 2 Brawlers for a hard encounter.
- Future: add Durability (e.g. +15) for a "Vested Shooter" variant; increase preferred range to 20m for a "Sniper" variant.

**Cannot do:** rush the player, absorb sustained fire, drop loot in MVP.

### Shared: Durability-before-HP Damage Resolution `[DRAFT]`

Both archetypes use the existing Durability-before-HP damage order: Durability depletes first, and HP damage begins only when Durability = 0. This applies to every combat entity (player, colonists, enemies). Full detail lives at §6.11.

| Step | Rule |
| --- | --- |
| Step 1 | Incoming hit dealt. Check if target has Durability > 0. |
| Step 2 (Durability > 0) | Damage reduces Durability first. If damage > remaining Durability, overflow carries into HP. |
| Step 3 (Durability = 0) | All damage applies directly to HP. |
| Step 4 | If HP ≤ 0: incapacitation / death, per permadeath rule. |

*Example: a Brawler hits a survivor with 25 Durability and 100 HP. First hit: 25 damage wipes Durability, HP remains 100. Second hit: 25 damage to HP, HP = 75.*

### MVP Encounter Templates `[DRAFT]`

Three ready-to-use encounter configurations for testing and scavenge missions:

- **Template 1 — Basic (tutorial / first mission):** 2× Brawler. No Shooters. Tests melee-only combat and basic positioning. Player should survive with ~60% HP remaining if equipped with Pistol + Leather Armor.
- **Template 2 — Standard (mid-tier scavenge):** 2× Brawler + 1× Shooter. The Shooter is positioned at the back of the room. Tests the core two-archetype dynamic.
- **Template 3 — Hard (late area / raid defense):** 3× Brawler + 2× Shooter. Shooters are positioned on opposite sides of the room. Designed to be very difficult without survivor backup. Not recommended as a solo encounter.

*GDD Addendum — Base Survival MVP | Enemy Archetypes | Option B Selected*

---

## 6. Colonists `[DRAFT]`

> Colonists are a **core entity** (the colony *is* the game), not a subsystem. They share the skill system with the player. Treated here as a core section, not under Subsystems.

### 6.1 Overview

The player begins alone. Colonists are recruited over time through expeditions, radio contacts, and random events. The colony grows to a maximum of 10 colonists (MVP cap: 5). Each has skills, attributes, and personal stakes. Losing one is permanent. The player lives among them — a participant, not a detached director.

### 6.2 Attributes

| Attribute | Description |
| --- | --- |
| **HP (Health Points)** | Vitality. Reaches 0 → permadeath (see Permadeath subsystem). Recoverable above 0 via the Clinic Bed. |
| **Durability** | The condition of equipped armor. Absorbs damage before HP. Depletes first, then HP takes damage. Unifies damage-absorption and item-wear into one property (see §6.11, §17 Equipment). |
| **Breath** | Short-term burst energy (100% fresh → 0% empty). Drained by sprint/jump/melee/ranged; regenerates when idle. See Energy subsystem. |
| **Stamina** | Long-term daily energy (100% fresh → 0% collapsed). Drains slowly over time (×2 while working); recovered only by sleep. At 0%: collapse. See Energy subsystem. |
| **Morale** | Placeholder — future mechanic. Affects work speed and raid performance. |

### 6.3 Skills

Each colonist and the player has a set of **skills** that determine how effectively they perform skilled work. Skills replace the old fixed "role" system — any colonist can do any regular job they meet the skill requirement for, and skills improve with use. Effectiveness that used to come from a role's passive bonus now comes from skill level.

| Skill | Activities that improve it |
| --- | --- |
| Medical | Treating injured colonists at the Clinic Bed |
| Mechanical | Repairing and upgrading vehicles at the Vehicle Lift |
| Construction | Building and repairing blocks (not demolishing) |
| Crafting | Crafting gear/furniture at the Workbench; smelting ore/scrap at the Forge |
| Combat | Fighting enemies during raids and expeditions |
| Farming | Tending Growing Troughs (post-MVP) |

**Levels.** Every skill starts at **Level 1 (Novice)** and progresses to Level 5 (Master). Only successful completions grant progress.

| Level | Name | Notes |
| --- | --- | --- |
| 1 | Novice | Starting level. Can do basic regular jobs. Slow, lower quality. |
| 2 | Competent | Solidly faster. |
| 3 | Skilled | Dependable speed/quality. |
| 4 | Expert | Fast, high quality. |
| 5 | Master | Top-tier. |

Each level requires more successful uses than the last (placeholder curve: ~20 / 50 / 100 / 200 uses; designer-configurable), so mastery takes sustained effort.

**Work-speed multiplier per level** (designer-configurable; placeholder for playtest):

| Level | Name | Multiplier |
| --- | --- | --- |
| 1 | Novice | **1.0×** |
| 2 | Competent | **1.2×** |
| 3 | Skilled | **1.4×** |
| 4 | Expert | **1.7×** |
| 5 | Master | **2.0×** |

**Combining with Stamina (locked rule):** effective work speed is **multiplicative** — `final = base_rate × skill_multiplier × stamina_multiplier`. A L3 Construction colonist (1.4×) at 30% Stamina (in the Tired band, 0.8× work floor sliding toward 0.6× at collapse) builds at `1.4 × 0.8 = 1.12×` base. Both systems always matter; a low-skill colonist who is also exhausted is very slow. See `ARCHITECTURE.md` "Subsystem: Skills" + "Subsystem: Energy" for the component query flow.

**Regular jobs (MVP).** Day-to-day work at the functional furniture (treat at the Clinic Bed, smelt at the Forge, craft at the Workbench, repair at the Vehicle Lift, build blocks) requires **minimum Level 1** — any colonist can pitch in on basic work, and skill level scales speed/effectiveness. Higher-tier gates (advanced operations) arrive with specialists, post-MVP.

**Specialists (post-MVP).** A separate tier above regular jobs: the player promotes an existing colonist into a colony-wide **specialist** slot — one per functional area, assignable only once its required furniture is built. Specialists grant a colony-wide buff *and* unlock advanced operations. The player character cannot hold a specialist slot. Deferred until post-MVP.

### 6.4 Labor management

Labor management is a core MVP system. Each colonist has a **labor panel** where the player enables/disables work types and assigns priorities — Dwarf-Fortress-style per-colonist assignment, not fixed roles.

| Control | Detail |
| --- | --- |
| Work-type toggles | Per colonist, each skill's work (Medical, Mechanical, Construction, Crafting, Combat) can be enabled or disabled. |
| Priorities | Each enabled work type has a priority number; lower = preferred. |
| Auto-assignment | A colonist auto-takes enabled work they are Level 1+ in, choosing by priority → proximity → highest skill. |
| Manual pin | The player can pin a specific job to a colonist, overriding auto-assignment. |
| Fallback | Colonists with nothing enabled, or no matching work, fall back to generalist duties (haul, clean) or idle. |

### 6.5 Named vs unnamed colonists

Named colonists have unique backstories, narrative weight, and may start with higher skill levels. Unnamed (generic) colonists are workhorses — competent but expendable relative to named ones.

| Type | Permadeath rule |
| --- | --- |
| **Named colonist** | Death is permanent and final. Death notification in Day Summary with memorial entry. |
| **Unnamed colonist** | Death is permanent and final. No memorial entry (generic colonist). |

### 6.6 The Companion

The player does not start completely alone. On Day 1, a named companion is present at the base — injured and incapacitated, but alive. They cannot work or fight until treated at the Clinic Bed. This makes the Clinic Bed the first meaningful construction goal and gives the player an immediate emotional reason to act.

The companion is a named colonist with a fixed identity. Their relationship to the player — lover, sibling, close friend, or former rival — is post-MVP story content. In MVP they function as a mechanically distinct colonist with enhanced stats and expanded dialogue.

| Property | Value |
| --- | --- |
| **Type** | Named colonist. Full permadeath rules apply. |
| **Stat boost** | +20% to all stats vs a common colonist: HP, work speed, movement speed, and combat damage. |
| **Background** | Fixed narrative identity, assigned during story design (TBD). Story/flavor only, no mechanical role. |
| **Dialogue** | More dialogue options than common colonists. Reacts to base events, expedition outcomes, deaths, and player decisions. Full relationship system is post-MVP. |
| **Day 1 state** | Injured and incapacitated. Present at base. Non-functional until treated at the Clinic Bed. |
| **Relationship (post-MVP)** | Lover, sibling, close friend, or former rival. Defined through post-MVP story content. |

### 6.7 Raid stance

Each colonist has a **player-set raid stance** that determines their behavior when a raid occurs and the player is not present to direct them. Stances are assigned per colonist via the colony management screen and are **not tied to skills or any role** — the player decides who fights, who holds a post, and who shelters.

> **MVP combat rule — colonists hold position.** Colonists do **not** pathfind toward enemies or relocate during a raid in MVP. Combat is purely reactive: from their assigned post, they engage any enemy that enters their weapon's range. The three stances differ only by *where the colonist stands at raid start*.

| Stance | Where they stand | Engagement |
| --- | --- | --- |
| **Fight** | Current position at raid start (manual / last-known). | Reactive: engages any enemy within weapon range from that spot. |
| **Fight post** | An assigned post tile (Watchtower / gate / barricade section). | Same reactive rule, from the post tile. |
| **Shelter** | An assigned safe-room tile. | Same reactive rule; if the safe room is breached, fights from position. |

**Engagement logic (all stances, every tick):**
```
if missile weapon equipped AND enemy within missile range → fire
elif melee weapon equipped AND enemy within melee range (1.5m) → swing
else → hold position
```

**Max pursuit distance:** 0 (no pursuit in MVP). Job-pathfinding (§6.10) is a separate system and also does not run during raids.

**Placement at raid start:** manual / last-known position. Fight-Post tiles are assigned via the Colony Management screen; everyone else stays where they were when the raid began.

*Note: Stances are entirely player-set. A colony with everyone on Fight and no one Sheltering risks losing stockpiles and medical supplies if the base is breached; setting some colonists to Shelter protects them but leaves the perimeter thinner.*

#### Fight post designation

Fight posts are assigned through the colony management screen by selecting a colonist and then tapping a built structure on the base map. Any watchtower, gate, or barricade section can serve as a post. The structure is highlighted in the world when selected, and shows the assigned colonist's portrait icon above it during raids.

| Rule | Detail |
| --- | --- |
| How to assign | Select colonist in colony management screen → tap a built structure on the base map. |
| Valid structures | Watchtowers, gates, barricade sections. Plain wall blocks cannot be assigned as posts. |
| One colonist per post | Each structure supports one assigned colonist. A watchtower with two floors can have two posts (one per floor). |
| Visual feedback | Assigned structures show the colonist's portrait icon in build mode and during raids. |
| Unassigned fallback | If a colonist's assigned post structure is destroyed during a raid, they switch to Fight stance for the remainder of the raid. |

### 6.8 Colonist capacity

Maximum colony size is determined by the number of Colonist Beds placed in the base. Each bed supports one colonist. The player character does not require a bed. Beds are voxel-built furniture; adding capacity requires construction time and materials.

| Bed count | Max colonists |
| --- | --- |
| 1–3 beds | 1–3 colonists |
| 4–6 beds | 4–6 colonists |
| 7–10 beds | 7–10 colonists (hard cap) |

*(MVP cap: 5 colonists.)*

### 6.9 Recruitment

**MVP recruitment sources** (carry the colony from solo+companion to the cap of 5):

- **Random world events** — a stranger arrives at the base gate. *(Primary MVP source.)*
- **Radio contacts** — established via the Command Desk at higher capability levels.

**Post-MVP:**

- **Rescue expeditions** — a potential recruit is stranded at a POI; extracted via a Rescue-type expedition (see §17 — Rescue is post-MVP).

Named colonists have unique backstories and may start with higher skill levels. They are rare.

### 6.10 Colonist AI & task assignment `[DRAFT]`

> **Terminology (locked):** A **Labor** is a *category* of work — the column in the colonist screen, with a 0–5 priority per colonist. A **Job** is a *discrete unit of work* registered on the Job Board — one claimable thing one colonist does to completion. **Avoid the word "Task"** (overloaded with Godot's NavigationServer/behaviour-tree internals).

#### Labors (MVP categories)

Each colonist has a priority 0–5 per Labor (1 = highest, 5 = lowest, **0 = disabled**).

| Labor | Source furniture/activity | MVP? |
|---|---|---|
| **Construction** | Blueprint builds, repairs | ✅ MVP |
| **Crafting** | Workbench (ammo, components) | ✅ MVP |
| **Smelting** | Forge (ore → metal, scrap → components) | ✅ MVP |
| **Mechanics** | Vehicle Lift (vehicle/equipment repair) | ✅ MVP |
| **Hauling** | Moving items to storage crates | ✅ MVP (without it, crafting starves) |
| Repair | Workbench — restores Durability on armor + other items (see §6.11) | ❌ post-MVP (ships with the wear-and-repair loop) |
| Farming | Growing Trough | ❌ post-MVP (deferred with water/food) |
| Cooking | Kitchen | ❌ post-MVP |

#### Job Board (discovery & claiming)

A central **Job Board** (singleton) that furniture and blueprints register Jobs to. When a colonist is idle, it queries the board for the highest-priority Labor (on that colonist) with an available Job, then the next, etc. Claim is atomic — one colonist per Job.

#### Pathing

- **Colonists use A\* on the voxel grid.** The world is already a grid of passable/blocked cells, so pathfinding is natural and stays correct as the player builds. A\* rebakes instantly when a block changes and is perfectly door-aware. No built-in avoidance (acceptable for MVP colony sizes).
- **Enemies (Brawler/Shooter) use NavigationAgent + navmesh** — they roam open terrain and benefit from avoidance. This split matches "colonists on-grid, enemies in the field."
- Per §6.7, colonists do **not** path during raids in MVP (they hold position and fight reactively). Pathing here covers job-related travel only.

#### Tie-break order

When multiple Jobs match a colonist's enabled Labors: **Priority → Proximity**. (Skill is dropped as a tie-breaker for MVP.) Final order: highest-priority Labor on that colonist → nearest available Job of that type.

#### Stacking

**No stacking in MVP.** A Job is claimed by exactly one colonist. (Post-MVP: additive build-rate stacking.)

#### Failure handling

When a colonist can't finish a Job (missing materials / blocked path / target destroyed):

1. Write an entry to the **Job Log** (timestamp + colonist + reason).
2. **Skip to the next enabled Job** — do not idle on the failure.
3. The failed Job stays on the board with an incremented failure count.

**Early-MVP rule (auto-remove):** after **3 consecutive failures**, the Job is **auto-removed** from the board. If it's a blueprint build, the blueprint stays placed; the Job can be re-registered later if conditions might be met.

**Late-MVP upgrade (blocked-state):** instead of auto-remove, the Job enters a "blocked" state with **auto-unblock triggers**:
- `NoMaterials` → unblocks when a matching item stack enters any colony storage crate.
- `NoPath` → unblocks when a block is built/demolished in a way that changes connectivity.
- `TargetDestroyed` → never auto-unblocks; Job is removed.
- The Job Log gains a single **"Retry"** button per blocked Job (the only player action on the board).

**Player interaction is read-only** (except the late-MVP Retry button). The Job Log is a diagnostic feed ("Workbench #3 job 'Craft 10 9mm' blocked — NoMaterials (12:42)"), not a to-do list. The player fixes root causes (source materials, clear a path) rather than clicking "retry" repeatedly.

*Effort estimate for late-MVP upgrade: ~1 day (two fields + two signal hooks + one button). Defer until the core loop is shipped and log spam is visible in playtest.*

### 6.11 Damage Resolution (shared by player, colonists, and enemies)

Durability acts as a damage buffer that depletes before HP. This applies to every combat entity. Durability represents the condition of equipped armor — it is both the ablative hit-absorption pool *and* the item's wear state (one unified property); see the note in §17 Equipment on wear/repair being post-MVP.

| Step | Rule |
| --- | --- |
| Step 1 | Incoming hit dealt. Check if target has Durability > 0. |
| Step 2 (Durability > 0) | Damage reduces Durability first. If damage > remaining Durability, overflow carries into HP. |
| Step 3 (Durability = 0) | All damage applies directly to HP. |
| Step 4 | If HP ≤ 0: incapacitation / death, per permadeath rule. |

*Example: a Brawler hits a survivor with 25 Durability and 100 HP. First hit: 25 damage wipes Durability, HP remains 100. Second hit: 25 damage to HP, HP = 75.*

> **Durability recovery:** regained via a **repair crafting job** (post-MVP — armor + other items). For **MVP interim**, Durability **auto-recovers to full on sleep** so armor functions as a reliable per-day ablative buffer without forcing replacement; the wear-and-repair loop (degrading through use, Workbench repair with materials) activates when the repair job ships. *If MVP playtesting shows this feels wrong, the fallback is "repair only by crafting job" once that job exists.*

---

## 7. Base Building `[DRAFT]`

> Core system (the voxel base *is* the core loop). Treated as a core section, not a subsystem.

### 7.1 Voxel construction

The base is built block by block in a voxel world. Blocks are not placed instantly — construction is manual work performed by the player or assigned colonists. A colonist or the player must physically work on a block to place or remove it. This means the base changes slowly and deliberately, which has two important effects: structural changes are visible and meaningful, and enemy pathfinding is not disrupted by instant geometry changes.

*MVP: No structure support or gravity — blocks may float freely (no foundation, adjacency, or support requirement). Structural support and gravity are post-MVP.*

| Construction rule | Detail |
| --- | --- |
| **Block placement** | Requires a colonist or the player to be within construction range and work on the block. Progress is shown as a build animation. |
| **Block removal** | Same manual process as placement. Cannot be instant-demolished. |
| **Materials** | Different block types require different resources. Wood, scrap, stone, metal, and reinforced variants each have different durability. Wood is the base material — salvaged timber, plastic, and debris collapsed into one cheap buildable block. |
| **Durability** | Blocks have HP. Enemies prioritize attacking low-HP blocks (weak points). Damaged blocks can be repaired by colonists or the player. HP values are defined in the Buildables table. |
| **Block footprint** | Equipment and furniture occupy multiple blocks. A Clinic Bed occupies 1×2 floor space. A Forge occupies 2×2. |

### 7.2 Buildables

The table below is the single source of truth for every buildable object's HP, volume (placement footprint), and material cost. All build/repair/demolition times derive from HP (see §7.4 Construction). Volume is a placement property only; it is not used to calculate HP.

| Type | HP | Height | Width | Depth | Description | Materials |
| --- | --- | --- | --- | --- | --- | --- |
| Wood Block | 50 | 1 | 1 | 1 | Base construction block. Salvaged timber, debris, plastic. | 3 Wood |
| Scrap Block | 100 | 1 | 1 | 1 | Construction block. Salvaged metal scraps. | 3 Scrap |
| Stone Block | 300 | 1 | 1 | 1 | Construction block. Quarried or scavenged stone. | 3 Stone |
| Metal Block | 600 | 1 | 1 | 1 | Construction block. Processed from ore or scrap. | 3 Metal |
| Reinforced Block | 1200 | 1 | 1 | 1 | Construction block. Metal + components. Highest HP tier. | 3 Reinforced |
| Wooden Door | 120 | 2 | 1 | 1 | Door; swings open/closed when interacted with. | 10 Wood |
| Gate | 200 | 2 | 2 | 1 | Wider opening for perimeter/vehicle access. | 10 Metal + 5 Components |
| Clinic Bed | 50 | 1 | 2 | 1 | Medical care; treats injuries and Stamina. | 100 Scrap |
| Workbench | 60 | 1 | 2 | 1 | Crafting station; required to craft other furniture. | 60 Scrap + 10 Components |
| Forge | 100 | 2 | 2 | 1 | Smelting; ore to metal, scrap to components. | 80 Scrap + 20 Components |
| Colonist Bed | 50 | 1 | 2 | 1 | Rest; each bed adds one colonist slot. | 40 Scrap + 5 Components |
| Command Desk | 60 | 1 | 2 | 1 | World map, expedition planning, colonist assignment. | 120 Scrap + 30 Components |
| Vehicle Lift | 100 | 2 | 2 | 1 | Vehicle repair and upgrades; required for expeditions. | 120 Scrap + 40 Components |
| Growing Trough | 40 | 1 | 2 | 1 | Crop cultivation; needs water nearby. Post-MVP. | 60 Scrap |
| Watchtower | 300 | 1 | 3 | 3 | Elevated platform; colonists gain range advantage. | 10 Stone |
| Spike Trap | 50 | 1 | 1 | 1 | Placed outside walls; slows and damages enemies. | 5 Scrap + 2 Components |
| Turret | 150 | 2 | 1 | 1 | Automated ranged defense; requires nearby power. | 40 Scrap + 30 Components |

*Note: All values are designer-configurable starting points for playtesting. Block HP and the Wooden Door were already specified; all furniture/defense HP, footprints, and costs, plus the Gate entry, are reasonable defaults filled in pending review.*

### 7.3 Items

All items in the game — construction materials, tools, weapons, armor, key items, and consumables.

| Item | Description |
| --- | --- |
| Wood | Salvaged timber, debris, and plastic from scavenge sites. The base construction material. |
| Scrap | Salvaged metal scraps from scavenge containers and wreckage. Used for Scrap blocks and furniture. |
| Stone | Stone from mining sites. Construction material. |
| Ore | Raw metal ore from mining veins. Refined into Metal at the Forge. |
| Metal | Refined from Ore at the Forge. Construction material for Metal blocks and gates. |
| Components | Electronics and machinery parts refined from Scrap at the Forge. Used in furniture, defenses, and Reinforced. |
| Reinforced | Composite of Metal + Components made at the Forge. Highest-tier construction material. |
| Fuel | Fuel from scavenge drums and vehicles. Powers expeditions and vehicles. |
| Med Supplies | Medical consumable from scavenge loot. **Dual role:** (a) consumed at the Clinic Bed to boost healing, and (b) usable as a standalone field-heal item. |
| Food / seeds | Crops and seeds from scavenge and trading. Dormant in MVP — no hunger mechanic until post-MVP. |
| Cloth | Woven fabric and cloth from scavenge sites. Used to craft Cloth armor. |
| Leather | Tanned hides and leather from scavenge sites. Used to craft Leather armor. |
| Radio Transceiver Unit | Key item. Consumed by the Command Center T2 upgrade. |
| Portable Generator | Key item. Consumed by the Workshop T2 upgrade. |
| Water Pump Motor | Key item. Consumed by the Farm T2 upgrade. |
| Medical Fridge Unit | Key item. Consumed by the Infirmary T2 upgrade. |
| Heavy Jack Lift | Key item. Consumed by the Garage T2 upgrade. |
| Insulation Panels | Key item. Consumed by the Living Quarters T2 upgrade. |
| Welding Gas Cylinders | Key item. Consumed by the Defenses T2 upgrade. |
| Stimpack | Future consumable (post-MVP). Temporarily suppresses Stamina penalties during a mission. |

*Note: Key Items are rare drops from deep scavenge loot (Zone C containers). Each Key Item drops at most once per playthrough and is consumed by a T2 base upgrade recipe.*

*Note: Trading is planned but not in MVP scope. A future mechanic will let the colony trade surplus resources with survivor factions encountered via the Command Desk radio.*

### 7.4 Construction

Plain blocks are 1m³; a standard interior wall is 3 blocks tall (3m). Build and repair time is derived from the block's HP and the equipped tool: **time = block HP ÷ (tool repair amount × tool rate of fire)**. This applies to every buildable object — build time scales with the object's HP as defined in the Buildables table. Material has no timing factor of its own; it only sets HP. **Stacking: no — in MVP a Job (and therefore a block under construction) is claimed by exactly one colonist.** (See §6.10; additive build-rate stacking is post-MVP.)

Colonists have a construction range — a sphere centered on the colonist. The radius is set by the equipped tool: **hammer = 3m**, **nailgun = 6m**. With no tool equipped, range is adjacent-only (~1.5m). A colonist can construct and repair any block within range, so the player can stay in one spot to build multiple blocks consecutively — a single "Start building" job builds all in-range jobs in sequence.

#### Construction tools

| Tool | Repair amount | Rate of fire | Range | Cost |
| --- | --- | --- | --- | --- |
| Bare hands | 5 | 1/sec | ~1.5m (adjacent) | — (default) |
| Hammer | 10 | 1/sec | 3m | 5 Scrap |
| Nailgun | 30 | 1/sec | 6m | 20 Scrap + 10 Components |

Repair tools: Left click to repair/build. Each repair tool has a repair value. Each tool use adds HP to a block based on the repair value. The block is fully constructed or repaired once it reaches 100% HP. The materials are removed from the colonist's inventory based on the repaired amount. Repair or construction fails if the colonist does not have enough materials.

Materials: Some blocks can be constructed from raw materials or placed whole. For example, a wooden door can be built on the spot with the required wood materials. A full door can also be constructed in a workbench and brought to the site. Using a constructed item is faster to build — for now, just multiply the construction tool's repair amount by 5 when using a pre-constructed item like a wooden door.

#### Blueprint mode

Blueprint mode is the construction planning tool, toggled with **B**. While active, the player places, removes, and selects blueprint blocks — the non-physical plan version of buildable objects (see Buildables). Placed blueprints are then constructed into real blocks by colonists (see Construction).

Rotation: The default rotation axis is **Z (vertical, top-to-bottom)** — the footprint spins like a top in the horizontal plane (this project uses Z-up; see `gotchas/blender_obj_export.md`). **Mouse wheel up/down** rotates the block in 90° increments around the active axis. **Pressing R** cycles the active axis: Z → X → Y → Z. The rotation axis passes through the **center of a block, not a seam** — this works cleanly for footprints with an odd number of blocks along the perpendicular axes.

**Even-sized footprint rotation rule:** when rotating an even-sized footprint (e.g. 2×2), first shift the placement pivot backward by **0.5m** on each axis so the pivot lands on a block center, then apply the 90° rotation. The player adjusts the crosshair position to re-place. Rotation is always allowed (no demolish-and-rebuild).

- Left-clicking places a blueprint block.
- Right-clicking removes it.
- Middle-clicking on a blueprint block selects it.

### 7.5 Demolition (block removal)

Removing is always faster than placing. Removal rate = tool repair amount × 2 × rate of fire (twice the build rate). Demolition time = block HP ÷ removal rate.

### 7.6 Block HP and durability

All blocks have HP. Damaged blocks retain their position until HP reaches 0, at which point they are destroyed and removed from the voxel grid, creating a breach.

- **Destroyed blocks:** Player-placed blocks that are destroyed are immediately replaced by a blueprint of the same block with the same rotation.
- **Collision:** A block is solid and blocks pathing as soon as it has any HP (≥1 HP — i.e., once construction begins). Blueprints are non-physical and do not collide or block pathing until construction starts and the block gains HP.

### 7.7 Gates, furniture, and repair

| Object | HP rule |
| --- | --- |
| **Damaged block repair** | Repair uses the same action and the same formula as construction (adding HP back to the block). Full repair from 0 HP therefore takes the same time as fresh placement. |
| **Visual damage states** | Blocks should display visual wear at 50% and 25% HP thresholds (crumbling scrap, cracked stone, bent metal). Placeholder textures acceptable for MVP. Communicates breach risk without requiring the player to monitor HP numbers. |

### 7.8 Functional rooms

Rooms are not defined by a boundary or a room type — they are defined by the functional furniture placed inside them. Each key functional area of the base is unlocked by placing its core furniture item anywhere in the base. Players are free to organize their base however they like; most will naturally cluster functional furniture into themed rooms for efficiency and clarity.

**What counts as "functional furniture":** only the 7 area-defining types in the table below (Clinic Bed, Workbench, Forge, Command Desk, Vehicle Lift, Colonist Bed, Growing Trough). Storage crates, watchtowers, spike traps, lamps, and other non-area furniture do **not** count — they're not capability unlocks.

**Visibility bonus (locked rule):** each placed functional-furniture **item** adds **+3 to all map edges equally** for raid threat (see §17 Raids). The count is **per item, not per type** — 3 Workbenches = +9 to all edges. This makes expansion costly; lean, specialized bases are rewarded. (Post-MVP: consider per-type capping if expansion feels too punishing.)

| Functional area | Core furniture item | What it unlocks |
| --- | --- | --- |
| Command & planning | Command Desk | World map access, expedition planning, colonist assignment interface. |
| Medical care | Clinic Bed | Injured survivor treatment, Stamina recovery acceleration for critical cases. |
| Crafting | Workbench | Equipment crafting, repair, and gear management. |
| Smelting & materials | Forge | Raw material processing — ore to metal, scrap to components. |
| Food production | Growing Trough | Crop cultivation. Requires water access nearby. **Post-MVP only** — not implemented in MVP. |
| Vehicle maintenance | Vehicle Lift | Vehicle repair and upgrades. Required for expedition capability. |
| Rest & recovery | Colonist Bed | Sleep recovery for colonists. Max colony size tied to bed count. |

### 7.9 Crafting

Crafting converts raw materials into furniture, equipment, and consumables at crafting stations. The **recipe system** is unified — one `Recipe` shape covers all craftable output (furniture, armor, weapons, ammo). Each recipe specifies the output item + count, the input materials + counts, the required station, the governing skill, and a base craft time (which the work-speed multiplier from §6.3 modifies).

**Stations and their recipes:**

| Station | Crafts | Examples |
|---|---|---|
| **Workbench** | Furniture, armor, weapons, ammo | Clinic Bed, Cloth/Leather/Scrap armor pieces, Knife, Pistol, Bullets |
| **Forge** | Materials (smelting) | Ore → Metal, Scrap → Components, Metal + Components → Reinforced |

(HP, footprint, and material costs for all furniture are listed in the Buildables table §7.2; armor crafting costs in §17 Equipment; weapon/ammo crafting costs in §17 Equipment.)

**MVP scope:**
- All recipes are **available from the start** — no tech tree, no unlocking, no discovery. The constraint is materials + station + skill gate (L1 Crafting for Workbench recipes, L1 Smelting for Forge recipes).
- The **Crafting Labor** (§6.10) claims craft Jobs from the Job Board; the colonist paths to the station, consumes materials from colony storage, applies the work-speed multiplier (skill × Stamina per §6.3), and deposits the output.
- See `ARCHITECTURE.md` "Subsystem: Crafting" for the recipe data model and craft-Job flow.

**Post-MVP:** recipe unlocking/tech tree, specialist-gated advanced recipes, the Durability wear-and-repair loop (armor repair Jobs at the Workbench — see §2 Out-of-Scope).

*Note: All costs are designer-configurable starting values. Clinic Bed at 100 scrap is a guess — adjust based on how long the forced Day 1 scavenge run feels in playtesting. The Workbench cost matters most: it gates all other crafting, so it should be achievable on Day 1 or early Day 2.*

*Note: Additional supporting equipment (storage crates, lighting, medical fridge, water pump, etc.) improves efficiency of the functional area but is not required to unlock it. This gives players a progression path — a functional but bare clinic on day one, a well-equipped one by week two.*

### 7.10 Perimeter and defenses

Defensive structures are voxel-built like everything else. The player chooses where to place walls, gates, watchtowers, and traps. Enemy raids target structural weak points — thinner walls, ungated openings, and isolated sections — so the layout of the perimeter directly affects raid outcomes.

| Structure type | Notes |
| --- | --- |
| **Walls** | Primary barrier. Different materials have different HP. Stone walls are much harder to breach than Scrap. |
| **Gates / doors** | Openings that colonists and the player can pass through. Enemies will path through open gates if available. |
| **Watchtowers** | Elevated platforms. A colonist occupies it; ranged attacks from elevation. **400 HP.** MVP: no combat buff (post-MVP: +range/accuracy for the occupant, plus mounted weapons). |
| **Spike traps** | Placed outside walls. **50 HP, 15 damage on contact.** Loses **10 HP each time it is touched by an enemy** (~5 contacts to destroy). **MVP trigger rule: only enemies trigger it** — colonists and the player pass through with no effect. Persistent until HP 0 (not one-use). *(Post-MVP: revisit trigger rule + HP-per-contact value.)* |
| **Turrets** | **Implemented Early (Steampunk / Horde Defense Pivot)**: Automated ranged defenses (Wooden Stake Turret, Rock Thrower, Arrow Launcher, Rifle Turret, Bomb Launcher, Gatling Gun Turret). Authored as Furniture capability (`TurretParams` on `FurnitureDef`). Targets the closest enemy within range and draws ammunition directly from Colony storage (or local inventory). Decoupled from the deferred Power system. |

#### 7.10.1 Planned Turret Automation: Deployable Sensor & Target Markers

For tactical perimeter defense and choke-point control (especially for area-of-effect and explosive turrets such as the Bomb Launcher), a coordinate-linked marker system is planned:

- **Deployable Sensor Markers**: Placeable perimeter beacons/trip sensors with designer/player configurable detection radii. When hostile entities enter the sensor zone, the sensor trips.
- **Target Markers**: Deployable ground markers designating a pre-calibrated impact coordinate/zone.
- **Trigger-to-Target Linking**: Turrets can be configured to link one or more sensor markers to a target marker. When a linked sensor is tripped, the turret fires upon the predetermined target marker (bombarding the killzone) rather than dynamically leading individual moving targets. Enables predictive choke point saturation and interlocking defensive fields.

### 7.11 Storage, equipment, and deferred systems

**MVP storage & supporting equipment:**

| Object | MVP behavior |
|---|---|
| **Storage Crate** | Proximity access — player/colonist must be within **2m** to store/retrieve. Acts as a shared colony inventory node. Capacity: **32 stacks** per crate. |
| **Lighting (lamp/torch)** | Affects player view distance/visibility only. **No effect on colonists in MVP.** |
| Medical Fridge | **Deferred to post-MVP** with the medical-system work. |
| Water Pump | **Deferred to post-MVP** (with the Water system, below). |

**Systems deferred to post-MVP (remove any dangling references):**

- **Power system** — spec generators, power range, wiring. Turrets have been implemented early with direct ammunition consumption from colony stockpiles, decoupling them from electrical wiring. Power grid remains deferred/out-of-scope.
- **Water system** — spec water sources, piping, access rules. Was referenced by the Growing Trough (itself post-MVP with food/hunger). Defer water with food/hunger. Add "Water system" to Out-of-Scope.

**Resolved (no longer TODO):**

- ~~Even-sized footprint rotation~~ → resolved, see §7.4 (0.5m pivot shift rule).
- ~~Stacking multiple colonists on one block~~ → resolved, see §6.10 (no stacking in MVP).
- ~~Defense structure build rules~~ → Watchtower, Spike Trap, and Turret defenses specified above.

---

## 8. Win and Fail Conditions `[DRAFT]`

### Win Condition `[DRAFT]`

**MVP has no win condition — it is open-ended sandbox.** Survival + colony growth *is* the game; the fail condition (below) is the sole end state. A campaign with story-driven win goals is planned for post-MVP.

- **Condition:** None (MVP).
- **On win:** N/A (MVP).

### Fail / Death Condition `[DRAFT]`

- **Condition:** All colonists **and** the player character are dead → Game Over.
- **Player death alone:** Does **not** end the game. Player respawns at base (at 50% HP + 1 day recovery if killed on an expedition; all mission loot lost).
- **Colonist death:** Permanent (see Permadeath subsystem).
- **On fail (Game Over):** Stop input → Game Over screen (see §12 for elements: days survived, memorial roster, cause of wipe, resource summary, build/enemy counts, [New Game] / [Main Menu] buttons). New game resets all state including map reveal.
- **Lives system:** No
- **Continues:** No
- **Restart behaviour:** New game resets all state including map reveal. (Victory state, future, preserves map reveal and memorial roster as a record.)

---

## 9. Starting Conditions (Day 1) `[DRAFT]`

The player begins in a ruined shelter with a named companion who is injured and incapacitated. The first goal is clear: build a Clinic Bed to revive them. All starting values are designer-configurable and intended as a playtesting baseline.

### 9.1 Starting structure

One small pre-built room approximately 3×3m interior with a 3m roof — roughly 16 Scrap blocks. No door; the entrance is open. The companion lies inside. The player's own bed is already placed inside the room. No other furniture exists. *The open entrance is intentional: it signals that doors must be built and teaches the construction system immediately.*

### 9.2 Starting resources

| Resource | Amount | Notes |
| --- | --- | --- |
| Scrap | 80 | Primary early building material. Used for both construction (Scrap blocks) and crafting. Enough for Clinic Bed + a few extra blocks. |
| Components | 15 | Required for furniture crafting. |
| Fuel | 20 | One short expedition's worth. |
| Stone | 0 | Must be acquired via mining or scavenge. |
| Ore | 0 | Post-MVP resource. Not available on Day 1. |

### 9.3 Starting equipment

| Item | Quantity | State | Notes |
| --- | --- | --- | --- |
| Knife | 1 | Equipped | Player's melee weapon. |
| Pistol | 1 | In storage | Available from Day 1, not yet equipped. |
| Leather Armor | 1 | Equipped | Player's starting armor (+25 Durability). |

### 9.4 Day 1 intended sequence

1. Player wakes in the ruined shelter. Companion is incapacitated inside.
2. Player opens inventory — sees 80 scrap, 15 components. Clinic Bed costs 100 scrap (see Furniture Crafting Costs).
3. **Player must go on a short scavenge run first.** They need at least 20 more scrap before the Clinic Bed is buildable. This immediately teaches the expedition system and map.
4. Player returns, crafts and places Clinic Bed inside the shelter.
5. Companion recovers. First colonist is now active.
6. Player sleeps → Day Summary fires → Day 2 begins with two active people.

*Note: The intentional scrap shortfall (80 of 100 needed) means the player cannot skip the expedition system on Day 1. If playtesting shows this creates frustrating friction rather than purposeful tension, increase starting scrap to 120 and remove the forced first expedition.*

### 9.5 Post-MVP: configurable start

Starting resources, equipment, and pre-built structure will be exposed as configurable options in a game creation screen post-MVP. This supports different difficulty modes (Survivor / Brutal / Custom) without requiring separate balance passes.

---

## 10. World Structure `[DRAFT]`

### 10.1 Map design

*MVP:* The world is divided into discrete maps. Each location — the player's base and every point of interest — is its own scene. Travel between maps consumes Fuel and advances time proportional to distance.

*Future:* True open world, with chunking handled by Zylann's voxel Godot plugin.

| Map type | Description |
| --- | --- |
| **Home base** | The player's colony. Fully voxel-built and persistent. All colonist activity happens here when the player is away. |
| **POI** | Mission-specific POIs. |

### 10.2 Fog of war

The world map opens fully fogged. Travelling to a POI reveals that sector and all immediately adjacent sectors permanently. Reveal triggers on arrival — an ambush intercept during travel does not grant the reveal. The home base sector and its immediate neighbors are pre-revealed at game start.

| Sector state | Map display | Notes |
| --- | --- | --- |
| **Fogged** | Dark overlay. No icons. | Cannot be targeted for travel. |
| **Revealed (unvisited)** | POI type icon visible, muted. | Can be targeted. Reveals fully on arrival. |
| **Visited** | Full icon, name, available missions. | Can be targeted for repeat visits. |

---

## 11. Progression `[DRAFT]`

- **Level structure:** Discrete maps per location (no procedural generation in MVP). Home base + POI scenes. Fog-of-war reveal on visit.
- **Number of levels/POIs:** **1 handcrafted scavenge POI** for MVP (the single explorable sector on the world map). Procedural generation and additional POI types are post-MVP.
- **Progression unlock:** Fog-of-war reveals POIs; skills level with use (L1→L5); colony grows via recruitment (bed-capped); raids escalate with colony age + visibility; Key Items gate T2 base upgrades.
- **Difficulty scaling:** Per-POI Easy / Normal / Hard tiers (see Expedition subsystem — Difficulty Scaling Reference); raid escalation scales with colony age and visibility (placeholder values, pending playtesting); threat-direction weights shift with player activity.
- **Save / checkpoint system:** Autosave on sleep, on quit-to-menu, and at in-game midnight (persistent voxel world state). No manual save in MVP. (See *Subsystem: Save & Reset*.)

---

## 12. Screens and UI `[DRAFT]`

> List every screen. Agents will invent screens if you don't enumerate them.

### HUD (In-Game) `[DRAFT]`

| Element | Description |
| --- | --- |
| **Resources** | Top left. Scrap, Components, Fuel, Stone, Ore counts always visible. Food count displayed but greyed out in MVP (dormant system). |
| **In-game clock** | Top right. Day counter and time of day. |
| **Colonist portraits** | Side panel. Each colonist's portrait with HP bar, Stamina status icon, and raid stance icon. Grayed with skull on death. |
| **Text notifications** | Bottom center. Construction complete, raid warning, colonist status changes. |
| **Build mode** | Toggled by the player. Overlay shows block placement ghost, material cost, and colonist assignment for construction jobs. |
| **Death feedback** | Mid-raid / mid-expedition: red screen-edge flash + audio sting on colonist death (no pause). Portrait grays out with skull icon immediately. |

### Day Summary `[DRAFT]`

Triggered on sleep. Shows: resources gained/lost, expeditions completed, colonists lost (Fallen section), construction completed, raids survived. *(See Expedition subsystem for mission-result block fields.)*

### Player screen `[DRAFT]`

Opened with **Z** (or **I** to jump straight to the Inventory tab). Full-screen overlay; pauses the game (consistent with §12 Pause Menu). Esc closes.

| Tab | Contents | MVP? |
|---|---|---|
| **Player Info** | Avatar portrait, name, callsign, HP/Durability/Stamina/Breath bars, days survived, plus stats (kills, builds, distance, resources) folded in. | ✅ MVP |
| **Inventory** | See *Inventory* spec below. Default tab when opened via **I**. | ✅ MVP |
| **Gear / Loadout** | Player's equipped slots: primary weapon, secondary weapon, armor, utility item. Click a slot → assign from inventory. (Distinct from colonist loadouts in the Colony screen.) | ✅ MVP |
| **Skills** | Skill tree / progression. Tab present-but-empty in MVP ("post-MVP"). | ❌ post-MVP (reserve the tab) |

*No separate Stats tab for MVP — stats fold into Player Info.*

### Colony Management `[DRAFT]`

Opened with **X**. Full-screen overlay; pauses the game. Five tabs:

- **Roster** *(default/first)* — one-row-per-colonist read-only dashboard: name, current Labor focus, HP, equipped weapon, raid stance, status (idle/working/sleeping/dead).
- **Labor** — grid: colonists as rows (alphabetical in MVP; sorting/filtering post-MVP), Labors as columns (Construction, Crafting, Smelting, Mechanics, Hauling). Cell = priority 0–5 (1 highest, 5 lowest, 0 disabled).
- **Defense** — per-colonist raid-stance radio (Fight / Fight Post / Shelter) + Fight-Post assignment (dropdown of placed Watchtowers + "None"). Radio buttons, not dropdowns — faster.
- **Loadouts** — loadout list on top (with **New** / **Delete** buttons); clicking a loadout shows its gear, one line per slot. Clicking a slot offers: pick a different discovered gear, leave empty, or auto-assign (MVP: nearest unclaimed item for that slot; post-MVP: "best" item). Below the loadout list: a colony list, each with a dropdown of available loadouts. *Per-colonist assignment in MVP; "Colonist Groups" (assign loadouts/priorities/away-teams by group) is pinned post-MVP.*
- **Expeditions** — checkbox crew list per expedition. *(Post-MVP: multiple away crews via dropdowns.)*

### World Map / Command Desk `[DRAFT]`

**Hex-grid** sector map. Each sector tile shows fog state (unexplored/explored/cleared). POIs render as icons on their sector. On hover/select a sector: a panel shows the **POI name with travel cost directly below it** (e.g. "Scrap Yard / Fuel: 2"). Crew assembler is a checkbox list (mirrors the Expeditions tab). 1 POI in MVP (see §11).

### Blueprint / Build Mode overlay

See §7.4 Blueprint mode (placement ghost, material cost, colonist assignment).

### Main Menu `[DRAFT]`

- **Elements:** **New Game** (prompts for playthrough name → creates save → starts), **Continue** (loads most recent autosave), **Load** (save-slot picker), **Settings** (see below), **Quit**.
- **Does NOT have:** Credits (post-MVP). Animated background (static key art for MVP).

### Pause Menu `[DRAFT]`

The game can be **fully paused everywhere** (raids and expeditions included — generous for MVP). Triggered by **Esc**; Esc again resumes.

- **Elements:** **Resume / Settings / Quit to Main Menu**.
- **Does NOT have:** Save entry (autosave only — see §17 Save & Reset).

### Game Over `[DRAFT]`

- **Trigger:** all colonists **and** the player character dead.
- **Elements:** "Game Over" title; **days survived** (primary stat); **colonist memorial roster** (name + how they died + day); **cause of final wipe** (last lethal event); **resources at death** (one-line scrap/materials/ammo summary); **build count / structures built**; **enemies killed (total)**.
- **Actions:** **[New Game]** / **[Main Menu]**.

### Settings `[DRAFT]`

- **Video:** Resolution + Fullscreen toggle + VSync toggle. (Quality presets → post-MVP.)
- **Audio:** Master / SFX / Music volume sliders. Music slider can sit at 0 (no music in MVP — see §13). Tab wired but largely inert for MVP.
- **Controls:** none in MVP. Keybinds → post-MVP.
- **Gameplay:** none in MVP.

### Inventory `[DRAFT]`

Lives inside the Player screen (Inventory tab — see above). Grid layout:

- **Top:** item details panel — empty until an item is selected. Shows item icon, name, description, current stack count. Usable items (e.g. healing) get action buttons here.
- **Bottom:** grid of slots, **10 per row**. **First row = hotbar** (slots 1–0). Remaining rows = general inventory. Default **30 total slots including hotbar**.

**Pickup (no auto-pickup):** items enter the inventory only via (1) interacting with a world item (**E**), or (2) taking from a container (crate proximity). No walkover auto-pickup.

**Stacking algorithm on add:**
1. If a stack of the same item type exists and is **not full** → transfer into it (up to cap).
2. Overflow → try the next same-type stack, or open a **new slot**.
3. **If no slot is available:**
   - From a container: subtract the transferred amount from the source stack (partial fill succeeds).
   - From a world item: partial fill goes to inventory; **remainder re-drops in the world** with the remaining stack count.
4. No same-type stack → empty slot.
5. No empty slot → same overflow rules apply.

**Slot preference:** auto-place **prefers non-hotbar slots first**; only auto-place in hotbar slots if no free non-hotbar slots remain.

**Item interaction:** click an item → details panel (top). Usable items → action buttons in the details panel.

**Hotbar:** first grid row (slots 1–0). Drag from inventory to reassign, or click-to-assign.

### Loadout Template editor `[DRAFT]`

See *Colony Management → Loadouts* tab above. Per-colonist assignment in MVP; "Colonist Groups" (loadouts/priorities/away-teams by group) is pinned post-MVP.

---

## 13. Audio `[DRAFT]`

**Audio is OUT OF SCOPE for MVP.** Defer all audio — SFX, music, voice/radio cues — to post-MVP. The game ships silent for MVP.

- Add to Out-of-Scope: SFX, music, voice/radio cues.
- The Audio tab in Settings (§12) stays wired-but-silent so the UI exists for later.
- Any SFX-trigger references elsewhere in the design (weapon-fire aggro, raid-warning cues, etc.) are gameplay/electronic cues only in MVP — not audio events. Re-introduce as audio hooks in post-MVP.

### Music

- Deferred to post-MVP.

### Sound Effects

- Deferred to post-MVP. The SFX event list below is preserved as a reference for the post-MVP audio pass:

- Colonist death (red screen-edge flash + audio sting)
- Scavenge wave warning ("Hostile activity detected" + radio cue at 2:30 before wave 1)
- Weapon fire (triggers enemy aggro if heard — implies an audio event)
- Construction complete (notification)
- Raid warning (notification)
- Block destruction / breach
- Loot interaction
- Vehicle extraction

---

## 14. Fixed Values `[DRAFT]`

> Values that are intentionally fixed and should NOT be made configurable or dynamic by the agent unless explicitly asked. The data-driven architecture (see Mod Support subsystem) externalises many *content* values as resource files by design — that is intended. This table is for values that should stay hardcoded or clearly scoped.

| Value | Setting | Notes |
| --- | --- | --- |
| Engine | Godot 4 (GDScript) | |
| Project axis | Z-up | See `gotchas/blender_obj_export.md` |
| Voxel block size | 1m³ | Standard interior wall = 3 blocks tall (3m) |
| Block gravity / support | Off in MVP (blocks may float) | Post-MVP: structural support + gravity |
| Max colony size | 10 (hard cap) | MVP cap: 5. Tied to Colonist Bed count. |
| Player character | Does not require a bed; cannot hold a specialist slot | |
| Raid safety-net threshold | Raids disabled while colonists < 3 (excluding player) | |
| Time advance | Continuous, passive; same rate during base activity and travel | No forced end-of-day |
| Night | No special penalties in MVP (atmospheric only) | |
| Damage model | Durability depletes before HP (all entities) | See §6.11 |
| Player death | Does not end the game; respawn at base | Game Over only when all colonists + player dead |
| Permadeath | Permanent for all colonists (named + unnamed) | |
| Save trigger | On sleep AND on quit-to-menu AND at in-game midnight (MVP) | No manual save in MVP |
| Debug console toggle | **~** or **F1** | Dev/playtest only |
| Blueprint mode toggle | **B** | |
| Rotation cycle key | **R** (Z → X → Y → Z) | Default axis Z |
| Brawler | HP 140, Durability 0, 25 melee dmg, 1/sec, 2.1 m/s (60% of 3.5), 10m detect, 1.5m attack range, 5s LOS-loss timeout | Drops nothing in MVP |
| Shooter | HP 60, Durability 0, 12 ranged dmg, 1 shot/1.5s, 2.98 m/s (85% of 3.5), 16m detect, 10m holding range | Drops nothing in MVP |
| Player base move speed | 3.5 m/s (walk) | Sprint 1.6× = 5.6 m/s |
| Breath costs (burst) | sprint −20/sec, jump −10, melee −5, ranged −2; regen +10/sec idle | See Energy subsystem; empty (< 20%) blocks sprint |
| Max enemies on screen | 24 (hard cap) | Spawn manager throttles waves at cap |
| Target framerate | 60 fps target, 30 fps floor on min-spec | |
| Gravity (3D) | 9.8 m/s² on Y (Godot default) | Affects player + NPC physics only; blocks are static |
| Max HP | Player 200, colonist 100 (before companion +20%) | Exposed as @export |
| Loop length | 1 in-game day ≈ 30 min real time | Session length is open-ended |
| Player state model | Two-layer: Mode (Normal/Blueprint) + State (Idle/Walk/Sprint/Attack/Interact/Sleep/Dead) | Single merged Attack state |

---

## 15. Platform and Technical Notes `[DRAFT]`

- **Platform:** PC (initial) — consoles later
- **Orientation:** Landscape only (PC title; portrait N/A)
- **Min PC specs:** Target device class: a 5-year-old mid-range gaming PC. Concrete min/recommended specs deferred until first vertical-slice playtest.
- **Target resolution:** 1080p (1920×1080) native, with support for arbitrary resolutions via Godot's stretch system (`canvas_items` stretch + `expand` aspect). Ultrawide best-effort (letterbox acceptable in MVP).
- **Performance targets:** 60 fps target, 30 fps floor on min-spec.
- **Ad integration:** N/A (PC, premium)
- **Consent (UMP/TCF):** N/A
- **In-app purchases:** **No** — no IAP for MVP, no IAP for full release (PC premium title).
- **Save system:** Yes — autosave on sleep, on quit-to-menu, and at in-game midnight; persistent voxel world state. No manual save in MVP.
- **Mod support:** Data-driven architecture in MVP (Tier 1 data mods); godot-mod-loader integration post-MVP; in-game browser post-launch (see *Subsystem: Mod Support*).
- **Input:** Keyboard + mouse (third-person). Full control map in §4 Player.

---

## 16. Art Direction `[DRAFT]`

- **Visual style:** Steampunk/industrial fantasy assets on a voxel block grid (gears, brass, cast iron, masonry, timber). Theme is mechanical frontier defense against monster swarms. MVP uses purchased asset bundles as **placeholder-final**: good enough to ship, replaced only where clearly wrong.
- **Colour palette:** No mandate for MVP. (Designer's call during the art pass.)
- **Art for v1.0 (MVP):** Placeholder-final via asset bundles. Block damage states accept placeholder textures per §7.7.
- **Notes:** Character/animation assets follow the MakeHuman/Mixamo pipeline (see `docs/HOWTO-use-makehuman-mixamo.md`); current character models live in `assets/makehuman/` and shared animations in `assets/mixamo/`. Enemies are **monsters/orcs/beasts** — Brawler/Shooter read as melee/ranged frontline swarms attacking in regular high-volume horde waves.

---

## 17. Subsystems `[DRAFT]`

> Subsystems are self-contained systems that plug into the core loop but are not the core loop itself. A subsystem can be removed without breaking the fundamental gameplay. Player, Colonists, Base Building, Enemies, Win/Fail, Starting Conditions, World Structure, and Progression live in their own core sections above.
>
> When briefing an agent on a subsystem task, paste the relevant subsystem entry along with any sections it depends on.

---

### Subsystem — Energy (Breath + Stamina) `[DRAFT]`

**What it does:**
Two distinct personal-energy pools on each character, both framed as depleting resources (100% fresh → 0% empty), consistent with HP/Durability/Fuel/Ammo.

- **Breath** — short-term burst energy. Drained by sprinting, jumping, melee swings, ranged fire. Regenerates in seconds when not exerting.
- **Stamina** — long-term daily energy. Drained slowly by time (and faster while actively working). Recovered only by sleep. When it hits 0, the character collapses until the next sleep.

Architecturally this is two separate components (`BreathComponent`, `StaminaComponent`) — see `ARCHITECTURE.md` "Subsystem: Energy". Splitting them lets burst costs and daily grind evolve independently, and lets the daily pool (Stamina) collapse a character without the burst pool (Breath) being involved.

**Entity attachment (MVP):**

| Entity | BreathComponent | StaminaComponent | MVP usage |
|---|---|---|---|
| Player | ✅ | ✅ | Sprint/jump/melee/ranged (Breath); daily collapse (Stamina) |
| Colonist | ✅ | ✅ | Breath unused in MVP (future special actions); daily collapse (Stamina) |
| Enemy (Brawler/Shooter) | ✅ | ❌ | Breath unused in MVP (future windup/heavy attacks); Stamina is a future addition |

BreathComponent is attached to enemies now so future Breath-consuming features (heavy attacks, windups) don't require architectural change — only new consumers.

---

#### Breath (short-term)

**What triggers it:**
Burst actions: sprinting (held), jumping, melee swings, ranged fire. Regenerates when none of these are happening.

**Costs (all tunable in `data/energy_config.tres`; values placeholder for first playtest):**

| Action | Cost | Notes |
|---|---|---|
| Sprint | **−20/sec** while held | ≈5s of continuous sprint from full |
| Jump | **−10** per jump | |
| Melee swing | **−5** per swing | Player (Brawler future) |
| Ranged fire | **−2** per shot | Player (Shooter future) |
| Regen (idle) | **+10/sec** when not doing any of the above | ≈10s to full from empty |

**Empty-Breath rule:** Breath < 20% **blocks sprint** (anti-spam) but does **NOT collapse** the character. The player can always walk. Jump/melee/ranged are also blocked if current Breath < the action's cost.

**Does NOT:**
- Cause collapse (that's Stamina's role).
- Affect work speed (Stamina does that).
- Have a daily-recovery dependency — Breath is fully self-contained: drain on exertion, regen when idle.

---

#### Stamina (long-term / daily)

**What triggers it:**
Continuous time drain (always, while awake). Active work (craft/build/smelt/haul) doubles the drain. Sleep is the only recovery in MVP.

**Costs (all tunable; placeholder for first playtest):**

| Source | Cost | Notes |
|---|---|---|
| Ambient time drain | **−0.21/min** (≈ −0.0035/sec) | Player + Colonists; always while awake |
| Active work multiplier | **×2 ambient** (−0.42/min while working) | Player + Colonists; applies while crafting/building/smelting/hauling |
| Sleep recovery | **full reset to 100%** | Primary (MVP: only) recovery method |

**Stamina bands (energy framing — low values are bad):**

| Band | Stamina range | Effect |
|---|---|---|
| Fresh | 100% – 45% | No penalty |
| Tired | < 45% | Work-speed penalty (floor 60% at collapse) |
| Exhausted | < 25% | Movement-speed penalty also kicks in (floor 40% at collapse) |
| Collapsed | 0% | Hard lock — stops all activity; cannot resume until sleep |

**Collapse rule:** a collapsed character is down for the rest of the day. The player can always choose to sleep (sleep is a player action, not a colonist action); collapsed colonists simply don't work or fight until the next day. This makes Stamina a daily budget — managing it across a colony is a persistent challenge.

**Fallback rate (designer note):** if −0.21/min feels too punishing in playtest, drop to −0.14/min (= old +0.0023/sec) and/or lower the work multiplier.

---

#### Status icons (HUD-derived, no MoodletSystem)

The HUD derives icons directly from component state — no separate moodlet manager exists in MVP. (Future moodlets like Injured, Well-Fed, etc. would warrant extracting a MoodletSystem; that's post-MVP.)

| Icon | Source | Condition |
|---|---|---|
| Drained | BreathComponent | Breath < 20% |
| Tired | StaminaComponent | Stamina < 45% (Tired band) |
| Exhausted | StaminaComponent | Stamina < 25% (Exhausted band) |
| Collapsed | StaminaComponent | Stamina = 0% |

---

#### Dependencies

- **Reads:** TimeSystem (for the day/midnight trigger that enables sleep reset); entity exertion state (sprint/jump/melee/ranged for Breath; working flag for Stamina).
- **Affects:** Player movement (Breath gates sprint; Stamina gates speed floors), colonist work speed (Stamina multiplier), colonist combat readiness (Stamina collapse disables fighting), Day Summary display.

**Does NOT (subsystem-wide):**
- Apply special modifiers during scavenge missions in MVP (standard rates throughout) — though sprinting during the free-loot window drains Breath as normal.
- Include a Stimpack suppression consumable in MVP (post-MVP).

---

### Subsystem — Permadeath `[DRAFT]`

**What it does:**
Death is permanent. Colonists are not a replaceable resource — they are finite people. Loss should feel like a consequence of decisions, not bad luck.

**What triggers it:**
An entity's HP reaching 0 (combat, raid, expedition), or a colonist being left behind on retreat.

**Inputs:**
- Entity HP ≤ 0 events (player, named colonist, unnamed colonist)
- Retreat-without-retrieval events (expedition extraction)

**Outputs:**
- Permanent roster removal
- Memorial entry (named colonists only)
- HUD feedback (portrait gray + skull, screen-edge flash, audio sting)
- Day Summary Fallen section entry
- Game Over if all colonists + player dead

**States / Logic:**

| Scenario | Outcome |
| --- | --- |
| Named colonist HP = 0 | Permanent death. Memorial entry added to roster. |
| Unnamed colonist HP = 0 | Permanent death. |
| Player character HP = 0 | Mission Failed. Player respawns at base. Colonist crew outcomes are resolved normally. |
| Named colonist left behind on retreat | Permanent death. |
| Unnamed colonist left behind | Permanent death. |

**HUD feedback:**
- Mid-raid / mid-expedition: red screen-edge flash and audio sting on colonist death. No pause.
- Colonist portrait grays out immediately with skull icon.
- Day Summary: dedicated Fallen section lists all deaths with brief circumstance.

**Game over condition:** All colonists and the player character are dead → Game Over. Player character death alone does not end the game — the player respawns at base and the colony continues.

**Does NOT:**
- Allow revival of dead colonists (no resurrection mechanic)
- Grant memorial entries to unnamed colonists
- End the game on player death alone

**GDD dependencies:**
- Reads: HP (§6 attributes), extraction/retrieval state (Expedition subsystem)
- Affects: colony roster (§6), Day Summary, Game Over (§8)

---

### Subsystem — Expeditions `[DRAFT]`

**What it does:**
Primary way the colony acquires new resources, recruits, and map knowledge. The player must personally lead expeditions — colonists cannot go alone. Choosing to leave the base always carries risk: a raid may arrive while the player is away.

**What triggers it:**
Player opens the world map at the Command Desk, selects a destination, assembles a crew, and departs.

**Inputs:**
- Destination POI + difficulty tier (per world map)
- Crew selection (player + 0–2 survivors)
- Fuel (consumed by travel)

**Outputs:**
- Resources (scrap, components, fuel, med supplies, key items)
- Recruits (Rescue type)
- Map reveal (sector + neighbors on arrival)
- Crew Stamina / HP changes
- Possible raid at base during absence (resolved on return)
- Day Summary mission block

**Expedition types:**

| Type | Description |
| --- | --- |
| **Scavenge** | Primary resource acquisition. Timed extraction format: site is clear on arrival, enemies arrive in waves. Player decides how deep to loot before extracting. |
| **Mining** | Resource extraction from terrain. Player and crew mine ore veins and stone deposits. Hostile encounters possible. Returns raw materials not found in scavenge sites. |
| **Rescue** | A named or unnamed survivor is stranded at a POI. Combat encounter to extract them. Success adds a recruit. |
| **Recon** | Exploration of a fogged sector. Light enemies. Primary reward is map reveal and POI intelligence. |
| **Story** | Narrative locations. Placeholder for future story arc. Not in MVP scope. |

**Expedition flow:**

- Player opens world map at Command Desk and selects a destination.
- Player assembles crew from available (non-sleeping, non-critical) colonists.
- Player and crew travel to destination — fuel consumed, time advances.
- Mission plays out in destination map scene.
- On return: resources unloaded, crew Stamina resolved, Day Summary updated.
- If a raid occurred during the expedition: damage and colonist outcomes are resolved on return.

#### Scavenge Mission — Timed Extraction (full spec) `[DRAFT]`

##### Mission overview

The Timed Extraction mission is the primary scavenge template for MVP. The site is clear on arrival — the player loots freely, but enemy reinforcements arrive in escalating waves after a short delay. The vehicle, and therefore extraction, is always at the entry point. The player must decide how deep to loot before the site becomes unextractable.

This structure tests three core systems in a single mission: combat, resource decision-making, and Stamina management. It also gives the Garage upgrade a meaningful mechanical hook — higher-tier vehicles allow a faster getaway under pressure.

| Field | Value |
| --- | --- |
| Mission type | Scavenge — Timed Extraction |
| Player count | Player + optional survivor crew (0–2) |
| Estimated duration | 8–15 minutes real time (varies by depth of loot run) |
| Difficulty tiers | Easy / Normal / Hard (set per POI on world map) |
| Repeatable | Yes — same map template, randomised loot and wave timing |
| Unlocked by | Available from Day 1. No base upgrade required. |
| Fuel cost (travel) | Scales with POI distance per existing travel formula |

##### Mission flow

**Phase 1 — Arrival (0:00–0:30)**

The player and crew arrive via vehicle. Entry point is fixed at the south edge of the map. The vehicle remains at the entry point for the entire mission — it is not hidden or destroyed.

- Arrival cinematic: brief fade-in. No cutscene required for MVP.
- Environment is visually clear of enemies. Ambient sounds only (wind, debris).
- Clock starts immediately on player control. No countdown is displayed yet.
- A short radio message plays: "Site looks quiet. Get what you can and get out." (one-time line, skippable.)

**Phase 2 — Free Loot Window (0:30–3:00)**

The player has 2.5 real-time minutes of uncontested looting. The site contains 4–6 loot containers distributed across the map's three zones (see Map Layout). No enemies are present.

- Loot containers show a prompt on interaction. Looting takes 3 seconds. Per §4, interactions do **not** cancel on damage — but during this free-loot window no enemies are present, so the interrupt rule is moot here. (Once waves arrive, the player can still loot; they just tank hits per the §4 risk-reward rule.)
- Each container yields a randomised resource draw from the loot table (see Loot Tables).
- Stamina continues to tick during this phase; sprinting between containers drains Breath (−20/sec) — the burst-recover tradeoff is intentional.
- At 2:30, 30 seconds before wave 1, a warning audio cue plays: "I'm picking up movement on the scanner. Might want to wrap up." HUD text: `Hostile activity detected`.

**Phase 3 — Wave Escalation (3:00 onward)**

Enemy waves spawn at the north edge of the map, opposite the vehicle, on a fixed timer. Wave composition scales by difficulty tier. The player can continue looting between engagements, but the site becomes progressively harder to hold.

| Wave | Spawn time (real) | Composition |
| --- | --- | --- |
| Wave 1 | 3:00 | 2× Brawler |
| Wave 2 | 5:30 | 2× Brawler + 1× Shooter |
| Wave 3 | 8:00 | 3× Brawler + 2× Shooter |
| Wave 4+ | Every 2:30 after wave 3 | Wave 3 composition repeats indefinitely |

*Note: Hard difficulty multiplies enemy HP by 1.25 and adds 1 extra Brawler to waves 2 and 3. Easy difficulty removes wave 3 and caps at wave 2 composition.*

**Phase 4 — Extraction**

The player extracts by returning to the vehicle at the entry point and interacting with it. There is no timer forcing extraction — the player chooses when to leave. The mission ends immediately on vehicle interaction.

- If all crew members are alive, full loot is retained.
- If a crew member is downed and not retrieved, their carried loot is lost. They are treated per the permadeath rule in effect.
- If the player is downed, Mission Failed. The player respawns at base with 50% HP. All loot from the mission is lost.
- Retreat under fire: the vehicle can be boarded even while enemies are in aggro state. Enemies do not follow into the vehicle.

*Note: Garage T2 upgrade (Mechanized Garage) adds an escape ambush mechanic. For timed extraction, this means: if the player boards the vehicle while more than 3 enemies are within 10m, the escape still succeeds with no ambush intercept. Without T2, an ambush during extraction causes a 15-second delay and deals 20 damage to the player before escape.*

##### Map layout

The MVP scavenge map is a single-building site with three internal zones and one external approach. All zones are accessible without keys or switches. The map is intentionally compact — designed to be navigable in under 60 seconds at full sprint.

| Zone | Name | Contents | Enemy spawn? | Notes |
| --- | --- | --- | --- | --- |
| A | Entry / Parking Lot | Vehicle (extraction point), 1× loot container | No | Open area. No cover. Player starts here. |
| B | Ground Floor | 2× loot container, scattered scrap piles | Wave 1 enters from north door | Main combat area. Cover objects: shelving units, overturned tables. |
| C | Back Storage | 2× loot container (higher loot value), 1× possible Key Item container | Waves 2+ may enter through rear window | Enclosed. Harder to exit quickly. High reward, higher risk. |

Map geometry notes for implementation:

- Total playable area: approximately 40m × 30m.
- North entry (enemy spawn) and south entry (player vehicle) should be clearly visually distinct — enemies always come from the opposite direction to extraction.
- Zone C should require the player to pass through Zone B to exit. This prevents a pure back-room camp strategy.
- Cover objects in Zone B should be destructible (optional for MVP; can be static).
- MVP map can be a single pre-built level. No procedural generation required at this stage.

##### Loot tables

Each loot container rolls independently from the table below. Rolls are resolved on interaction, not on mission start. Zone C containers use the "Deep Loot" modifier.

**Standard Container (Zones A and B)**

| Resource | Min | Max | Roll weight |
| --- | --- | --- | --- |
| Scrap | 20 | 50 | Always included |
| Components | 5 | 15 | 70% chance |
| Fuel | 5 | 15 | 40% chance |
| Med Supplies | 1 | 3 | 25% chance |
| Key Item | — | — | 5% chance — rolls from Key Item table |

**Deep Loot Container (Zone C only)**

| Resource | Min | Max | Roll weight |
| --- | --- | --- | --- |
| Scrap | 40 | 90 | Always included |
| Components | 10 | 25 | 85% chance |
| Fuel | 10 | 20 | 55% chance |
| Med Supplies | 2 | 5 | 40% chance |
| Key Item | — | — | 20% chance — rolls from Key Item table |

**Key Item Table (MVP)**

When a Key Item roll succeeds, one item is drawn at random from this pool. Key Items are consumed by base upgrade recipes and have no direct use otherwise.

| Field | Value |
| --- | --- |
| Radio Transceiver Unit | Used by: Command Center T2 |
| Portable Generator | Used by: Workshop T2 |
| Water Pump Motor | Used by: Farm T2 |
| Medical Fridge Unit | Used by: Infirmary T2 |
| Heavy Jack Lift | Used by: Garage T2 |
| Insulation Panels | Used by: Living Quarters T2 |
| Welding Gas Cylinders | Used by: Defenses T2 |

*Note: Each Key Item can only drop once per playthrough — remove it from the pool after it has been found. This prevents duplicate drops and ensures upgrade progression is gated by exploration, not luck.*

##### Success and failure conditions

| Field | Value |
| --- | --- |
| Full success | Player extracts via vehicle with at least 1 resource collected and all crew alive. |
| Partial success | Player extracts but one or more crew members were downed and not retrieved. Loot from downed crew is lost. |
| Narrow escape | Player extracts with 0 crew, all downed or dead. Player retains only personally carried loot. |
| Mission failed | Player HP reaches 0. All mission loot lost. Player respawns at base with 50% HP and 1 day of recovery time. |
| Abandoned | Player returns to vehicle before collecting any loot. No penalty. Fuel cost is still spent. |

##### Energy (Breath + Stamina) integration

Both pools function normally throughout the mission — no special modifiers apply during scavenge missions in MVP. Notable interactions:

- **Breath** is the operative constraint during the free-loot window. Sprinting between containers drains Breath (−20/sec); players who rush risk being winded when the first wave arrives. Breath regenerates between sprints (+10/sec), so pacing matters more than conservation.
- **Stamina** drains at the standard ambient rate throughout (×2 while looting/working). A player arriving at a scavenge mission already low on Stamina (< 45%) takes a work-speed penalty — slowing loot interaction time. Combat itself is unaffected by Stamina in MVP (combat costs Breath, not Stamina).
- On return to base, the Day Summary displays each returning crew member's Stamina level. Players who return exhausted are nudged toward sleeping before the next mission.

*Note: Future — a "Stimpack" consumable could temporarily suppress Stamina penalties during a mission. This is not in MVP scope.*

##### Day Summary output

On successful extraction, the Day Summary screen displays a mission result block:

| Field | Value |
| --- | --- |
| Mission name | Timed Extraction — [POI Name] |
| Outcome | Success / Partial / Narrow Escape |
| Scrap collected | Total units |
| Components collected | Total units |
| Fuel collected | Total units |
| Key Items found | List by name, or "None" |
| Crew status | Name — Healthy / Injured / Downed / Lost |
| Waves survived | e.g. "Extracted before wave 2" |
| Time elapsed | Real minutes in mission |

##### Difficulty scaling reference

| Parameter | Easy | Normal | Hard |
| --- | --- | --- | --- |
| Free loot window | 4:00 | 3:00 | 2:00 |
| Wave 1 spawn | 4:00 | 3:00 | 2:30 |
| Wave 1 composition | 1× Brawler | 2× Brawler | 2× Brawler + 1× Shooter |
| Wave 2 spawn | 7:00 | 5:30 | 4:30 |
| Wave 2 composition | 2× Brawler | 2× Brawler + 1× Shooter | 3× Brawler + 2× Shooter |
| Wave 3 spawn | None | 8:00 | 7:00 |
| Wave 3 composition | — | 3× Brawler + 2× Shooter | 4× Brawler + 2× Shooter |
| Enemy HP modifier | 0.8× | 1.0× | 1.25× |
| Loot quantity | +20% | Standard | -15% |
| Key Item chance (Zone C) | 30% | 20% | 20% |

##### Debug and testing hooks (scavenge-specific)

| Command | Effect |
| --- | --- |
| `spawn_wave [n]` | Immediately spawns wave `n` composition at north spawn point |
| `set_loot_window [seconds]` | Overrides the free loot window duration for the current mission |
| `fill_containers` | Sets all containers to maximum loot values |
| `force_key_item [name]` | Forces a specific Key Item into the next container opened |
| `skip_to_wave [n]` | Fast-forwards wave timer to the specified wave |
| `teleport_extraction` | Teleports player to vehicle extraction point |
| `mission_summary_preview` | Displays a mock Day Summary with test values |

*GDD Addendum — Base Survival MVP | Scavenge Mission: Timed Extraction | Option C Selected*

**Does NOT (Expedition subsystem):**
- Allow colonist-only expeditions (player must lead)
- Grant fog reveal on ambush intercept during travel (reveal only on arrival)
- Include Mining/Rescue/Recon/Story expedition types in MVP

**GDD dependencies:**
- Reads: Player + Colonist state, Fuel, Stamina, world map reveal state (§10)
- Affects: resources, roster (Rescue), map reveal, Day Summary, possible base Raid resolution on return

---

### Subsystem — Raids & Threat Direction `[DRAFT]`

**What it does:**
Raids are the primary external threat. Enemies arrive at the base and attempt to breach it, harm colonists, and destroy or loot the colony's stockpiles. Raids escalate over time — the longer the colony survives and the more it builds, the larger and more frequent the attacks become.

**What triggers it:**
Raid schedule once the colony reaches the safety-net threshold (≥ 3 colonists). Weighted-random edge selection per wave.

**Inputs:**
- Colony age (days survived)
- Colony visibility (active functional furniture count, colonist count)
- Per-edge threat weights (modified by POI visits, decay, random floor)

**Outputs:**
- Enemy waves spawning at the base map edges
- Structural damage (blocks, gates, furniture)
- Colonist injury/death (per stances)
- Stockpile loot/loss if breached

**Enemy behavior:**

| Enemy type | Behaviour |
| --- | --- |
| **Brawler** | Rushes toward colonists. Targets the nearest structural weak point if no colonist is accessible. High HP, melee only. Does not path around obstacles — it attacks them. |
| **Shooter** | Maintains distance. Fires at colonists in range. Paths around obstacles rather than through them. Targets open gates and thin walls when colonists are out of sight. |

**Structural targeting:**
Enemies evaluate the perimeter for weak points before choosing an entry path. Weak points are determined by block HP — Scrap blocks (100 HP) are always the primary target, followed by any damaged block regardless of tier, then stone (300 HP). Brawlers attack the weakest block in range. Shooters path through the lowest-resistance opening (open gates first, then Scrap blocks, then damaged blocks). Metal (600 HP) and reinforced (1200 HP) blocks are rarely targeted unless no lower-HP option exists.

#### Raid spawn locations — threat direction system

Enemies do not spawn from a fixed edge, nor from a fully random one. Instead, each map edge (north, south, east, west) has a **threat weight** that reflects how much activity the colony has had in that direction. Raids are weighted-randomly drawn from these edges — high-weight edges are hit more often, low-weight edges rarely. Players are never shown the numbers directly, but learn the pattern through experience.

**Threat weight rules:**

| Rule | Detail |
| --- | --- |
| Starting weights | All four edges begin at equal weight (25 each, total 100). |
| POI visit | Visiting a POI in a given quadrant raises that edge's weight by +15. |
| Weight decay | All weights drift back toward equal over time — approximately −2 per day per edge, floored at 10. This prevents any edge from becoming permanently safe. |
| Random floor | Every edge has a minimum 10% chance of being selected regardless of weight. Prevents the system from being fully solved and ensures occasional flanks from unexpected directions. |
| Colony visibility bonus | Each placed functional-furniture **item** adds +3 to all edges equally (per item, not per type — see §7.8). Only the 7 area-defining furniture types count. |

**Spawn point within the chosen edge:**
Once an edge is selected, enemies spawn at a random point along the full length of that edge, just outside the map boundary. This distributes pressure across the whole face of the perimeter rather than funnelling it to a fixed corner. Spawn points are randomised per wave, not fixed per raid — a multi-wave raid may hit different points along the same edge.

**Design intent:**
The system creates a narrative loop: the player scavenges north repeatedly, the north edge becomes higher risk, the player reinforces the north wall. The world pushes back in the direction the colony has been active. Occasional unexpected flanks from low-weight edges keep players honest about maintaining a full perimeter rather than ignoring three sides entirely.

**Implementation reference — three values control the system's feel:**

- **Weight increment per POI visit** (default: +15) — raise to make threat escalate faster per expedition.
- **Daily decay rate** (default: −2/day) — lower to make threats persist longer; raise for faster cooldown.
- **Random floor** (default: 10%) — raise to increase unpredictability; lower to reward deliberate perimeter planning more.

#### Early game safety net

Raids are disabled while the colony has fewer than 3 colonists (not counting the player character). This gives the player time to establish the base and learn construction before enemy pressure begins. The threshold is intended for playtesting at 3 — adjust if the early game feels too slow or too rushed.

| Condition | Behaviour |
| --- | --- |
| Colony has fewer than 3 colonists | Raids fully disabled. Player and companion can build and explore freely. No enemy spawns at base. |
| Colony reaches 3 colonists | Safety net lifts. Raids enter the normal escalation schedule. Signal: "Your colony is growing. Others have noticed." |
| Player away on expedition (below threshold) | No raids occur at the base while the player is away and below threshold. Expedition enemies still function normally. |

#### Raid escalation

Raid frequency and enemy count scale with two factors: colony age (days survived) and colony visibility (functional-furniture item count + colonist count — see §7.8 for what counts). A larger, more active colony attracts more attention.

**MVP placeholder curve** (all values in one exported Resource so designers tune without code; numbers explicitly placeholder, revisit at first playtest):

| Day | Waves/raid | Enemies/wave | Shooters in rotation? |
|---|---|---|---|
| 1–2 | 1 | 4 | No |
| 3–5 | 1 | 6 | No |
| 6–9 | 1 | 8 | Yes (15% of wave) |
| 10–14 | 2 | 8 | Yes (20%) |
| 15+ | 2 | 10 | Yes (25%) |
| 20+ | 3 | 10 | Yes (30%) |

- **Raid frequency:** every night (day boundary). Expedition days (player away) still trigger a base raid.
- **Cap:** 24 enemies on screen (see §14) — spawn manager throttles waves at cap; queued enemies spawn as others die.
- **Visibility scaling:** wave size above is *base*; +1 enemy per 10 furniture tiles in the colony (soft, capped).
- Shooters enter the rotation on Day 6 (≈3 hours at the 30-min/day loop); multi-wave raids start Day 10.

#### Colonist behavior during raids

Each colonist executes their assigned raid stance (see §6.7). **In MVP, colonists hold position** — they do not pathfind or pursue. Combat is reactive from their assigned post/slot. Key rules:

- **Fight** stance colonists engage any enemy within weapon range from where they stand at raid start. (No pursuit in MVP — max pursuit distance 0.)
- **Fight Post** stance colonists hold their assigned structure (watchtower, gate, or barricade section) and engage from there. The player assigns a colonist to a specific built structure via the colony management screen; no extra marker object is needed. Structures with assigned colonists are visually flagged in build mode.
- **Shelter** stance colonists retreat to the designated safe room at raid start and hold there. Safe room must be built and designated in advance. If the safe room is breached, they fight from position per the same reactive rule. Enemies who breach the base target stockpiles before attempting to find the safe room.
- If no safe room has been designated, Shelter-stance colonists default to Fight Post behavior.

**Does NOT:**
- Spawn raids below the 3-colonist threshold
- Reveal threat weights to the player in-game (debug command only: `show_threat_weights`)
- Follow players into the extraction vehicle

**GDD dependencies:**
- Reads: colony size + visibility (§6, §7.8 functional furniture), per-edge threat weights
- Affects: base structures (§7), colonist HP/roster (§6, Permadeath), stockpiles, Day Summary

---

### Subsystem — Equipment `[DRAFT]`

**What it does:**
Colonists can be equipped with weapons and armor. Equipment affects combat performance. Equipment is crafted at the Workbench or found on expeditions.

**What triggers it:**
Player assigns loadouts via colony management screen; colonists auto-equip when heading to a raid post or joining an expedition; equipment returns to storage on return.

**Inputs:**
- Crafted/found equipment in storage
- Player loadout template assignments

**Outputs:**
- Durability per equipped armor piece
- Weapon damage / rate of fire / range
- Ammo consumption (ranged)

**Equipment slots:**

| Slot | Notes |
| --- | --- |
| Armor — Head, Body, Arms, Legs, Feet, Hands (6 slots) | Each piece provides Durability that absorbs damage before HP. |
| Melee weapon (1 slot) | For close combat. |
| Ranged weapon (1 slot) | For ranged attacks; consumes ammo. |

**Armor:** 6 slots, 3 material sets (all MVP). Durability per piece:

| Slot | Cloth | Leather | Scrap |
| --- | --- | --- | --- |
| Head | 2 | 4 | 6 |
| Body | 4 | 8 | 12 |
| Arms | 2 | 4 | 6 |
| Legs | 2 | 4 | 6 |
| Feet | 1 | 2 | 3 |
| Hands | 1 | 2 | 3 |
| **Full set** | **12** | **24** | **36** |

Crafting cost per piece:

| Slot | Cloth | Leather | Scrap |
| --- | --- | --- | --- |
| Head | 2 Cloth | 3 Leather | 3 Scrap |
| Body | 4 Cloth | 6 Leather | 6 Scrap |
| Arms | 2 Cloth | 3 Leather | 3 Scrap |
| Legs | 2 Cloth | 3 Leather | 3 Scrap |
| Feet | 1 Cloth | 2 Leather | 2 Scrap |
| Hands | 1 Cloth | 2 Leather | 2 Scrap |

**Weapons:** Melee weapons deal fixed damage; ranged weapon damage comes from the loaded ammo (see Ammo).

| Weapon | Class | Damage | Rate of fire | Ammo | Range | Cost |
| --- | --- | --- | --- | --- | --- | --- |
| Knife | Melee | 25 | 1/s | — | melee | 2 Metal | **MVP** |
| Pistol | Ranged | see Ammo | 4/s | bullets | 12m | 5 Metal + 5 Components | **MVP** |
| Club | Melee | 30 | 0.8/s | — | melee | 2 Wood | *post-MVP* |
| Bow | Ranged | see Ammo | 1/s | arrows | 15m | 3 Wood + 1 Cloth | *post-MVP* |

**Ammo:**

| Ammo | Used by | Damage | Effect | Cost | |
| --- | --- | --- | --- | --- | --- |
| Bullet | Pistol | 15 | Standard round. | 1 Scrap | **MVP** |
| Armor-Piercing Round | Pistol | 15 | Bypasses Durability. | 1 Metal + 1 Component | **MVP** |
| Stone Arrow | Bow | 15 | — | 1 Wood + 1 Stone | *post-MVP* |
| Metal Arrow | Bow | 25 | — | 1 Wood + 1 Metal | *post-MVP* |

**Loadout templates:**
The player can create and name loadout templates via the colony management screen and assign them to individual colonists. Colonists automatically equip their assigned loadout when heading to a raid post or joining an expedition. Equipment is returned to storage on return.

**Does NOT:**
- Include the Durability wear-and-repair loop in MVP (the Durability *stat* is in MVP as the damage buffer; the wear/repair *loop* is post-MVP)
- Persist equipped gear on colonists between missions (returned to storage)

**GDD dependencies:**
- Reads: Workbench crafting state (§7.9), storage inventory
- Affects: combat Durability/HP resolution (§6.11), raid/expedition performance

---

### Subsystem — Day / Night and Time `[DRAFT]`

**What it does:**
Time advances continuously at all times — during base work, construction, expeditions, and combat. There is no hard daily limit or forced end-of-day. The day/night cycle is atmospheric and simulation-driven.

**What triggers it:**
Always-on passive time advance.

**Inputs:**
- Real-time delta (continuous)

**Outputs:**
- In-game clock (day counter + time of day)
- Stamina accumulation (feeds Energy subsystem)
- Travel time proportional to POI distance

| Rule | Detail |
| --- | --- |
| Time advance | Passive. Same rate during base activity and travel. |
| Travel time | Proportional to POI distance. Longer travel = more time passes = more Stamina drained. |
| Night | No special penalties in MVP. Atmospheric only. Future: visibility reduction, morale effects. |
| Sleep | Voluntary. Player interacts with their bed. Restores Stamina (full reset) and triggers Day Summary. Well-Rested bonus if slept at appropriate Stamina level. |
| No forced cutoff | Tasks and expeditions can continue through the night. The game does not force a day end. |

**Does NOT:**
- Apply night penalties in MVP
- Force an end-of-day cutoff
- Use discrete day phases (no hard daily structure)

**GDD dependencies:**
- Reads: real-time delta
- Affects: Stamina (accumulation + recovery), HUD clock, Day Summary trigger, travel cost

---

### Subsystem — Save & Reset `[DRAFT]`

**What it does:**
Persists game state on sleep and handles reset on Game Over / Victory.

**What triggers it:**
Player sleep (bed interaction) → autosave. **Also: autosave at in-game midnight (day boundary) and on quit-to-menu.** Future: autosave on expedition return.

**Inputs:**
- All tracked state (see below)

**Outputs:**
- Persistent save file
- Game Over reset (all state) / Victory preservation (map reveal + memorial roster)

**Tracked state:**

- Current day
- Colonist HP / Stamina / Morale / skills / loadout / raid stance
- Colonist roster — including deceased (stored as memorial entries)
- Voxel world state — all placed and removed blocks
- Furniture and equipment placement
- Resources and inventory
- World map reveal state (per-sector: fogged / revealed / visited)

**Save triggers:**
Saves automatically when the player sleeps (bed interaction), **at in-game midnight (day boundary), and on quit-to-menu**. Future: autosave on expedition return. Manual save not planned for MVP.

**Reset conditions:**

| Condition | Outcome |
| --- | --- |
| All colonists and player dead | Game Over. New game resets all state including map reveal. |
| Victory (future — story goal) | Victory state. Map reveal and memorial roster preserved as a record. |

**Does NOT:**
- Support manual save in MVP
- Preserve map reveal on Game Over reset (full reset)

**GDD dependencies:**
- Reads: every system's state
- Affects: Game Over (§8), progression (§11)

---

### Subsystem — Mod Support `[DRAFT]`

**What it does:**
Rust Frontier: Colony Defense is designed to be moddable from day one. The game uses a data-driven architecture where block types, enemy stats, furniture definitions, loot tables, colonist skills, raid escalation curves, and starting conditions are all defined in external resource files — not hardcoded in scripts. This means mods can add or override content by supplying replacement resource files, with no engine modification required.

**What triggers it:**
Mod loader reads `/mods` folder at startup (post-MVP integration).

**Inputs:**
- Mod zip files in `/mods` folder
- `manifest.json` per mod

**Outputs:**
- Overridden / new content (blocks, enemies, furniture, loot, skills, raid curves, starting conditions)
- Load order resolution

**Mod loader:**
**godot-mod-loader** (https://github.com/GodotModding/godot-mod-loader) is the chosen mod loader. General-purpose, open-source mod loader for GDScript-based Godot 4 games that supports overriding existing scripts, scenes, and resources without modifying or distributing vanilla game files. Mods are distributed as standard zip files.

| Property | Detail |
| --- | --- |
| Repository | https://github.com/GodotModding/godot-mod-loader |
| Licence | MIT |
| Engine support | Godot 4.x |
| Mod format | Zip files placed in a /mods folder next to the game executable |
| Capabilities | Add new content, override existing scripts/scenes/resources, load order management, dependency declaration |
| Documentation | Full wiki at the repository |

**Mod tiers:**

| Tier | What modders can do | Dev cost |
| --- | --- | --- |
| 1 — Data mods | New block types, enemy variants, furniture, loot tables, colonist skills, starting conditions, raid curves. All defined as resource files. | Low — requires data-driven architecture (already planned) |
| 2 — Script mods | New AI behavior, new game mechanics, new UI panels, total conversions. Requires hooking into the game's signal/event system. | Medium — requires a documented signal API post-MVP |

MVP targets Tier 1 only. Tier 2 (script mods) is post-MVP once the internal API is stable enough to document.

**Data-driven architecture requirement:**
For Tier 1 mods to work, the following systems must store their definitions in external resource files (`.tres` or `.json`) rather than hardcoded GDScript values. This is an architectural constraint that affects how these systems are built from day one.

| System | Must externalise |
| --- | --- |
| Block types | HP, construction time modifier, material tier, texture reference |
| Enemy archetypes | HP, damage, speed, behavior type, loot drop |
| Furniture definitions | Craft cost, footprint, functional area unlock, HP |
| Loot tables | Resource type, min/max amounts, drop weights, Key Item pool |
| Colonist skills | Name, level, progression curve |
| Raid escalation | Wave compositions, timing, threshold triggers |
| Starting conditions | Resources, equipment, pre-built structure definition |

**Mod manifest format:**
Each mod zip must contain a `manifest.json` at its root. Minimum required fields:

```json
{
  "name": "My Mod",
  "version": "1.0.0",
  "author": "Author Name",
  "description": "Short description.",
  "dependencies": [],
  "load_before": [],
  "load_after": []
}
```

**Distribution:**

| Platform | Status | Notes |
| --- | --- | --- |
| Manual install (/mods folder) | Day one | Players drop zip files into the mods folder. No integration needed. |
| Nexus Mods | Day one | Free hosting. Modders upload zips. No in-game browser. |
| mod.io | Post-launch | Adds in-game mod browser. Requires API integration and UI work. Godot GDExtension plugin available. |
| Steam Workshop | Post-launch | Requires GodotSteam plugin and in-game browser UI. Best if Steam is the primary platform. |

**MVP scope for mod support:**
The data-driven architecture is in scope for MVP — it is a prerequisite for the game to be moddable at all and does not add significant scope if designed in from the start. The mod loader itself (godot-mod-loader integration) is a short post-MVP task once the data layer is stable. An in-game mod browser is post-launch.

**Does NOT:**
- Include script mod (Tier 2) support in MVP
- Include in-game mod browser in MVP
- Require mod loader integration for the data-driven architecture to ship

**GDD dependencies:**
- Reads: every content definition (blocks, enemies, furniture, loot, skills, raids, starting conditions)
- Affects: architecture (all content systems must be data-driven from day one)

---

### Subsystem — Debug Console / Testing Hooks `[DRAFT]`

**What it does:**
Provides dev/playtest console commands for rapid iteration. Debug console enabled via tilde (~) or F1. All commands below are for development and playtesting only.

**What triggers it:**
Developer / playtester opens the console and enters commands.

**Inputs:**
- Console command strings

**Outputs:**
- Direct state mutation for testing

| Command | Effect |
| --- | --- |
| `add_resource [item_id] [n]` | Adds n of any item (scrap, wood, leather, med_supplies, etc. — first arg is the `item_def_id`). |
| `spawn_survivor` | Spawns a generic unnamed colonist at base |
| `kill_survivor [id]` | Triggers permadeath on a specific colonist |
| `set_hp [id] [value]` | Sets HP on any character (use `"player"` for the player; colonist_id otherwise) |
| `set_durability [id] [value]` | Sets Durability on any character (same id convention) |
| `set_stamina [id] [value]` | Sets Stamina (0–100%) on any character |
| `set_breath [id] [value]` | Sets Breath (0–100%) on any character |
| `teleport_mission` | Teleports player to currently selected expedition map |
| `spawn_wave [n] [edge]` | Spawns wave n enemy composition at the specified edge (north/south/east/west). Omit edge for weighted-random. |
| `set_threat [edge] [value]` | Sets threat weight for a specific edge (0–100). Useful for testing raid direction without running expeditions. |
| `show_threat_weights` | Displays current threat weight for all four edges in the debug overlay. |
| `reveal_sector [id]` | Forces a sector to Visited state, reveals neighbors |
| `fog_all` | Resets all sectors to Fogged (except home base neighbors) |
| `fast_time` | Toggles accelerated time passage |
| `win_game` | Triggers victory state (post-MVP feature; command tests the flow) |
| `place_block [type] [x] [y] [z]` | Places a voxel block instantly (bypasses manual construction) |
| `god_mode` | Player and colonists take no damage |

**Does NOT:**
- Ship enabled in release builds
- Include scavenge-specific hooks here (see Expeditions subsystem)

**GDD dependencies:**
- Reads/mutates: resources, colonist state, world map, raid/threat, time, blocks, win state

---

## 18. Decisions Log

> Running log of significant design decisions. Update this whenever something changes. Paste recent entries when briefing an AI agent mid-project.
>
> *Dates marked † were backfilled from GDD v2.5 — the original decision date was not recorded. Going forward, date new entries on the day they're made.*

| Date | Decision | Reason |
| --- | --- | --- |
| 2026-06-19† (v2.5) | Skill system replaced the old fixed "role" system; any colonist can do any regular job they meet the skill requirement for. | Replaces passive role bonuses with use-based leveling; more flexible, soft replayability lever. |
| 2026-06-19† (v2.5) | MVP colony cap set to 5 colonists; full 10-colonist cap deferred to post-MVP (bed-capped). | Scope control; 10-colony management + AI is too much for MVP. |
| 2026-06-19† (v2.5) | Scavenge mission = Timed Extraction format ("Option C"). | Tests combat + resource decisions + fatigue in a single mission; gives Garage upgrade a mechanical hook. |
| 2026-06-19† (v2.5) | Enemy MVP archetypes = Brawler + Shooter only ("Option B"). | Minimal pair (melee pressure + ranged pressure) produces the core engage/retreat dynamic without complex AI trees. |
| 2026-06-19† (v2.5) | No structure support or gravity for voxel blocks in MVP (blocks may float). | Scope cut; post-MVP addition. |
| 2026-06-19† (v2.5) | Growing Trough / food / hunger deferred to post-MVP; Growing Trough is a non-functional placeholder in MVP. | Hunger loop is a major system; not needed to validate the core loop. |
| 2026-06-19† (v2.5) | MVP uses discrete scenes per map; true open world (Zylann voxel plugin chunking) deferred. | Scope / technical risk control. |
| 2026-06-19† (v2.5) | Player character cannot hold a specialist slot (specialists are NPC-only, post-MVP). | Keeps specialists a colony-management choice, not a player-power choice. |
| 2026-06-19† (v2.5) | All buildable HP / footprint / cost values are designer-configurable starting points pending playtesting (Wooden Door / block HP were already specified; furniture + Gate filled in as defaults). | Tune in playtesting, not upfront. |
| 2026-06-19† (v2.5) | Permadeath applies equally to named and unnamed colonists (named get memorial entries; unnamed do not). | Loss should feel like a consequence of decisions; colonists are finite people. |
| 2026-06-19† (v2.5) | Damage model = AP depletes before HP for all entities (resolves earlier GDD ambiguity). | Single shared, unambiguous damage resolution. |
| 2026-06-27 | Reformatted GDD v2.5 into the Coding Agent Playbook GDD template (PC-adapted); added Brawler/Shooter state machines (drafted from v2.5 prose stubs). | AI-friendliness: explicit scope, state machines, fixed values, decisions log, stability tags. |
| 2026-07-04 | **Decisions fold (v2.6):** title → `Vek: Holdout`; theme corrected to alien invasion (scrappunk/xeno-tech), not zombies. Player state machine locked (Mode+State model, single merged Attack, no cancel-on-damage). Input map locked (Z/X/C+I+M). Move speed 3.5 m/s + 1.6× sprint. HP: player 200 / colonist 100. Brawler = Chase + 1.5m + 5s LOS; Shooter = Reposition + 10m holding. Colonist combat = hold position, reactive (no pursuit MVP). §6.10 colonist AI filled: Labor/Job terminology, Job Board, A* colonists / NavAgent enemies, log+skip+auto-remove failure (blocked-state late MVP), no stacking, Priority>Proximity. §7.4 even-footprint rotation rule (0.5m pivot). §7.10/7.11 defenses + storage spec; Power/Water/Turret/Water-Pump/Medical-Fridge deferred. All §12 screens specced (Player screen w/ tabs, Colony Mgmt 5 tabs incl. Roster, hex World Map, Main/Pause/Game Over/Settings/Inventory). Audio out of MVP. Fixed Values filled (24-enemy cap, 60/30 fps, 9.8 gravity, 1080p). 1 day = 30 min loop; midnight + quit autosave. No IAP ever. | Resolves every `[TBD]` flagged in `GDD.gaps.md` via the `GDD.gaps.review.md` / `review2.md` review pass. Sources for each decision are cross-referenced in those files. |
| 2026-07-04 | **Follow-up resolutions:** (1) Recruitment scope — §6.9 reordered so random world events + radio contacts carry MVP recruitment; Rescue expeditions stay post-MVP. (2) Medical Supplies role — dual: Clinic Bed healing boost + standalone field-heal item. (3) MVP weapon/armor scope locked: Knife (melee) + Pistol (ranged) only — Club and Bow are post-MVP; armor tiers are Cloth/Leather/Scrap (all MVP, no "Metal" tier). Alien enemies use humanoid proxies for MVP prototyping. | Resolves the 3 open items in `GDD.gaps.md` post-fold. Asset manifest (`tmp/required_models.md`) updated to match. |
| 2026-07-27 | **FINAL-tag pass (partial) + Durability rename.** §1 Overview marked `[FINAL]` (theme/audience/pitch locked). All other reviewed sections (§3 Core Loop, §6.11 Damage Resolution, §7.2 Buildables, §17 Energy, §17 Raids, §14 Fixed Values) kept `[DRAFT]` pending playtest. **Armor Points (AP) renamed → Durability** across the GDD; the property now unifies damage-absorption and item-wear into one stat. The Durability *stat* is in MVP (as the ablative hit buffer); the wear-and-repair *loop* stays post-MVP. **Open question added:** how does Durability regenerate (sleep / Workbench repair / fresh armor only)? — see `GDD.gaps.md`. | Conservative FINAL-tagging: lock only what survives pure reasoning; leave feel-dependent values for playtest. Rename resolves the AP-misleads-as-damage-reduction concern and frees "armor"/"damage reduction" for a future DR mechanic. |
| 2026-07-27 | **Durability recovery + prototype art.** (1) Durability is regained via a **repair crafting job** (post-MVP — covers armor + other items; added as a post-MVP Labor in §6.10). MVP interim: Durability auto-recovers to full on sleep so armor is a reliable per-day buffer. (2) Early prototypes use **capsule proxies** instead of models — no model sourcing needed until prototype → art-pass transition. | Resolves the Durability-regen open question (gaps §2.1) and the asset-cross-check blocker (gaps §3.1). GDD now has 0 MVP-blocking and 0 vertical-slice-blocking open items. |
| 2026-08-28 | **Theme & Title Pivot:** Title updated to `Rust Frontier: Colony Defense`. Motif pivoted from alien invasion to steampunk/low-fantasy mechanical frontier (no magic, purely mechanical/steam/iron/clockwork/blackpowder technology). Core loop expanded with high-volume regular horde defense (tower defense / horde night dynamic against monster/orc swarms) established as a king's border stronghold during a wartime stalemate. | Player/designer alignment on game identity, market positioning, and fantasy-steampunk tower defense synergy. |
| 2026-09-04 | **Turrets Early Implementation & Tactical Markers Spec:** Defensive turrets pulled forward from post-MVP into active development in alignment with the horde-defense steampunk stronghold loop. Turrets operate via Furniture capability (`TurretParams`), targeting closest enemies and consuming ammo from colony storage. Sensor markers (configurable radius) and target markers specced as a planned automation feature for predictive AOE/explosive bombardment. | Deepens tower defense tactical gameplay and provides concrete sinks for crafted ammunition types. |
| 2026-07-28 | **Fatigue split → Breath + Stamina (Energy subsystem).** Single Fatigue pool (0.0 rested → 1.0 collapsed, filled toward bad) split into two depleting pools (100% fresh → 0% empty, consistent with HP/Durability): **Breath** (short-term burst — sprint/jump/melee/ranged; regenerates +10/sec when idle) and **Stamina** (long-term daily — ambient −0.21/min, ×2 while working; sleep-only recovery; collapse at 0%). Architecturally two separate components: `BreathComponent` (on all entities) + `StaminaComponent` (player + colonists; enemies future). Breath attached to enemies now for future windup/heavy-attack costs without architectural change. "Fatigue" term retired; old subsystem renamed "Energy (Breath + Stamina)". | The original pool conflated two timescales (sprint-burn cleared only on sleep = odd). Split makes sprinting feel good (burst+recover) and keeps the daily-grind pressure distinct. Energy framing matches every other HUD bar. Separate components keep burst-cost and daily-budget mechanics independently evolvable. Driven by ARCHITECTURE.md review item #1 (FatigueComponent referenced but never defined). |

---

## 19. Open Questions `[DRAFT]`

> Status as of 2026-07-04 (v2.6): **all gaps from the original v2.5 open-TODOs list have been resolved** and folded into the relevant sections above. The original question/answer/rationale trail is archived at `.archive/v2.6-decisions/`.

**Still open (deferred by design — not blocking the MVP build):**

- **§7.1 FINAL-tag list** — which sections to lock as `[FINAL]` (change only via Decisions Log) vs keep `[DRAFT]`. Deferred per designer call; resurface at vertical-slice lock time.
- **Asset cross-check** — `tmp/required_models.md` lists every MVP model/icon/rig needed; awaiting the designer's "have/need" pass against purchased asset bundles. Open weapon/armor questions flagged in that file.
- **Theme / monster lore detail** — confirmed steampunk/mechanical frontier setting with monster/orc swarm threats; deeper lore (monarchy border politics, monster origins) is in development and will inform the post-MVP art pass.
- **Tuning passes** — raid curve, Stamina thresholds, Breath costs, movement feel, spike-trap HP-per-touch, and recovery-on-death are explicitly placeholder and flagged for first playtest.

_Date: 2026-07-04_
