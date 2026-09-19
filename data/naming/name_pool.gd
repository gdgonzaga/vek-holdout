class_name NamePool
extends Resource
## Authored pool of names for randomly naming generic (unnamed) colonists (ARCH colonists.md,
## GDD 6.5). Referenced by ColonistDef.name_pool; ColonistNamer rolls a first + last name.
## First names are split into two lists for authoring; ColonistNamer flips a fair coin
## between the non-empty lists, then picks uniformly within the chosen one. Colonists store
## no gender, so the split only shapes which names appear. Any list may be left empty (a
## pool with only last names yields single-name colonists).

@export var id: String = ""
@export var male_first_names: PackedStringArray = PackedStringArray()
@export var female_first_names: PackedStringArray = PackedStringArray()
@export var last_names: PackedStringArray = PackedStringArray()
