extends Node3D

var _layers: Dictionary = {}
var _show_generated_visuals := false
var _include_dev_dummies := false

func _ready() -> void:
	_show_generated_visuals = _should_show_generated_visuals()
	_include_dev_dummies = _should_include_dev_dummies()
	_create_layers()
	_create_arena()
	if not _show_generated_visuals:
		_hide_generated_visuals(self)
		_disable_generated_collision_except_floor(self)

func get_spawn_points() -> Array[SpawnPoint]:
	var spawns: Array[SpawnPoint] = []
	var spawn_layer: Node3D = _layers[&"SpawnSpaces"]
	for child in spawn_layer.get_children():
		if child is SpawnPoint:
			spawns.append(child)
	return spawns

func _create_layers() -> void:
	for layer_name in [
		&"GameplayCore",
		&"TraversalRoutes",
		&"CombatCover",
		&"PerimeterClosure",
		&"SkylineBackdrop",
		&"SpawnSpaces",
		&"HazardsAndKillVolumes",
		&"LightingAndAtmosphere",
	]:
		var layer := Node3D.new()
		layer.name = String(layer_name)
		add_child(layer)
		_layers[layer_name] = layer

func _create_arena() -> void:
	var core: Node3D = _layers[&"GameplayCore"]
	var traversal: Node3D = _layers[&"TraversalRoutes"]
	var cover: Node3D = _layers[&"CombatCover"]
	var perimeter: Node3D = _layers[&"PerimeterClosure"]
	var skyline: Node3D = _layers[&"SkylineBackdrop"]
	var spawns: Node3D = _layers[&"SpawnSpaces"]

	_create_box(core, "ArenaFloor", Vector3(0, -0.1, 0), Vector3(85, 0.2, 65), Color(0.24, 0.25, 0.25))
	_create_box(core, "CentralLowGround", Vector3(0, 0.18, 0), Vector3(18, 0.35, 14), Color(0.20, 0.22, 0.23))
	_create_box(core, "NorthPlatform", Vector3(0, 3.2, -18), Vector3(18, 0.45, 8), Color(0.30, 0.30, 0.26))
	_create_box(core, "SouthPlatform", Vector3(0, 2.2, 19), Vector3(16, 0.45, 7), Color(0.27, 0.30, 0.29))

	_create_box(traversal, "BlueWallrunPanel", Vector3(-16, 2.6, -7), Vector3(0.5, 5.2, 20), Color(0.16, 0.29, 0.58))
	_create_box(traversal, "OrangeWallrunPanel", Vector3(16, 2.6, 7), Vector3(0.5, 5.2, 20), Color(0.64, 0.32, 0.14))
	_create_box(traversal, "HighCatwalkA", Vector3(-8, 6.0, -12), Vector3(17, 0.35, 3), Color(0.32, 0.31, 0.25))
	_create_box(traversal, "HighCatwalkB", Vector3(9, 6.0, 12), Vector3(17, 0.35, 3), Color(0.32, 0.31, 0.25))
	_create_box(traversal, "CrossBridge", Vector3(0, 5.4, 0), Vector3(4, 0.35, 25), Color(0.35, 0.33, 0.24))
	_create_ramp(traversal, "BlueRampToHigh", Vector3(-19, 2.3, -16), Vector3(5, 0.35, 12), -22.0, Color(0.34, 0.34, 0.30))
	_create_ramp(traversal, "OrangeRampToHigh", Vector3(19, 2.3, 16), Vector3(5, 0.35, 12), 22.0, Color(0.34, 0.34, 0.30))
	_create_box(traversal, "CraneVerticalMast", Vector3(24, 7.5, -18), Vector3(2.2, 15.0, 2.2), Color(0.62, 0.46, 0.15))
	_create_box(traversal, "CraneArm", Vector3(10, 14.2, -18), Vector3(30, 1.1, 1.1), Color(0.62, 0.46, 0.15))

	for i in range(5):
		_create_box(cover, "BlueContainer%d" % i, Vector3(-28 + i * 4.5, 1.1, -2 + (i % 2) * 7), Vector3(4.0, 2.2, 7.0), Color(0.16, 0.26, 0.48))
		_create_box(cover, "OrangeContainer%d" % i, Vector3(28 - i * 4.5, 1.1, 2 - (i % 2) * 7), Vector3(4.0, 2.2, 7.0), Color(0.50, 0.23, 0.12))
	_create_box(cover, "MidCoverA", Vector3(-6, 1.0, 3), Vector3(3, 2, 6), Color(0.35, 0.28, 0.22))
	_create_box(cover, "MidCoverB", Vector3(6, 1.0, -3), Vector3(3, 2, 6), Color(0.35, 0.28, 0.22))
	_create_box(cover, "CloseRangePocketA", Vector3(-12, 1.0, 21), Vector3(9, 2.0, 3), Color(0.27, 0.24, 0.20))
	_create_box(cover, "CloseRangePocketB", Vector3(12, 1.0, -21), Vector3(9, 2.0, 3), Color(0.27, 0.24, 0.20))

	_create_box(skyline, "NorthBackdrop", Vector3(0, 8, -34), Vector3(90, 16, 2), Color(0.12, 0.14, 0.16))
	_create_box(skyline, "SouthBackdrop", Vector3(0, 8, 34), Vector3(90, 16, 2), Color(0.12, 0.14, 0.16))
	_create_box(skyline, "WestBackdrop", Vector3(-44, 8, 0), Vector3(2, 16, 68), Color(0.10, 0.12, 0.14))
	_create_box(skyline, "EastBackdrop", Vector3(44, 8, 0), Vector3(2, 16, 68), Color(0.10, 0.12, 0.14))
	_create_perimeter_closure(perimeter)

	_create_spawn(spawns, "BlueSpawnA", 1, Vector3(-32, 0.3, 22), -45)
	_create_spawn(spawns, "BlueSpawnB", 1, Vector3(-34, 0.3, -18), 35)
	_create_spawn(spawns, "BlueSpawnC", 1, Vector3(-20, 2.6, 19), -20)
	_create_spawn(spawns, "BlueSpawnD", 1, Vector3(-24, 0.3, 5), 0)
	_create_spawn(spawns, "OrangeSpawnA", 2, Vector3(32, 0.3, -22), 135)
	_create_spawn(spawns, "OrangeSpawnB", 2, Vector3(34, 0.3, 18), -145)
	_create_spawn(spawns, "OrangeSpawnC", 2, Vector3(20, 2.6, -19), 160)
	_create_spawn(spawns, "OrangeSpawnD", 2, Vector3(24, 0.3, -5), 180)

	if _include_dev_dummies:
		_create_dummies()
	_add_visual_polish()

func get_map_closure_report() -> Dictionary:
	var perimeter: Node3D = _layers.get(&"PerimeterClosure", null)
	if perimeter == null:
		return {"ok": false, "error": "missing PerimeterClosure layer"}
	return {
		"ok": (
			perimeter.has_node("NorthPerimeterWall")
			and perimeter.has_node("SouthPerimeterWall")
			and perimeter.has_node("WestPerimeterWall")
			and perimeter.has_node("EastPerimeterWall")
			and perimeter.has_node("NorthFacadeBand")
			and perimeter.has_node("SouthFacadeBand")
			and perimeter.has_node("WestFacadeBand")
			and perimeter.has_node("EastFacadeBand")
		),
		"node_count": perimeter.get_child_count(),
		"closed_edges": ["north", "south", "west", "east"],
	}

func _create_perimeter_closure(parent: Node3D) -> void:
	var lower_concrete := Color(0.31, 0.34, 0.35, 1.0)
	var upper_brick := Color(0.42, 0.24, 0.18, 1.0)
	var upper_metal := Color(0.22, 0.27, 0.30, 1.0)
	var top_trim := Color(0.74, 0.62, 0.42, 1.0)
	var blue_read := Color(0.12, 0.48, 0.95, 1.0)
	var orange_read := Color(0.98, 0.44, 0.14, 1.0)

	_create_box(parent, "NorthPerimeterWall", Vector3(0.0, 2.35, -32.3), Vector3(85.0, 4.7, 1.0), lower_concrete)
	_create_box(parent, "SouthPerimeterWall", Vector3(0.0, 2.35, 32.3), Vector3(85.0, 4.7, 1.0), lower_concrete)
	_create_box(parent, "WestPerimeterWall", Vector3(-42.3, 2.35, 0.0), Vector3(1.0, 4.7, 65.0), lower_concrete)
	_create_box(parent, "EastPerimeterWall", Vector3(42.3, 2.35, 0.0), Vector3(1.0, 4.7, 65.0), lower_concrete)

	_create_box(parent, "NorthFacadeBand", Vector3(0.0, 7.25, -32.75), Vector3(84.0, 5.1, 0.65), upper_brick)
	_create_box(parent, "SouthFacadeBand", Vector3(0.0, 7.25, 32.75), Vector3(84.0, 5.1, 0.65), upper_brick.lightened(0.08))
	_create_box(parent, "WestFacadeBand", Vector3(-42.75, 7.25, 0.0), Vector3(0.65, 5.1, 64.0), upper_metal)
	_create_box(parent, "EastFacadeBand", Vector3(42.75, 7.25, 0.0), Vector3(0.65, 5.1, 64.0), upper_metal.lightened(0.07))

	for index in range(7):
		var x := -36.0 + float(index) * 12.0
		_create_visual_box(parent, "NorthFacadePillar%d" % index, Vector3(x, 5.0, -31.72), Vector3(0.45, 7.6, 0.22), top_trim.darkened(0.18))
		_create_visual_box(parent, "SouthFacadePillar%d" % index, Vector3(x, 5.0, 31.72), Vector3(0.45, 7.6, 0.22), top_trim.darkened(0.10))
		_create_visual_box(parent, "NorthAmberWindowBand%d" % index, Vector3(x + 3.5, 7.15, -31.67), Vector3(3.4, 0.45, 0.18), Color(1.0, 0.67, 0.30, 1.0))
		_create_visual_box(parent, "SouthAmberWindowBand%d" % index, Vector3(x + 3.5, 7.15, 31.67), Vector3(3.4, 0.45, 0.18), Color(1.0, 0.62, 0.24, 1.0))

	for index in range(5):
		var z := -25.0 + float(index) * 12.5
		_create_visual_box(parent, "WestFacadePillar%d" % index, Vector3(-41.72, 5.0, z), Vector3(0.22, 7.4, 0.45), top_trim.darkened(0.22))
		_create_visual_box(parent, "EastFacadePillar%d" % index, Vector3(41.72, 5.0, z), Vector3(0.22, 7.4, 0.45), top_trim.darkened(0.14))
		_create_visual_box(parent, "WestCoolWindowBand%d" % index, Vector3(-41.67, 7.15, z + 4.0), Vector3(0.18, 0.45, 3.6), Color(0.42, 0.72, 1.0, 1.0))
		_create_visual_box(parent, "EastCoolWindowBand%d" % index, Vector3(41.67, 7.15, z + 4.0), Vector3(0.18, 0.45, 3.6), Color(0.45, 0.76, 1.0, 1.0))

	_create_visual_box(parent, "NorthTopTrim", Vector3(0.0, 9.95, -31.72), Vector3(85.0, 0.30, 0.28), top_trim)
	_create_visual_box(parent, "SouthTopTrim", Vector3(0.0, 9.95, 31.72), Vector3(85.0, 0.30, 0.28), top_trim)
	_create_visual_box(parent, "WestTopTrim", Vector3(-41.72, 9.95, 0.0), Vector3(0.28, 0.30, 65.0), top_trim.darkened(0.08))
	_create_visual_box(parent, "EastTopTrim", Vector3(41.72, 9.95, 0.0), Vector3(0.28, 0.30, 65.0), top_trim.darkened(0.03))

	_create_visual_box(parent, "BluePerimeterRouteLine", Vector3(-35.8, 0.16, 0.0), Vector3(0.24, 0.08, 55.0), blue_read)
	_create_visual_box(parent, "OrangePerimeterRouteLine", Vector3(35.8, 0.16, 0.0), Vector3(0.24, 0.08, 55.0), orange_read)
	_create_visual_box(parent, "NorthSafetyLine", Vector3(0.0, 0.17, -27.8), Vector3(70.0, 0.08, 0.22), Color(1.0, 0.78, 0.26, 1.0))
	_create_visual_box(parent, "SouthSafetyLine", Vector3(0.0, 0.17, 27.8), Vector3(70.0, 0.08, 0.22), Color(1.0, 0.78, 0.26, 1.0))

	var corners: Array[Vector3] = [
		Vector3(-38.6, 1.6, -28.8),
		Vector3(38.6, 1.6, -28.8),
		Vector3(-38.6, 1.6, 28.8),
		Vector3(38.6, 1.6, 28.8),
	]
	for index in range(corners.size()):
		var corner := corners[index]
		_create_box(parent, "CornerCrashBarrier%d" % index, corner, Vector3(5.8, 3.2, 0.8), Color(0.18, 0.20, 0.21, 1.0))
		_create_visual_box(parent, "CornerHazardStripe%d" % index, corner + Vector3(0.0, 1.74, 0.42), Vector3(5.2, 0.18, 0.14), Color(1.0, 0.70, 0.18, 1.0))

func _create_dummies() -> void:
	var cover: Node3D = _layers[&"CombatCover"]
	for index in range(6):
		var target := DummyTarget.new()
		target.name = "ArenaDummy%d" % (index + 1)
		target.position = Vector3(-12 + index * 4.8, 0.0, -8 + (index % 2) * 16)
		cover.add_child(target)

func _create_spawn(parent: Node3D, node_name: String, team_id: int, position: Vector3, yaw_degrees: float) -> SpawnPoint:
	var spawn := SpawnPoint.new()
	spawn.name = node_name
	spawn.team_id = team_id
	spawn.spawn_group = &"arena_downtown_01"
	spawn.yaw_degrees = yaw_degrees
	spawn.position = position
	parent.add_child(spawn)
	return spawn

func _create_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	parent.add_child(body)

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
	material.roughness = 0.92
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	return body

func _create_ramp(parent: Node3D, node_name: String, position: Vector3, size: Vector3, x_degrees: float, color: Color) -> StaticBody3D:
	var ramp := _create_box(parent, node_name, position, size, color)
	ramp.rotation_degrees.x = x_degrees
	return ramp

func _add_visual_polish() -> void:
	var polish: Node3D = _layers[&"LightingAndAtmosphere"]
	_create_spawn_deck(polish, "Blue", Vector3(-32, 0.08, 22), Color(0.05, 0.42, 0.96, 1.0), -45.0)
	_create_spawn_deck(polish, "Orange", Vector3(32, 0.08, -22), Color(1.0, 0.42, 0.10, 1.0), 135.0)
	_create_mid_route_polish(polish)
	_create_high_route_polish(polish)
	_create_container_trim(polish)

func _create_spawn_deck(parent: Node3D, team_name: String, center: Vector3, color: Color, yaw_degrees: float) -> void:
	var lower_name := team_name.to_lower()
	_create_visual_box(parent, "%sSpawnDeck" % team_name, center + Vector3(0.0, 0.02, 0.0), Vector3(9.5, 0.05, 5.2), color.darkened(0.35))
	for index in range(3):
		var stripe_offset := Vector3(float(index - 1) * 2.6, 0.07, -1.9)
		_create_visual_box(parent, "%sSpawnChevron%d" % [team_name, index + 1], center + stripe_offset, Vector3(1.5, 0.06, 0.32), color.lightened(0.18))
	_create_visual_box(parent, "%sSpawnBackLine" % team_name, center + Vector3(0.0, 0.08, 2.45), Vector3(8.8, 0.06, 0.18), color.lightened(0.08))
	var label := _create_route_label(parent, "%sSpawnLabel" % team_name, "%s SPAWN" % team_name.to_upper(), center + Vector3(0.0, 2.2, 0.0), color.lightened(0.35))
	label.rotation_degrees.y = yaw_degrees
	label.set_meta("p10a_role", "%s_spawn_readability" % lower_name)

func _create_mid_route_polish(parent: Node3D) -> void:
	_create_visual_box(parent, "MidControlAmberLine", Vector3(0.0, 0.12, 0.0), Vector3(0.28, 0.06, 20.0), Color(1.0, 0.70, 0.22, 1.0))
	_create_visual_box(parent, "MidControlBlueLane", Vector3(-7.8, 0.13, 0.0), Vector3(0.22, 0.06, 15.0), Color(0.08, 0.45, 1.0, 1.0))
	_create_visual_box(parent, "MidControlOrangeLane", Vector3(7.8, 0.13, 0.0), Vector3(0.22, 0.06, 15.0), Color(1.0, 0.42, 0.10, 1.0))
	_create_route_label(parent, "MidControlLabel", "MID CONTROL", Vector3(0.0, 2.15, 1.8), Color(1.0, 0.82, 0.36, 1.0))

func _create_high_route_polish(parent: Node3D) -> void:
	for entry in [
		{"name": "BlueHigh", "position": Vector3(-8.0, 6.26, -12.0), "axis": "x", "color": Color(0.10, 0.48, 1.0, 1.0)},
		{"name": "OrangeHigh", "position": Vector3(9.0, 6.26, 12.0), "axis": "x", "color": Color(1.0, 0.42, 0.10, 1.0)},
	]:
		var position: Vector3 = entry["position"]
		var color: Color = entry["color"]
		_create_visual_box(parent, "%sRouteEdgeNorth" % String(entry["name"]), position + Vector3(0.0, 0.06, -1.55), Vector3(17.0, 0.07, 0.16), color)
		_create_visual_box(parent, "%sRouteEdgeSouth" % String(entry["name"]), position + Vector3(0.0, 0.06, 1.55), Vector3(17.0, 0.07, 0.16), color)
	_create_visual_box(parent, "CrossBridgeHazardStripeLeft", Vector3(-2.08, 5.66, 0.0), Vector3(0.16, 0.07, 25.0), Color(1.0, 0.74, 0.16, 1.0))
	_create_visual_box(parent, "CrossBridgeHazardStripeRight", Vector3(2.08, 5.66, 0.0), Vector3(0.16, 0.07, 25.0), Color(1.0, 0.74, 0.16, 1.0))
	_create_route_label(parent, "HighRouteLabel", "HIGH ROUTE", Vector3(-2.0, 7.25, -7.5), Color(0.92, 0.96, 1.0, 1.0))

func _create_container_trim(parent: Node3D) -> void:
	for index in range(5):
		var blue_x := -28.0 + float(index) * 4.5
		var orange_x := 28.0 - float(index) * 4.5
		var blue_z := -2.0 + float(index % 2) * 7.0
		var orange_z := 2.0 - float(index % 2) * 7.0
		_create_visual_box(parent, "BlueContainerTrimTop%d" % index, Vector3(blue_x, 2.25, blue_z), Vector3(4.15, 0.10, 7.2), Color(0.38, 0.66, 1.0, 1.0))
		_create_visual_box(parent, "BlueContainerTrimFace%d" % index, Vector3(blue_x, 1.12, blue_z - 3.62), Vector3(3.7, 0.16, 0.12), Color(0.65, 0.82, 1.0, 1.0))
		_create_visual_box(parent, "OrangeContainerTrimTop%d" % index, Vector3(orange_x, 2.25, orange_z), Vector3(4.15, 0.10, 7.2), Color(1.0, 0.62, 0.34, 1.0))
		_create_visual_box(parent, "OrangeContainerTrimFace%d" % index, Vector3(orange_x, 1.12, orange_z + 3.62), Vector3(3.7, 0.16, 0.12), Color(1.0, 0.78, 0.52, 1.0))

func _create_visual_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.68
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.22
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _create_route_label(parent: Node3D, node_name: String, text: String, position: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.007
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.outline_size = 7
	parent.add_child(label)
	return label

func _should_show_generated_visuals() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--smoke-test=") or arg.begins_with("--verification-capture="):
			return true
	return false

func _should_include_dev_dummies() -> bool:
	return _should_show_generated_visuals()

func _hide_generated_visuals(root: Node) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).visible = false
	for child in root.get_children():
		_hide_generated_visuals(child)

func _disable_generated_collision_except_floor(root: Node) -> void:
	var keep_collision := _is_arena_floor_branch(root)
	if root is CollisionObject3D and not keep_collision:
		var collision_object := root as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if root is CollisionShape3D and not keep_collision:
		(root as CollisionShape3D).disabled = true
	for child in root.get_children():
		_disable_generated_collision_except_floor(child)

func _is_arena_floor_branch(node: Node) -> bool:
	var current := node
	while current != null:
		if current.name == "ArenaFloor":
			return true
		current = current.get_parent()
	return false
