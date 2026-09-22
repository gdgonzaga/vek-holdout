extends RefCounted
## In-memory TerrainMaterialDef and DigToolParams fixtures for suites that exercise mining
## (dig carving, real-time LMB damage/heal, smooth-material placement). The shipped
## data/terrain/materials/*.tres and data/mining/dig_tool.tres are retuned as the game is
## balanced, so a test that reads them breaks on a content edit. Every value here is explicit
## and owned by the tests, not by game content; change one only together with the tests that
## read it.
##
## Every function returns a fresh Resource (Resources are ref-counted, nothing to free), so a
## test may mutate its copy freely (for example setting `place_radius` after the call). Ids are
## synthetic ("test_*"); yield items are unregistered ItemDefs — DigAction and
## SmoothGrid.apply_damage_at only ever read `entry.item_def.id` to spawn a WorldItem, they
## never look the id up in ItemDB, so nothing needs registering there.
##
## Usage:
##   const TerrainFixtures = preload("res://test/helpers/terrain_fixtures.gd")
##   var soil: TerrainMaterialDef = TerrainFixtures.material("test_soft", 100, {"test_item": 2})
##   var tool: DigToolParams = TerrainFixtures.dig_tool()


# =================
# Primary Functions
# =================

## A terrain material with an explicit break pool, heal time and yield list.
## `yields` is the {item_id: count} shorthand for TerrainMaterialDef.yields (Array[ItemAmount]).
static func material(id: String, hp: int = 100, yields: Dictionary = {}, minutes_to_full_heal: float = 0.25) -> TerrainMaterialDef:
	var def := TerrainMaterialDef.new()
	# 1. Identity and break pool: the fields every mining test reads (id, hp, heal time).
	_set_identity(def, id, hp, minutes_to_full_heal)
	# 2. Yields: the id->count shorthand turned into the typed ItemAmount entries dig code expects.
	def.yields = _build_yields(yields)
	return def


## A dig tool with an explicit swing time and per-swing damage, sized for a 1x1x1 box dig
## (the tests that need a sphere dig set shape/carve_radius on the returned object).
static func dig_tool(work_time: float = 0.5, swing_damage: int = 50) -> DigToolParams:
	var tool := DigToolParams.new()
	tool.work_time = work_time
	tool.shape = DigToolParams.Shape.BOX
	tool.box_size = Vector3(1.0, 1.0, 1.0)
	tool.snap_grid = true
	tool.swing_damage = swing_damage
	return tool


# ===================
# Auxiliary Functions
# ===================

static func _set_identity(def: TerrainMaterialDef, id: String, hp: int, minutes_to_full_heal: float) -> void:
	## Auxiliary: the identity and break-pool fields every mining test cares about.
	def.id = id
	def.display_name = id
	def.hp = hp
	def.minutes_to_full_heal = minutes_to_full_heal


static func _build_yields(yields: Dictionary) -> Array[ItemAmount]:
	## Auxiliary: turns the plain {item_id: count} shorthand into the typed ItemAmount array
	## TerrainMaterialDef.yields (and DigAction/SmoothGrid.apply_damage_at) expect.
	var entries: Array[ItemAmount] = []
	for item_id: String in yields:
		entries.append(_one_yield(item_id, yields[item_id]))
	return entries


static func _one_yield(item_id: String, count: int) -> ItemAmount:
	## Auxiliary: one synthetic ItemDef + ItemAmount pair for a single yield entry.
	var item_def := ItemDef.new()
	item_def.id = item_id
	var amount := ItemAmount.new()
	amount.item_def = item_def
	amount.count = count
	return amount
