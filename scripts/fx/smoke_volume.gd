extends Node3D

@export var radius := 4.0
@export var lifetime_sec := 14.0
@export var growth_time_sec := 0.65
@export var start_scale := 0.25
@export var settled_scale := 1.10
@export var final_scale := 1.22

const PUFF_LAYOUT := [
	{"offset": Vector3(-0.42, 0.08, 0.20), "scale": Vector3(0.72, 0.60, 0.78), "alpha": 0.82},
	{"offset": Vector3(0.36, 0.18, -0.10), "scale": Vector3(0.66, 0.74, 0.64), "alpha": 0.78},
	{"offset": Vector3(0.02, 0.46, 0.24), "scale": Vector3(0.58, 0.52, 0.70), "alpha": 0.76},
	{"offset": Vector3(-0.12, -0.22, -0.34), "scale": Vector3(0.78, 0.62, 0.58), "alpha": 0.80},
	{"offset": Vector3(0.18, -0.06, 0.36), "scale": Vector3(0.70, 0.66, 0.62), "alpha": 0.74},
]

var _elapsed := 0.0
var _smoke_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	_rebuild_smoke_meshes()

func _physics_process(delta: float) -> void:
	_elapsed += delta
	var grow_t := clampf(_elapsed / maxf(growth_time_sec, 0.001), 0.0, 1.0)
	var grow_eased := 1.0 - pow(1.0 - grow_t, 3.0)
	var life_t := clampf(_elapsed / maxf(lifetime_sec, 0.001), 0.0, 1.0)
	var slow_swell_t := clampf((_elapsed - growth_time_sec) / maxf(lifetime_sec - growth_time_sec, 0.001), 0.0, 1.0)
	var current_scale := lerpf(start_scale, settled_scale, grow_eased)
	if grow_t >= 1.0:
		current_scale = lerpf(settled_scale, final_scale, slow_swell_t)
	scale = Vector3.ONE * current_scale
	if _elapsed >= lifetime_sec:
		queue_free()

func configure(seconds: float, effect_radius: float) -> void:
	lifetime_sec = seconds
	radius = effect_radius
	if is_node_ready():
		_rebuild_smoke_meshes()

func set_lifetime(seconds: float) -> void:
	lifetime_sec = seconds

func set_radius(effect_radius: float) -> void:
	radius = effect_radius
	if is_node_ready():
		_rebuild_smoke_meshes()

func get_runtime_summary() -> Dictionary:
	return {
		"radius": radius,
		"lifetime_sec": lifetime_sec,
		"growth_time_sec": growth_time_sec,
		"elapsed": _elapsed,
		"scale": scale,
	}

func _rebuild_smoke_meshes() -> void:
	_smoke_materials.clear()
	for child in get_children():
		if String(child.name).begins_with("SmokePuff"):
			child.queue_free()
	var mesh_instance: MeshInstance3D = $MeshInstance3D
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh_instance.mesh = mesh
	var base_material := _build_smoke_material(0.76)
	mesh_instance.material_override = base_material
	_smoke_materials.append(base_material)
	_add_puff_meshes(base_material)

func _add_puff_meshes(base_material: StandardMaterial3D) -> void:
	for index in range(PUFF_LAYOUT.size()):
		var entry: Dictionary = PUFF_LAYOUT[index]
		var puff := MeshInstance3D.new()
		puff.name = "SmokePuff%d" % (index + 1)
		puff.position = entry["offset"] * radius
		puff.scale = entry["scale"]
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 20
		mesh.rings = 10
		puff.mesh = mesh
		var material := base_material.duplicate() as StandardMaterial3D
		material.albedo_color.a = float(entry["alpha"])
		puff.material_override = material
		_smoke_materials.append(material)
		add_child(puff)

func _build_smoke_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.30, 0.36, 0.38, alpha)
	material.roughness = 1.0
	material.metallic = 0.0
	return material
