extends Node3D

@export var lifetime_sec := 0.18

var _elapsed := 0.0

func _ready() -> void:
	var mesh_instance: MeshInstance3D = $MeshInstance3D
	var material := mesh_instance.material_override as StandardMaterial3D
	if material != null:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_energy_multiplier = 4.0

func _process(delta: float) -> void:
	_elapsed += delta
	scale = Vector3.ONE * lerpf(1.0, 0.25, _elapsed / lifetime_sec)
	if _elapsed >= lifetime_sec:
		queue_free()

func align_to_normal(normal: Vector3) -> void:
	var safe_normal := normal.normalized()
	if safe_normal.length_squared() <= 0.001:
		safe_normal = Vector3.UP
	var up := Vector3.UP
	if absf(safe_normal.dot(up)) > 0.98:
		up = Vector3.FORWARD
	look_at(global_position + safe_normal, up)
