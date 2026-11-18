class_name BackgroundJobs
extends RefCounted
## Worker-thread work for game/ (the reach field, a charge route), in one
## place. Each job sits in a named slot (one job per slot at a time) and has a
## key saying what it works out. poll(), on the main thread, collects finished
## jobs: `done` is called with the job, unless `wanted` (if given) now returns
## another key, in which case the result is stale and dropped.
##
## Work on a worker only reads the state; sending a command, undo and redo
## wait for every job first (wait_all()), so the state never changes under one.


class Job:
	extends RefCounted
	var key: String = ""
	## Runs on the worker; what it returns is `result`.
	var work: Callable
	## Main thread, with this job, once it is collected.
	var done: Callable
	## Optional: () -> String, the key wanted now.
	var wanted: Callable
	var result: Variant = null
	var started_usec: int = 0
	var task: int = -1

	## Milliseconds since the job started.
	func ms() -> float:
		return (Time.get_ticks_usec() - started_usec) / 1000.0


var _jobs: Dictionary[StringName, Job] = {}
var _mutex: Mutex = Mutex.new()
## How many finished jobs were dropped as stale (for checks).
var discarded: int = 0


## Starts `work` on a worker in `slot`. A job already in the slot is waited
## for first and dropped.
func start(slot: StringName, key: String, work: Callable, done: Callable, wanted: Callable = Callable()) -> void:
	wait(slot)
	var job: Job = Job.new()
	job.key = key
	job.work = work
	job.done = done
	job.wanted = wanted
	job.started_usec = Time.get_ticks_usec()
	_jobs[slot] = job
	job.task = WorkerThreadPool.add_task(_run.bind(job))


func _run(job: Job) -> void:
	var result: Variant = job.work.call()
	_mutex.lock()
	job.result = result
	_mutex.unlock()


## Whether a job sits in `slot` (running, or finished and not yet collected).
func is_running(slot: StringName) -> bool:
	return _jobs.has(slot)


## The key of the job in `slot`, or "".
func key_of(slot: StringName) -> String:
	var job: Job = _jobs.get(slot)
	return job.key if job != null else ""


## Blocks until the job in `slot` is done and drops it (`done` is not called).
func wait(slot: StringName) -> void:
	var job: Job = _jobs.get(slot)
	if job == null:
		return
	WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.erase(slot)


func wait_all() -> void:
	for slot: StringName in _jobs.keys():
		wait(slot)


## Collects finished jobs: calls `done`, or drops a stale one.
func poll() -> void:
	for slot: StringName in _jobs.keys():
		var job: Job = _jobs.get(slot)
		if job == null or not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.erase(slot)
		if job.wanted.is_valid() and String(job.wanted.call()) != job.key:
			discarded += 1
			continue
		job.done.call(job)
