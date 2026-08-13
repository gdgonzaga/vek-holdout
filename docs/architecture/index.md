# Architecture — Vek: Holdout

Last updated: 2026-08-13 (colonist sprint documented — Job/JobBoard + labor taxonomy, Colonist entity, voxel A* pathfinder, ColonistAI claim→path→arrive loop, Workshop blueprint; Colonists/Overview/Build/Data-Schemas/Tech-Debt/Maps/Save pages synced to the new code)

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
| [Voxel / World](voxel-world.md) | Blocky-voxel world, VoxelGrid, BlockLibrary | — |
| [Player](player.md) | Third-person controller, camera rig, Mode+State | §4 |
| [Build](build.md) | Blueprint mode, BuildLibrary, ghost preview, furniture layer | §7.4 |
| [Actions & Interaction](actions.md) | E-key menu, GameAction/Condition/ActionOption chain | §4 |
| [Functional Rooms](functional-rooms.md) | Furniture-count tracking, capability unlocks | §7.8 |
| [Colonists](colonists.md) | Roster, Job Board, labor AI, raid stances | §6 |
| [Skills](skills.md) | Per-entity L1–L5 progression, work-speed multipliers | §6.3 |
| [Combat](combat.md) | Durability-before-HP, weapons, enemy archetypes | §6.11 |
| [Equipment & Loadouts](equipment.md) | 8-slot gear, auto-equip/unequip, templates | §17 |
| [Energy](energy.md) | Breath (burst) + Stamina (daily) pools | §17 |
| [Permadeath & Memorial](permadeath-memorial.md) | Deceased roster, Day Summary/Game Over | §17 |
| [Raids](raids.md) | Raid scheduler, threat weights, spawn manager | §17 |
| [Maps](maps.md) | MapLibrary, wiring, per-map scenes, authoring | — |
| [Expeditions](expeditions.md) | POI discovery, depart/return, scavenge missions | §17 |
| [Loot](loot.md) | Loot tables, containers, Key Item pool | §17 |
| [Inventory](inventory.md) | Weight-based inventory, ItemDef, ItemDB autoload | §4.5, §7.3 |
| [Crafting](crafting.md) | Recipes, Workbench/Forge, craft Jobs | §7.9 |
| [UI](ui.md) | HUD + all full-screen screens | §12 |
| [Game Log](game-log.md) | On-screen message feed, history buffer | §12 |
| [Debug Console](debug-console.md) | Command registry, dev-only tools | §17 |

## Reference

| Page | Description |
|---|---|
| [Data Schemas](data-schemas.md) | All `.tres` Resource schemas (blocks, characters, items, etc.) |
| [Debug Commands](debug-commands.md) | Full command reference for the debug console |

## Tracking

| Page | Description |
|---|---|
| [Tech Debt & Unimplemented](tech-debt.md) | Known debt, unimplemented subsystems, missing schemas |

## About

| Page | Description |
|---|---|
| [Adding a page](contributing.md) | How to add a new architecture page, conventions, and MkDocs wiring |
