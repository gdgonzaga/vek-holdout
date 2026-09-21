class_name MapEditorConfig
extends Resource
## Defaults the map editor applies to newly created maps. Kept as data so the
## editor script holds no content ids (AGENTS.md hard rule 1).

## Shared noise def used when the launcher's noise dropdown gives no valid path.
@export var default_noise_def: TerrainGenDef

## Flora a freshly created map may spawn; the author can change it per map later.
@export var default_flora_palette: Array[BuildableDef] = []
