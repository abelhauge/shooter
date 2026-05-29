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
const REMOTE_WEAPON_PATH_BY_SLOT := {
	&"primary": "res://assets/weapons/viewmodels/generated/rifle_from_fbx.glb",
	&"secondary": "res://assets/weapons/viewmodels/generated/pistol_from_fbx.glb",
}
const AVATAR_YAW_CORRECTION_DEGREES := 180.0

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
var _remote_weapon_root: Node3D
var _animation_player: AnimationPlayer
var _avatar_source_path := ""
var _avatar_vertex_count := 0
var _active_animation := ""
var _remote_weapon_source_path := ""
var _remote_weapon_vertex_count := 0
var _snapshot_count := 0
var _headless_visuals := false
var _previous_position := Vector3.ZERO
var _remote_speed_mps := 0.0

func _ready() -> void:
	_headless_visuals = _should_skip_remote_visuals()
	target_position = global_position
	_previous_position = global_position
	_avatar_root = Node3D.new()
	_avatar_root.name = "AvatarRoot"
	add_child(_avatar_root)
	_remote_weapon_root = Node3D.new()
	_remote_weapon_root.name = "RemoteWeaponRoot"
	_remote_weapon_root.position = Vector3(0.25, 1.18, -0.34)
	_remote_weapon_root.rotation_degrees = Vector3(-8.0, 180.0, 0.0)
	_remote_weapon_root.scale = Vector3.ONE
	add_child(_remote_weapon_root)
	weapon_box.visible = false
	if _headless_visuals:
		_disable_headless_meshes()
	label.visible = show_debug_label

func _process(delta: float) -> void:
	var t := 1.0 if interpolation_sec <= 0.0 else clampf(delta / interpolation_sec, 0.0, 1.0)
	global_position = global_position.lerp(target_position, t)
	rotation.y = lerp_angle(rotation.y, target_yaw, t)
	_remote_speed_mps = global_position.distance_to(_previous_position) / maxf(delta, 0.001)
	_previous_position = global_position
	visible = is_alive
	label.text = "Peer %d  T%d\n%s\n%s  %.0f HP" % [peer_id, team_id, String(movement_state), String(active_slot), health]
	label.visible = show_debug_label
	_update_animation()

func apply_snapshot(position: Vector3, yaw: float, pitch: float, state: StringName, slot: StringName) -> void:
	target_position = position
	target_yaw = yaw
	target_pitch = pitch
	movement_state = state
	if active_slot != slot:
		active_slot = slot
		_refresh_remote_weapon()
	_snapshot_count += 1

func apply_combat_state(next_team_id: int, next_health: float, next_is_alive: bool) -> void:
	if team_id != next_team_id:
		_load_team_avatar(next_team_id)
	team_id = next_team_id
	health = next_health
	is_alive = next_is_alive
	_update_animation()

func get_runtime_summary() -> Dictionary:
	return {
		"peer_id": peer_id,
		"team_id": team_id,
		"team_name": TEAM_NAME_BY_ID.get(team_id, "unknown"),
		"source_asset_path": _avatar_source_path,
		"has_humanoid_mesh": _avatar_vertex_count > 0,
		"avatar_vertex_count": _avatar_vertex_count,
		"avatar_yaw_correction_degrees": AVATAR_YAW_CORRECTION_DEGREES,
		"has_animation_player": _animation_player != null,
		"active_animation": _active_animation,
		"has_team_marker_plates": false,
		"remote_weapon_source_path": _remote_weapon_source_path,
		"has_remote_weapon_asset": _remote_weapon_vertex_count > 0,
		"remote_weapon_vertex_count": _remote_weapon_vertex_count,
		"uses_fallback_body": body.visible,
		"uses_fallback_weapon_box": weapon_box.visible,
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
	_animation_player = null
	_active_animation = ""
	if _headless_visuals:
		body.visible = false
		return
	var avatar := _load_avatar_scene(_avatar_source_path)
	if avatar == null:
		body.visible = true
		return
	avatar.name = "TeamAvatar"
	avatar.scale = Vector3(0.9, 0.9, 0.9)
	avatar.rotation_degrees.y = AVATAR_YAW_CORRECTION_DEGREES
	_avatar_root.add_child(avatar)
	_hide_embedded_weapon_meshes(avatar)
	_animation_player = _find_animation_player(avatar)
	_avatar_vertex_count = _count_mesh_vertices(avatar)
	body.visible = false
	_update_animation()
	_refresh_remote_weapon()

func _load_avatar_scene(path: String) -> Node3D:
	return _load_gltf_scene(path, "Remote humanoid GLTF import failed")

func _refresh_remote_weapon() -> void:
	if _remote_weapon_root == null:
		return
	for child in _remote_weapon_root.get_children():
		child.queue_free()
	_remote_weapon_source_path = ""
	_remote_weapon_vertex_count = 0
	weapon_box.visible = false
	if _headless_visuals or not REMOTE_WEAPON_PATH_BY_SLOT.has(active_slot):
		return
	var weapon := _load_gltf_scene(REMOTE_WEAPON_PATH_BY_SLOT[active_slot], "Remote weapon GLB import failed")
	if weapon == null:
		return
	weapon.name = "RemoteWeapon_%s" % String(active_slot)
	weapon.position = Vector3.ZERO
	weapon.rotation_degrees = Vector3.ZERO
	weapon.scale = Vector3(0.16, 0.16, 0.16) if active_slot == &"primary" else Vector3(0.055, 0.055, 0.055)
	_remote_weapon_root.add_child(weapon)
	_remote_weapon_source_path = REMOTE_WEAPON_PATH_BY_SLOT[active_slot]
	_remote_weapon_vertex_count = _count_mesh_vertices(weapon)

func _load_gltf_scene(path: String, error_context: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		push_error("%s for %s: %s" % [error_context, path, error_string(error)])
		return null
	return document.generate_scene(state) as Node3D

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

func _update_animation() -> void:
	if _animation_player == null:
		return
	var target_animation := _select_animation_name()
	if target_animation == "" or _active_animation == target_animation:
		return
	_animation_player.play(target_animation)
	_active_animation = target_animation

func _select_animation_name() -> String:
	if not is_alive or movement_state == &"dead":
		return _first_existing_animation(["Death"])
	if movement_state == &"stunned":
		return _first_existing_animation(["HitRecieve", "Idle_Gun"])
	if movement_state == &"sliding" or movement_state == &"wallrunning":
		return _first_existing_animation(["Run", "Run_Shoot", "Idle_Gun"])
	if _remote_speed_mps > 0.35:
		return _first_existing_animation(["Run_Shoot", "Run", "Walk"])
	return _first_existing_animation(["Idle_Gun_Pointing", "Idle_Gun", "Idle"])

func _first_existing_animation(candidates: Array[String]) -> String:
	if _animation_player == null:
		return ""
	for candidate in candidates:
		if _animation_player.has_animation(candidate):
			return candidate
	return ""

func _hide_embedded_weapon_meshes(root: Node) -> void:
	if root is MeshInstance3D and String(root.name).to_lower().contains("pistol"):
		(root as MeshInstance3D).visible = false
	for child in root.get_children():
		_hide_embedded_weapon_meshes(child)

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
