extends GdUnitTestSuite
## LogFeed duplicate-collapse behavior: a repeat of the newest message must
## increment the existing line's counter in place, never spawn a second line.

var _feed: LogFeed


func before_test() -> void:
	# LogFeed._ready repopulates from GameLog's buffer, so start each test
	# with an empty history. GameLog persists (autoload) across suites.
	GameLog.clear()
	_feed = auto_free(LogFeed.new())
	add_child(_feed)


func test_first_message_spawns_one_line() -> void:
	GameLog.info("Raid repelled.")
	assert_int(_feed._lines.size()).is_equal(1)
	assert_str(_feed._lines[0].label.text).is_equal(
			"[color=#ffffff]Raid repelled.[/color]")


func test_duplicate_collapses_into_counter() -> void:
	GameLog.info("Raid repelled.")
	GameLog.info("Raid repelled.")
	assert_int(_feed._lines.size()).is_equal(1)
	assert_str(_feed._lines[0].label.text).is_equal(
			"[color=#ffffff]Raid repelled.[/color] x2")


func test_counter_keeps_incrementing() -> void:
	for i in 5:
		GameLog.combat("A raid has begun!")
	assert_int(_feed._lines.size()).is_equal(1)
	assert_str(_feed._lines[0].label.text).is_equal(
			"[color=#ff7d7d]A raid has begun![/color] x5")


func test_different_message_spawns_new_line() -> void:
	GameLog.info("Raid repelled.")
	GameLog.info("Day 2 begins")
	assert_int(_feed._lines.size()).is_equal(2)
	# Newest at index 0; the older line keeps its uncounted text.
	assert_str(_feed._lines[0].label.text).is_equal(
			"[color=#ffffff]Day 2 begins[/color]")
	assert_str(_feed._lines[1].label.text).is_equal(
			"[color=#ffffff]Raid repelled.[/color]")


func test_break_in_run_resets_collapse() -> void:
	GameLog.info("Raid repelled.")
	GameLog.info("Raid repelled.")
	GameLog.info("Day 2 begins")
	GameLog.info("Raid repelled.")
	assert_int(_feed._lines.size()).is_equal(3)
	# Only the newest (index 0) collapses; the older "Raid repelled." line
	# is not retro-merged with it.
	assert_str(_feed._lines[0].label.text).is_equal(
			"[color=#ffffff]Raid repelled.[/color]")
	assert_str(_feed._lines[2].label.text).is_equal(
			"[color=#ffffff]Raid repelled.[/color] x2")


func test_duplicate_refreshes_timeout() -> void:
	GameLog.info("Raid repelled.")
	var first_spawn: float = _feed._lines[0].spawn_time
	# Bump the engine clock so a refreshed spawn_time is distinguishable.
	var before: float = Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 <= before:
		OS.delay_msec(2)
	GameLog.info("Raid repelled.")
	assert_float(_feed._lines[0].spawn_time).is_greater(first_spawn)
