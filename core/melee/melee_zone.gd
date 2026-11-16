class_name MeleeZone
extends RefCounted
## The 1" zone around a model and who is in melee (docs/rules/movement.md,
## "Melee and Retreat"; ruling 9 of brief 007): a model within 1" of an enemy
## model, edge to edge and measured in 3D between the two cylinders, is in
## melee with it. Down models count. Exactly 1" apart is not within 1" (the
## same edge MoveLegality uses for moves).

## A model may only come within this distance of an enemy by charging.
const DISTANCE: float = MoveLegality.ENEMY_DISTANCE_INCHES
const EPSILON: float = 0.0001


## The shortest distance between two vertical cylinders standing at `a` and
## `b` (centres of the base undersides) with these radii and heights; 0 if
## they touch or overlap.
static func cylinder_gap(a: Vector3, a_radius: float, a_height: float, b: Vector3, b_radius: float, b_height: float) -> float:
	var horizontal: float = Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) - a_radius - b_radius
	var vertical: float = maxf(maxf(b.y - (a.y + a_height), a.y - (b.y + b_height)), 0.0)
	if horizontal <= 0.0:
		return vertical
	if vertical <= 0.0:
		return horizontal
	return sqrt(horizontal * horizontal + vertical * vertical)


## The distance between two models' cylinders; `at` puts `a` somewhere else.
static func gap(a: ModelState, b: ModelState, at: Variant = null) -> float:
	var position: Vector3 = at if at != null else a.position
	return cylinder_gap(position, a.base_radius_inches(), a.height_inches(), b.position, b.base_radius_inches(), b.height_inches())


## Whether two cylinders `gap` apart are within 1" of each other.
static func is_within(p_gap: float) -> bool:
	return p_gap < DISTANCE - EPSILON


## The enemy models on the table within 1" of `model` (at `at`, if given,
## instead of where it is), in id order.
static func enemies_within(state: GameState, model: ModelState, at: Variant = null) -> Array[ModelState]:
	var result: Array[ModelState] = []
	for other: ModelState in state.models:
		if other.player == model.player or not other.on_table() or not model.on_table():
			continue
		if is_within(gap(model, other, at)):
			result.append(other)
	return result


## Their ids.
static func enemy_ids_within(state: GameState, model: ModelState, at: Variant = null) -> Array[int]:
	var ids: Array[int] = []
	for other: ModelState in enemies_within(state, model, at):
		ids.append(other.id)
	return ids


static func in_melee(state: GameState, model: ModelState) -> bool:
	return not enemies_within(state, model).is_empty()


## Pairs of models in melee with each other, as [lower id, higher id].
static func melee_pairs(state: GameState) -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	for model: ModelState in state.models:
		if model.player != 0:
			continue
		for other: ModelState in enemies_within(state, model):
			pairs.append(Vector2i(mini(model.id, other.id), maxi(model.id, other.id)))
	return pairs
