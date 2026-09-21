extends GdUnitTestSuite

## PlayerMotor's pure air-control rule. One mid-air cardinal axis (forward/back or strafe)
## resolves to a signed scalar from which keys are held and the momentum captured at takeoff.
## Expected values are hand-derived from the documented per-axis table, not from the code:
##   both keys held            -> 0       (cancel)
##   pos held, momentum > 0    -> momentum (preserve: you jumped that way)
##   pos held, momentum <= 0   -> +nudge   (brake/nudge toward pos)
##   neg held, momentum < 0    -> momentum (preserve)
##   neg held, momentum >= 0   -> -nudge   (brake/nudge toward neg)
##   neither held              -> 0        (snap stop, no coasting)

const NUDGE := 0.5


func test_resolve_air_axis_matches_the_documented_table() -> void:
	# Break caught: any wrong branch of the air-control rule (a flipped sign, momentum kept when the
	# key opposes it, coasting with no key held, or a wrong nudge).
	var cases: Array[Dictionary] = [
		{"neg": true, "pos": true, "momentum": 2.0, "want": 0.0, "why": "both keys cancel"},
		{"neg": false, "pos": true, "momentum": 2.0, "want": 2.0, "why": "pos held, momentum along pos is preserved"},
		{"neg": false, "pos": true, "momentum": 0.0, "want": NUDGE, "why": "pos held, no momentum nudges toward pos"},
		{"neg": false, "pos": true, "momentum": -1.5, "want": NUDGE, "why": "pos held against momentum nudges, not preserves"},
		{"neg": true, "pos": false, "momentum": -2.0, "want": -2.0, "why": "neg held, momentum along neg is preserved"},
		{"neg": true, "pos": false, "momentum": 0.0, "want": -NUDGE, "why": "neg held, no momentum nudges toward neg"},
		{"neg": true, "pos": false, "momentum": 1.5, "want": -NUDGE, "why": "neg held against momentum nudges, not preserves"},
		{"neg": false, "pos": false, "momentum": 3.0, "want": 0.0, "why": "no key snaps the axis to a stop"},
	]
	for entry: Dictionary in cases:
		var got := PlayerMotor.resolve_air_axis(entry["neg"], entry["pos"], entry["momentum"], NUDGE)
		assert_float(got).override_failure_message(entry["why"]).is_equal_approx(entry["want"], 0.0001)
