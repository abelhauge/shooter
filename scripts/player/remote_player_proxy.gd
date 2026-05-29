class_name RemotePlayerProxy
extends Node3D

const AVATAR_PATH_BY_TEAM := {
	1: "res://assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF/Swat.gltf",
	2: "res://assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF/Worker.gltf",
}
const TEAM_COLOR_BY_ID := {
	1: Color(0.10, 0.42, 1.0, 1.0),
	2: Color(1.0, 0.42, 0.10, 1.0),
}
const TEAM_NAME_BY_ID := {
	1: "blue",
	2: "orange",
}

@export var interpolation_sec := NetworkConstants.REMOTE_INTERPOLATION_SEC
@export var show_debug_label := false

var peer_id := 0
var target_position := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
var movement_state: StringName = &"airborne"
var active_slot: StringName = &"primary"
var team_id := 0
var health := 100.0
var is_alive := true

@onready var label: Label3D = $Label3D
@onready var body: MeshInstance3D = $Body
@onready var weapon_box: MeshInstance3D = $WeaponBox

var _avatar_root: Node3D
var _team_color_root: Node3D
var _avatar_source_path := ""
var _avatar_vertex_count := 0
var _snapshot_count := 0
var _headless_visuals := false

func _ready() -> void:
	_headless_visuals = _should_skip_remote_visuals()
	target_position = global_position
	_avatar_root = Node3D.new()
	_avatar_root.name = "AvatarRoot"
	add_child(_avatar_root)
	_team_color_root = Node3D.new()
	_team_color_root.name = "TeamColorRoot"
	add_child(_team_color_root)
	if _headless_visuals:
		_disable_headless_meshes()
	label.visible = show_debug_label

func _process(delta: float) -> void:
	var t := 1.0 if interpolation_sec <= 0.0 else clampf(delta / interpolation_sec, 0.0, 1.0)
	global_position = global_position.lerp(target_position, t)
	rotation.y = lerp_angle(rotation.y, target_yaw, t)
	visible = is_alive
	label.text = "Peer %d  T%d\n%s\n%s  %.0f HP" % [peer_id, team_id, String(movement_state), String(active_slot), health]
	label.visible = show_debug_label

func apply_snapshot(position: Vector3, yaw: float, pitch: float, state: StringName, slot: StringName) -> void:
	target_position = position
	target_yaw = yaw
	target_pitch = pitch
	movement_state = state
	active_slot = slot
	_snapshot_count += 1

func apply_combat_state(next_team_id: int, next_health: float, next_is_alive: bool) -> void:
	if team_id != next_team_id:
		_load_team_avatar(next_team_id)
		_rebuild_team_color_markers(next_team_id)
	team_id = next_team_id
	health = next_health
	is_alive = next_is_alive

func get_runtime_summary() -> Dictionary:
	return {
		"peer_id": peer_id,
		"team_id": team_id,
		"team_name": TEAM_NAME_BY_ID.get(team_id, "unknown"),
		"source_asset_path": _avatar_source_path,
		"has_humanoid_mesh": _avatar_vertex_count > 0,
		"avatar_vertex_count": _avatar_vertex_count,
		"uses_fallback_body": body.visible,
		"snapshot_count": _snapshot_count,
		"target_position": target_position,
		"target_yaw": target_yaw,
		"current_yaw": rotation.y,
		"is_alive": is_alive,
		"debug_label_visible": label.visible,
	}

func _load_team_avatar(next_team_id: int) -> void:
	if _avatar_root == null or not AVATAR_PATH_BY_TEAM.has(next_team_id):
		return
	for child in _avatar_root.get_children():
		child.queue_free()
	_avatar_source_path = AVATAR_PATH_BY_TEAM[next_team_id]
	_avatar_vertex_count = 0
	if _headless_visuals:
		body.visible = false
		return
	var avatar := _load_avatar_scene(_avatar_source_path)
	if avatar == null:
		body.visible = true
		return
	avatar.name = "TeamAvatar"
	avatar.scale = Vector3(0.9, 0.9, 0.9)
	_avatar_root.add_child(avatar)
	_avatar_vertex_count = _count_mesh_vertices(avatar)
	body.visible = false

func _load_avatar_scene(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		push_error("Remote humanoid GLTF import failed for %s: %s" % [path, error_string(error)])
		return null
	return document.generate_scene(state) as Node3D

func _rebuild_team_color_markers(next_team_id: int) -> void:
	if _team_color_root == null:
		return
	for child in _team_color_root.get_children():
		child.queue_free()
	if _headless_visuals:
		return
	var color: Color = TEAM_COLOR_BY_ID.get(next_team_id, Color.WHITE)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.45
	material.roughness = 0.55
	_add_team_plate("TeamChestPlate", Vector3(0.0, 1.14, -0.34), Vector3(0.48, 0.28, 0.06), material)
	_add_team_plate("TeamBackPlate", Vector3(0.0, 1.14, 0.34), Vector3(0.48, 0.28, 0.06), material)
	_add_team_plate("TeamShoulderLeft", Vector3(-0.38, 1.38, -0.04), Vector3(0.13, 0.13, 0.34), material)
	_add_team_plate("TeamShoulderRight", Vector3(0.38, 1.38, -0.04), Vector3(0.13, 0.13, 0.34), material)

func _add_team_plate(node_name: String, position: Vector3, size: Vector3, material: Material) -> void:
	var marker := MeshInstance3D.new()
	marker.name = node_name
	marker.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	marker.mesh = mesh
	marker.material_override = material
	_team_color_root.add_child(marker)

func _count_mesh_vertices(root: Node) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mesh := (root as MeshInstance3D).mesh
		if mesh != null:
			count += maxi(1, mesh.get_surface_count())
	for child in root.get_children():
		count += _count_mesh_vertices(child)
	return count

func _disable_headless_meshes() -> void:
	body.visible = false
	body.mesh = null
	body.material_override = null
	weapon_box.visible = false
	weapon_box.mesh = null
	weapon_box.material_override = null

func _should_skip_remote_visuals() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	for arg in OS.get_cmdline_user_args():
		if arg == "--verification-capture=p12-client" or arg == "--verification-capture=p13-client":
			return true
	return false
