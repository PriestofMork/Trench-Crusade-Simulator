class_name Session
extends RefCounted
## What every interaction mode shares: the state, the command sender, the
## selection, background jobs, state-keyed caches, the confirmation prompt,
## sight, and the views and UI they draw on. main.gd builds it and fills in
## the few things only it can do (refresh every view, change the selection,
## leave the active mode).

var state: GameState
var sender: CommandSender
var selection: Selection
var jobs: BackgroundJobs = BackgroundJobs.new()
var caches: StateCaches = StateCaches.new()
var sight: SightOverlay
var prompt: ConfirmPrompt
var hud: Hud
var tray: DiceTray
var camera: TableCamera
var views: Dictionary[int, ModelView] = {}
var indicator: MovementIndicator
var preview: PathPreview
var melee_view: MeleeView
var sight_view: SightView
## The label by the cursor (distance, what a charge needs, sight).
var distance_label: Label

var _refresh: Callable
var _select: Callable
var _deselect: Callable
var _leave_mode: Callable


## main.gd's refresh_all(), select_model(id), deselect() and the way back
## to the default mode (which then refreshes).
func set_host(refresh: Callable, select: Callable, unselect: Callable, leave_mode: Callable) -> void:
	_refresh = refresh
	_select = select
	_deselect = unselect
	_leave_mode = leave_mode


## Brings every view in line with the state (skipped while events play).
func refresh_all() -> void:
	_refresh.call()


func select_model(id: int) -> void:
	_select.call(id)


func deselect() -> void:
	_deselect.call()


## Leaves the active mode for the default one, and refreshes.
func leave_mode() -> void:
	_leave_mode.call()


func send(command: Command) -> String:
	return sender.send(command)


func is_busy() -> bool:
	return sender.is_busy()


func message(text: String) -> void:
	hud.show_message(text)


## `text` in the colour of errors, for the HUD.
static func bad(text: String) -> String:
	return "[color=#%s]%s[/color]" % [UiStyle.BAD_COLOUR.to_html(false), text]


## Why the selected model may not take `action_id` now, or "".
func action_error(action_id: StringName) -> String:
	var model: ModelState = selection.model()
	if model == null:
		return "No model selected."
	var error: String = TurnFlow.activation_error(state, model.player, model)
	if error == "":
		error = BeginActionCommand.unavailable_reason(state, model, action_id)
	return error


## Breaks the references between the shared parts (they point at each other).
func dispose() -> void:
	jobs.wait_all()
	sender = null
	sight = null
	_refresh = Callable()
	_select = Callable()
	_deselect = Callable()
	_leave_mode = Callable()
