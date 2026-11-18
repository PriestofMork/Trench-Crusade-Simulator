extends GutTest
## Charge mode in the game (brief 008c, ruling 2): opening it searches no
## route, hovering an enemy never searches, clicking a target works out its
## route once (on a worker), and clicking it again costs nothing.
## Model ids as in data/tables/height_test_table.json: 15 the charger, 16
## its clear target.

var main: Node3D


func before_each() -> void:
	main = load("res://game/main.tscn").instantiate()
	add_child_autoqfree(main)
	await wait_frames(3)
	TurnHelper.settle(main.state)


func _searches() -> int:
	return main.state.charge_routes().searches


func _wait_ready() -> void:
	for i: int in 600:
		if main.is_charge_ready():
			return
		await wait_frames(1)


func test_hovering_never_searches_and_a_second_click_costs_nothing() -> void:
	main.select_model(15)
	await wait_frames(2)
	var fields: int = ReachField.built
	assert_eq(main.enter_charge_mode(), "")
	assert_eq(main.charge_declarations().get(16, "missing"), "", "16 can be declared")
	assert_eq(main.charge_label_text(16), "can charge")
	assert_eq(_searches(), 0, "opening charge mode searched nothing")
	main._hover_override = main.state.get_model(16).position
	await wait_frames(5)
	assert_eq(main.charge_hover(), 16, "16 is highlighted")
	assert_eq(_searches(), 0, "hovering searched nothing")
	assert_eq(ReachField.built, fields, "no reach field was built")
	main._hover_override = null
	assert_eq(main.request_charge(16), "")
	if not main.is_charge_ready():
		assert_eq(main.charge_label_text(16), "…", "the label waits for the route")
	await _wait_ready()
	assert_not_null(main.charge_plan())
	assert_eq(main.charge_label_text(16), "certain")
	assert_ne(main.confirm_text(), "", "Confirm or Cancel")
	var after_first: int = _searches()
	assert_eq(after_first, 1, "one search for the clicked target")
	main.cancel_confirm()
	assert_eq(main.request_charge(16), "")
	assert_true(main.is_charge_ready(), "no worker needed")
	assert_not_null(main.charge_plan(), "shown at once")
	assert_eq(_searches(), after_first, "the second click searched nothing")
	main.toggle_charge_rolls()
	await _wait_ready()
	assert_eq(_searches(), after_first + 1, "the other route choice, once")
	main.toggle_charge_rolls()
	assert_true(main.is_charge_ready())
	assert_eq(_searches(), after_first + 1, "back to the first choice: cached")
