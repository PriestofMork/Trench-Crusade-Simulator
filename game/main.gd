extends Node3D
## Main scene: builds a GameState, places the starting models through commands
## and creates the views from the state.

const TABLE_THICKNESS: float = 1.0
const BASE_MM_CHOICES: Array[int] = [25, 32, 40]

## Placeholder terrain boxes: centre (x, z) and size, inches. Visual only for now;
## terrain volumes move into core when terrain collision is implemented.
const TERRAIN_BOXES: Array[Dictionary] = [
	{"center": Vector2(14, 16), "size": Vector3(6, 3, 4)},
	{"center": Vector2(34, 32), "size": Vector3(4, 5, 8)},
	{"center": Vector2(24, 24), "size": Vector3(8, 2, 3)},
	{"center": Vector2(36, 12), "size": Vector3(3, 4, 3)},
]

var state: GameState

@onready var _camera: TableCamera = $TableCamera
@onready var _table_root: Node3D = $Table
@onready var _models_root: Node3D = $Models


func _ready() -> void:
	state = GameState.new(1)
	_build_table()
	_build_terrain()
	_place_starting_models()
	_build_model_views()
	_camera.set_table_bounds(state.table_width, state.table_depth)


func _build_table() -> void:
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
	_table_root.add_child(table)


func _build_terrain() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.48)
	for i: int in TERRAIN_BOXES.size():
		var entry: Dictionary = TERRAIN_BOXES[i]
		var center: Vector2 = entry["center"]
		var size: Vector3 = entry["size"]
		var box: BoxMesh = BoxMesh.new()
		box.size = size
		var terrain: MeshInstance3D = MeshInstance3D.new()
		terrain.name = "Terrain%d" % i
		terrain.mesh = box
		terrain.material_override = material
		terrain.position = Vector3(center.x, size.y / 2.0, center.y)
		_table_root.add_child(terrain)


func _place_starting_models() -> void:
	for player: int in 2:
		var z: float = 4.0 if player == 0 else state.table_depth - 4.0
		for i: int in 3:
			var pos: Vector3 = Vector3(18.0 + i * 6.0, 0.0, z)
			var error: String = state.execute(PlaceModelCommand.new(player, pos, BASE_MM_CHOICES[i]))
			if error != "":
				push_error("Starting placement rejected: %s" % error)


func _build_model_views() -> void:
	for model: ModelState in state.models:
		var view: ModelView = ModelView.new()
		view.setup(model)
		_models_root.add_child(view)
