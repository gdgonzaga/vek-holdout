# Architecture — Xeno Frontier: Colony Defense

Last updated: 2026-09-12 (multi-leg job completion for hauling/construction, AI behavior-tree task dedupe, and shared Player/Colonist equipment + hunger setup).

> Companion to `GDD.md` (v2.7). Every subsystem below maps to a GDD section; cross-references are in each subsystem's Files table. **Scope:** medium solo project — simple over flexible, no over-engineering.

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
| [AI & Behavior Trees](ai.md) | LimboAI engine, ColonistBrain, ColonistNeeds, custom tasks | §6 |
| [Pathfinding & Navigation](pathfinding.md) | Voxel A*, hybrid walkability, stepped 3D locomotion, physics assist | §6 |
| [Skills](skills.md) | Per-entity L1–L5 progression, work-speed multipliers | §6.3 |
| [Maps](maps.md) | MapLibrary, wiring, per-map scenes, authoring | — |
| [Expeditions](expeditions.md) | POI discovery, depart/return, scavenge missions | §17 |
| [Inventory](inventory.md) | Weight-based inventory, ItemDef, ItemDB autoload | §4.5, §7.3 |
| [Crafting](crafting.md) | Recipes, Workbench/Forge, craft Jobs | §7.9 |
| [Farming](farming.md) | Farm plots, hydration, tending, crop growth & yields | §6 |
| [Wild Flora](wild-flora.md) | Trees, bushes, wild plants, foraging, real-time felling & stage progression | §6, §7.4 |
| [Hunger](hunger.md) | HungerComponent, FoodParams, starvation, pocket feeding, player food | §6.12 |
| [Recreation](recreation.md) | RecreationParams capability, occupancy slots, recreation need satisfaction | §6 |
| [Mining](mining.md) | Voxel digging, strata materials, dig box designation, markers | §7.5 |
| [Combat](combat.md) | Durability-before-HP, weapons, enemy archetypes, turrets | §6.11 |
| [Equipment & Loadouts](equipment.md) | 8-slot gear, auto-equip/unequip, EquipmentAudit | §17 |
| [Raids](raids.md) | Night raid controller, spawn pacing, threat model | §17 |
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
| [Job system extensions](job-extensions.md) | Plan-of-record for the job features (Core/Crafting/Harvesting/Farming built; Patrol planned) |
| [Open world](open-world.md) | Non-binding streaming-world migration analysis — not a planned feature |

## Planned

Pages for subsystems that exist only as design (their folders are empty or near-empty placeholders). Each carries a "planned — not yet built" status banner.

| Page | Subsystem | GDD |
|---|---|---|
| [Energy](energy.md) | Breath (burst) + Stamina (daily) pools | §17 |
| [Permadeath & Memorial](permadeath-memorial.md) | Deceased roster, Day Summary/Game Over | §17 |
| [Loot](loot.md) | Loot tables, containers, Key Item pool | §17 |
| [Debug Console](debug-console.md) | Command registry, dev-only tools | §17 |
| [Debug Commands](debug-commands.md) | Full command reference for the debug console | §17 |

## About

| Page | Description |
|---|---|
| [Adding a page](contributing.md) | How to add a new architecture page, conventions, and MkDocs wiring |
