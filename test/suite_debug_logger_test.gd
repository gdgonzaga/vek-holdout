extends GdUnitTestSuite

const _TEST_LOG_PATH := "user://logs/test_debug_logger.log"


func before_test() -> void:
	DebugLogger.reset_state()
	DebugLogger.set_log_file_path(_TEST_LOG_PATH)
	DebugLogger.set_log_to_file(true)
	DebugLogger.set_log_to_console(false)
	DebugLogger.set_subsystem_enabled(&"colonist", true)
	if FileAccess.file_exists(_TEST_LOG_PATH):
		DirAccess.remove_absolute(_TEST_LOG_PATH)


func after_test() -> void:
	DebugLogger.close()
	if FileAccess.file_exists(_TEST_LOG_PATH):
		DirAccess.remove_absolute(_TEST_LOG_PATH)
	DebugLogger.reset_state()


func test_debug_logger_writes_entry_to_file() -> void:
	DebugLogger.log_msg(&"core", "Test core message")
	DebugLogger.flush()

	assert_bool(FileAccess.file_exists(_TEST_LOG_PATH)).is_false() # core not enabled by default

	DebugLogger.set_subsystem_enabled(&"core", true)
	DebugLogger.log_msg(&"core", "Test core message 2")
	DebugLogger.flush()

	assert_bool(FileAccess.file_exists(_TEST_LOG_PATH)).is_true()
	var content: String = FileAccess.get_file_as_string(_TEST_LOG_PATH)
	assert_str(content).contains("[CORE] Test core message 2")


func test_colonist_logger_formats_header_and_category() -> void:
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist := colonist_scene.instantiate() as Colonist
	auto_free(colonist)
	colonist.display_name = "TestMiner"
	colonist.colonist_id = "col_123456"

	ColonistLogger.log_msg(colonist, &"ACTIVITY", "Switched to mining")
	ColonistLogger.flush()

	var content: String = FileAccess.get_file_as_string(_TEST_LOG_PATH)
	assert_str(content).contains("[COLONIST] [Colonist:TestMiner(col_12)]")
	assert_str(content).contains("[ACTIVITY] Switched to mining")


func test_colonist_logger_respects_disabled_flag() -> void:
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist := colonist_scene.instantiate() as Colonist
	auto_free(colonist)

	ColonistLogger.set_enabled(false)
	assert_bool(ColonistLogger.is_enabled()).is_false()

	ColonistLogger.log_msg(colonist, &"ACTIVITY", "Should not be logged")
	ColonistLogger.flush()

	assert_bool(FileAccess.file_exists(_TEST_LOG_PATH)).is_false()


func test_colonist_logger_brain_eval_summary() -> void:
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist := colonist_scene.instantiate() as Colonist
	auto_free(colonist)

	var scores := {&"sleep": 0.85, &"work": 0.40}
	var deficits := {&"hunger": 0.0, &"rest": 0.85}
	var target_node := Node3D.new()
	target_node.name = "Furniture_bed"
	auto_free(target_node)
	add_child(target_node)

	ColonistLogger.log_brain_eval(colonist, &"sleep", scores, deficits, target_node, false, true)
	ColonistLogger.flush()

	var content: String = FileAccess.get_file_as_string(_TEST_LOG_PATH)
	assert_str(content).contains("[BRAIN] Goal: 'sleep' [INERTIA_APPLIED]")
	assert_str(content).contains("Scores: {sleep:0.85, work:0.40}")
	assert_str(content).contains("Deficits: {hunger:0.00, rest:0.85}")
	assert_str(content).contains("Target: Furniture_bed")


func test_colonist_logger_job_claim_and_need() -> void:
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist := colonist_scene.instantiate() as Colonist
	auto_free(colonist)

	ColonistLogger.log_job_claim(colonist, &"CLAIMED", "job_abc12345", "mining", "Anchor (10, 5, 2)")
	ColonistLogger.log_need(colonist, &"rest", 0.0, 1.0, "UseSmartObject")
	ColonistLogger.flush()

	var content: String = FileAccess.get_file_as_string(_TEST_LOG_PATH)
	assert_str(content).contains("[JOB] JobClaim CLAIMED [job:job_abc1 labor:mining] | Anchor (10, 5, 2)")
	assert_str(content).contains("[NEED] Need rest: 0.00 -> 1.00 (UseSmartObject)")


func test_colonist_brain_evaluate_goals_emits_log() -> void:
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist := colonist_scene.instantiate() as Colonist
	auto_free(colonist)
	add_child(colonist)

	colonist.brain.evaluate_goals()
	ColonistLogger.flush()

	var content: String = FileAccess.get_file_as_string(_TEST_LOG_PATH)
	assert_str(content).contains("[BRAIN] Goal:")
