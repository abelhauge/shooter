class_name ProceduralViewModel
extends Node3D

@export var weapon_id: StringName = &"weapon"
@export var viewmodel_kind := "knife"
@export var placeholder_note := "Deliberate v1 project-owned placeholder."
@export var model_position := Vector3(0.18, -0.14, -0.48)
@export var model_rotation_degrees := Vector3.ZERO
@export var model_scale := Vector3.ONE
@export var primary_color := Color(0.42, 0.47, 0.52, 1.0)
@export var accent_color := Color(0.95, 0.56, 0.18, 1.0)

var model_root: Node3D
var vertex_count := 0

func _ready() -> void:
	model_root = Node3D.new()
	model_root.name = "ProceduralModel"
	model_root.position = model_position
	model_root.rotation_degrees = model_rotation_degrees
	model_root.scale = model_scale
	add_child(model_root)
	_build_model()
	vertex_count = _count_mesh_vertices(model_root)

func get_runtime_summary() -> Dictionary:
	return {
		"source_fbx_path": "",
		"generated_glb_path": "",
		"has_mesh": vertex_count > 0,
		"vertex_count": vertex_count,
		"placeholder_type": "deliberate_v1",
		"placeholder_note": placeholder_note,
		"viewmodel_kind": viewmodel_kind,
		"material_override": true,
	}

func _build_model() -> void:
	match viewmodel_kind:
		"knife":
			_build_knife()
		"smoke_bomb":
			_build_throwable(Color(0.18, 0.22, 0.24, 1.0), Color(0.55, 0.62, 0.66, 1.0))
		"grenade":
			_build_throwable(Color(0.20, 0.34, 0.19, 1.0), Color(0.88, 0.72, 0.28, 1.0))
		"flamethrower":
			_build_flamethrower()
		"lasso":
			_build_lasso()
		"taser_gun":
			_build_taser_gun()
		"redbull":
			_build_can()
		"portal_gun":
			_build_portal_gun()
		_:
			_add_box("Body", Vector3.ZERO, Vector3(0.18, 0.12, 0.52), primary_color)

func _build_knife() -> void:
	_add_box("Grip", Vector3(0.0, -0.05, 0.12), Vector3(0.08, 0.12, 0.24), Color(0.10, 0.10, 0.10, 1.0))
	_add_box("Guard", Vector3(0.0, 0.02, -0.03), Vector3(0.18, 0.035, 0.045), accent_color)
	_add_box("Blade", Vector3(0.0, 0.05, -0.28), Vector3(0.055, 0.035, 0.44), Color(0.72, 0.78, 0.82, 1.0))

func _build_throwable(body_color: Color, band_color: Color) -> void:
	_add_cylinder("Canister", Vector3.ZERO, 0.11, 0.28, Vector3(90.0, 0.0, 0.0), body_color)
	_add_box("BandA", Vector3(0.0, 0.0, -0.08), Vector3(0.24, 0.035, 0.035), band_color)
	_add_box("BandB", Vector3(0.0, 0.0, 0.08), Vector3(0.24, 0.035, 0.035), band_color)
	_add_box("Pin", Vector3(0.0, 0.15, -0.02), Vector3(0.16, 0.025, 0.025), accent_color)

func _build_flamethrower() -> void:
	_add_box("Frame", Vector3(0.0, -0.02, 0.02), Vector3(0.18, 0.14, 0.42), Color(0.18, 0.20, 0.22, 1.0))
	_add_cylinder("Barrel", Vector3(0.0, 0.04, -0.36), 0.045, 0.46, Vector3(90.0, 0.0, 0.0), Color(0.08, 0.08, 0.08, 1.0))
	_add_cylinder("FuelTank", Vector3(0.12, -0.05, 0.08), 0.07, 0.28, Vector3(0.0, 0.0, 0.0), accent_color)
	_add_box("Grip", Vector3(-0.05, -0.18, 0.12), Vector3(0.08, 0.18, 0.08), Color(0.08, 0.08, 0.08, 1.0))

func _build_lasso() -> void:
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var position := Vector3(cos(angle) * 0.13, sin(angle) * 0.09, 0.0)
		var segment := _add_box("Coil%02d" % index, position, Vector3(0.05, 0.025, 0.025), accent_color)
		segment.rotation_degrees.z = rad_to_deg(angle)
	_add_box("Handle", Vector3(0.02, -0.13, 0.12), Vector3(0.075, 0.18, 0.075), primary_color)

func _build_taser_gun() -> void:
	_add_box("Body", Vector3(0.0, 0.0, 0.02), Vector3(0.18, 0.12, 0.30), primary_color)
	_add_box("Grip", Vector3(0.0, -0.15, 0.13), Vector3(0.085, 0.20, 0.08), Color(0.06, 0.07, 0.08, 1.0))
	_add_box("BatteryPack", Vector3(0.0, -0.03, 0.22), Vector3(0.13, 0.08, 0.10), Color(0.20, 0.22, 0.24, 1.0))
	_add_cylinder("LeftProbe", Vector3(-0.045, 0.035, -0.18), 0.018, 0.20, Vector3(90.0, 0.0, 0.0), accent_color)
	_add_cylinder("RightProbe", Vector3(0.045, 0.035, -0.18), 0.018, 0.20, Vector3(90.0, 0.0, 0.0), accent_color)
	_add_box("ChargeWindow", Vector3(0.0, 0.065, -0.02), Vector3(0.12, 0.018, 0.11), accent_color)

func _build_can() -> void:
	_add_cylinder("Can", Vector3.ZERO, 0.085, 0.28, Vector3(0.0, 0.0, 0.0), Color(0.08, 0.22, 0.82, 1.0))
	_add_box("Label", Vector3(0.0, 0.0, -0.002), Vector3(0.19, 0.13, 0.018), Color(0.90, 0.10, 0.10, 1.0))
	_add_cylinder("Top", Vector3(0.0, 0.145, 0.0), 0.087, 0.018, Vector3(0.0, 0.0, 0.0), Color(0.78, 0.80, 0.78, 1.0))

func _build_portal_gun() -> void:
	_add_box("Core", Vector3(0.0, 0.0, 0.02), Vector3(0.20, 0.14, 0.34), Color(0.20, 0.22, 0.25, 1.0))
	_add_cylinder("EmitterBlue", Vector3(-0.065, 0.02, -0.22), 0.05, 0.08, Vector3(90.0, 0.0, 0.0), Color(0.10, 0.48, 1.0, 1.0))
	_add_cylinder("EmitterOrange", Vector3(0.065, 0.02, -0.22), 0.05, 0.08, Vector3(90.0, 0.0, 0.0), Color(1.0, 0.50, 0.08, 1.0))
	_add_box("Grip", Vector3(0.0, -0.16, 0.12), Vector3(0.08, 0.18, 0.08), Color(0.08, 0.08, 0.09, 1.0))

func _add_box(node_name: String, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = _make_material(color)
	model_root.add_child(mesh_instance)
	return mesh_instance

func _add_cylinder(node_name: String, position: Vector3, radius: float, height: float, rotation_degrees_value: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 18
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation_degrees_value
	mesh_instance.material_override = _make_material(color)
	model_root.add_child(mesh_instance)
	return mesh_instance

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.2
	material.roughness = 0.48
	return material

func _count_mesh_vertices(root: Node) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mesh := (root as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				count += vertices.size()
	for child in root.get_children():
		count += _count_mesh_vertices(child)
	return count
