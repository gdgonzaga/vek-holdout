class_name CropDef
extends Resource
## Global definition for a farmable crop (ARCH "Farming", GDD §6 / Farming).
## Authored as .tres resources in data/crops/.

enum TendingMode {
	NONE = 0,
	MILESTONE = 1,
	DECAY = 2,
}

@export var id: String = ""
@export var display_name: String = ""

# --- Growth ---
## Total in-game hours required to reach maturity (1.0 growth_progress).
@export var growth_time_hours: float = 12.0
## Number of visual growth stages (e.g. 3: Sprout, Growing, Mature).
@export var growth_stages: int = 3
## Optional custom meshes for each stage. Fallback to procedural primitives if empty.
@export var stage_meshes: Array[Mesh] = []

# --- Hydration ---
## Maximum water capacity (percentage, typically 100.0).
@export var max_water: float = 100.0
## Water decay rate in % per in-game hour.
@export var water_decay_per_hour: float = 4.0
## Threshold % below which the crop triggers a Water job on the JobBoard.
@export var thirsty_threshold: float = 30.0

# --- Tending ---
## Tending mode: NONE (0), MILESTONE (1), DECAY (2).
@export var tending_mode: TendingMode = TendingMode.NONE
## Milestone progress points (0.0 to 1.0) that trigger a Tend requirement.
@export var tending_milestones: Array[float] = []
## Duration in in-game hours that a tended state lasts before needing tending again.
@export var tending_decay_hours: float = 0.0
## Growth multiplier applied while the crop needs tending (0.0 = growth halts).
@export var untended_growth_mult: float = 0.0
## In-game hours crop can remain untended before yield penalties accumulate.
@export var neglect_hours: float = 0.0
## Fraction of yield lost per neglect_hours exceeded (e.g. 0.25 = 25% loss).
@export var neglect_yield_penalty: float = 0.0

# --- Gating ---
## Requirements to sow/plant this crop (e.g. MinSkillCondition, HasItemCondition).
@export var plant_conditions: Array[Condition] = []
## Requirements to tend this crop (e.g. MinSkillCondition, tool check).
@export var tend_conditions: Array[Condition] = []

# --- Yields & Harvesting ---
## Optional seed item consumed to plant (Phase 1: optional / free if empty).
@export var seed_item_id: String = ""
## Yield definitions by achieved growth progress milestone.
@export var yield_tiers: Array[CropYieldTier] = []
## Base work seconds required to harvest, scaled by harvesting skill.
@export var base_harvest_time: float = 3.0

# --- Withering ---
## Hours a MATURE crop can sit unharvested before withering (0.0 = never withers).
@export var wither_hours: float = 0.0
