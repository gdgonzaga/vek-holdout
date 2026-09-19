## Shared fixtures for enemy-def suites: writes EnemyDef .tres files under a
## user:// fixture dir and constructs an isolated EnemyLibrary instance
## against it (EnemyLibrary has no constructor-injectable dir, unlike
## BlockLibrary, so tests call ._load_dir() directly, bypassing _ready()).
## Plain script on purpose (never extends GdUnitTestSuite — the runner would
## scan it as a suite).

const EnemyLibraryScript := preload("res://subsystems/combat/enemy_library.gd")


## Writes a_valid.tres (id="valid_enemy") and b_empty_id.tres (id="") and
## returns the dir path. The empty-id fixture exercises the skip-on-load path.
static func make_enemy_dir(tag: String) -> String:
	var dir := "user://fixture_enemies_%s/" % tag
	DirAccess.make_dir_recursive_absolute(dir)
	var d := DirAccess.open(dir)
	if d != null:
		for existing in d.get_files():
			d.remove(existing)
	_write_def(dir + "a_valid.tres", "valid_enemy")
	_write_def(dir + "b_empty_id.tres", "")
	return dir


## Constructs an EnemyLibrary instance loaded from the given fixture dir,
## without going through the autoload's own _ready() directory scan.
static func make_library(dir: String) -> Node:
	var lib: Node = EnemyLibraryScript.new()
	lib._load_dir(dir)
	return lib


static func _write_def(path: String, enemy_id: String) -> void:
	var def := EnemyDef.new()
	def.id = enemy_id
	def.display_name = enemy_id
	var err := ResourceSaver.save(def, path)
	assert(err == OK, "fixture save failed at %s (err %d)" % [path, err])
