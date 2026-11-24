extends ResourcePreloader

const CONTEXT_MESH: int = 1
const CONTEXT_MULTIMESH: int = 2
const CONTEXT_UNKNOWN = CONTEXT_MESH | CONTEXT_MULTIMESH

export (int) var shaders_per_frame: int = 64

var cache: Dictionary = {}
var locals: Dictionary = {}
var queue: Array = []
var promise: Promise
var versions_compiled: int = 0

var camera: Camera
var mesh: Mesh
var multimesh: MultiMesh
var nodes: CanvasLayer

var mat_meshes: Dictionary

func _ready():
	set_process(false)
	
	camera = Camera.new()
	camera.transform.origin.z = 2.0
	add_child(camera)
	
	mesh = QuadMesh.new()
	multimesh = MultiMesh.new()
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	
	for res_name in get_resource_list():
		queue_shaders(get_resource(res_name))
	for vfx_path in [
		"res://nodes/battle_vfx/beams/death_ray/DeathRay.tscn",
		"res://nodes/battle_vfx/beams/ice_beam/IceBeam.tscn",
		"res://nodes/battle_vfx/beams/laser_beam/LaserBeam.tscn",
		"res://nodes/battle_vfx/beams/recording/RecordingBeam.tscn",
		"res://nodes/battle_vfx/particles/Mist.tscn",
		"res://nodes/battle_vfx/projectiles/FirePointLight.tscn",
		"res://nodes/battle_vfx/projectiles/FirePointLightFlash.tscn",
		"res://nodes/battle_vfx/projectiles/FirePointLightIncinerate.tscn",
		"res://nodes/battle_vfx/projectiles/StarPointLight.tscn",
		"res://nodes/battle_vfx/scenes/bomb_voyage/BombVoyageTarget.tscn",
		"res://nodes/battle_vfx/scenes/record_success/RecordSuccess.tscn",
		"res://nodes/battle_vfx/scenes/true_illumination/TrueIllumination.tscn",
	]:
		if ResourceLoader.exists(vfx_path):
			queue_shaders(load(vfx_path))

func freeing_scene(scene: Node):
	if not locals.has(scene):
		return
	for mat in locals[scene].keys():
		cache.erase(mat)
	locals.erase(scene)

func queue_shaders(v: Resource, context: int = CONTEXT_UNKNOWN):
	if v == null:
		return
	
	if v.has_meta("shaders_queued"):
		if (v.get_meta("shaders_queued") & context) == context or v is PackedScene:
			return
		v.set_meta("shaders_queued", v.get_meta("shaders_queued") | context)
	else:
		v.set_meta("shaders_queued", context)
	
	var external_deps = []
	if v.resource_path != "" and not ("::" in v.resource_path):
		for dep in ResourceLoader.get_dependencies(v.resource_path):
			external_deps.push_back(load(dep))
	
	if v is PackedScene:
		context = _detect_context(v._bundled.variants, external_deps)
	
	for dep in external_deps:
		queue_shaders(dep, context)
	
	if v is Material:
		_queue_mat(v, context)
	elif v is PackedScene:
		_queue_shaders_scene(v, context)
	elif v is Mesh:
		_queue_shaders_mesh(v, context)
	elif v is MeshLibrary:
		_queue_shaders_meshlib(v)

func _detect_context(variants: Array, external_deps: Array) -> int:
	var particle_mats: int = 0
	var spatial_mats: int = 0
	for v in variants:
		if is_particles_mat(v):
			particle_mats += 1
		elif is_spatial_mat(v):
			spatial_mats += 1
	for v in external_deps:
		if is_particles_mat(v):
			particle_mats += 1
		elif is_spatial_mat(v):
			spatial_mats += 1
	
	if particle_mats == 0:
		return CONTEXT_MESH
	elif spatial_mats == particle_mats:
		return CONTEXT_MULTIMESH
	else:
		return CONTEXT_UNKNOWN

func _queue_mat(mat: Material, context: int):
	assert (context != 0)
	if cache.has(mat):
		if not cache[mat]:
			return
	if mat is ShaderMaterial and mat.shader:
		if mat.shader.has_meta("shader_mat_cached"):
			if (mat.shader.get_meta("shader_mat_cached") & context) == context:
				return
			mat.shader.set_meta("shader_mat_cached", mat.shader.get_meta("shader_mat_cached") | context)
		else:
			mat.shader.set_meta("shader_mat_cached", context)
	queue.push_back(mat)
	cache[mat] = false

func _queue_shaders_scene(scene: PackedScene, context: int):
	for v in scene._bundled.variants:
		if v is Resource:
			queue_shaders(v, context)

func _queue_shaders_mesh(mesh: Mesh, context: int):
	for i in range(mesh.get_surface_count()):
		var mat = mesh.surface_get_material(i)
		queue_shaders(mat, context)
		if not mat_meshes.has(mat):
			mat_meshes[mat] = []
		mat_meshes[mat].push_back(mesh)

func _queue_shaders_meshlib(meshlib: MeshLibrary):
	for id in meshlib.get_item_list():
		var mesh = meshlib.get_item_mesh(id)
		if mesh != null:
			queue_shaders(mesh, CONTEXT_MULTIMESH)

func process_queue() -> Promise:
	promise = Promise.new()
	promise.progress_max = queue.size()
	nodes = CanvasLayer.new()
	nodes.layer = - 128
	add_child(nodes)
	versions_compiled = 0
	set_process(true)
	camera.make_current()
	return promise

func _process(delta):
	assert (promise != null)
	
	for i in range(shaders_per_frame):
		if queue.size() == 0:
			camera.clear_current()
			promise.fulfill(null)
			nodes.queue_free()
			nodes = null
			mat_meshes.clear()
			print("Compiled " + str(versions_compiled) + " shader versions. Cache size: " + str(cache.size()))
			set_process(false)
			return
		
		var mat = queue.pop_front()
		process_mat(mat)
		promise.progress = promise.progress_max - queue.size()

func is_spatial_mat(mat: Resource) -> bool:
	return mat is SpatialMaterial or (mat is ShaderMaterial and mat.shader and mat.shader.get_mode() == Shader.MODE_SPATIAL)

func is_particles_mat(mat: Resource) -> bool:
	return mat is ParticlesMaterial or (mat is ShaderMaterial and mat.shader and mat.shader.get_mode() == Shader.MODE_PARTICLES)

func is_canvas_mat(mat: Resource) -> bool:
	return mat is CanvasItemMaterial or (mat is ShaderMaterial and mat.shader and mat.shader.get_mode() == Shader.MODE_CANVAS_ITEM)

func is_local_mat(mat: Material) -> bool:
	if mat is ShaderMaterial and mat.shader:
		if mat.shader.resource_path != "" and mat.shader.resource_path.find("::") == - 1:
			return false
	return mat.resource_local_to_scene or mat.resource_path == ""

func process_mat(mat: Material):
	if is_local_mat(mat):
		assert (get_tree().current_scene != null)
		var scene = get_tree().current_scene
		if scene != null:
			if not locals.has(scene):
				locals[scene] = {}
			locals[scene][mat] = true
	
	if is_spatial_mat(mat):
		assert (mat.has_meta("shaders_queued"))
		if mat.get_meta("shaders_queued") & CONTEXT_MESH != 0:
			var meshes = mat_meshes.get(mat, [mesh])
			for m0 in meshes:
				var node = MeshInstance.new()
				node.mesh = m0
				node.material_override = mat
				nodes.add_child(node)
			versions_compiled += 1
		if mat.get_meta("shaders_queued") & CONTEXT_MULTIMESH != 0:
			var multi = MultiMeshInstance.new()
			multi.multimesh = multimesh
			multi.material_override = mat
			nodes.add_child(multi)
			versions_compiled += 1
	elif is_particles_mat(mat):
		var node = Particles.new()
		node.amount = 1
		node.emitting = true
		node.process_material = mat
		node.draw_pass_1 = mesh
		nodes.add_child(node)
		versions_compiled += 1
	elif is_canvas_mat(mat):
		var node = Sprite.new()
		node.texture = preload("res://icon.png")
		node.material = mat
		nodes.add_child(node)
		versions_compiled += 1
	else:
		return
	cache[mat] = true
	
	if mat is ShaderMaterial and mat.shader:
		cache[mat.shader] = true
