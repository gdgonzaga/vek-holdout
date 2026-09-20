class_name EnemyDef
extends Resource
## Data-driven definition for one hostile enemy archetype (GDD §5). Backs
## EnemyBase.enemy_def; EnemyLibrary indexes instances by `id` for save
## round-trips. Schema: docs/architecture/data-schemas.md (EnemyDef).

@export var id: String = ""
@export var display_name: String = "Enemy"
@export var max_hp: int = 100
@export var max_durability: int = 0
@export var base_move_speed: float = 5.0
@export var detect_range: float = 16.0
## Seconds without line of sight before a chasing enemy should give up
## (GDD §5 Brawler/Shooter tables). Not consumed by any AI task yet — pure
## forward-compatible data; see docs/architecture/data-schemas.md (EnemyDef).
@export var los_loss_timeout: float = 5.0
@export var behavior_tree: BehaviorTree = null
## Polymorphic combat data — assign a MeleeActionParams or RangedActionParams
## instance (data/capability_params/). Null means this archetype never attacks.
@export var attack_params: CombatActionParams = null
## Rolled by EnemyBase on death (LootRoller). Null means this archetype drops
## nothing. Schema: docs/architecture/data-schemas.md (LootTable).
@export var loot_table: LootTable = null
@export var moodlet_defs: Array[MoodletDef] = []
