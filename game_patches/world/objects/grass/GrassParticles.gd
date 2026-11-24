tool
extends Particles

const GrassProcessMat = preload("grass_process_mat.tres")

export (float) var spacing: float = 2.0 setget set_spacing
export (float) var rand_theta_max: float = 0.5 setget set_rand_theta_max
export (bool) var rand_flip: bool = true setget set_rand_flip

var ready: bool

func _ready():
	lifetime = 86400.0
	process_material = GrassProcessMat.duplicate()
	init_params()
	
	ready = true

func _enter_tree():
	if not Engine.editor_hint:
		material_override.set_meta("live_uses", material_override.get_meta("live_uses", 0) + 1)

func _exit_tree():
	if not Engine.editor_hint:
		material_override.set_meta("live_uses", material_override.get_meta("live_uses", 0) - 1)
		assert (material_override.get_meta("live_uses", 0) >= 0)

func set_spacing(value: float):
	spacing = value
	if ready:
		init_params()

func set_rand_theta_max(value: float):
	rand_theta_max = value
	if ready:
		init_params()

func set_rand_flip(value: bool):
	rand_flip = value
	if ready:
		init_params()

func init_params():
	var aabb = visibility_aabb
	var rows = int(max(1, aabb.size.x / spacing))
	var cols = int(max(1, aabb.size.z / spacing))
	amount = rows * cols
	process_material.set_shader_param("random_seed", int(transform.origin.x * 100.0) ^ int(transform.origin.z * 10000.0))
	process_material.set_shader_param("offset", Vector3(0.0, draw_pass_1.size.y / 2.0, 0.0))
	process_material.set_shader_param("rows", rows)
	process_material.set_shader_param("spacing", spacing)
	process_material.set_shader_param("aabb_min", aabb.position)
	process_material.set_shader_param("aabb_max", aabb.end)
	process_material.set_shader_param("rand_theta_max", rand_theta_max)
	process_material.set_shader_param("rand_flip", rand_flip)
