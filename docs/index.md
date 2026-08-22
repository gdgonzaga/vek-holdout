# Architecture — Vek: Holdout

Last updated: 2026-08-17 (doc-vs-code audit: as-built pages synced with the code — EventBus registry, farming/harvesting coverage, labor/skill/action counts, UI inventory incl. colony_management; the unbuilt subsystem pages (combat, equipment, energy, permadeath-memorial, raids, loot, debug console/commands) now carry "planned — not yet built" banners and live in the Planned nav group; log_history screen moved to ui/log_history/ so the H key works. Prior: job-system extension foundations built — JobDef requirement gating, MaterialSink haul contract, ItemDef tags + tool retention, Furniture state bag, Skills live; harvesting + farming features built)

> Companion to `GDD.md` (v2.6). Every subsystem below maps to a GDD section; cross-references are in each subsystem's Files table. **Scope:** medium solo project — simple over flexible, no over-engineering.

---

## Overview

| Page | Description |
|---|---|
| [Overview](architecture/overview.md) | Directory structure, scene tree, autoloads, signal registry, conventions |

## Subsystems

| Page | Subsystem | GDD |
|---|---|---|
| [Core](architecture/core.md) | Root scenes, shared utilities, time | — |
| [Save / Load](architecture/save.md) | Multi-slot persistence, parked state, conventions | — |
| [Voxel / World](architecture/voxel-world.md) | Blocky + smooth voxel worlds, BlockyGrid/SmoothGrid, BlockLibrary | — |
| [Player](architecture/player.md) | Third-person controller, camera rig, Mode+State | §4 |
| [Build](architecture/build.md) | Blueprint mode, BuildLibrary, ghost preview, furniture layer | §7.4 |
| [Actions & Interaction](architecture/actions.md) | E-key menu, GameAction/Condition/ActionOption chain | §4 |
| [Functional Rooms](architecture/functional-rooms.md) | Furniture-count tracking, capability unlocks | §7.8 |
| [Colonists](architecture/colonists.md) | Roster, labor AI, raid stances | §6 |
| [Jobs](architecture/jobs.md) | Job Board, hauling, construction, farming, JobDef contract | §6 |
| [Skills](architecture/skills.md) | Per-entity L1–L5 progression, work-speed multipliers | §6.3 |
| [Maps](architecture/maps.md) | MapLibrary, wiring, per-map scenes, authoring | — |
| [Expeditions](architecture/expeditions.md) | POI discovery, depart/return, scavenge missions | §17 |
| [Inventory](architecture/inventory.md) | Weight-based inventory, ItemDef, ItemDB autoload | §4.5, §7.3 |
| [Crafting](architecture/crafting.md) | Recipes, Workbench/Forge, craft Jobs | §7.9 |
| [Farming](architecture/farming.md) | Farm plots, hydration, tending, crop growth & yields | §6 |
| [Mining](architecture/mining.md) | Voxel digging, strata materials, dig box designation, markers | §7.5 |
| [UI](architecture/ui.md) | HUD + all full-screen screens | §12 |
| [Game Log](architecture/game-log.md) | On-screen message feed, history buffer | §12 |

## Reference

| Page | Description |
|---|---|
| [Data Schemas](architecture/data-schemas.md) | All `.tres` Resource schemas (blocks, characters, items, etc.) |

## Tracking

| Page | Description |
|---|---|
| [Tech Debt & Unimplemented](architecture/tech-debt.md) | Known debt, unimplemented subsystems, missing schemas |

## Planned

Pages for subsystems that exist only as design (their folders are empty placeholders). Each carries a "planned — not yet built" status banner.

| Page | Subsystem | GDD |
|---|---|---|
| [Combat](architecture/combat.md) | Durability-before-HP, weapons, enemy archetypes | §6.11 |
| [Equipment & Loadouts](architecture/equipment.md) | 8-slot gear, auto-equip/unequip, templates | §17 |
| [Energy](architecture/energy.md) | Breath (burst) + Stamina (daily) pools | §17 |
| [Permadeath & Memorial](architecture/permadeath-memorial.md) | Deceased roster, Day Summary/Game Over | §17 |
| [Raids](architecture/raids.md) | Raid scheduler, threat weights, spawn manager | §17 |
| [Loot](architecture/loot.md) | Loot tables, containers, Key Item pool | §17 |
| [Debug Console](architecture/debug-console.md) | Command registry, dev-only tools | §17 |
| [Debug Commands](architecture/debug-commands.md) | Full command reference for the debug console | §17 |
| [Open world](architecture/open-world.md) | Streaming-world migration analysis | — |
| [Job system extensions](architecture/job-extensions.md) | Plan-of-record for the job features | §6 |

## About

| Page | Description |
|---|---|
| [Adding a page](architecture/contributing.md) | How to add a new architecture page, conventions, and MkDocs wiring |
