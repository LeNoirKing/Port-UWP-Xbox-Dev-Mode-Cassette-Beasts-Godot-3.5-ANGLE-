extends "JobQueue.gd"

var promises_by_path: Dictionary = {}

func _init():
	thread_count = 4

func load_async(path: String) -> Resource:
	return yield(load_promise(path).join(), "completed")

func load_promise(path: String) -> Promise:
	if promises_by_path.has(path):
		return promises_by_path[path]
	var promise = Promise.new()
	post(Bind.new(self, "_load_task", [path, promise]), promise)
	promises_by_path[path] = promise
	_async_cleanup(path, promise)
	return promise

func _async_cleanup(path: String, promise: Promise):
	yield(promise.join(), "completed")
	promises_by_path.erase(path)

func _load_task(path: String, promise: Promise) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	var loader = ResourceLoader.load_interactive(path)
	var err = OK
	while err == OK:
		err = loader.poll()
		promise.progress_max = loader.get_stage_count()
		promise.progress = loader.get_stage()
	if err != ERR_FILE_EOF:
		push_error("Failed to load_async: " + path)
	return loader.get_resource()
