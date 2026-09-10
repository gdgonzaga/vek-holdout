class_name EquipmentVisualizer
extends Node
## Visual attachment layer for the Equipment component. Listens to
## Equipment.slot_changed and instantiates or clears GLB scenes /
## MeshInstance3D nodes on per-slot socket Node3Ds in the character hierarchy.
##
## Socket nodes live on the Skeleton3D found in the parent character. Each slot
## maps to a named BoneAttachment3D. Unmapped or unfound sockets are silently
## ignored — the architecture is ready for art assets to slot in without
## changes to this script. ARCH: equipment.md.

# ================
# Primary Functions
# ================

## Bone name fallbacks for auto-created sockets, keyed by slot ID.
## When no scene-authored BoneAttachment3D is found, these bone names are tried
## in order. Extend this table as new skeleton rigs are added.
const SLOT_BONE_HINTS: Dictionary = {
	"main_hand": ["socket_hand_r", "RightHand", "mixamorig:RightHand"],
	"off_hand":  ["socket_hand_l", "LeftHand",  "mixamorig:LeftHand"],
	"holster":   [],
	"head":      ["Head", "mixamorig:Head"],
	"torso":     ["Spine", "mixamorig:Spine1"],
	"legs":      ["Hips",  "mixamorig:Hips"],
	"feet":      ["LeftFoot", "mixamorig:LeftFoot"],
	"back":      ["Spine", "mixamorig:Spine"],
}

## Resolved socket nodes, populated in _ready. slot_id -> Node3D (BoneAttachment3D).
## Slots with no resolvable socket remain absent from this dict — they are skipped.
var _sockets: Dictionary = {}


func _ready() -> void:
	# 1. Equipment Connection: Wire slot_changed before sockets are resolved so
	#    no early equips fired during _ready on siblings are missed.
	_connect_to_sibling_equipment()

	# 2. Socket Resolution: Walk the parent's Skeleton3D and resolve or create
	#    a BoneAttachment3D for each slot that has bone hints.
	_resolve_all_sockets()


## Called by Equipment.slot_changed. Clears the old visual and attaches a new
## one if item is non-null. Silently skips slots with no resolved socket.
func on_slot_changed(slot_id: String, item: ItemDef) -> void:
	# 1. On-demand Socket Resolution: Resolve socket if skeleton was added after _ready or outside tree.
	_ensure_socket_resolved(slot_id)
	if not _sockets.has(slot_id):
		return
	var socket: Node3D = _sockets[slot_id]

	# 2. Socket Cleanup: Remove any previously attached visual child.
	_clear_socket_children(socket)

	if item == null:
		return

	# 3. Visual Attachment: Instantiate item's GLB scene or mesh on the socket.
	_attach_item_visual(item, socket)

# ====================
# Auxiliary Functions
# ====================

func _ensure_socket_resolved(slot_id: String) -> void:
	## Auxiliary: Attempts on-demand socket resolution if not yet cached.
	if _sockets.has(slot_id):
		return
	var skeleton: Skeleton3D = _find_skeleton()
	if skeleton != null:
		var socket: BoneAttachment3D = _resolve_socket_for_slot(skeleton, slot_id)
		if socket != null:
			_sockets[slot_id] = socket


func _connect_to_sibling_equipment() -> void:
	## Auxiliary: Finds the Equipment sibling node on the parent character and connects
	## slot_changed so all future equip/unequip events drive visual updates.
	var parent: Node = get_parent()
	if parent == null:
		return
	var eq: Equipment = parent.get_node_or_null("Equipment") as Equipment
	if eq == null:
		return
	if not eq.slot_changed.is_connected(on_slot_changed):
		eq.slot_changed.connect(on_slot_changed)


func _resolve_all_sockets() -> void:
	## Auxiliary: Iterates all slots with bone hints and resolves or creates their sockets.
	var skeleton: Skeleton3D = _find_skeleton()
	if skeleton == null:
		# No skeleton yet (headless test, pre-scene-load). Sockets stay empty.
		return
	for slot_id: String in SLOT_BONE_HINTS:
		var socket: BoneAttachment3D = _resolve_socket_for_slot(skeleton, slot_id)
		if socket != null:
			_sockets[slot_id] = socket


func _find_skeleton() -> Skeleton3D:
	## Auxiliary: Searches the parent character's subtree for the first Skeleton3D.
	var parent: Node = get_parent()
	if parent == null:
		return null
	return parent.find_child("*Skeleton*", true, false) as Skeleton3D


func _resolve_socket_for_slot(skeleton: Skeleton3D, slot_id: String) -> BoneAttachment3D:
	## Auxiliary: Returns an existing named socket or creates one from bone hints.
	##            Returns null if no matching bone is found in this skeleton.
	var socket_name: String = _socket_node_name(slot_id)

	# Prefer a scene-authored socket by its canonical name.
	var existing: BoneAttachment3D = skeleton.get_node_or_null(socket_name) as BoneAttachment3D
	if existing != null:
		return existing

	# Fall back: auto-create from the bone hints list for this slot.
	return _create_socket_from_hints(skeleton, slot_id, socket_name)


func _socket_node_name(slot_id: String) -> String:
	## Auxiliary: Returns the canonical BoneAttachment3D node name for a slot.
	##            e.g. "main_hand" -> "EquipSocket_main_hand".
	return "EquipSocket_" + slot_id


func _create_socket_from_hints(skeleton: Skeleton3D, slot_id: String, socket_name: String) -> BoneAttachment3D:
	## Auxiliary: Tries each bone hint in order; creates and returns a BoneAttachment3D
	##            on the first match. Returns null if no hint bone exists in the skeleton.
	var hints: Array = SLOT_BONE_HINTS.get(slot_id, [])
	var bone_name: String = _first_matching_bone(skeleton, hints)
	if bone_name.is_empty():
		return null
	var socket := BoneAttachment3D.new()
	socket.name = socket_name
	socket.bone_name = bone_name
	skeleton.add_child(socket)
	return socket


func _first_matching_bone(skeleton: Skeleton3D, hints: Array) -> String:
	## Auxiliary: Returns the first hint bone name that exists in the skeleton, or "".
	for hint: String in hints:
		if skeleton.find_bone(hint) != -1:
			return hint
	# Broad fallback: substring match on "righthand" / "hand_r" patterns.
	return _fuzzy_bone_match(skeleton, hints)


func _fuzzy_bone_match(skeleton: Skeleton3D, hints: Array) -> String:
	## Auxiliary: Case-insensitive substring search across all bone names for any hint token.
	##            Used as a last resort when exact names miss (e.g. custom rig naming).
	for i: int in range(skeleton.get_bone_count()):
		var b: String = skeleton.get_bone_name(i).to_lower()
		for hint: String in hints:
			var h: String = hint.to_lower()
			if h in b:
				return skeleton.get_bone_name(i)
	return ""


func _clear_socket_children(socket: Node3D) -> void:
	## Auxiliary: Removes and frees all children of a socket node to clear the old visual.
	for child: Node in socket.get_children():
		socket.remove_child(child)
		child.queue_free()


func _attach_item_visual(item: ItemDef, socket: Node3D) -> void:
	## Auxiliary: Instantiates the item's PackedScene or mesh and attaches it to the socket.
	if item.scene != null:
		var visual: Node = item.scene.instantiate()
		if visual is Node3D:
			(visual as Node3D).name = "EquippedVisual"
			# Sanitization: hide internal hitbox/collision meshes before adding to tree.
			_sanitize_visual_node(visual)
			socket.add_child(visual)
		else:
			visual.queue_free()
	elif item.mesh != null:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "EquippedVisual"
		mesh_inst.mesh = item.mesh
		if item.material != null:
			mesh_inst.material_override = item.material
		socket.add_child(mesh_inst)


func _sanitize_visual_node(node: Node) -> void:
	## Auxiliary: Recursively hides collision shapes, hitbox meshes, and Area3D nodes
	##            inside an imported GLB so only the visible mesh renders in-hand.
	for child: Node in node.get_children():
		var lower: String = child.name.to_lower()
		if child is MeshInstance3D:
			if "hitbox" in lower or "hibox" in lower or "area" in lower or "col" in lower:
				(child as MeshInstance3D).visible = false
		elif child is CollisionShape3D or child is CollisionObject3D or child is Area3D:
			if child is Node3D:
				(child as Node3D).visible = false
		_sanitize_visual_node(child)
