extends Node




const MAX_DELAY = {
	false: 8, 
	true: 120
}

class Job:
	var path: String
	var loader: ResourceInteractiveLoader
	var promise: Promise

var on_loading_screen: bool = false
var queue: Array = []
var jobs_by_path: Dictionary = {}

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(queue.size() > 0)

func load_promise(path: String) -> Promise:
	if jobs_by_path.has(path):
		return jobs_by_path[path].promise
	var job = Job.new()
	job.path = path
	job.promise = Promise.new()
	queue.push_back(job)
	jobs_by_path[path] = job
	set_process(true)
	return job.promise

func load_async(path: String) -> Resource:
	return yield(load_promise(path).join(), "completed")

func _process_job(job):
	if job.loader == null:
		if ResourceLoader.exists(job.path):
			job.loader = ResourceLoader.load_interactive(job.path)
		else:
			job.promise.call_deferred("fulfill", null)
			return true
	
	assert (job.loader != null)
	var err = job.loader.poll()
	job.promise.progress_max = job.loader.get_stage_count()
	job.promise.progress = job.loader.get_stage()
	if err == OK:
		return false
	if err != ERR_FILE_EOF:
		push_error("Failed to load_async: " + job.path)
	job.promise.call_deferred("fulfill", job.loader.get_resource())
	return true

func _process(_delta):
	var max_delay = MAX_DELAY[on_loading_screen]
	var start_tick = Time.get_ticks_msec()
	
	while queue.size() > 0 and (Time.get_ticks_msec() - start_tick) < max_delay:
		var job = queue[0]
		if _process_job(job):
			queue.pop_front()
			jobs_by_path.erase(job.path)
	
	if queue.size() == 0:
		set_process(false)
