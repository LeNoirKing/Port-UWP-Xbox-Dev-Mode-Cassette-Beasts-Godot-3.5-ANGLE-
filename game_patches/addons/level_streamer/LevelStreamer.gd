tool
extends ResourcePreloader
class_name LevelStreamer

const INSTANCE_WHEN_SETTING: String = "application/level_streamer/instance_chunks_when"
enum InstanceWhenValue{LOADING_SCREEN, BOUNDARY_MATCH, IN_RANGE}

const Chunk = preload("Chunk.gd")
const Boundary = preload("Boundary.gd")

export (Vector2) var chunk_size: Vector2 = Vector2(20, 20)
export (float) var vertical_extent: float = 500.0

export (int, LAYERS_3D_PHYSICS) var roaming_collision_mask: int = 1
export (int, LAYERS_3D_PHYSICS) var empty_static_collision_mask: int = 1
export (int, LAYERS_3D_PHYSICS) var partial_static_collision_mask: int = 0
export (float) var inner_margin: float = 5.0
export (float) var mid_margin: float = 7.0
export (float) var outer_margin: float = 9.0
export (float) var instance_margin: float = 36.0
export (float) var camera_near_distance: float = 24.0
export (float) var camera_far_distance: float = 100.0
export (Vector2) var debug_map_size: Vector2
export (Vector2) var debug_map_offset: Vector2






export (String) var chunk_name_format: String = "chunk_%s_%s"
export (PackedScene) var oob_chunk: PackedScene
export (Vector2) var default_start_chunk: Vector2 = Vector2(0, 0)
export (bool) var force_synchronous_loading: bool = false

onready var level = get_parent()
onready var debug_map = $DebugMap if has_node(@"DebugMap") else null

var first_tick: bool = true
var load_index: int = 0
var load_task_stepper: Bind
var instances: Dictionary
var chunks: Dictionary
var hot_chunks: Array
var boundaries: Array
var current_boundary: Boundary
var _swapping_boundary: bool = false

func _ready():
	if Engine.editor_hint:
		set_process(false)
	else:
		SceneManager.connect("freeing_scene", self, "_on_freeing_scene")
		
		for child in get_children():
			if child is Boundary:
				boundaries.push_back(child)
		
		if debug_map:
			debug_map.texture = ImageTexture.new()
			var image = Image.new()
			image.create(debug_map_size.x, debug_map_size.y, false, Image.FORMAT_RGBA8)
			image.lock()
			image.fill(Color.white)
			image.unlock()
			debug_map.texture.create_from_image(image, 0)
			debug_map.visible = Debug.stream_map
			Debug.connect("debug_stream_map_changed", debug_map, "set_visible")

func get_instance_when():
	if not ProjectSettings.has_setting(INSTANCE_WHEN_SETTING):
		return InstanceWhenValue.LOADING_SCREEN
	var value = ProjectSettings.get_setting(INSTANCE_WHEN_SETTING)
	if value == InstanceWhenValue.BOUNDARY_MATCH and boundaries.size() == 0:
		return InstanceWhenValue.LOADING_SCREEN
	return value

func get_chunk_list() -> PoolStringArray:
	return get_resource_list()

func get_chunk(res_name: String) -> PackedScene:
	
	return get_resource(res_name) as PackedScene

func has_chunk(res_name: String) -> bool:
	return has_resource(res_name)

func _load_task(initial_chunk):
	if initial_chunk != null:
		default_start_chunk = initial_chunk
	
	if get_instance_when() == InstanceWhenValue.IN_RANGE:
		return null
	
	elif get_instance_when() == InstanceWhenValue.BOUNDARY_MATCH:
		current_boundary = _find_best_boundary(default_start_chunk)
		if not current_boundary:
			return null
		if instances.size() > 0:
			return _swap_boundary(current_boundary)
	
	elif instances.size() > 0:
		assert (get_instance_when() == InstanceWhenValue.LOADING_SCREEN)
		return null
	
	pause_mode = Node.PAUSE_MODE_PROCESS
	load_index = 0
	var promise = Promise.new()
	load_task_stepper = Bind.new(self, "_load_task_step", [promise])
	promise.progress_max = get_chunk_list().size()
	return promise

func _load_task_step(promise: Promise):
	if load_index >= get_chunk_list().size():
		promise.fulfill(null)
		load_task_stepper = null
		pause_mode = Node.PAUSE_MODE_INHERIT
		return
	
	while load_index < get_resource_list().size():
		var res_name = get_chunk_list()[load_index]
		
		load_index += 1
		promise.progress = load_index
		
		if instances.has(res_name):
			continue
		var chunk_index = _parse_chunk_name(res_name)
		if chunk_index == null:
			push_error("Couldn't parse chunk name " + res_name)
		if chunk_index != null and _matches_current_boundary(chunk_index) and not chunks.has(chunk_index):
			if Debug.is_verbose_logging(): print("Instancing " + res_name)
			var node = get_chunk(res_name).instance()
			instances[res_name] = node
			break

func _matches_current_boundary(chunk_index: Vector2):
	if get_instance_when() != InstanceWhenValue.BOUNDARY_MATCH:
		return true
	return current_boundary and current_boundary.chunk_matches(chunk_index)

func _find_best_boundary(chunk_index: Vector2) -> Boundary:
	for boundary in boundaries:
		if boundary.is_boundary_crossed(chunk_index):
			return boundary
	for boundary in boundaries:
		if boundary.chunk_matches(chunk_index):
			return boundary
	return null

func _parse_chunk_name(res_name: String):
	var parts = chunk_name_format.split("%s")
	assert (parts.size() >= 2)
	assert (parts.size() <= 3)
	
	var s: String = res_name.substr(0, parts[0].length())
	if s != parts[0]:
		return null
	var i = res_name.find(parts[1], parts[0].length())
	if i < 0:
		return null
	var xs = res_name.substr(parts[0].length(), i - parts[0].length())
	if not xs.is_valid_integer():
		return null
	s = res_name.substr(i + parts[1].length())
	i = s.length() if parts.size() == 2 or parts[2] == "" else s.find(parts[2])
	if i < 0:
		return null
	var ys = s.substr(0, i)
	if not ys.is_valid_integer():
		return null
	return Vector2(int(xs), int(ys))

func _on_freeing_scene(scene):
	if scene.is_a_parent_of(self):
		for node in instances.values():
			node.queue_free()

func editor_clear():
	for node in instances.values():
		node.queue_free()
	for chunk in chunks.values():
		chunk.free_chunk()
	instances.clear()
	chunks.clear()
	hot_chunks.clear()

func _process(_delta):
	if Engine.editor_hint:
		return
	
	if load_task_stepper:
		load_task_stepper.call_func()
		return
	
	if SceneManager.is_popping:
		
		return
	
	var camera = get_viewport().get_camera()
	observe(camera, get_viewport(), force_synchronous_loading or first_tick)
	first_tick = false
	
	if debug_map and debug_map.visible:
		_update_debug_map()

func _update_debug_map():
	var image = debug_map.texture.get_data()
	image.lock()
	for chunk in chunks.values():
		var index = chunk_for_pos_3d(chunk.global_transform.origin)
		var image_pos = index - debug_map_offset
		if image_pos.x < 0 or image_pos.y < 0 or image_pos.x >= image.get_width() or image_pos.y >= image.get_height():
			continue
		if chunk.is_full():
			image.set_pixelv(image_pos, Color.black)
		elif not chunk.is_empty():
			image.set_pixelv(image_pos, Color.gray)
		else:
			image.set_pixelv(image_pos, Color.white)
	image.unlock()
	debug_map.texture.set_data(image)

func get_view_bounds(camera: Camera, viewport: Viewport) -> AABB:
	var near = Vector3(0.0, 0.0, - camera_near_distance)
	var far = Vector3(0.0, 0.0, - camera_far_distance)
	var left = far.rotated(Vector3.UP, deg2rad(camera.fov / 2.0))
	var right = left * Vector3( - 1.0, 1.0, 1.0)
	var aabb = AABB(camera.global_transform.xform(near), Vector3())
	aabb = aabb.expand(camera.global_transform.xform(far))
	aabb = aabb.expand(camera.global_transform.xform(left))
	aabb = aabb.expand(camera.global_transform.xform(right))
	aabb.position.y = - vertical_extent
	aabb.end.y = vertical_extent
	
	for player in WorldSystem.get_players():
		aabb = aabb.expand(player.global_transform.origin)
	
	return aabb

func swap_boundary(boundary: Boundary):
	if _swapping_boundary or SceneManager.transitioning:
		return
	_swapping_boundary = true
	SceneManager.transition = SceneManager.TransitionKind.TRANSITION_FADE
	yield(SceneManager.show_loading(Bind.new(self, "_swap_boundary", [boundary]), "UI_LOADING_WORLD_BOUNDARY"), "completed")
	_swapping_boundary = false

func _swap_boundary(boundary: Boundary):
	var promise = Promise.new()
	promise.progress_max = get_chunk_list().size()
	_swap_boundary_1(boundary, promise)
	return promise

func _swap_boundary_1(boundary: Boundary, promise: Promise):
	load_index = 0
	pause_mode = Node.PAUSE_MODE_PROCESS
	load_task_stepper = Bind.new(self, "_swap_boundary_step", [boundary, promise])

func _swap_boundary_step(boundary: Boundary, promise: Promise):
	if current_boundary != boundary:
		current_boundary = boundary
		return
	
	if load_index == 0:
		hot_chunks.clear()
		for chunk_index in chunks.keys():
			if not current_boundary.chunk_matches(chunk_index):
				if Debug.is_verbose_logging(): print("Freeing chunk " + str(chunk_index))
				chunks[chunk_index].free_chunk()
				chunks.erase(chunk_index)
		for res_name in instances.keys():
			var chunk_index = _parse_chunk_name(res_name)
			if chunk_index == null or not current_boundary.chunk_matches(chunk_index):
				if Debug.is_verbose_logging(): print("Freeing instance " + res_name)
				instances[res_name].queue_free()
				instances.erase(res_name)
	
	_load_task_step(promise)

func _check_boundaries() -> Boundary:
	if get_instance_when() == InstanceWhenValue.BOUNDARY_MATCH:
		var camera = get_viewport().get_camera()
		var chunk_pos = Vector2(camera.global_transform.origin.x / chunk_size.x, camera.global_transform.origin.z / chunk_size.y)
		for boundary in boundaries:
			if boundary != current_boundary and boundary.is_boundary_crossed(chunk_pos):
				return boundary
	return null

func observe(camera: Camera, viewport: Viewport, synchronous: bool = false):
	
	var boundary = _check_boundaries()
	if boundary:
		swap_boundary(boundary)
		return
	
	var aabb = get_view_bounds(camera, viewport)
	var inner_aabb = aabb.grow(inner_margin)
	var mid_aabb = aabb.grow(mid_margin)
	var outer_aabb = aabb.grow(outer_margin)
	var instance_aabb = aabb.grow(instance_margin)
	
	var x_min = round(instance_aabb.position.x / chunk_size.x)
	var x_max = round(instance_aabb.end.x / chunk_size.x)
	var z_min = round(instance_aabb.position.z / chunk_size.y)
	var z_max = round(instance_aabb.end.z / chunk_size.y)
	
	for x in range(x_min, x_max + 1):
		for z in range(z_min, z_max + 1):
			var index = Vector2(x, z)
			
			if not _matches_current_boundary(index):
				continue
			if not chunks.has(index):
				level.add_child(load_chunk(index, synchronous))
			if not hot_chunks.has(index):
				hot_chunks.push_front(index)
	
	for i in range(hot_chunks.size() - 1, - 1, - 1):
		var index = hot_chunks[i]
		var chunk = chunks[index]
		if chunk.observe(outer_aabb, mid_aabb, inner_aabb, camera.global_transform.origin, synchronous) and not synchronous:
			
			
			hot_chunks.remove(i)
			hot_chunks.push_front(index)
			
			break
		elif chunk.is_empty():
			hot_chunks.remove(i)

func force_load_position(pos: Vector3):
	var index = chunk_for_pos_3d(pos)
	if not chunks.has(index):
		level.add_child(load_chunk(index, true))
	var chunk = chunks[index]
	chunk.insert_all()
	if not hot_chunks.has(index):
		hot_chunks.push_front(index)
	
	for neighbor in [Vector3( - 2, 0, 0), Vector3(2, 0, 0), Vector3(0, 0, - 2), Vector3(0, 0, 2)]:
		var npos = pos + neighbor
		var nindex = chunk_for_pos_3d(npos)
		if nindex != index:
			if not chunks.has(nindex):
				level.add_child(load_chunk(nindex, true))
			var nchunk = chunks[nindex]
			nchunk.insert_all()
			if not hot_chunks.has(nindex):
				hot_chunks.push_front(nindex)

func load_chunk(index: Vector2, synchronous: bool):
	var res_name = chunk_name_format % [str(int(index.x)), str(int(index.y))]
	var pos = chunk_pos(index)
	
	var chunk = Chunk.new()
	chunk.name = res_name
	chunk.chunk_size = chunk_size
	chunk.vertical_extent = vertical_extent
	chunk.roaming_collision_mask = roaming_collision_mask
	chunk.empty_static_collision_mask = empty_static_collision_mask
	chunk.partial_static_collision_mask = partial_static_collision_mask
	chunk.synchronous = synchronous
	chunk.transform.origin = chunk_pos(index)
	if instances.has(res_name):
		if Debug.is_verbose_logging(): print("Adding chunk from instances " + str(index))
		chunk.chunk_res = instances[res_name]
		instances.erase(res_name)
	else:
		if Debug.is_verbose_logging(): print("Chunk wasn't in instances; going to instance it now" + str(index))
		if has_chunk(res_name):
			chunk.chunk_res = get_chunk(res_name)
		else:
			chunk.chunk_res = oob_chunk
		chunk.connect("removed_terrain", self, "_erase_chunk", [index, chunk])
	chunks[index] = chunk
	return chunk

func _erase_chunk(index: Vector2, chunk: Chunk):
	
	chunk.free_chunk()
	chunks.erase(index)

func erase_chunk(index: Vector2):
	
	var chunk = chunks.get(index)
	if chunk:
		chunk.free_chunk()
	chunks.erase(index)

func chunk_for_pos_3d(pos: Vector3) -> Vector2:
	return chunk_for_pos_2d(Vector2(pos.x, pos.z))

func chunk_for_pos_2d(pos: Vector2) -> Vector2:
	var result = (pos + chunk_size / 2) / chunk_size
	return Vector2(floor(result.x), floor(result.y))

func chunk_pos(index: Vector2) -> Vector3:
	return Vector3(index.x * chunk_size.x, 0.0, index.y * chunk_size.y)

func find_warp_target(chunk_index, name: String, force_load: bool = false) -> Spatial:
	
	if chunk_index == null:
		chunk_index = default_start_chunk
	assert (chunk_index is Vector2)
	
	if not chunks.has(chunk_index):
		if force_load:
			level.add_child(load_chunk(chunk_index, true))
			assert (chunks.has(chunk_index))
	if not chunks.has(chunk_index):
		return null
	return chunks[chunk_index].find_warp_target(name, force_load)
