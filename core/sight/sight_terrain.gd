class_name SightTerrain
extends RefCounted
## The terrain as line of sight sees it: one convex solid per piece that
## blocks sight (rulings 4 and 5 of brief 008). Built once per terrain set
## (GameState.sight_terrain()); only read afterwards.

var solids: Array[SightGeometry.Solid] = []


func _init(pieces: Array[TerrainPiece]) -> void:
	for piece: TerrainPiece in pieces:
		if piece.blocks_sight:
			solids.append(SightGeometry.piece_solid(piece))
