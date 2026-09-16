class_name EquipmentVisualizer
extends Node
## Visual attachment layer for the Equipment component. Listens to
## Equipment.slot_changed and instantiates or clears GLB scenes /
## MeshInstance3D nodes on per-slot skeleton sockets or wear bone attachments.
##
## Supports both rigid equipment attached to BoneAttachment3D sockets
## (EquipSocket_<slot> for tools/weapons, WearBone_<bone> for wearables) and
## skinned clothing meshes reparented under the character Skeleton3D. ARCH: equipment.md.

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

## Resolved single-bone socket nodes for tools/weapons. slot_id -> Node3D (BoneAttachment3D).
## Slots with no resolvable socket remain absent from this dict — they are skipped.
var _sockets: Dictionary = {}

## Visual nodes created per slot. slot_id -> Array[Node].
## Tracks multi-part wearable meshes and skinned scenes for lifecycle management and clean unequip.
var _slot_visuals: Dictionary = {}


func _ready() -> void:
	# 1. Equipment Connection: Wire slot_changed before sockets are resolved so
	#    no early equips fired during _ready on siblings are missed.
	_connect_to_sibling_equipment()

	# 2. Socket Resolution: Walk the parent's Skeleton3D and resolve or create
	#    a BoneAttachment3D for each slot that has bone hints.
	_resolve_all_sockets()


## Called by Equipment.slot_changed. Clears old visuals and mounts new ones if item is non-null.
func on_slot_changed(slot_id: String, item: ItemDef) -> void:
	# 1. Visual Cleanup: Clears all previous visual nodes attached for this slot.
	_clear_slot_visuals(slot_id)

	if item == null:
		return

	if item.is_wearable():
		# 2. Wearable Attachment: Attaches rigid parts and/or skinned garment scene to skeleton.
		_attach_wearable(slot_id, item)
		return

	# 3. Socket Resolution: Ensures the single-bone socket exists for traditional items.
	_ensure_socket_resolved(slot_id)
	if not _sockets.has(slot_id):
		return
	var socket: Node3D = _sockets[slot_id]

	# 4. Item Visual Attachment: Instantiates item's scene or mesh on the resolved socket.
	_attach_item_visual(item, socket)


# ====================
# Auxiliary Functions
# ====================

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
	# 1. Skeleton Lookup: Searches character hierarchy for active Skeleton3D node.
	var skeleton: Skeleton3D = _find_skeleton()
	if skeleton == null:
		return
	for slot_id: String in SLOT_BONE_HINTS:
		# 2. Slot Socket Resolution: Finds scene-authored socket or creates one from bone hints.
		var socket: BoneAttachment3D = _resolve_socket_for_slot(skeleton, slot_id)
		if socket != null:
			_sockets[slot_id] = socket


func _clear_slot_visuals(slot_id: String) -> void:
	## Auxiliary: Cleans up all visual nodes allocated for a slot, covering wearables and sockets.
	if _slot_visuals.has(slot_id):
		var nodes: Array = _slot_visuals[slot_id]
		for node_var: Variant in nodes:
			var node := node_var as Node
			if node != null and is_instance_valid(node):
				if node.get_parent() != null:
					node.get_parent().remove_child(node)
				node.queue_free()
		_slot_visuals[slot_id] = []
	if _sockets.has(slot_id):
		# 1. Socket Children Removal: Evicts legacy single-bone socket children to avoid leftovers.
		_clear_socket_children(_sockets[slot_id])


func _clear_socket_children(socket: Node3D) -> void:
	## Auxiliary: Removes and frees all children of a socket node to clear the old visual.
	for child: Node in socket.get_children():
		socket.remove_child(child)
		child.queue_free()


func _attach_wearable(slot_id: String, item: ItemDef) -> void:
	## Auxiliary: Orchestrates visual attachment for wearable gear items.
	if item.wearable == null:
		return
	# 1. Skeleton Lookup: Resolves character Skeleton3D required for bone attachments and skinning.
	var skeleton: Skeleton3D = _find_skeleton()
	if skeleton == null:
		return
	# 2. Rigid Parts Attachment: Mounts rigid armor/accessory parts to bone attachments.
	_attach_wearable_rigid_parts(slot_id, skeleton, item.wearable.rigid_parts)
	# 3. Skinned Scene Attachment: Reparents skinned clothing meshes to character skeleton.
	_attach_wearable_skinned_scene(slot_id, skeleton, item.wearable.skinned_scene)


func _attach_wearable_rigid_parts(slot_id: String, skeleton: Skeleton3D, parts: Array[WearablePart]) -> void:
	## Auxiliary: Mounts each valid rigid part to its designated bone attachment node.
	for part: WearablePart in parts:
		if part == null or part.bone.is_empty():
			continue
		# 1. Single Part Mounting: Mounts one rigid part if its target bone exists in the skeleton.
		_mount_single_rigid_part(slot_id, skeleton, part)


func _mount_single_rigid_part(slot_id: String, skeleton: Skeleton3D, part: WearablePart) -> void:
	## Auxiliary: Resolves the bone attachment, creates the part mesh, and records the visual node.
	var bone_name: String = String(part.bone)
	if skeleton.find_bone(bone_name) == -1:
		return
	# 1. Bone Attachment Resolution: Ensures BoneAttachment3D exists on skeleton for this bone.
	var attachment: BoneAttachment3D = _ensure_wear_bone_attachment(skeleton, bone_name)
	if attachment == null:
		return
	# 2. Part Mesh Creation: Instantiates and configures MeshInstance3D with mesh, material, and offset.
	var mesh_inst: MeshInstance3D = _create_rigid_part_mesh(part)
	attachment.add_child(mesh_inst)
	# 3. Visual Tracking: Records mesh under slot for clean lifecycle cleanup on unequip.
	_record_slot_visual(slot_id, mesh_inst)


func _ensure_wear_bone_attachment(skeleton: Skeleton3D, bone_name: String) -> BoneAttachment3D:
	## Auxiliary: Returns existing WearBone_<bone> node or instantiates and attaches a new one.
	var node_name: String = "WearBone_" + bone_name
	var existing: BoneAttachment3D = skeleton.get_node_or_null(node_name) as BoneAttachment3D
	if existing != null:
		return existing
	var attachment := BoneAttachment3D.new()
	attachment.name = node_name
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	return attachment


func _create_rigid_part_mesh(part: WearablePart) -> MeshInstance3D:
	## Auxiliary: Constructs and positions a MeshInstance3D from WearablePart definition.
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "WearableVisual"
	mesh_inst.mesh = part.mesh
	if part.material != null:
		mesh_inst.material_override = part.material
	mesh_inst.transform = part.offset
	return mesh_inst


func _attach_wearable_skinned_scene(slot_id: String, skeleton: Skeleton3D, scene: PackedScene) -> void:
	## Auxiliary: Instantiates a skinned scene and reparents all skinned meshes to the character skeleton.
	if scene == null:
		return
	var inst: Node = scene.instantiate()
	# 1. Mesh Sanitization: Hides internal colliders and helper nodes before processing.
	_sanitize_visual_node(inst)
	var skinned_meshes: Array[MeshInstance3D] = []
	# 2. Skinned Mesh Extraction: Collects all meshes in the scene carrying active skin bindings.
	_collect_skinned_meshes(inst, skinned_meshes)
	# 3. Skinned Mesh Reparenting: Transfers collected skinned meshes directly under the Skeleton3D.
	_reparent_skinned_meshes(slot_id, skeleton, inst, skinned_meshes)


func _collect_skinned_meshes(node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	## Auxiliary: Recursively locates MeshInstance3D nodes that have a valid skin resource.
	if node is MeshInstance3D and (node as MeshInstance3D).skin != null:
		out_meshes.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		# 1. Child Traversal: Recursively evaluates child nodes for skinned mesh instances.
		_collect_skinned_meshes(child, out_meshes)


func _reparent_skinned_meshes(slot_id: String, skeleton: Skeleton3D, inst: Node, meshes: Array[MeshInstance3D]) -> void:
	## Auxiliary: Reparents skinned meshes to skeleton, points skeleton path to parent, and frees instance remnant.
	for mesh_inst: MeshInstance3D in meshes:
		mesh_inst.owner = null
		var cur_parent: Node = mesh_inst.get_parent()
		if cur_parent != null:
			cur_parent.remove_child(mesh_inst)
		skeleton.add_child(mesh_inst)
		mesh_inst.skeleton = NodePath("..")
		# 1. Visual Tracking: Records reparented skinned mesh under slot for unequip cleanup.
		_record_slot_visual(slot_id, mesh_inst)
	if not (inst is MeshInstance3D):
		inst.queue_free()


func _record_slot_visual(slot_id: String, visual_node: Node) -> void:
	## Auxiliary: Registers an allocated visual node under slot_id for tracking and destruction.
	if not _slot_visuals.has(slot_id):
		var arr: Array[Node] = []
		_slot_visuals[slot_id] = arr
	(_slot_visuals[slot_id] as Array[Node]).append(visual_node)


func _ensure_socket_resolved(slot_id: String) -> void:
	## Auxiliary: Attempts on-demand socket resolution if not yet cached.
	if _sockets.has(slot_id):
		return
	# 1. Skeleton Lookup: Locates active Skeleton3D in parent character hierarchy.
	var skeleton: Skeleton3D = _find_skeleton()
	if skeleton != null:
		# 2. Socket Resolution: Resolves socket for slot on the discovered skeleton.
		var socket: BoneAttachment3D = _resolve_socket_for_slot(skeleton, slot_id)
		if socket != null:
			_sockets[slot_id] = socket


func _resolve_socket_for_slot(skeleton: Skeleton3D, slot_id: String) -> BoneAttachment3D:
	## Auxiliary: Returns an existing named socket or creates one from bone hints.
	##            Returns null if no matching bone is found in this skeleton.
	# 1. Node Name Resolution: Computes canonical EquipSocket_<slot> node name.
	var socket_name: String = _socket_node_name(slot_id)
	var existing: BoneAttachment3D = skeleton.get_node_or_null(socket_name) as BoneAttachment3D
	if existing != null:
		return existing
	# 2. Fallback Creation: Creates socket dynamically from hint bone list if unauthored.
	return _create_socket_from_hints(skeleton, slot_id, socket_name)


func _socket_node_name(slot_id: String) -> String:
	## Auxiliary: Returns the canonical BoneAttachment3D node name for a slot.
	##            e.g. "main_hand" -> "EquipSocket_main_hand".
	return "EquipSocket_" + slot_id


func _create_socket_from_hints(skeleton: Skeleton3D, slot_id: String, socket_name: String) -> BoneAttachment3D:
	## Auxiliary: Tries each bone hint in order; creates and returns a BoneAttachment3D
	##            on the first match. Returns null if no hint bone exists in the skeleton.
	var hints: Array = SLOT_BONE_HINTS.get(slot_id, [])
	# 1. Bone Matching: Scans skeleton bones for exact or fuzzy match with hints.
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
	# 1. Fuzzy Fallback: Performs case-insensitive substring search if exact matches fail.
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


func _attach_item_visual(item: ItemDef, socket: Node3D) -> void:
	## Auxiliary: Instantiates the item's PackedScene or mesh and attaches it to the socket.
	if item.scene != null:
		var visual: Node = item.scene.instantiate()
		if visual is Node3D:
			(visual as Node3D).name = "EquippedVisual"
			# 1. Node Sanitization: Hides collision and hitbox shapes before adding to tree.
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
		# 1. Child Sanitization: Recursively sanitizes child nodes.
		_sanitize_visual_node(child)


func _find_skeleton() -> Skeleton3D:
	## Auxiliary: Searches the parent character's subtree for the first Skeleton3D.
	var parent: Node = get_parent()
	if parent == null:
		return null
	return parent.find_child("*Skeleton*", true, false) as Skeleton3D
