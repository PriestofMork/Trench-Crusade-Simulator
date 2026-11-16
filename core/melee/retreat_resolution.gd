class_name RetreatResolution
extends Resolution
## A Retreat under way (RetreatBehaviour): the free attacks against the model
## before it moves. Lives on GameState.resolution; undo snapshots copy it.

var player: int = -1
var action_id: StringName = &""
## The enemies within 1" when the Retreat began (their zones are open for the
## retreat move), in id order.
var enemies: Array[int] = []
## The order the free attacks are made in (empty until it is known).
var order: Array[int] = []
## The next attack in `order`.
var next: int = 0


func copy() -> Resolution:
	var result: RetreatResolution = RetreatResolution.new()
	copy_into(result)
	result.player = player
	result.action_id = action_id
	result.enemies = enemies.duplicate()
	result.order = order.duplicate()
	result.next = next
	return result
