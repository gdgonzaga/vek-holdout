class_name MapIdRules
extends RefCounted
## Naming rule for map ids: snake_case, and the id is the folder name under
## data/maps/ (AGENTS.md "Data conventions"), so it must never carry a path.

const ID_PATTERN: String = "^[a-z][a-z0-9_]*$"


## Empty string when map_id is valid, otherwise the message to show the author.
static func validate(map_id: String) -> String:
	if map_id.is_empty():
		return "Map name cannot be empty"
	var pattern := RegEx.create_from_string(ID_PATTERN)
	if pattern.search(map_id) == null:
		return "Map name must be snake_case: lowercase letters, digits and underscores, starting with a letter"
	return ""
