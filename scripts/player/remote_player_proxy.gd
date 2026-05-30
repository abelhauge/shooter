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
const REMOTE_WEAPON_ATTACHMENT_NAMES := ["Wrist.R", "LowerArm.R"]
const REMOTE_WEAPON_TRANSFORM_BY_SLOT := {
	&"primary": {
		"position": Vector3(0.02, -0.04, -0.03),
		"rotation": Vector3(-8.0, 180.0, 0.0),
		"scale": Vector3(0.18, 0.18, 0.18),
	},
	&"secondary": {
		"position": Vector3(0.035, -0.02, -0.045),
		"rotation": Vector3(84.0, -78.0, -8.0),
		"scale": Vector3(0.055, 0.055, 0.055),
	},
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
var player_name := "Player"

@onready var label: Label3D = $Label3D
@onready var body: MeshInstance3D = $Body
@onready var weapon_box: MeshInstance3D = $WeaponBox

var _avatar_root: Node3D
var _remote_weapon_root: Node3D
var _remote_weapon_socket: BoneAttachment3D
var _animation_player: AnimationPlayer
var _avatar_source_path := ""
var _avatar_vertex_count := 0
var _active_animation := ""
var _available_animations: Array[String] = []
var _remote_weapon_source_path := ""
var _remote_weapon_vertex_count := 0
var _remote_weapon_attachment_name := ""
var _remote_weapon_attached_to_avatar := false
var _snapshot_count := 0
var _headless_visuals := false
var _previous_position := Vector3.ZERO
var _remote_speed_mps := 0.0
var _movement_animation_hold_sec := 0.0

func _ready() -> void:
	_headless_visuals = _should_skip_remote_visuals()
	target_position = global_position
	_previous_position = global_position
	_avatar_root = Node3D.new()
	_avatar_root.name = "AvatarRoot"
	add_child(_avatar_root)
	_remote_weapon_root = Node3D.new()
	_remote_weapon_root.name = "RemoteWeaponRoot"
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
	_movement_animation_hold_sec = maxf(0.0, _movement_animation_hold_sec - delta)
	visible = is_alive
	if show_debug_label:
		label.text = "%s  #%d  T%d\n%s\n%s  %.0f HP" % [player_name, peer_id, team_id, String(movement_state), String(active_slot), health]
	else:
		label.text = player_name
	label.visible = is_alive and player_name != ""
	_update_animation()

func set_player_name(next_player_name: String) -> void:
	player_name = _sanitize_player_name(next_player_name)
	if label != null:
		label.text = player_name

func apply_snapshot(position: Vector3, yaw: float, pitch: float, state: StringName, slot: StringName) -> void:
	if target_position.distance_to(position) > 0.08:
		_movement_animation_hold_sec = 1.0
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
		"player_name": player_name,
		"team_id": team_id,
		"team_name": TEAM_NAME_BY_ID.get(team_id, "unknown"),
		"source_asset_path": _avatar_source_path,
		"has_humanoid_mesh": _avatar_vertex_count > 0,
		"avatar_vertex_count": _avatar_vertex_count,
		"avatar_yaw_correction_degrees": AVATAR_YAW_CORRECTION_DEGREES,
		"has_animation_player": _animation_player != null,
		"active_animation": _active_animation,
		"available_animations": _available_animations,
		"has_team_marker_plates": false,
		"remote_weapon_source_path": _remote_weapon_source_path,
		"has_remote_weapon_asset": _remote_weapon_vertex_count > 0,
		"remote_weapon_vertex_count": _remote_weapon_vertex_count,
		"remote_weapon_attachment_name": _remote_weapon_attachment_name,
		"remote_weapon_attached_to_avatar": _remote_weapon_attached_to_avatar,
		"uses_fallback_body": body.visible,
		"uses_fallback_weapon_box": weapon_box.visible,
		"snapshot_count": _snapshot_count,
		"target_position": target_position,
		"target_yaw": target_yaw,
		"current_yaw": rotation.y,
		"remote_speed_mps": _remote_speed_mps,
		"movement_animation_hold_sec": _movement_animation_hold_sec,
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
	_available_animations = []
	_remote_weapon_attachment_name = ""
	_remote_weapon_attached_to_avatar = false
	_remote_weapon_socket = null
	if _remote_weapon_root != null and _remote_weapon_root.get_parent() != self:
		_remote_weapon_root.reparent(self, false)
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
	_available_animations = _collect_animation_names(_animation_player)
	_configure_animation_loops()
	_attach_weapon_root_to_avatar(avatar)
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
	_remote_weapon_attached_to_avatar = _remote_weapon_root.get_parent() != self
	if _headless_visuals or not REMOTE_WEAPON_PATH_BY_SLOT.has(active_slot):
		return
	var weapon := _load_gltf_scene(REMOTE_WEAPON_PATH_BY_SLOT[active_slot], "Remote weapon GLB import failed")
	if weapon == null:
		return
	weapon.name = "RemoteWeapon_%s" % String(active_slot)
	var transform_data: Dictionary = REMOTE_WEAPON_TRANSFORM_BY_SLOT.get(active_slot, {})
	weapon.position = transform_data.get("position", Vector3.ZERO)
	weapon.rotation_degrees = transform_data.get("rotation", Vector3.ZERO)
	weapon.scale = transform_data.get("scale", Vector3(0.1, 0.1, 0.1))
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

func _collect_animation_names(animation_player: AnimationPlayer) -> Array[String]:
	var names: Array[String] = []
	if animation_player == null:
		return names
	for animation_name in animation_player.get_animation_list():
		names.append(String(animation_name))
	return names

func _configure_animation_loops() -> void:
	if _animation_player == null:
		return
	for animation_name in ["Idle", "Idle_Gun", "Idle_Gun_Pointing", "Run", "Run_Back", "Run_Left", "Run_Right", "Run_Shoot", "Walk", "Roll"]:
		if _animation_player.has_animation(animation_name):
			var animation := _animation_player.get_animation(animation_name)
			if animation != null:
				animation.loop_mode = Animation.LOOP_LINEAR

func _attach_weapon_root_to_avatar(avatar: Node) -> void:
	if _remote_weapon_root == null:
		return
	var skeleton := _find_skeleton(avatar)
	var bone_name := _first_existing_bone_name(skeleton, REMOTE_WEAPON_ATTACHMENT_NAMES)
	if skeleton != null and bone_name != "":
		_remote_weapon_socket = BoneAttachment3D.new()
		_remote_weapon_socket.name = "RemoteWeaponSocket"
		_remote_weapon_socket.bone_name = bone_name
		skeleton.add_child(_remote_weapon_socket)
		_remote_weapon_root.reparent(_remote_weapon_socket, false)
		_remote_weapon_root.position = Vector3.ZERO
		_remote_weapon_root.rotation_degrees = Vector3.ZERO
		_remote_weapon_root.scale = Vector3.ONE
		_remote_weapon_attachment_name = bone_name
		_remote_weapon_attached_to_avatar = true
	else:
		_remote_weapon_root.reparent(self, false)
		_remote_weapon_root.position = Vector3(0.28, 1.20, -0.34)
		_remote_weapon_root.rotation_degrees = Vector3(-5.0, 0.0, -3.0)
		_remote_weapon_root.scale = Vector3.ONE
		_remote_weapon_attachment_name = ""
		_remote_weapon_attached_to_avatar = false

func _find_skeleton(root_node: Node) -> Skeleton3D:
	if root_node is Skeleton3D:
		return root_node as Skeleton3D
	for child in root_node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _first_existing_bone_name(skeleton: Skeleton3D, bone_names: Array) -> String:
	if skeleton == null:
		return ""
	for bone_name in bone_names:
		if skeleton.find_bone(String(bone_name)) >= 0:
			return String(bone_name)
	return ""

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
	if movement_state == &"airborne":
		return _first_existing_animation(["Roll", "Run", "Idle_Gun_Pointing"])
	if movement_state == &"sliding" or movement_state == &"wallrunning":
		return _first_existing_animation(["Run", "Run_Shoot", "Idle_Gun"])
	if _remote_speed_mps > 0.35 or _movement_animation_hold_sec > 0.0:
		return _first_existing_animation(["Run", "Run_Shoot", "Walk"])
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

func _sanitize_player_name(raw_name: String) -> String:
	var sanitized := ""
	for index in range(raw_name.length()):
		var character := raw_name.substr(index, 1)
		if character >= "a" and character <= "z":
			sanitized += character
		elif character >= "A" and character <= "Z":
			sanitized += character
		elif character >= "0" and character <= "9":
			sanitized += character
		elif character == "_" or character == "-":
			sanitized += character
		elif character == " " and sanitized.length() > 0 and not sanitized.ends_with(" "):
			sanitized += character
		if sanitized.length() >= 18:
			break
	sanitized = sanitized.strip_edges()
	return sanitized if sanitized != "" else "Player"
