class_name SuiteEditorContentLoaderTest
extends GdUnitTestSuite

const FIXTURE: String = "user://editor_content_loader_test/"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(FIXTURE + "nested/deeper")


func after_test() -> void:
	_remove_tree(FIXTURE)


func _remove_tree(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path + sub + "/")
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + f)
	DirAccess.remove_absolute(path)


func _save(res: Resource, path: String) -> void:
	assert_int(ResourceSaver.save(res, path)).is_equal(OK)


func test_furniture_scan_recurses_filters_by_type_and_sorts_by_id() -> void:
	var top := FurnitureDef.new()
	top.id = "zz_b"
	_save(top, FIXTURE + "top.tres")
	var nested := FurnitureDef.new()
	nested.id = "zz_a"
	_save(nested, FIXTURE + "nested/deeper/nested.tres")
	var flora := WildFloraDef.new()
	flora.id = "zz_flora"
	_save(flora, FIXTURE + "nested/flora.tres")

	var defs := EditorContentLoader.load_furniture_defs(FIXTURE)

	var ids: Array[String] = []
	for d in defs:
		ids.append(d.id)
	assert_array(ids).is_equal(["zz_a", "zz_b"])


func test_structure_scan_reads_tres_and_res_in_subfolders_sorted_by_name() -> void:
	var one := StructureDef.new()
	one.id = "zz_one"
	one.display_name = "Beta"
	_save(one, FIXTURE + "nested/one.tres")
	var two := StructureDef.new()
	two.id = "zz_two"
	two.display_name = "Alpha"
	_save(two, FIXTURE + "two.res")

	var defs := EditorContentLoader.load_structure_defs(FIXTURE)

	assert_int(defs.size()).is_equal(2)
	assert_str(defs[0].id).is_equal("zz_two")


func test_missing_directory_yields_an_empty_list() -> void:
	assert_array(EditorContentLoader.load_furniture_defs("user://no_such_dir_editor_content/")).is_empty()
