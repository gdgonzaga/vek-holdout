extends RefCounted
## Throwaway-map fixtures shared by the map editor suites. Every map created
## here uses SANDBOX_PREFIX so a crashed run leaves obviously disposable output,
## and tests never depend on shipped map content.

const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")

const SANDBOX_PREFIX: String = "zz_sandbox_"
const MAPS_DIR: String = "res://data/maps/"


static func map_id(suffix: String) -> String:
	return SANDBOX_PREFIX + suffix


## Deletes the map folder and its files. Safe to call when it does not exist.
static func remove_map(id: String) -> void:
	var dir := DirAccess.open(MAPS_DIR + id)
	if dir == null:
		return
	for entry in dir.get_files():
		dir.remove(entry)
	DirAccess.open(MAPS_DIR).remove(id)


static func heightmap_payload(id: String) -> Dictionary:
	var image := Image.create(32, 32, false, Image.FORMAT_RGB8)
	image.fill(Color(0.75, 0.75, 0.75))
	return {
		"map_id": id,
		"map_type": MapDef.MapType.POI,
		"terrain_mode": EditorLauncherClass.TerrainMode.HEIGHTMAP,
		"noise_def_path": "",
		"image": image,
		"height_start": -7.0,
		"height_range": 21.0,
	}


static func blocky_only_payload(id: String) -> Dictionary:
	return {
		"map_id": id,
		"map_type": MapDef.MapType.POI,
		"terrain_mode": EditorLauncherClass.TerrainMode.NONE,
	}


## Unload, then drain two frames so in-flight streaming workers finish before
## the sqlite files are deleted (otherwise they spam errors into the log).
static func dispose(tree: SceneTree, editor: MapEditor, id: String) -> void:
	editor.unload_map()
	await tree.process_frame
	await tree.process_frame
	remove_map(id)


## Saves a standalone noise def under user:// (a stand-in for a shared baseline
## def that must never be modified by per-map edits) and returns the loaded copy.
static func save_noise_def(path: String, noise_seed: int, frequency: float) -> TerrainGenDef:
	var def := TerrainGenDef.new()
	def.id = "sandbox_noise"
	def.noise_seed = noise_seed
	def.noise_frequency = frequency
	def.take_over_path(path)
	ResourceSaver.save(def, path)
	return def
