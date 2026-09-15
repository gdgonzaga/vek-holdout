class_name MoodletLayoutResolver
extends RefCounted
## Pure moodlet evaluation + billboard-row layout arithmetic, shared by
## ColonistMoodletVisualizer, EnemyMoodletVisualizer, WildFloraMoodletVisualizer,
## and their entities' get_active_moodlets() (ARCH colonists.md "Moodlet
## System"). Extracted after 8d42ae5 fixed the group-before-cap starvation bug
## in ColonistMoodletVisualizer alone and left the same bug live in
## EnemyMoodletVisualizer — a third hand-copied visualizer would have made
## that divergence worse instead of fixing it.


## Evaluates every def in moodlet_defs against entity (any IStatProvider
## implementer) and returns the active, texture-bearing ones in configured
## order. Each entry: { "def": MoodletDef, "index": int, "texture": Texture2D,
## "name": String }.
static func evaluate_active_moodlets(entity: Node, moodlet_defs: Array[MoodletDef]) -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for m_def in moodlet_defs:
		if m_def == null:
			continue
		var idx: int = m_def.evaluate_icon_index(entity)
		if idx < 0:
			continue
		var tex: Texture2D = m_def.get_active_texture(entity)
		if tex == null:
			continue
		active.append({
			"def": m_def,
			"index": idx,
			"texture": tex,
			"name": m_def.display_name,
		})
	return active


## Buckets active moodlet records by their line_number property, capping each
## row independently at per_line_cap rather than capping the flat list before
## grouping — so a crowded row (e.g. status icons) can never starve out an
## unrelated row's icon (e.g. the activity row) the way slicing the flat
## pre-grouped list used to.
static func group_moodlets_by_line(valid_moodlets: Array[Dictionary], per_line_cap: int) -> Dictionary:
	var grouped: Dictionary = {}
	for moodlet_data: Dictionary in valid_moodlets:
		var m_def: MoodletDef = moodlet_data.get("def", null) as MoodletDef
		var line_num: int = m_def.line_number if m_def != null else 0
		if not grouped.has(line_num):
			grouped[line_num] = []
		var line_list: Array = grouped[line_num]
		if line_list.size() < per_line_cap:
			line_list.append(moodlet_data)
	return grouped


## Extracts sorted ascending line numbers from a grouped dictionary.
static func get_sorted_active_lines(grouped_lines: Dictionary) -> Array[int]:
	var keys: Array[int] = []
	for k in grouped_lines.keys():
		keys.append(int(k))
	keys.sort()
	return keys


## Sums sprite counts across all active lines after per-line capping.
static func count_grouped_sprites(grouped_lines: Dictionary, active_lines: Array[int]) -> int:
	var total := 0
	for line_num in active_lines:
		total += (grouped_lines[line_num] as Array).size()
	return total
