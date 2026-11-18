extends GutTest
## Brief 008d: the seams between main.gd, the shared session parts and the
## mode controllers.


## A mode that records what main.gd calls on it.
class RecordingMode:
	extends InteractionMode
	var calls: Array[String] = []

	func enter() -> void:
		calls.append("enter")

	func exit() -> void:
		calls.append("exit")


var main: Node3D
var _wanted: String = ""
var _done: Array[Variant] = []


func before_each() -> void:
	main = load("res://game/main.tscn").instantiate()
	add_child_autoqfree(main)
	_done.clear()


func test_switching_modes_calls_exit_and_enter() -> void:
	var session: Session = main.session()
	var first: RecordingMode = RecordingMode.new(session)
	var second: RecordingMode = RecordingMode.new(session)
	assert_true(main.move.active, "Move is the default")
	assert_eq(main.enter_mode(first), "")
	assert_eq(first.calls, ["enter"] as Array[String])
	assert_true(first.active and not main.move.active, "the new mode is the active one")
	assert_eq(main.enter_mode(second), "")
	assert_eq(first.calls, ["enter", "exit"] as Array[String], "the old mode is left")
	assert_eq(second.calls, ["enter"] as Array[String])
	assert_false(first.active)
	main.deselect()
	assert_eq(second.calls, ["enter", "exit"] as Array[String], "deselecting leaves the mode")
	assert_true(main.move.active, "back to Move")


func test_a_mode_that_cannot_open_leaves_the_active_one_alone() -> void:
	assert_ne(main.enter_mode(main.charge), "", "no model selected: no charge mode")
	assert_true(main.move.active)
	assert_false(main.charge.active)


func test_a_state_change_clears_every_cache() -> void:
	var session: Session = main.session()
	var state: GameState = main.state
	main.sight.sight(1, 7)
	session.caches.store(MoveMode.CACHE, "a reach key", [])
	assert_eq(session.caches.count(SightOverlay.CACHE), 1)
	assert_eq(session.caches.count(), 2)
	assert_not_null(state.pending, "the first player is to be chosen")
	assert_eq(session.send(ChooseFirstPlayerCommand.new(state.pending.player, 0)), "")
	assert_eq(session.caches.count(), 0, "a command clears them all")
	main.sight.sight(1, 7)
	assert_eq(session.caches.count(), 1)
	assert_eq(session.sender.undo(), "")
	assert_eq(session.caches.count(), 0, "so does undo")


func test_a_stale_job_is_discarded() -> void:
	var jobs: BackgroundJobs = BackgroundJobs.new()
	_wanted = "a"
	jobs.start(&"slot", "a", func() -> int: return 7, _on_done, func() -> String: return _wanted)
	_wanted = "b"
	await _collect(jobs)
	assert_eq(_done.size(), 0, "a result for a key no longer wanted is dropped")
	assert_eq(jobs.discarded, 1)


func test_a_current_job_is_collected() -> void:
	var jobs: BackgroundJobs = BackgroundJobs.new()
	_wanted = "a"
	jobs.start(&"slot", "a", func() -> int: return 7, _on_done, func() -> String: return _wanted)
	await _collect(jobs)
	assert_eq(_done, [7] as Array[Variant], "done is called with the result")
	assert_eq(jobs.discarded, 0)


func test_waiting_for_a_job_drops_it() -> void:
	var jobs: BackgroundJobs = BackgroundJobs.new()
	jobs.start(&"slot", "a", func() -> int: return 7, _on_done)
	assert_true(jobs.is_running(&"slot"))
	jobs.wait(&"slot")
	assert_false(jobs.is_running(&"slot"))
	jobs.poll()
	assert_eq(_done.size(), 0, "a job waited for is not collected")


func _on_done(job: BackgroundJobs.Job) -> void:
	_done.append(job.result)


func _collect(jobs: BackgroundJobs) -> void:
	for i: int in 300:
		jobs.poll()
		if not jobs.is_running(&"slot"):
			return
		await get_tree().process_frame
