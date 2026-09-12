class_name RecreationParams
extends FurnitureCapability
## Capability parameters for recreation furniture (arcade cabinets, statues, murals).
## Marks this furniture as a colonist recreation destination for the &"recreation"
## need declared in data/needs/need_recreation.tres. FurnitureLayer spawns
## RecreationComponent when this is non-null.
##
## Group membership still comes from FurnitureDef.tags (Furniture._register_tag_groups),
## so a recreation def MUST also declare tags = ["recreation_object"] to match
## NeedDef.target_group — RecreationComponent warns loudly when it doesn't.
## See docs/architecture/recreation.md.

## Recreation need restored per second while a colonist is actively using this
## object (0.0 to 1.0 scale). 0.08 fills an empty need in roughly 12 seconds.
@export var recreation_per_second: float = 0.08

## Seconds a colonist commits to once a session starts, even if the need fills
## early. Without a floor, a high-rate object tops the need up in a fraction of a
## second and the colonist bounces straight back to work — visibly twitchy.
@export var min_session_seconds: float = 4.0

## Hard ceiling on a single session. The colonist leaves and ColonistBrain
## re-arbitrates even if the need is not yet full, so no single object can
## monopolise a colonist indefinitely.
@export var max_session_seconds: float = 20.0

## Simultaneous users. 1 = exclusive (arcade cabinet); N = N at once (a couch);
## -1 = unlimited (statue, mural — any number of onlookers benefit at once).
@export var capacity: int = 1

## Max distance in metres from the furniture at which a colonist still accrues.
## 1.5 means the colonist must stand adjacent; a TV would author roughly 6.0 so
## it can be watched from across a room.
@export var use_radius: float = 1.5

## Optional standing spots, local to the furniture origin. The furniture's own
## transform supplies rotation at runtime, so these are authored unrotated. When
## non-empty they are the exact positions colonists are sent to (one per slot)
## and they cap the effective capacity. When empty, colonists path to a walkable
## cell near the furniture instead.
@export var use_offsets: Array[Vector3] = []

## Animation override played for the duration of the session.
@export var use_animation: StringName = &"Interact"


# =================
# Primary Functions
# =================

## Simultaneous users this object actually supports. Returns -1 for unlimited.
## Authored offsets are a hard cap: there is no sensible place to put a user
## beyond the last authored spot, so slots can never exceed use_offsets.size().
func effective_capacity() -> int:
	if use_offsets.is_empty():
		return capacity
	if capacity < 0:
		return use_offsets.size()
	return mini(capacity, use_offsets.size())


## Session ceiling clamped to never fall below the floor. Guards against an
## authoring slip (max < min) locking BTActionUseRecreation into a state where
## the minimum commitment can never be satisfied.
func session_ceiling_seconds() -> float:
	return maxf(min_session_seconds, max_session_seconds)
