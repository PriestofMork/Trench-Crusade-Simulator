class_name ActiveRoll
extends RefCounted
## A roll between its request and its result: the modifiers collected so far
## and how far the pre-roll choices have got. Lives on GameState.active_roll.

var request: RollRequest
## Automatic modifiers first, then those from answered choices, in order.
var modifiers: Array[RollModifier] = []
## Index into Ruleset.choice_providers of the next provider to ask.
var next_choice: int = 0
## The choice waiting for an answer, or null.
var current_choice: RollChoice = null


func _init(p_request: RollRequest) -> void:
	request = p_request
