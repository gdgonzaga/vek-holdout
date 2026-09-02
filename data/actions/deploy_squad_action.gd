class_name DeploySquadAction
extends GameAction
## Enters tactical deployment placement mode for a colonist's whole squad.

func execute(_actor: Node, target: Node) -> void:
	if target == null or Colony == null:
		return
	var squad_id: String = str(target.get("squad_id"))
	if squad_id == "":
		return
	var members := Colony.get_squad_members(squad_id)
	if not members.is_empty():
		EventBus.command_mode_requested.emit(members)
