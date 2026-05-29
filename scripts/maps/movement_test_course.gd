extends Node3D

func _ready() -> void:
	_create_course()

func _create_course() -> void:
	_create_box("Floor", Vector3(0, -0.1, 0), Vector3(42, 0.2, 42), Color(0.28, 0.30, 0.32))
	_create_box("StartPlatform", Vector3(0, 0.35, 10), Vector3(7, 0.7, 6), Color(0.22, 0.26, 0.29))
	_create_box("SlideLane", Vector3(0, 0.05, 0), Vector3(5, 0.15, 16), Color(0.18, 0.22, 0.25))
	_create_box("LowBridge", Vector3(0, 1.55, 0), Vector3(5.5, 0.35, 4.5), Color(0.12, 0.14, 0.16))
	_create_box("LeftWallrunWall", Vector3(-5.5, 2.0, -4.0), Vector3(0.45, 4.0, 14.0), Color(0.25, 0.36, 0.55))
	_create_box("RightWallrunWall", Vector3(5.5, 2.0, -4.0), Vector3(0.45, 4.0, 14.0), Color(0.55, 0.32, 0.20))
	_create_box("UpperCatwalk", Vector3(0, 4.2, -11.0), Vector3(12.0, 0.35, 3.0), Color(0.34, 0.32, 0.25))
	_create_box("JumpPadLanding", Vector3(-11.0, 2.0, -11.0), Vector3(4.0, 0.35, 4.0), Color(0.29, 0.34, 0.30))
	_create_box("ContainerA", Vector3(11.0, 1.1, -4.0), Vector3(4.0, 2.2, 8.0), Color(0.20, 0.32, 0.58))
	_create_box("ContainerB", Vector3(14.5, 2.2, -11.0), Vector3(4.0, 4.4, 4.0), Color(0.58, 0.28, 0.18))
	_create_ramp("RampToCatwalk", Vector3(-4.0, 1.5, -9.0), Vector3(4.0, 0.35, 8.0), -22.0, Color(0.36, 0.36, 0.32))
	_create_targets()

func _create_targets() -> void:
	for index in range(4):
		var target := DummyTarget.new()
		target.name = "CombatDummy%d" % (index + 1)
		target.position = Vector3(-7.5 + index * 5.0, 0.0, -17.0)
		add_child(target)

func _create_box(node_name: String, position: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	add_child(body)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	return body

func _create_ramp(node_name: String, position: Vector3, size: Vector3, x_degrees: float, color: Color) -> StaticBody3D:
	var ramp := _create_box(node_name, position, size, color)
	ramp.rotation_degrees.x = x_degrees
	return ramp

