class_name MeleeView
extends Node3D
## What brief 007 adds to the table: links between models in melee, the
## faint 1" zones of the enemies of a model selected for movement, the
## labels of charge mode ("certain", "needs 3+", "cannot reach", or the
## model actually charged), and the arc of contact positions a charger may
## end on. Only displays what it is given; it never changes the state.

const LINK_COLOUR: Color = Color(1.0, 0.42, 0.18, 0.95)
const ZONE_COLOUR: Color = Color(1.0, 0.45, 0.35, 0.28)
const ARC_COLOUR: Color = Color(1.0, 0.85, 0.4, 0.9)
const ARC_HOVER_COLOUR: Color = Color(1.0, 1.0, 0.75, 1.0)
const LABEL_COLOURS: Dictionary[String, Color] = {
	"certain": Color(0.55, 0.95, 0.55),
	"roll": Color(1.0, 0.85, 0.4),
	"out": Color(0.7, 0.7, 0.72),
}
const LINK_WIDTH: float = 0.14
const ZONE_WIDTH: float = 0.05
const ARC_WIDTH: float = 0.12
const LIFT: float = 0.045
const SEGMENTS: int = 64

var _links: MeshInstance3D
var _zones: MeshInstance3D
var _arc: MeshInstance3D
var _arc_hover: MeshInstance3D
var _labels: Dictionary[int, Label3D] = {}
var _arc_points: Array[Vector3] = []


func _init() -> void:
	name = "MeleeView"
	_links = _child("MeleeLinks", _material(LINK_COLOUR, 5))
	_zones = _child("EnemyZones", _material(ZONE_COLOUR, 1))
	_arc = _child("ContactArc", _material(ARC_COLOUR, 6))
	_arc_hover = _child("ContactHover", _material(ARC_HOVER_COLOUR, 7))


## A strip between the bases of each pair in melee.
func show_links(state: GameState) -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	for pair: Vector2i in MeleeZone.melee_pairs(state):
		var a: ModelState = state.get_model(pair.x)
		var b: ModelState = state.get_model(pair.y)
		var flat: Vector3 = Vector3(b.position.x - a.position.x, 0.0, b.position.z - a.position.z)
		if flat.length() < 0.001:
			continue
		var direction: Vector3 = flat.normalized()
		var from: Vector3 = a.position + direction * a.base_radius_inches() * 0.5
		var to: Vector3 = b.position - direction * b.base_radius_inches() * 0.5
		var side: Vector3 = Vector3(-direction.z, 0.0, direction.x) * LINK_WIDTH * 0.5
		var lift: Vector3 = Vector3(0.0, LIFT + 0.01, 0.0)
		from += lift
		to += lift
		vertices.append_array([from - side, to - side, to + side, from - side, to + side, from + side])
		# A diamond on each base, so a link reads even end-on.
		for end: ModelState in [a, b]:
			_add_ring(vertices, end.position + lift, end.base_radius_inches() + 0.22, 0.1)
	_set_mesh(_links, vertices)


## The 1" zone around each enemy of `model` (outlines at 1" from their
## bases), or nothing for a null model.
func show_zones(state: GameState, model: ModelState) -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	if model != null:
		for other: ModelState in state.models:
			if other.player == model.player or not other.on_table():
				continue
			var at: Vector3 = other.position + Vector3(0.0, LIFT, 0.0)
			_add_ring(vertices, at, other.base_radius_inches() + MeleeZone.DISTANCE, ZONE_WIDTH)
	_set_mesh(_zones, vertices)


## Charge mode: a label over each enemy in range with what charging it
## takes. `plans` maps a declared target's id to its plan.
func show_charge_labels(state: GameState, plans: Dictionary[int, ChargePlan]) -> void:
	clear_charge_labels()
	for id: int in plans:
		var plan: ChargePlan = plans[id]
		var model: ModelState = state.get_model(id)
		var label: Label3D = Label3D.new()
		label.name = "ChargeLabel%d" % id
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0012
		label.font_size = 24
		label.outline_size = 10
		label.text = charge_text(plan)
		var colour: Color = LABEL_COLOURS["out"]
		if plan.reachable():
			colour = LABEL_COLOURS["certain"] if plan.is_certain() else LABEL_COLOURS["roll"]
		label.modulate = colour
		label.position = model.position + Vector3(0.0, model.height_inches() + 1.15, 0.0)
		add_child(label)
		_labels[id] = label


## What a charge label says.
static func charge_text(plan: ChargePlan) -> String:
	if plan.interposed() and plan.reachable():
		return "%s → %d" % [plan.label(), plan.target_id]
	return plan.label()


func clear_charge_labels() -> void:
	for label: Label3D in _labels.values():
		label.queue_free()
	_labels.clear()


## The places a charger may end around its target's base, as an arc of
## dots (base centres).
func show_contact_arc(points: Array[Vector3]) -> void:
	_arc_points = points
	var vertices: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in points:
		_add_disc(vertices, point + Vector3(0.0, LIFT + 0.02, 0.0), 0.1)
	_set_mesh(_arc, vertices)
	_set_mesh(_arc_hover, PackedVector3Array())


## Marks the base the charger would have at `point`, or nothing for null.
func show_contact_hover(point: Variant, base_radius: float) -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	if point != null:
		var at: Vector3 = point
		_add_ring(vertices, at + Vector3(0.0, LIFT + 0.03, 0.0), base_radius, ARC_WIDTH)
		_add_disc(vertices, at + Vector3(0.0, LIFT + 0.03, 0.0), 0.12)
	_set_mesh(_arc_hover, vertices)


func clear_contact_arc() -> void:
	_arc_points = []
	_set_mesh(_arc, PackedVector3Array())
	_set_mesh(_arc_hover, PackedVector3Array())


static func _add_ring(vertices: PackedVector3Array, centre: Vector3, radius: float, width: float) -> void:
	var inner: float = radius - width * 0.5
	var outer: float = radius + width * 0.5
	for k: int in SEGMENTS:
		var d0: Vector3 = Vector3(cos(TAU * k / SEGMENTS), 0, sin(TAU * k / SEGMENTS))
		var d1: Vector3 = Vector3(cos(TAU * (k + 1) / SEGMENTS), 0, sin(TAU * (k + 1) / SEGMENTS))
		vertices.append_array([
			centre + d0 * inner, centre + d1 * inner, centre + d1 * outer,
			centre + d0 * inner, centre + d1 * outer, centre + d0 * outer,
		])


static func _add_disc(vertices: PackedVector3Array, centre: Vector3, radius: float) -> void:
	for k: int in 16:
		var a0: float = TAU * k / 16
		var a1: float = TAU * (k + 1) / 16
		vertices.append_array([centre, centre + Vector3(cos(a0), 0, sin(a0)) * radius, centre + Vector3(cos(a1), 0, sin(a1)) * radius])


static func _set_mesh(instance: MeshInstance3D, vertices: PackedVector3Array) -> void:
	if vertices.is_empty():
		instance.mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.mesh = mesh


func _child(child_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var child: MeshInstance3D = MeshInstance3D.new()
	child.name = child_name
	child.material_override = material
	child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(child)
	return child


static func _material(colour: Color, priority: int) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	material.no_depth_test = priority >= 5
	return material
