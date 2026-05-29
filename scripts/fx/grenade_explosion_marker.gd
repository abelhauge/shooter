extends Node3D

@export var lifetime_sec := 0.52

var _elapsed := 0.0
var _base_radius := 1.0

func _ready() -> void:
	var shell := $Shell as MeshInstance3D
	var shell_material := shell.material_override as StandardMaterial3D
	if shell_material != null:
		shell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shell_material.no_depth_test = true
	var core := $Core as MeshInstance3D
	var core_material := core.material_override as StandardMaterial3D
	if core_material != null:
		core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core_material.no_depth_test = true

func setup(radius: float) -> void:
	_base_radius = maxf(0.1, radius)
	scale = Vector3.ONE * _base_radius

func _process(delta: float) -> void:
	_elapsed += delta
	var progress := clampf(_elapsed / lifetime_sec, 0.0, 1.0)
	scale = Vector3.ONE * _base_radius * lerpf(1.0, 0.08, progress)
	if _elapsed >= lifetime_sec:
		queue_free()
