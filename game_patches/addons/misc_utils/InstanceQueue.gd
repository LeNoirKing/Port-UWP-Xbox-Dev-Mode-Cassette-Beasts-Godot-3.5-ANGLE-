extends Node

class Job extends Reference:
	var scene: PackedScene
	var promise: Promise

var queue: Array

func instance_async(scene: PackedScene) -> Resource:
	assert (scene != null)
	return yield(instance_promise(scene).join(), "completed")

func instance_promise(scene: PackedScene) -> Promise:
	assert (scene != null)
	var job = Job.new()
	job.scene = scene
	job.promise = Promise.new()
	queue.push_back(job)
	set_process(true)
	return job.promise

func _ready():
	set_process(false)

func _process(_delta):
	var start_tick = Time.get_ticks_msec()
	while queue.size() > 0:
		var job = queue.pop_front()
		if job:
			job.promise.fulfill(job.scene.instance())
		if (Time.get_ticks_msec() - start_tick) >= 5:
			break
	if queue.size() == 0:
		set_process(false)
