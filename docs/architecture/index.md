# Architecture — Vek: Holdout

Last updated: 2026-08-17 (doc-vs-code audit: as-built pages synced with the code — EventBus registry, farming/harvesting coverage, labor/skill/action counts, UI inventory incl. colony_management; the unbuilt subsystem pages (combat, equipment, energy, permadeath-memorial, raids, loot, debug console/commands) now carry "planned — not yet built" banners and live in the Planned nav group; log_history screen moved to ui/log_history/ so the H key works. Prior: job-system extension foundations built — JobDef requirement gating, MaterialSink haul contract, ItemDef tags + tool retention, Furniture state bag, Skills live; harvesting + farming features built)

> Companion to `GDD.md` (v2.6). Every subsystem below maps to a GDD section; cross-references are in each subsystem's Files table. **Scope:** medium solo project — simple over flexible, no over-engineering.

---

## Overview

| Page | Description |
|---|---|
| [Overview](overview.md) | Directory structure, scene tree, autoloads, signal registry, conventions |

## Subsystems

| Page | Subsystem | GDD |
|---|---|---|
| [Core](core.md) | Root scenes, shared utilities, time | — |
| [Save / Load](save.md) | Multi-slot persistence, parked state, conventions | — |
| [Voxel / World](voxel-world.md) | Blocky + smooth voxel worlds, BlockyGrid/SmoothGrid, BlockLibrary | — |
| [Player](player.md) | Third-person controller, camera rig, Mode+State | §4 |
| [Build](build.md) | Blueprint mode, BuildLibrary, ghost preview, furniture layer | §7.4 |
| [Actions & Interaction](actions.md) | E-key menu, GameAction/Condition/ActionOption chain | §4 |
| [Functional Rooms](functional-rooms.md) | Furniture-count tracking, capability unlocks | §7.8 |
| [Colonists](colonists.md) | Roster, labor AI, raid stances | §6 |
| [Jobs](jobs.md) | Job Board, hauling, construction, farming, JobDef contract | §6 |
| [Pathfinding & Navigation](pathfinding.md) | Voxel A*, hybrid walkability, stepped 3D locomotion, physics assist | §6 |
| [Skills](skills.md) | Per-entity L1–L5 progression, work-speed multipliers | §6.3 |
| [Maps](maps.md) | MapLibrary, wiring, per-map scenes, authoring | — |
| [Expeditions](expeditions.md) | POI discovery, depart/return, scavenge missions | §17 |
| [Inventory](inventory.md) | Weight-based inventory, ItemDef, ItemDB autoload | §4.5, §7.3 |
| [Crafting](crafting.md) | Recipes, Workbench/Forge, craft Jobs | §7.9 |
| [Farming](farming.md) | Farm plots, hydration, tending, crop growth & yields | §6 |
| [Mining](mining.md) | Voxel digging, strata materials, dig box designation, markers | §7.5 |
| [UI](ui.md) | HUD + all full-screen screens | §12 |
| [Game Log](game-log.md) | On-screen message feed, history buffer | §12 |

## Reference

| Page | Description |
|---|---|
| [Data Schemas](data-schemas.md) | All `.tres` Resource schemas (blocks, characters, items, etc.) |

## Tracking

| Page | Description |
|---|---|
| [Tech Debt & Unimplemented](tech-debt.md) | Known debt, unimplemented subsystems, missing schemas |

## Planned

Pages for subsystems that exist only as design (their folders are empty placeholders). Each carries a "planned — not yet built" status banner.

| Page | Subsystem | GDD |
|---|---|---|
| [Combat](combat.md) | Durability-before-HP, weapons, enemy archetypes | §6.11 |
| [Equipment & Loadouts](equipment.md) | 8-slot gear, auto-equip/unequip, templates | §17 |
| [Energy](energy.md) | Breath (burst) + Stamina (daily) pools | §17 |
| [Permadeath & Memorial](permadeath-memorial.md) | Deceased roster, Day Summary/Game Over | §17 |
| [Raids](raids.md) | Raid scheduler, threat weights, spawn manager | §17 |
| [Loot](loot.md) | Loot tables, containers, Key Item pool | §17 |
| [Debug Console](debug-console.md) | Command registry, dev-only tools | §17 |
| [Debug Commands](debug-commands.md) | Full command reference for the debug console | §17 |
| [Open world](open-world.md) | Streaming-world migration analysis | — |
| [Job system extensions](job-extensions.md) | Plan-of-record for the job features | §6 |

## About

| Page | Description |
|---|---|
| [Adding a page](contributing.md) | How to add a new architecture page, conventions, and MkDocs wiring |
