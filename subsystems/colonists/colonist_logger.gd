class_name ColonistLogger
extends RefCounted
## Specialized logger for Colonist AI, behaviors, tasks, and state transitions.
## Delegates file I/O and configuration to the core DebugLogger under the &"colonist" subsystem.

const SUBSYSTEM_NAME: StringName = &"colonist"


# =================
# Primary Functions
# =================

## Returns whether colonist debug logging is currently active.
static func is_enabled() -> bool:
	return DebugLogger.is_subsystem_enabled(SUBSYSTEM_NAME)


## Enables or disables colonist debug logging at runtime.
static func set_enabled(enabled: bool) -> void:
	DebugLogger.set_subsystem_enabled(SUBSYSTEM_NAME, enabled)


## Writes a general debug message tagged with colonist identification.
static func log_msg(colonist: Node, category: StringName, message: String) -> void:
	# 1. Active Check: Skip processing if colonist logging is disabled.
	if not is_enabled():
		return

	# 2. Header Formatting: Extract colonist display name and ID.
	var header: String = _format_colonist_header(colonist)

	# 3. Message Dispatch: Send formatted string to core DebugLogger.
	DebugLogger.log_msg(SUBSYSTEM_NAME, "%s [%s] %s" % [header, str(category).to_upper(), message])


## Alias for log_msg.
static func log(colonist: Node, category: StringName, message: String) -> void:
	# 1. Message Dispatch: Delegate directly to log_msg.
	log_msg(colonist, category, message)


## Logs a detailed breakdown of utility AI goal evaluation from ColonistBrain.
static func log_brain_eval(
	colonist: Node,
	winning_goal: StringName,
	scores: Dictionary,
	deficits: Dictionary,
	target: Variant,
	critical: bool,
	inertia: bool
) -> void:
	# 1. Active Check: Skip if colonist logging is disabled.
	if not is_enabled():
		return

	# 2. Summary Formatting: Construct compact human-readable brain decision text.
	var summary: String = _format_brain_eval_summary(winning_goal, scores, deficits, target, critical, inertia)

	# 3. Log Dispatch: Output under the BRAIN category.
	log_msg(colonist, &"BRAIN", summary)


## Logs a behavior tree task execution event (e.g. ENTER, RUNNING, SUCCESS, FAILURE).
static func log_task(colonist: Node, task_name: StringName, event: StringName, details: String = "") -> void:
	# 1. Active Check: Skip if colonist logging is disabled.
	if not is_enabled():
		return

	var msg := "%s %s" % [task_name, str(event).to_upper()]
	if not details.is_empty():
		msg += " | %s" % details

	# 2. Log Dispatch: Output under the TASK category.
	log_msg(colonist, &"TASK", msg)


## Logs a job claim attempt, success, or rejection reason from JobBoard / BTActionClaimJob.
static func log_job_claim(colonist: Node, event: StringName, job_id: String, labor_id: String, details: String = "") -> void:
	# 1. Active Check: Skip if colonist logging is disabled.
	if not is_enabled():
		return

	var short_id := job_id.left(8) if not job_id.is_empty() else "none"
	var msg := "JobClaim %s [job:%s labor:%s]" % [str(event).to_upper(), short_id, labor_id]
	if not details.is_empty():
		msg += " | %s" % details

	# 2. Log Dispatch: Output under the JOB category.
	log_msg(colonist, &"JOB", msg)


## Logs a need restoration or critical decay change on a colonist.
static func log_need(colonist: Node, need_id: StringName, old_val: float, new_val: float, reason: String = "") -> void:
	# 1. Active Check: Skip if colonist logging is disabled.
	if not is_enabled():
		return

	var msg := "Need %s: %.2f -> %.2f" % [need_id, old_val, new_val]
	if not reason.is_empty():
		msg += " (%s)" % reason

	# 2. Log Dispatch: Output under the NEED category.
	log_msg(colonist, &"NEED", msg)


## Flushes any buffered log entries to disk.
static func flush() -> void:
	DebugLogger.flush()


# ===================
# Auxiliary Functions
# ===================

static func _format_colonist_header(colonist: Node) -> String:
	## Auxiliary: Resolves colonist display name and shortened UUID header.
	if colonist == null or not is_instance_valid(colonist):
		return "[Colonist:Unknown]"

	var name_str: String = ""
	if "display_name" in colonist and not str(colonist.display_name).is_empty():
		name_str = str(colonist.display_name)
	else:
		name_str = colonist.name

	var id_str: String = ""
	if "colonist_id" in colonist and not str(colonist.colonist_id).is_empty():
		id_str = str(colonist.colonist_id).left(6)

	if not id_str.is_empty():
		return "[Colonist:%s(%s)]" % [name_str, id_str]
	return "[Colonist:%s]" % name_str


static func _format_brain_eval_summary(
	winning_goal: StringName,
	scores: Dictionary,
	deficits: Dictionary,
	target: Variant,
	critical: bool,
	inertia: bool
) -> String:
	## Auxiliary: Builds single-line formatted summary of utility AI scores and decisions.
	var score_entries: Array[String] = []
	for g in scores:
		score_entries.append("%s:%.2f" % [g, float(scores[g])])
	var scores_str := "{" + ", ".join(score_entries) + "}"

	var deficit_entries: Array[String] = []
	for n in deficits:
		deficit_entries.append("%s:%.2f" % [n, float(deficits[n])])
	var deficits_str := "{" + ", ".join(deficit_entries) + "}"

	var target_str := "none"
	if target != null:
		if is_instance_valid(target) and target is Node:
			target_str = (target as Node).name
			if target is Node3D:
				var p: Vector3 = (target as Node3D).global_position
				target_str += "@(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z]
		else:
			target_str = str(target)

	var flags: Array[String] = []
	if critical:
		flags.append("CRITICAL_NEED")
	if inertia:
		flags.append("INERTIA_APPLIED")
	var flags_str := (" [%s]" % ", ".join(flags)) if not flags.is_empty() else ""

	return "Goal: '%s'%s | Scores: %s | Deficits: %s | Target: %s" % [
		winning_goal,
		flags_str,
		scores_str,
		deficits_str,
		target_str
	]
