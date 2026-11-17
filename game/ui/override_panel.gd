class_name OverridePanel
extends PanelContainer
## Manual override for the selected model (toggled with O): markers, Down,
## a Down result (through the rules, with the ledge roll),
## and each warband's "all success rolls risky" flag. Builds override
## commands and hands them to `send`; it never changes the state itself.

## Called with an OverrideCommand to run.
var send: Callable = Callable()

var _title: RichTextLabel
var _model_box: VBoxContainer
var _counts: Dictionary[StringName, Label] = {}
var _down: Button
var _down_result: Button
var _risky: Array[Button] = []
var _model_id: int = -1
var _refreshing: bool = false


func _init() -> void:
	name = "OverridePanel"
	add_theme_stylebox_override("panel", UiStyle.panel(Color(0.6, 0.35, 0.8)))
	custom_minimum_size = Vector2(330, 0)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = UiStyle.rich(17)
	box.add_child(_title)
	_model_box = VBoxContainer.new()
	box.add_child(_model_box)
	for kind: StringName in Markers.KINDS:
		var row: HBoxContainer = HBoxContainer.new()
		var name_label: Label = UiStyle.label(Markers.label(kind), 15)
		name_label.custom_minimum_size = Vector2(110, 0)
		row.add_child(name_label)
		var minus: Button = UiStyle.button("−", "Less_%s" % kind)
		minus.custom_minimum_size = Vector2(38, 30)
		minus.pressed.connect(_change.bind(kind, -1))
		row.add_child(minus)
		var count: Label = UiStyle.label("0", 16)
		count.custom_minimum_size = Vector2(36, 0)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(count)
		_counts[kind] = count
		var plus: Button = UiStyle.button("+", "More_%s" % kind)
		plus.custom_minimum_size = Vector2(38, 30)
		plus.pressed.connect(_change.bind(kind, 1))
		row.add_child(plus)
		_model_box.add_child(row)
	_down = UiStyle.button("Down", "DownToggle")
	_down.toggle_mode = true
	_down.toggled.connect(_on_down)
	_model_box.add_child(_down)
	_down_result = UiStyle.button("Down result (ledge roll if near a ledge)", "DownResult")
	_down_result.tooltip_text = "Apply a Down result as a rule would: next to a ledge the model first makes the ledge roll"
	_down_result.pressed.connect(_on_down_result)
	_model_box.add_child(_down_result)
	box.add_child(HSeparator.new())
	for player: int in 2:
		var risky: Button = UiStyle.button("", "Risky%d" % player)
		risky.toggle_mode = true
		risky.add_theme_color_override("font_color", UiStyle.player_colour(player))
		risky.add_theme_color_override("font_pressed_color", UiStyle.player_colour(player))
		risky.toggled.connect(_on_risky.bind(player))
		box.add_child(risky)
		_risky.append(risky)
	visible = false


func refresh(state: GameState, model_id: int) -> void:
	_refreshing = true
	_model_id = model_id
	var model: ModelState = state.get_model(model_id)
	_title.text = "[b]Override[/b]  " + ("model %d" % model_id if model != null else "(select a model)")
	_model_box.visible = model != null
	if model != null:
		for kind: StringName in Markers.KINDS:
			_counts[kind].text = str(model.marker_count(kind))
		_down.button_pressed = model.down
		_down.text = "Down: yes" if model.down else "Down: no"
	for player: int in 2:
		var on: bool = state.warbands[player].has_flag(WarbandState.ALL_SUCCESS_ROLLS_RISKY)
		_risky[player].button_pressed = on
		_risky[player].text = "%s: all success rolls risky: %s" % [UiStyle.player_name(player), "on" if on else "off"]
	_refreshing = false


## Sets a marker count for the selected model (as the +/- buttons do). For scripted runs.
func set_markers(kind: StringName, count: int) -> void:
	if _model_id != -1 and send.is_valid():
		send.call(SetMarkersOverride.new(_model_id, kind, clampi(count, 0, Markers.CAP)))


## Ticks or clears Down for the selected model (as the checkbox does). For scripted runs.
func set_down(down: bool) -> void:
	_down.button_pressed = down


func _change(kind: StringName, delta: int) -> void:
	if _model_id == -1 or not send.is_valid():
		return
	var count: int = int(_counts[kind].text) + delta
	send.call(SetMarkersOverride.new(_model_id, kind, clampi(count, 0, Markers.CAP)))


func _on_down(pressed: bool) -> void:
	if _refreshing or _model_id == -1 or not send.is_valid():
		return
	send.call(SetDownOverride.new(_model_id, pressed))


func _on_down_result() -> void:
	if _model_id == -1 or not send.is_valid():
		return
	send.call(DownResultOverride.new(_model_id))


func _on_risky(pressed: bool, player: int) -> void:
	if _refreshing or not send.is_valid():
		return
	send.call(SetWarbandFlagOverride.new(player, WarbandState.ALL_SUCCESS_ROLLS_RISKY, pressed))
