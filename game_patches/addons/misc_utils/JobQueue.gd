extends Node

class _Job:
	extends Reference
	var task
	var promise: Promise
	func run():
		var result = task.call_func()
		promise.call_deferred("fulfill", result)

export var thread_count: int = 1

var threads = []
var mutex = Mutex.new()
var sem = Semaphore.new()

var jobs = []

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	var count = max(1, thread_count)
	for i in range(count):
		var t = Thread.new()
		var err = t.start(self, "thread_func", null, 0)
		if err == OK:
			threads.push_back(t)
		else:
			push_error("Cannot start JobQueue thread: " + str(err))

func _exit_tree():
	for _i in range(threads.size()):
		post("::STOP::")
	for t in threads:
		t.wait_to_finish()
	threads.clear()

func post(task, promise = null) -> Promise:
	var job = _Job.new()
	if promise != null:
		job.promise = promise
	else:
		job.promise = Promise.new()
	job.task = task
	mutex.lock()
	jobs.push_back(job)
	sem.post()
	mutex.unlock()
	return job.promise

func thread_func(_userdata = null):
	while true:
		sem.wait()
		
		mutex.lock()
		var job = jobs.pop_front() if jobs.size() > 0 else null
		mutex.unlock()
		
		if job == null:
			continue
		if job.task is String and job.task == "::STOP::":
			return
		job.run()
