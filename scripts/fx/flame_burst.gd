extends Node3D

@export var lifetime_sec := 0.18

var _elapsed := 0.0

func _ready() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var material := (child as MeshInstance3D).material_override as StandardMaterial3D
			if material != null:
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.no_depth_test = true

func _process(delta: float) -> void:
	_elapsed += delta
	var progress := clampf(_elapsed / lifetime_sec, 0.0, 1.0)
	scale = Vector3.ONE * lerpf(1.0, 0.18, progress)
	if _elapsed >= lifetime_sec:
		queue_free()
