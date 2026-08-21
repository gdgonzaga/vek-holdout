class_name TerrainStrata
extends RefCounted
## Deterministic natural-material selection for the smooth terrain's GENERATED
## ground — the mining strata (terrain_mining/plan.md). Authored blobs carry
## identity in per-block voxel metadata (F12) and never consult this; strata
## answers only "what material is the generator's ground here", computed from
## depth rules plus seeded coherent noise with NO storage: the same position
## and seed answer the same material forever, across streaming, saves and
## reloads (the property that lets the sidecar stay edits-only).
##
## Depth is measured from the PRISTINE generated surface (surface row = 0,
## stable under digging — dig deeper, get deeper materials) via the injected
## pristine_height callable (F13's closed form, owned by SmoothGrid).
##
## Scoring per candidate: coherent 3D noise at a per-material wavelength
## (frequency ~ 1/vein_size) mapped to [0,1], combined with the weight in a
## softmax — argmax(log(spawn_weight) + TEMPERATURE * n). Softmax is
## load-bearing: an additive noise + weight-share score degenerates (a 10:2:1
## weighting means the 0.77 share bias dominates the [0,1] noise entirely —
## the heaviest material wins every position, no veins, seed-invariant), and
## pure multiplicative argmax(noise * weight) needs noise RATIO > weight
## ratio, which OpenSimplex2's ~[-0.5, 0.5] practical range cannot deliver
## for 10:1 authorings. With TEMPERATURE = 4 a 10:1 upset needs a noise gap
## of only ~0.57 — reachable, so win-regions stay contiguous (veins of
## ~vein_size) while the long-run mix tracks spawn_weight. Tunable heuristic
## nonetheless; pivot if playtesting shows high-frequency fields fracturing
## big low-frequency veins: one shared noise field partitioned into
## weight-proportional ranges (clean contiguous boundaries, at the cost of
## one shared vein scale).

## Noise vote strength in the score (see material_id_at): an upset needs a
## noise-value gap of only log(weight_ratio) / TEMPERATURE, so authorable
## weight ratios are effectively capped near e^TEMPERATURE (~55 at 4.0).
## Empirically lands the shipped 10:2:1 mix at roughly its proportions.
const TEMPERATURE := 4.0

var _materials: Array[TerrainMaterialDef] = []
var _noises: Array[FastNoiseLite] = []
var _pristine_height: Callable


## Catalog + seed + height source. Materials are sorted by id so the noise
## index (and therefore the generated world) never depends on directory scan
## order. Call once after construction; an empty catalog makes every query
## answer "" (SmoothGrid then falls back to default_material).
func setup(materials: Array, seed: int, pristine_height: Callable) -> void:
	_materials = []
	_noises = []
	for m: TerrainMaterialDef in materials:
		if m != null and m.id != "":
			_materials.append(m)
	_materials.sort_custom(func(a: TerrainMaterialDef, b: TerrainMaterialDef) -> bool:
		return a.id < b.id)
	for i: int in _materials.size():
		var noise := FastNoiseLite.new()
		noise.seed = seed + i + 1
		noise.frequency = 1.0 / float(maxi(1, _materials[i].vein_size))
		_noises.append(noise)
	_pristine_height = pristine_height


## Material id for the natural ground at pos, or "" when no band matches
## (above the pristine surface, or a depth no material claims — the caller
## falls back to its default material).
func material_id_at(pos: Vector3i) -> String:
	if _materials.is_empty() or not _pristine_height.is_valid():
		return ""
	var surface := float(_pristine_height.call(pos.x, pos.z))
	if surface != surface:  # NAN — no ground in this column
		return ""
	var depth := int(floor(surface)) - pos.y

	var best := ""
	var best_score := -INF
	for i: int in _materials.size():
		var m: TerrainMaterialDef = _materials[i]
		if depth < m.min_depth or depth > m.max_depth or m.spawn_weight <= 0.0:
			continue
		# OpenSimplex2's practical range is ~[-0.5, 0.5]; the +0.5 shift (NOT
		# *0.5+0.5, which compresses to [0.25, 0.75] and caps the reachable
		# weight ratio at 3:1) maps it onto [0, 1] with clipping at the tails.
		var n := clampf(_noises[i].get_noise_3d(pos.x, pos.y, pos.z) + 0.5, 0.0, 1.0)
		var score: float = log(m.spawn_weight) + TEMPERATURE * n
		if score > best_score:
			best_score = score
			best = m.id
	return best
