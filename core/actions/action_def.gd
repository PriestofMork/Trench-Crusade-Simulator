class_name ActionDef
extends RefCounted
## One action a model can take, as data (data/rules/core_rules.json,
## "actions"): an id, whether it is a move action, whether it is risky, and
## the behaviour that carries it out, and what being in melee does to it
## (ruling 9 of brief 007: a model in melee cannot Move, Dash or Charge; only
## a model in melee can Retreat). The activation code only reads these
## fields; new actions are new entries plus, if needed, a new behaviour.

enum Melee {
	## Melee makes no difference.
	ANY,
	## Not while the model is in melee.
	FORBIDDEN,
	## Only while the model is in melee.
	REQUIRED,
}

var id: StringName
var label: String
## Move actions (Move, Charge, Retreat): one per activation.
var move_action: bool = false
## Whether the action's roll is risky.
var risky: bool = false
var behaviour: ActionBehaviour
var melee: Melee = Melee.ANY


func _init(
	p_id: StringName, p_label: String, p_move_action: bool, p_risky: bool, p_behaviour: ActionBehaviour,
	p_melee: Melee = Melee.ANY
) -> void:
	melee = p_melee
	id = p_id
	label = p_label
	move_action = p_move_action
	risky = p_risky
	behaviour = p_behaviour
