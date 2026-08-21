extends GdUnitTestSuite

## Unit tests for TerrainStrata — the deterministic natural-material selector
## for the smooth terrain (terrain_mining/plan.md). Pins: depth-band gating
## against the PRISTINE surface (surface row = depth 0, above-surface = no
## candidate), determinism across instances and seeds, spawn_weight semantics
## (0 = never, relative mix ratios), vein coherence from the per-material
## coherent noise, and the empty-catalog / NAN-height fallbacks.
##
## Deterministic asserts are only made where a single material can answer
## (single-candidate bands); overlapping bands are pinned statistically over
## large fixed-seed samples — stable per build, never flaky.

const FLAT_SURFACE := 10.0
const SEED := 42


func _flat_height(_x: int, _z: int) -> float:
	return FLAT_SURFACE


func _nan_height(_x: int, _z: int) -> float:
	return NAN


func _def(id: String, min_depth: int, max_depth: int, weight: float, vein: int) -> TerrainMaterialDef:
	var d := TerrainMaterialDef.new()
	d.id = id
	d.min_depth = min_depth
	d.max_depth = max_depth
	d.spawn_weight = weight
	d.vein_size = vein
	return d


## Position at the given depth below the flat surface (floor(10) = 10).
func _depth_pos(depth: int) -> Vector3i:
	return Vector3i(0, int(FLAT_SURFACE) - depth, 0)


## Test catalog: real band/weight structure (10:2:1) but SMALL vein scales —
## the shipped defs mine 60-wide rock provinces (intentional), and statistical
## asserts inside one province would never see the minority materials. The
## selector's properties show up at wavelengths the sampling window spans.
func _ore_catalog() -> Array:
	return [
		_def("ground", 0, 3, 1.0, 16),
		_def("rock", 3, 0x7FFFFFFF, 10.0, 12),
		_def("iron_ore", 12, 0x7FFFFFFF, 2.0, 6),
		_def("gold_ore", 24, 0x7FFFFFFF, 1.0, 4),
	]


func test_empty_catalog_answers_empty() -> void:
	var s := TerrainStrata.new()
	s.setup([], SEED, Callable(self, "_flat_height"))
	assert_str(s.material_id_at(_depth_pos(1))).is_empty()


func test_nan_height_answers_empty() -> void:
	var s := TerrainStrata.new()
	s.setup(_ore_catalog(), SEED, Callable(self, "_nan_height"))
	assert_str(s.material_id_at(_depth_pos(1))).is_empty()


func test_band_gating_single_candidate_depths() -> void:
	var s := TerrainStrata.new()
	s.setup(_ore_catalog(), SEED, Callable(self, "_flat_height"))
	assert_str(s.material_id_at(_depth_pos(0))).is_equal("ground")   # surface row
	assert_str(s.material_id_at(_depth_pos(1))).is_equal("ground")   # dirt-only band
	assert_str(s.material_id_at(_depth_pos(5))).is_equal("rock")     # below all ores
	assert_str(s.material_id_at(_depth_pos(-2))).is_empty()          # above the surface


func test_zero_spawn_weight_never_generates() -> void:
	# Weight 0 removes the material from candidacy entirely — even when it is
	# the only def whose band matches the depth.
	var lonely := _def("void_ore", 0, 0x7FFFFFFF, 0.0, 8)
	var s := TerrainStrata.new()
	s.setup([lonely], SEED, Callable(self, "_flat_height"))
	assert_str(s.material_id_at(_depth_pos(4))).is_empty()


func test_determinism_across_instances_and_queries() -> void:
	var a := TerrainStrata.new()
	a.setup(_ore_catalog(), SEED, Callable(self, "_flat_height"))
	var b := TerrainStrata.new()
	b.setup(_ore_catalog(), SEED, Callable(self, "_flat_height"))
	var mismatches := 0
	for x: int in range(-22, 23, 2):
		for z: int in range(-22, 23, 2):
			var pos := Vector3i(x, -20, z)  # depth 30: rock/iron/gold mix band
			var first: String = a.material_id_at(pos)
			assert_str(a.material_id_at(pos)).is_equal(first)  # stable per instance
			if b.material_id_at(pos) != first:
				mismatches += 1
	assert_int(mismatches).is_equal(0)


func test_seed_changes_the_generated_world() -> void:
	var a := TerrainStrata.new()
	a.setup(_ore_catalog(), SEED, Callable(self, "_flat_height"))
	var b := TerrainStrata.new()
	b.setup(_ore_catalog(), SEED + 1000, Callable(self, "_flat_height"))
	var diffs := 0
	for x: int in range(-48, 49, 2):
		for z: int in range(-48, 49, 2):
			if a.material_id_at(Vector3i(x, -20, z)) != b.material_id_at(Vector3i(x, -20, z)):
				diffs += 1
	# Independent per-point disagreement odds are ~1 - sum(p^2) ~ 0.38 over
	# 2401 samples — anything above a third of the expected count says the
	# seeds generate genuinely different worlds.
	assert_int(diffs).is_greater(300)


func test_statistical_mix_follows_spawn_weights() -> void:
	var s := TerrainStrata.new()
	s.setup(_ore_catalog(), SEED, Callable(self, "_flat_height"))
	var counts := {"rock": 0, "iron_ore": 0, "gold_ore": 0}
	var samples := 0
	for x: int in range(-48, 49, 2):
		for z: int in range(-48, 49, 2):
			var id: String = s.material_id_at(Vector3i(x, -20, z))  # depth 30
			if counts.has(id):
				counts[id] = int(counts[id]) + 1
			samples += 1
	# Softmax scoring (log(weight) + TEMPERATURE * noise): the long-run mix
	# tracks the 10:2:1 weights. The ordering must be strict and all three
	# must appear in bulk.
	assert_int(counts["rock"]).is_greater(counts["iron_ore"])
	assert_int(counts["iron_ore"]).is_greater(counts["gold_ore"])
	assert_int(counts["gold_ore"]).is_greater(50)
	assert_int(samples).is_greater(2000)


func test_vein_coherence_adjacent_over_distant() -> void:
	var s := TerrainStrata.new()
	s.setup(_ore_catalog(), SEED, Callable(self, "_flat_height"))
	var adjacent_same := 0
	var adjacent_total := 0
	var distant_same := 0
	var distant_total := 0
	for x: int in range(-32, 33, 4):
		for z: int in range(-32, 33, 4):
			var pos := Vector3i(x, -5, z)  # depth 15: rock/iron overlap band
			var here: String = s.material_id_at(pos)
			if here != "":
				adjacent_total += 1
				if s.material_id_at(pos + Vector3i(1, 0, 0)) == here:
					adjacent_same += 1
				distant_total += 1
				if s.material_id_at(pos + Vector3i(17, 0, 17)) == here:
					distant_same += 1
	var adjacent_rate := float(adjacent_same) / maxf(1.0, float(adjacent_total))
	var distant_rate := float(distant_same) / maxf(1.0, float(distant_total))
	# Coherent noise correlates neighbors; 17 apart is past the iron wavelength
	# (6 here) and well into decorrelation. In a degenerate picker (independent
	# per-cell choices) both rates collapse to sum(p^2) and the gap is 0 —
	# anything above a small margin proves veins. Observed ~0.10 on the fixed
	# seed; the margin keeps the test robust to harmless rescoring tweaks.
	assert_float(adjacent_rate - distant_rate).is_greater(0.05)
