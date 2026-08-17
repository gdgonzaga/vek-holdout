# Debug Console — Command Reference

Full list of *planned* commands. GDD §17 Debug Console + §17 Scavenge-specific hooks. All dev/playtest only.

> **Implementation status: planned, not yet built.** None of these commands exist — there is no console, command registry, or `Command` resource anywhere in the codebase (see [Debug Console](debug-console.md)). This is the intended command surface for the console when it lands, kept as the design reference.

## Resources

| Command | Effect |
|---|---|
| `add_resource [item_id] [n]` | Adds n of any item (first arg is the `item_def_id`: scrap, wood, leather, med_supplies, etc.). |

## Characters (player + colonists via id; `"player"` for the player)

| Command | Effect |
|---|---|
| `spawn_survivor` | Spawns a generic unnamed colonist at base. |
| `kill_survivor [id]` | Triggers permadeath on a colonist. |
| `set_hp [id] [value]` | Sets HP on any character. |
| `set_durability [id] [value]` | Sets Durability on any character. |
| `set_stamina [id] [value]` | Sets Stamina (0–100%) on any character. |
| `set_breath [id] [value]` | Sets Breath (0–100%) on any character. |

## Expeditions / travel

| Command | Effect |
|---|---|
| `teleport_mission` | Teleports player to currently selected expedition map. |
| `teleport_extraction` | Teleports player to vehicle extraction point (scavenge-only). |
| `set_loot_window [seconds]` | Overrides free loot window duration (scavenge-only). |
| `fill_containers` | Sets all containers to max loot values (scavenge-only). |
| `force_key_item [name]` | Forces a specific Key Item into the next container (scavenge-only). |
| `skip_to_wave [n]` | Fast-forwards wave timer to wave n (scavenge-only). |
| `mission_summary_preview` | Mock Day Summary with test values (scavenge-only). |

## Raids / threat

| Command | Effect |
|---|---|
| `spawn_wave [n] [edge?]` | Spawns wave n at edge (omit for weighted-random). Also used scavenge-only with no edge (north). |
| `set_threat [edge] [value]` | Sets threat weight 0–100 for an edge. |
| `show_threat_weights` | Displays threat weights in debug overlay. |

## World map / fog

| Command | Effect |
|---|---|
| `reveal_sector [id]` | Forces sector to Visited, reveals neighbors. |
| `fog_all` | Resets all sectors to Fogged (except home neighbors). |

## Time / progression

| Command | Effect |
|---|---|
| `fast_time` | Toggles accelerated time passage. |
| `win_game` | Triggers victory state (post-MVP feature; command tests the flow). |

## Build

| Command | Effect |
|---|---|
| `place_block [type] [x] [y] [z]` | Places a voxel block instantly (bypasses construction). |

## Cheats

| Command | Effect |
|---|---|
| `god_mode` | Player and colonists take no damage. |
