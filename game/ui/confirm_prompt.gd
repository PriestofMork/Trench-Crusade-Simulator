class_name ConfirmPrompt
extends PanelContainer
## The one confirmation panel, at the bottom of the screen: a question with
## Confirm (Enter) and Cancel (Esc). Each mode asks with its own kind
## (&"move", &"charge", &"retreat", ...) and its own answers.

## What the panel asks about; &"" when it is closed.
var kind: StringName = &""
var _label: RichTextLabel
var _on_confirm: Callable
var _on_cancel: Callable


func _init() -> void:
	name = "ConfirmMove"
	add_theme_stylebox_override("panel", UiStyle.panel(Color(1.0, 0.55, 0.15)))
	var confirm_box: VBoxContainer = VBoxContainer.new()
	add_child(confirm_box)
	_label = UiStyle.rich(17)
	_label.custom_minimum_size = Vector2(460, 0)
	confirm_box.add_child(_label)
	var confirm_row: HBoxContainer = HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 8)
	confirm_box.add_child(confirm_row)
	var confirm_button: Button = UiStyle.button("Confirm (Enter)", "ConfirmMoveButton")
	confirm_button.pressed.connect(func() -> void: confirm())
	confirm_row.add_child(confirm_button)
	var cancel_button: Button = UiStyle.button("Cancel (Esc)", "CancelMoveButton")
	cancel_button.pressed.connect(func() -> void: cancel())
	confirm_row.add_child(cancel_button)
	visible = false


func _process(_delta: float) -> void:
	var view: Vector2 = get_viewport_rect().size
	size = Vector2(0.0, 0.0)
	position = Vector2((view.x - size.x) / 2.0, view.y - size.y - 24.0)


## Opens the panel. `on_confirm` returns "" or why it could not be done.
func ask(p_kind: StringName, text: String, on_confirm: Callable, on_cancel: Callable) -> void:
	kind = p_kind
	_label.text = text
	_on_confirm = on_confirm
	_on_cancel = on_cancel
	visible = true


func close() -> void:
	kind = &""
	visible = false


func is_open() -> bool:
	return kind != &""


## The question, or "" when the panel is closed (for scripted checks).
func text() -> String:
	return _label.get_parsed_text() if is_open() else ""


## Does what the panel asks about (Confirm or Enter).
func confirm() -> String:
	if not is_open():
		return "Nothing to confirm."
	return _on_confirm.call()


## Closes the panel without doing it (Cancel or Escape).
func cancel() -> void:
	if is_open():
		_on_cancel.call()
