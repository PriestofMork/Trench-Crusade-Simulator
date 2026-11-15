class_name OverrideCommand
extends Command
## Base for manual overrides (docs/design.md, "Manual override"): direct
## changes made by hand so games stay playable before every rule is
## automated. Kept apart from rule commands: they check no turn order or
## pending decision, and report what they did in an OVERRIDE_APPLIED event.


func _override_event(model_id: int, text: String) -> Array[GameEvent]:
	return [GameEvent.new(GameEvent.Kind.OVERRIDE_APPLIED, -1, model_id, {"text": text})]
