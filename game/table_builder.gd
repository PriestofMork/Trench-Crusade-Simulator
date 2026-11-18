class_name TableBuilder
extends RefCounted
## Builds the scene's nodes for main.gd: the table top, terrain and model
## views from the state, and the overlays and UI the session draws on.

const TABLE_THICKNESS: float = 1.0
const TRAY_WIDTH: float = 420.0


static func build_table(root: Node3D, state: GameState) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(state.table_width, TABLE_THICKNESS, state.table_depth)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.31, 0.24)
	var table: MeshInstance3D = MeshInstance3D.new()
	table.name = "TableTop"
	table.mesh = box
	table.material_override = material
	# Top face at y = 0; the table spans x in [0, width] and z in [0, depth].
	table.position = Vector3(state.table_width / 2.0, -TABLE_THICKNESS / 2.0, state.table_depth / 2.0)
	root.add_child(table)


## The terrain views under `table_root`, and one view per model under
## `models_root`, into `views` by id.
static func build_views(table_root: Node3D, models_root: Node3D, state: GameState, views: Dictionary[int, ModelView]) -> void:
	for piece: TerrainPiece in state.terrain:
		var terrain: TerrainView = TerrainView.new()
		terrain.setup(piece)
		table_root.add_child(terrain)
	for model: ModelState in state.models:
		var view: ModelView = ModelView.new()
		view.state = state
		view.setup(model)
		models_root.add_child(view)
		views[model.id] = view


## The 3D overlays under `parent` and the UI layer ("Ui"), into the session.
## Returns the layer.
static func build_overlays(parent: Node3D, session: Session) -> CanvasLayer:
	session.indicator = MovementIndicator.new()
	parent.add_child(session.indicator)
	session.preview = PathPreview.new()
	parent.add_child(session.preview)
	session.melee_view = MeleeView.new()
	parent.add_child(session.melee_view)
	session.sight_view = SightView.new()
	parent.add_child(session.sight_view)

	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Ui"
	parent.add_child(layer)
	var label: Label = Label.new()
	label.name = "DistanceLabel"
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.12))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	layer.add_child(label)
	session.distance_label = label
	session.hud = Hud.new()
	layer.add_child(session.hud)
	session.tray = DiceTray.new()
	session.tray.custom_minimum_size = Vector2(TRAY_WIDTH, 0)
	layer.add_child(session.tray)
	session.prompt = ConfirmPrompt.new()
	layer.add_child(session.prompt)
	return layer
