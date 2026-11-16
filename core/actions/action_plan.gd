class_name ActionPlan
extends RefCounted
## What an action with a target works out for that target before it is taken
## (a charge's path and the roll it needs): built by the behaviour when the
## command is validated, and handed to begin() when it is applied.

var target_id: int = -1
## "" if the action may be taken against the target, else why not.
var error: String = ""
