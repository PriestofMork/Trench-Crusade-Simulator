class_name ModelView
extends MeshInstance3D
## Draws one model as its rules cylinder: base diameter by height, coloured by owner.

const PLAYER_COLOURS: Array[Color] = [
	Color(0.75, 0.18, 0.15),  # player 0: red
	Color(0.18, 0.35, 0.75),  # player 1: blue
]

var model_id: int = -1


func setup(model: ModelState) -> void:
	model_id = model.id
	name = "Model%d" % model.id
	var height: float = model.height_inches()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = model.base_radius_inches()
	cylinder.bottom_radius = model.base_radius_inches()
	cylinder.height = height
	mesh = cylinder
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = PLAYER_COLOURS[model.player]
	material_override = material
	# CylinderMesh is centred on its origin; the model position is the base underside.
	position = model.position + Vector3(0.0, height / 2.0, 0.0)
