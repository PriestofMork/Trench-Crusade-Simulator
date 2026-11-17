class_name Interrupt
extends Resolution
## Something that must be resolved in the middle of something else before it
## goes on, such as the ledge roll of a Down result (LedgeRoll). Interrupts
## live on GameState.interrupts, newest last, beside whatever resolution is
## under way, and undo snapshots copy them.
##
## An interrupt started by a roll reaction holds that roll (`held`): the roll
## pipeline does not hand the result to its requester until the interrupt is
## over (RollPipeline). One started elsewhere calls `done(state, events)` when
## it is over. Both are kept as data (the result is never changed once made,
## `done` is a static function), so undo, redo and replay restore them.

## The roll whose requester is waiting for this to be over, or null.
var held: RollResult = null
## Called as done(state, events) when this is over, if no roll is held.
var done: Callable = Callable()


func copy() -> Resolution:
	var result: Interrupt = Interrupt.new()
	copy_into(result)
	return result


func copy_into(target: Resolution) -> void:
	super(target)
	var interrupt: Interrupt = target as Interrupt
	interrupt.held = held
	interrupt.done = done


## Starts it (once it is on GameState.interrupts). Subclasses override.
func begin(state: GameState, events: Array[GameEvent]) -> void:
	finish(state, events)


## The newest interrupt is over: takes it off and lets what waited for it go on.
static func finish(state: GameState, events: Array[GameEvent]) -> void:
	var interrupt: Interrupt = state.interrupts.pop_back()
	if interrupt.held != null:
		var request: RollRequest = interrupt.held.request
		if request.on_resolved.is_valid():
			request.on_resolved.call(state, interrupt.held, events)
	elif interrupt.done.is_valid():
		interrupt.done.call(state, events)


## Starts `interrupt` now, or, while roll reactions are running, once they
## are done (the roll pipeline then makes it hold that roll).
static func push(state: GameState, interrupt: Interrupt, events: Array[GameEvent]) -> void:
	state.interrupts.append(interrupt)
	if state.reactions_running == 0:
		interrupt.begin(state, events)
