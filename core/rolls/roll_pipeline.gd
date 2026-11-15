class_name RollPipeline
extends RefCounted
## Runs every roll the same way: collect the automatic modifiers from the
## registered providers, ask each registered pre-roll choice in turn (as
## pending decisions, so core never waits), roll through the resolver, run
## the registered reactions, then hand the result to the requester.
## Refers to no specific rule: everything specific is a registered provider.


static func start(state: GameState, request: RollRequest, events: Array[GameEvent]) -> void:
	var roll: ActiveRoll = ActiveRoll.new(request)
	for provider: RollModifierProvider in state.rules.modifier_providers:
		roll.modifiers.append_array(provider.modifiers(state, request))
	state.active_roll = roll
	var event: GameEvent = GameEvent.new(GameEvent.Kind.ROLL_REQUESTED, request.roller, request.actor_id)
	event.roll = roll
	events.append(event)
	_advance(state, events)


## Why `player` may not answer the current choice with `amount`, or "".
static func choice_error(state: GameState, player: int, amount: int) -> String:
	var error: String = PendingDecision.check(state, PendingDecision.Kind.ROLL_CHOICE, player)
	if error != "":
		return error
	var roll: ActiveRoll = state.active_roll
	var provider: RollChoiceProvider = state.rules.choice_providers[roll.next_choice]
	return provider.spend_error(state, roll.current_choice, amount)


## Answers the current choice and carries on to the next one or the dice.
static func answer_choice(state: GameState, amount: int, events: Array[GameEvent]) -> void:
	var roll: ActiveRoll = state.active_roll
	var provider: RollChoiceProvider = state.rules.choice_providers[roll.next_choice]
	var choice: RollChoice = roll.current_choice
	var added: Array[RollModifier] = provider.spend(state, roll.request, choice, amount)
	roll.modifiers.append_array(added)
	state.pending = null
	roll.current_choice = null
	roll.next_choice += 1
	var event: GameEvent = GameEvent.new(GameEvent.Kind.ROLL_CHOICE_MADE, choice.player, choice.model_id, {
		"amount": amount, "provider": choice.provider_id, "label": choice.label, "modifiers": added
	})
	event.roll = roll
	events.append(event)
	_advance(state, events)


static func _advance(state: GameState, events: Array[GameEvent]) -> void:
	var roll: ActiveRoll = state.active_roll
	var providers: Array[RollChoiceProvider] = state.rules.choice_providers
	while roll.next_choice < providers.size():
		var choice: RollChoice = providers[roll.next_choice].offer(state, roll.request)
		if choice != null:
			roll.current_choice = choice
			var decision: PendingDecision = PendingDecision.new(
				PendingDecision.Kind.ROLL_CHOICE, choice.player, choice.label
			)
			decision.model_id = choice.model_id
			decision.choice = choice
			TurnFlow.ask(state, decision, events)
			events[events.size() - 1].roll = roll
			return
		roll.next_choice += 1
	_resolve(state, events)


static func _resolve(state: GameState, events: Array[GameEvent]) -> void:
	var roll: ActiveRoll = state.active_roll
	state.active_roll = null
	var result: RollResult = RollResolver.resolve(roll.request, roll.modifiers, state.dice)
	var event: GameEvent = GameEvent.new(GameEvent.Kind.ROLL_RESOLVED, roll.request.roller, roll.request.actor_id)
	event.roll = roll
	event.result = result
	events.append(event)
	for reaction: RollReaction in state.rules.reactions:
		reaction.react(state, result, events)
	if roll.request.on_resolved.is_valid():
		roll.request.on_resolved.call(state, result, events)
