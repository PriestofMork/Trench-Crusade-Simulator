class_name InteractionMode
extends RefCounted
## One interaction mode (move, charge, retreat, a contact choice; later shoot
## and fight): what hovering, a click and a key mean while it is active.
## main.gd keeps exactly one mode active and routes input to it; a mode that
## does not handle hover or a click leaves it to the default mode (Move).
## Modes share everything through the Session, never through each other.

var session: Session
## Set by main.gd while this mode is the active one.
var active: bool = false


func _init(p_session: Session) -> void:
	session = p_session


## Why the mode cannot be opened now ("" if it can). Checked before the
## active mode is left.
func enter_error() -> String:
	return ""


func enter() -> void:
	pass


func exit() -> void:
	pass


## Every frame while a model is selected and nothing plays back. Returns
## whether the mode handled it.
func hover() -> bool:
	return false


## A left click on the table. Returns whether the mode handled it.
func click(_screen_position: Vector2) -> bool:
	return false


## A key press (after undo, redo and the confirmation panel's keys). Returns
## whether the mode handled it.
func key(_event: InputEventKey) -> bool:
	return false


## Brings the mode's views in line with the state (after events play back).
func refresh() -> void:
	pass


## The selected model's descent mode was switched (C).
func descent_changed() -> void:
	pass


## Whether the selected model's enemy zones are drawn.
func shows_zones() -> bool:
	return false


## Whether the sight overview and hover labels are drawn.
func shows_sight() -> bool:
	return true
