class_name DieFace
extends Control
## One die drawn as a die: a rounded square with pips. Only displays a value
## it is given; it never rolls.

enum Look { TUMBLING, KEPT, DROPPED, PLAIN }

const PIPS: Dictionary[int, Array] = {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
	3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
	4: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	6: [Vector2(0.27, 0.25), Vector2(0.73, 0.25), Vector2(0.27, 0.5), Vector2(0.73, 0.5), Vector2(0.27, 0.75), Vector2(0.73, 0.75)],
}

var value: int = 1
var look: Look = Look.TUMBLING
## Turn of the face while tumbling, radians.
var tilt: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(52, 52)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_value(p_value: int, p_look: Look, p_tilt: float = 0.0) -> void:
	value = p_value
	look = p_look
	tilt = p_tilt
	queue_redraw()


func _draw() -> void:
	var side: float = minf(size.x, size.y) - 6.0
	var centre: Vector2 = size / 2.0
	draw_set_transform(centre, tilt, Vector2.ONE)
	var rect: Rect2 = Rect2(Vector2(-side, -side) / 2.0, Vector2(side, side))
	var face: Color = Color(0.96, 0.94, 0.88)
	var pip: Color = Color(0.12, 0.1, 0.1)
	var border: Color = Color(0.35, 0.33, 0.3)
	match look:
		Look.KEPT:
			border = UiStyle.GOLD_COLOUR
		Look.DROPPED:
			face = Color(0.42, 0.41, 0.4)
			pip = Color(0.25, 0.24, 0.24)
			border = Color(0.3, 0.3, 0.3)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = face
	box.border_color = border
	box.set_border_width_all(4 if look == Look.KEPT else 2)
	box.set_corner_radius_all(int(side * 0.18))
	draw_style_box(box, rect)
	for spot: Vector2 in PIPS[clampi(value, 1, 6)]:
		draw_circle(rect.position + spot * side, side * 0.085, pip)
	draw_set_transform(Vector2.ZERO)
