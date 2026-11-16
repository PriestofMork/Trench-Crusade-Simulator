extends GutTest
## The dice tray's marker prompt as laid out on screen (the play-test bug: a
## prompt with blood and infection both on offer was squashed into one
## letter per line), and the counts it answers with.

var tray: DiceTray
var answers: Array = []


func before_each() -> void:
	tray = DiceTray.new()
	tray.custom_minimum_size = Vector2(420, 0)
	add_child_autofree(tray)
	answers.clear()
	tray.choice_answered.connect(func(amounts: Array[int]) -> void: answers.append(amounts))


func _decision(options: Array[RollChoice.Option]) -> PendingDecision:
	var decision: PendingDecision = PendingDecision.new(PendingDecision.Kind.ROLL_CHOICE, 0, "")
	decision.choice = RollChoice.new(&"blood", 0, 3, "Spend blood and infection markers of model 3 (+1 die each)", options)
	return decision


func _both() -> Array[RollChoice.Option]:
	return [
		RollChoice.Option.new(Markers.BLOOD, "Blood", 2, 1), RollChoice.Option.new(Markers.INFECTION, "Infection", 6, 1),
	] as Array[RollChoice.Option]


func test_two_options_lay_out_as_two_short_rows() -> void:
	tray.ask_choice(_decision(_both()))
	await wait_frames(3)
	for i: int in 2:
		var row: Control = tray.find_child("Row%d" % i, true, false)
		assert_not_null(row)
		assert_lt(row.size.y, 50.0, "row %d is one line high" % i)
		var label: Label = row.get_child(0)
		assert_gt(label.size.x, 60.0, "the option name has room")
		assert_eq(label.get_line_count(), 1)
	var button: Button = tray.prompt_button("Pick1_6")
	assert_lt(button.size.y, 50.0)
	assert_lt(tray.size.y, 500.0, "the tray stays a normal size")


func test_picking_counts_and_spending_answers_one_count_each() -> void:
	tray.ask_choice(_decision(_both()))
	await wait_frames(2)
	# As a click does: toggling the button on.
	tray.prompt_button("Pick0_2").button_pressed = true
	tray.prompt_button("Pick1_3").button_pressed = true
	tray.prompt_button("Pick1_1").button_pressed = true
	tray.prompt_button("SpendPicked").pressed.emit()
	assert_eq(answers.size(), 1)
	assert_eq(answers[0], [2, 1] as Array[int])


func test_nothing_picked_spends_nothing() -> void:
	tray.ask_choice(_decision(_both()))
	await wait_frames(2)
	tray.prompt_button("SpendPicked").pressed.emit()
	assert_eq(answers[0], [0, 0] as Array[int])


func test_one_option_answers_with_one_click() -> void:
	var options: Array[RollChoice.Option] = [RollChoice.Option.new(Markers.INFECTION, "Infection", 2, 1)]
	tray.ask_choice(_decision(options))
	await wait_frames(2)
	assert_null(tray.prompt_button("SpendPicked"))
	tray.prompt_button("Spend2").pressed.emit()
	assert_eq(answers[0], [2] as Array[int])
