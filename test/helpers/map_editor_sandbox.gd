extends RefCounted
## Throwaway-map fixtures shared by the map editor suites. Every map created
## here uses SANDBOX_PREFIX so a crashed run leaves obviously disposable output,
## and tests never depend on shipped map content.

const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")

const SANDBOX_PREFIX: String = "zz_sandbox_"
const MAPS_DIR: String = "res://data/maps/"  # hygiene-ok: the editor authors into res://data/maps by design (tech-debt.md); sweep_stale() cleans crash leftovers


static func map_id(suffix: String) -> String:
	return SANDBOX_PREFIX + suffix


## Removes throwaway maps that a crashed earlier run left in res://data/maps/. Call from a suite's before(). # hygiene-ok: doc comment naming MAPS_DIR, not a literal path in code
static func sweep_stale() -> void:
	for folder: String in DirAccess.get_directories_at(MAPS_DIR):
		if folder.begins_with(SANDBOX_PREFIX):
			remove_map(folder)


## Absolute path of a sandbox map's folder, for assertions about what is on disk.
static func map_dir(id: String) -> String:
	return MAPS_DIR + id + "/"


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
		"map_type": MapDef.MapType.BASE,
		"terrain_mode": EditorLauncherClass.TerrainMode.HEIGHTMAP,
		"noise_def_path": "",
		"image": image,
		"height_start": -7.0,
		"height_range": 21.0,
	}


static func blocky_only_payload(id: String) -> Dictionary:
	return {
		"map_id": id,
		"map_type": MapDef.MapType.BASE,
		"terrain_mode": EditorLauncherClass.TerrainMode.NONE,
	}


## Unload, then drain two frames so in-flight streaming workers finish before
## the sqlite files are deleted (otherwise they spam errors into the log).
## Under a loaded suite run the 2-frame drain is occasionally not enough time
## for a background voxel-stream worker to release its file handles, which
## leaked a zz_sandbox_* folder in one full-suite run during R12A hardening;
## retry the removal for a few more frames (bounded, no wall-clock wait) before
## giving up rather than trusting a single fixed-size drain.
static func dispose(tree: SceneTree, editor: MapEditor, id: String) -> void:
	editor.unload_map()
	await tree.process_frame
	await tree.process_frame
	remove_map(id)
	var extra_frames := 0
	while DirAccess.dir_exists_absolute(map_dir(id)) and extra_frames < 10:
		await tree.process_frame
		remove_map(id)
		extra_frames += 1


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
