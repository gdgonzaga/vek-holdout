extends JobDef
class_name DeployJobDef
## Direct tactical placement / stationing labor (ARCH "Subsystem: Colonists").
## The colonist travels to the target location and stays stationed there
## indefinitely until dismissed.


func meets_requirements(actor: Node, job: Variant) -> bool:
	if job != null and "target_colonist_id" in job and str(job.target_colonist_id) != "":
		var cid: String = actor.colonist_id if "colonist_id" in actor else ""
		if cid != str(job.target_colonist_id):
			return false
	return super.meets_requirements(actor, job)


func complete(_actor: Node, _job: Variant) -> void:
	# Persistent stationing: do not call _finish, so job remains on the board.
	pass


func is_available(_job: Variant) -> bool:
	return true


func should_close(_job: Variant) -> bool:
	return false


func work_site(_actor: Node, job: Variant) -> Variant:
	if job != null and "location" in job:
		return job.location
	return null
