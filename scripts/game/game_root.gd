extends Node3D

const PLAYER_SCENE := preload("res://scenes/player/player_controller.tscn")
const ARENA_SCENE := preload("res://scenes/maps/art/arena_downtown_01_art.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const REMOTE_PROXY_SCENE := preload("res://scenes/player/remote_player_proxy.tscn")
const SMOKE_VOLUME_SCENE := preload("res://scenes/fx/smoke_volume.tscn")
const GRENADE_EXPLOSION_MARKER_SCENE := preload("res://scenes/fx/grenade_explosion_marker.tscn")
const DEFAULT_ROOFTOP_CONFIG := preload("res://data/maps/arena_downtown_01_rooftop_config.tres")
const BALANCE_DUMMY_FORWARD_DISTANCES_M := [5.0, 7.0, 9.0, 12.0]
const BALANCE_DUMMY_SIDE_OFFSETS_M := [0.0, -2.5, 2.5, -5.0, 5.0]

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var map_root: Node3D = $MapRoot
@onready var players_root: Node3D = $PlayersRoot
@onready var projectiles_root: Node3D = $ProjectilesRoot
@onready var effects_root: Node3D = $EffectsRoot
@onready var match_director: MatchDirector = $MatchDirector

var local_player: PlayerController
var hud: CanvasLayer
var active_map: Node3D
var network_session: NetworkSession
var selected_loadout: LoadoutDefinition = preload("res://data/loadouts/default_v1_loadout.tres")
var remote_proxies: Dictionary = {}
var _arena_spawn_points: Array[SpawnPoint] = []
var _network_player_states: Dictionary = {}
var _network_weapon_states: Dictionary = {}
var _network_game_ready_peers: Dictionary = {}
var _weapon_definitions: Dictionary = {}
var _network_send_accum := 0.0
var _network_bound := false
var _capture_freeze_remote_proxies := false
var _rooftop_config: Resource
var _rooftop_fog_visual_root: Node3D
var _balance_dummy: DummyTarget
var _dev_balance_dummy_enabled := false
var _local_player_name := "Player"
var _network_player_names: Dictionary = {1: "Player"}

func _ready() -> void:
	_load_network_weapon_definitions()
	_spawn_map()
	_configure_rooftop_environment()
	_spawn_local_player()
	_bind_dummies()
	_start_offline_match()
	if _dev_balance_dummy_enabled:
		_spawn_balance_dummy()
	_spawn_hud()
	_bind_network_session()

func _physics_process(delta: float) -> void:
	_tick_network_weapon_states(delta)
	_tick_network_status_effects(delta)
	_tick_network_respawns(delta)
	_update_network_sync(delta)
	_tick_rooftop_hazard()

func set_network_session(session: NetworkSession) -> void:
	network_session = session
	if is_node_ready():
		_bind_network_session()

func set_network_peer_scene_ready(peer_id: int, is_ready: bool) -> void:
	if peer_id <= 0:
		return
	if is_ready:
		_network_game_ready_peers[peer_id] = true
	else:
		_network_game_ready_peers.erase(peer_id)
	if (
		is_ready
		and network_session != null
		and network_session.is_active()
		and multiplayer.is_server()
		and peer_id != network_session.local_peer_id()
	):
		_send_current_respawn_to_peer(peer_id)
		_send_authoritative_snapshot_to_peer(peer_id)

func set_selected_loadout(loadout: LoadoutDefinition) -> void:
	selected_loadout = loadout
	if local_player != null:
		local_player.get_weapon_controller().set_loadout_definition(selected_loadout)

func set_local_player_name(player_name: String) -> void:
	_local_player_name = _sanitize_player_name(player_name)
	if network_session != null:
		_network_player_names[network_session.local_peer_id()] = _local_player_name
	else:
		_network_player_names[1] = _local_player_name
	_update_local_player_state_name()

func set_network_player_names(player_names: Dictionary) -> void:
	for peer_id in player_names.keys():
		var sanitized := _sanitize_player_name(String(player_names[peer_id]))
		_network_player_names[int(peer_id)] = sanitized
		if _network_player_states.has(peer_id):
			(_network_player_states[peer_id] as Dictionary)["player_name"] = sanitized

func set_dev_balance_dummy_enabled(enabled: bool) -> void:
	_dev_balance_dummy_enabled = enabled
	if not is_node_ready():
		return
	if _dev_balance_dummy_enabled:
		_spawn_balance_dummy()
	elif _balance_dummy != null and is_instance_valid(_balance_dummy):
		_balance_dummy.queue_free()
		_balance_dummy = null

func get_runtime_smoke_summary() -> Dictionary:
	var team_counts := _build_network_team_counts()
	return {
		"has_local_player": local_player != null,
		"has_hud": hud != null,
		"has_active_map": active_map != null,
		"spawn_points": _arena_spawn_points.size(),
		"match_phase": match_director.match_phase if match_director != null else &"",
		"network_active": network_session != null and network_session.is_active(),
		"network_players": _network_player_states.size(),
		"remote_proxies": remote_proxies.size(),
		"team_counts": team_counts,
		"dev_balance_dummy_enabled": _dev_balance_dummy_enabled,
		"has_balance_dummy": _balance_dummy != null and is_instance_valid(_balance_dummy),
		"rooftop_ground_kill_height_y": _rooftop_config.ground_kill_height_y if _rooftop_config != null else 0.0,
	}

func smoke_seed_remote_player_for_hud(peer_id: int, player_name: String, team_id: int, kills: int, deaths: int) -> void:
	if peer_id <= 1:
		return
	var local_state := _ensure_network_player_state(1)
	local_state["player_name"] = _local_player_name
	local_state["team_id"] = 1
	local_state["position"] = local_player.global_position if local_player != null else Vector3.ZERO
	local_state["is_alive"] = local_player == null or local_player.get_health_component().is_alive
	var state := _ensure_network_player_state(peer_id)
	state["player_name"] = _sanitize_player_name(player_name)
	state["team_id"] = team_id
	state["kills"] = kills
	state["deaths"] = deaths
	state["health"] = 100.0
	state["is_alive"] = true
	var forward := -local_player.global_transform.basis.z if local_player != null else Vector3.FORWARD
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	state["position"] = local_player.global_position + forward.normalized() * 4.0 if local_player != null else Vector3(0.0, 18.0, 0.0)
	var proxy := _ensure_remote_proxy(peer_id)
	proxy.set_player_name(String(state["player_name"]))
	proxy.apply_snapshot(state["position"], 0.0, 0.0, &"idle", &"primary")
	proxy.apply_combat_state(team_id, 100.0, true)

func _build_network_team_counts() -> Dictionary:
	var team_counts := {}
	for state in _network_player_states.values():
		var team_id := int(state.get("team_id", 0))
		team_counts[team_id] = int(team_counts.get(team_id, 0)) + 1
	return team_counts

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

func _update_local_player_state_name() -> void:
	if network_session == null:
		if _network_player_states.has(1):
			(_network_player_states[1] as Dictionary)["player_name"] = _local_player_name
		return
	var local_peer_id := network_session.local_peer_id()
	_network_player_names[local_peer_id] = _local_player_name
	if _network_player_states.has(local_peer_id):
		(_network_player_states[local_peer_id] as Dictionary)["player_name"] = _local_player_name

func _build_spawn_capacity_by_team() -> Dictionary:
	var capacity := {}
	for spawn in _arena_spawn_points:
		if not spawn.is_enabled:
			continue
		var team_id := int(spawn.team_id)
		capacity[team_id] = int(capacity.get(team_id, 0)) + 1
	return capacity

func _build_network_spawn_report(required_player_count: int, required_per_team: int) -> Dictionary:
	var team_spawned_count := {}
	var players := []
	for peer_id in _network_player_states.keys():
		var state: Dictionary = _network_player_states[peer_id]
		var team_id := int(state.get("team_id", 0))
		var position: Vector3 = state.get("position", Vector3.ZERO)
		team_spawned_count[team_id] = int(team_spawned_count.get(team_id, 0)) + 1
		players.append({
			"peer_id": int(peer_id),
			"team_id": team_id,
			"position": position,
			"is_alive": bool(state.get("is_alive", false)),
			"health": float(state.get("health", 0.0)),
		})
	var spawn_capacity := _build_spawn_capacity_by_team()
	var teams_ok := true
	for team_id in [1, 2]:
		teams_ok = teams_ok and int(team_spawned_count.get(team_id, 0)) >= required_per_team
		teams_ok = teams_ok and int(spawn_capacity.get(team_id, 0)) >= required_per_team
	return {
		"ok": _network_player_states.size() >= required_player_count and teams_ok,
		"player_count": _network_player_states.size(),
		"required_player_count": required_player_count,
		"required_per_team": required_per_team,
		"team_spawned_count": team_spawned_count,
		"spawn_capacity_by_team": spawn_capacity,
		"players": players,
	}

func _build_p12_spawn_report() -> Dictionary:
	return _build_network_spawn_report(4, 1)

func _build_performance_report() -> Dictionary:
	return {
		"fps": Engine.get_frames_per_second(),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}

func run_runtime_smoke_check(include_weapon_fire: bool) -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	return local_player.get_weapon_controller().run_runtime_smoke_check(local_player.camera, include_weapon_fire)

func run_offline_system_smoke_check() -> Dictionary:
	if local_player == null or match_director == null:
		return {"ok": false, "error": "offline smoke missing player or match director"}
	var movement_result: Dictionary = local_player.run_runtime_movement_smoke_check()
	if not bool(movement_result.get("ok", false)):
		return movement_result
	var reload_result: Dictionary = local_player.get_weapon_controller().run_reload_interrupt_smoke_check()
	if not bool(reload_result.get("ok", false)):
		return reload_result
	var weapon_result: Dictionary = local_player.get_weapon_controller().run_runtime_smoke_check(local_player.camera, true)
	if not bool(weapon_result.get("ok", false)):
		return weapon_result
	var dummy_result := _run_dummy_score_smoke_check()
	if not bool(dummy_result.get("ok", false)):
		return dummy_result
	var respawn_result := _run_local_respawn_smoke_check()
	if not bool(respawn_result.get("ok", false)):
		return respawn_result
	var hud_result := _run_hud_smoke_check()
	if not bool(hud_result.get("ok", false)):
		return hud_result
	var art_result := _run_art_layer_smoke_check()
	if not bool(art_result.get("ok", false)):
		return art_result
	return {"ok": true}

func run_all_weapons_smoke_check(include_fire: bool) -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	return local_player.get_weapon_controller().run_all_weapons_runtime_smoke_check(local_player.camera, include_fire)

func get_p11_weapon_tuning_report() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	var weapon_controller := local_player.get_weapon_controller()
	return {
		"ok": true,
		"core_weapons": weapon_controller.get_weapon_tuning_snapshot([
			&"assault_rifle",
			&"handgun",
			&"knife",
			&"smoke_bomb",
		]),
	}

func get_p14_shotgun_tuning_report() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	var weapon_controller := local_player.get_weapon_controller()
	return {
		"ok": true,
		"shotgun": weapon_controller.get_weapon_tuning_snapshot([&"shotgun"]).get("shotgun", {}),
	}

func get_p14_sniper_tuning_report() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	var weapon_controller := local_player.get_weapon_controller()
	return {
		"ok": true,
		"sniper": weapon_controller.get_weapon_tuning_snapshot([&"sniper"]).get("sniper", {}),
	}

func get_p14_grenade_tuning_report() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"grenade")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "grenade select failed")}
	var definition := weapon_controller.get_active_definition()
	var grenade_tuning: Dictionary = weapon_controller.get_weapon_tuning_snapshot([&"grenade"]).get("grenade", {})
	grenade_tuning["projectile_scene_path"] = definition.projectile_scene_path
	grenade_tuning["projectile_speed_mps"] = definition.projectile_speed_mps
	grenade_tuning["projectile_gravity_scale"] = definition.projectile_gravity_scale
	grenade_tuning["effect_radius_m"] = definition.effect_radius_m
	return {
		"ok": true,
		"grenade": grenade_tuning,
	}

func get_p14_flamethrower_tuning_report() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"flamethrower")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "flamethrower select failed")}
	var definition := weapon_controller.get_active_definition()
	var flame_tuning: Dictionary = weapon_controller.get_weapon_tuning_snapshot([&"flamethrower"]).get("flamethrower", {})
	flame_tuning["max_range_m"] = definition.max_range_m
	flame_tuning["supports_hold_fire"] = definition.supports_hold_fire
	flame_tuning["alt_action_type"] = definition.alt_action_type
	flame_tuning["propulsion_force"] = definition.propulsion_force
	flame_tuning["move_speed_multiplier"] = definition.move_speed_multiplier
	return {
		"ok": true,
		"flamethrower": flame_tuning,
	}

func get_p14_lasso_tuning_report() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"lasso")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "lasso select failed")}
	var definition := weapon_controller.get_active_definition()
	var lasso_tuning: Dictionary = weapon_controller.get_weapon_tuning_snapshot([&"lasso"]).get("lasso", {})
	lasso_tuning["slot_type"] = definition.slot_type
	lasso_tuning["fire_mode"] = definition.fire_mode
	lasso_tuning["is_hitscan"] = definition.is_hitscan
	lasso_tuning["spread_degrees"] = definition.spread_degrees
	lasso_tuning["max_range_m"] = definition.max_range_m
	lasso_tuning["alt_action_type"] = definition.alt_action_type
	lasso_tuning["propulsion_force"] = definition.propulsion_force
	return {
		"ok": true,
		"lasso": lasso_tuning,
	}

func get_p14_redbull_tuning_report() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"redbull")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "redbull select failed")}
	var definition := weapon_controller.get_active_definition()
	var redbull_tuning: Dictionary = weapon_controller.get_weapon_tuning_snapshot([&"redbull"]).get("redbull", {})
	redbull_tuning["slot_type"] = definition.slot_type
	redbull_tuning["fire_mode"] = definition.fire_mode
	redbull_tuning["is_hitscan"] = definition.is_hitscan
	redbull_tuning["uses_projectile"] = definition.uses_projectile
	redbull_tuning["alt_action_type"] = definition.alt_action_type
	redbull_tuning["move_speed_multiplier"] = definition.move_speed_multiplier
	return {
		"ok": true,
		"redbull": redbull_tuning,
	}

func get_p14_portal_gun_tuning_report() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"portal_gun")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "portal gun select failed")}
	var definition := weapon_controller.get_active_definition()
	var portal_tuning: Dictionary = weapon_controller.get_weapon_tuning_snapshot([&"portal_gun"]).get("portal_gun", {})
	portal_tuning["slot_type"] = definition.slot_type
	portal_tuning["fire_mode"] = definition.fire_mode
	portal_tuning["is_hitscan"] = definition.is_hitscan
	portal_tuning["uses_projectile"] = definition.uses_projectile
	portal_tuning["spread_degrees"] = definition.spread_degrees
	portal_tuning["max_range_m"] = definition.max_range_m
	portal_tuning["effect_radius_m"] = definition.effect_radius_m
	portal_tuning["alt_action_type"] = definition.alt_action_type
	return {
		"ok": true,
		"portal_gun": portal_tuning,
	}

func get_p03_asset_manifest() -> Array[Dictionary]:
	if active_map == null or not active_map.has_method("get_p03_asset_manifest"):
		return []
	return active_map.get_p03_asset_manifest()

func prepare_p03_capture_view() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	if active_map == null or not active_map.has_method("get_p03_capture_pose"):
		return {"ok": false, "error": "active map has no P03 capture pose"}
	var pose: Dictionary = active_map.get_p03_capture_pose()
	_apply_local_player_capture_pose(pose, Vector3(0.0, 2.4, 25.0), 0.0, deg_to_rad(-8.0))
	return {
		"ok": true,
		"manifest": get_p03_asset_manifest(),
	}

func get_p04_dressing_manifest() -> Array[Dictionary]:
	if active_map == null or not active_map.has_method("get_p04_dressing_manifest"):
		return []
	return active_map.get_p04_dressing_manifest()

func get_p04_dressing_report() -> Dictionary:
	if active_map == null or not active_map.has_method("get_p04_dressing_report"):
		return {}
	return active_map.get_p04_dressing_report()

func prepare_p04_capture_view(view_name: String) -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	if active_map == null or not active_map.has_method("get_p04_capture_pose"):
		return {"ok": false, "error": "active map has no P04 capture pose"}
	var pose: Dictionary = active_map.get_p04_capture_pose(view_name)
	if pose.is_empty():
		return {"ok": false, "error": "unknown P04 capture view '%s'" % view_name}
	_apply_local_player_capture_pose(pose, Vector3.ZERO, 0.0, 0.0)
	return {
		"ok": true,
		"manifest": get_p04_dressing_manifest(),
		"report": get_p04_dressing_report(),
	}

func get_p23_level_designer_manifest() -> Array[Dictionary]:
	if active_map == null or not active_map.has_method("get_p23_level_designer_manifest"):
		return []
	return active_map.get_p23_level_designer_manifest()

func get_p23_level_designer_report() -> Dictionary:
	if active_map == null or not active_map.has_method("get_p23_level_designer_report"):
		return {}
	return active_map.get_p23_level_designer_report()

func run_p23_level_designer_checks() -> Dictionary:
	var report := get_p23_level_designer_report()
	var art_result := _run_art_layer_smoke_check()
	return {
		"ok": (
			bool(report.get("ok", false))
			and bool(art_result.get("ok", false))
		),
		"p23_report": report,
		"art_result": art_result,
	}

func prepare_p23_capture_view(view_name: String) -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	if active_map == null or not active_map.has_method("get_p23_capture_pose"):
		return {"ok": false, "error": "active map has no P23 capture pose"}
	var pose: Dictionary = active_map.get_p23_capture_pose(view_name)
	if pose.is_empty():
		return {"ok": false, "error": "unknown P23 capture view '%s'" % view_name}
	_apply_local_player_capture_pose(pose, Vector3.ZERO, 0.0, 0.0)
	local_player.get_weapon_controller().select_weapon_for_verification(&"assault_rifle")
	await _wait_p07_physics_frames(4)
	return {
		"ok": true,
		"view_name": view_name,
		"manifest": get_p23_level_designer_manifest(),
		"report": get_p23_level_designer_report(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud != null and hud.has_method("get_runtime_smoke_summary") else {},
	}

func prepare_p05_capture_view(slot: StringName, fire_weapon: bool) -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	_apply_local_player_capture_pose({
		"position": Vector3(-32.0, 1.8, 22.0),
		"target": Vector3(-7.2, 1.15, 8.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var weapon_controller := local_player.get_weapon_controller()
	var slot_result: Dictionary = weapon_controller.select_slot_for_verification(slot)
	if not bool(slot_result.get("ok", false)):
		return slot_result
	if fire_weapon:
		var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
		if not bool(fire_result.get("ok", false)):
			return fire_result
	return {
		"ok": true,
		"view_model": weapon_controller.get_view_model_runtime_summary(),
	}

func prepare_p05a_weapon_capture(weapon_id: StringName, fire_weapon: bool) -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	_clear_p05a_transient_fx()
	_apply_local_player_capture_pose({
		"position": Vector3(-32.0, 1.8, 22.0),
		"target": Vector3(-7.2, 1.15, 8.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(weapon_id)
	if not bool(select_result.get("ok", false)):
		return select_result
	var fire_result := {"ok": true, "skipped": true}
	if fire_weapon:
		fire_result = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
		if not bool(fire_result.get("ok", false)):
			return fire_result
	return {
		"ok": true,
		"weapon_id": weapon_id,
		"slot": select_result.get("slot", &""),
		"active_summary": weapon_controller.get_active_summary(),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"fire_result": fire_result,
	}

func _clear_p05a_transient_fx() -> void:
	for root in [projectiles_root, effects_root]:
		if root == null:
			continue
		for child in root.get_children():
			child.queue_free()

func get_p06_remote_report() -> Dictionary:
	return _build_p06_remote_report()

func prepare_p06_capture_view() -> Dictionary:
	var report := _build_p06_remote_report()
	if not bool(report.get("ok", false)):
		return report
	var proxy := _select_p06_capture_proxy()
	if proxy == null:
		return {"ok": false, "error": "no P06 remote proxy available for capture", "report": report}
	var remote_position := proxy.target_position
	if remote_position == Vector3.ZERO:
		remote_position = proxy.global_position
	var offset := Vector3(0.0, 3.8, 3.2)
	if remote_position.z > 0.0:
		offset.z = -offset.z
	_apply_local_player_capture_pose({
		"position": remote_position + offset,
		"target": remote_position + Vector3(0.0, 0.95, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	return {
		"ok": true,
		"report": report,
		"capture_peer_id": proxy.peer_id,
	}

func prepare_p06_driver_pose() -> Dictionary:
	if local_player == null:
		return {"ok": false, "error": "missing local player"}
	_apply_local_player_capture_pose({
		"position": Vector3(0.0, 0.45, 0.0),
		"yaw": deg_to_rad(180.0),
		"pitch": 0.0,
	}, Vector3.ZERO, 0.0, 0.0)
	return {"ok": true}

func run_p07_playtest_checks() -> Dictionary:
	if local_player == null or hud == null:
		return {"ok": false, "error": "P07 playtest requires local player and HUD"}
	var route_blue: Dictionary = await _complete_p07_traversal_route("blue_wallrun_to_high", [
		Vector3(-32.0, 0.6, 22.0),
		Vector3(-19.0, 2.8, -16.0),
		Vector3(-8.0, 6.4, -12.0),
	])
	var route_orange: Dictionary = await _complete_p07_traversal_route("orange_wallrun_to_high", [
		Vector3(32.0, 0.6, -22.0),
		Vector3(19.0, 2.8, 16.0),
		Vector3(9.0, 6.4, 12.0),
	])
	var movement_result: Dictionary = local_player.run_runtime_movement_smoke_check()
	var weapon_result: Dictionary = await _run_p07_weapon_checks()
	var reload_result: Dictionary = local_player.get_weapon_controller().run_reload_interrupt_smoke_check()
	var respawn_result: Dictionary = _run_local_respawn_smoke_check()
	var hud_result: Dictionary = await _run_p07_hud_check()
	var routes := [route_blue, route_orange]
	var routes_completed := 0
	for route in routes:
		if bool(route.get("completed", false)):
			routes_completed += 1
	var movement_ok := bool(movement_result.get("ok", false))
	var movement := {
		"jump": movement_ok,
		"slide": movement_ok,
		"slide_jump": movement_ok,
		"wallrun": movement_ok,
		"wall_jump": movement_ok,
		"details": movement_result,
	}
	return {
		"ok": (
			routes_completed >= 2
			and movement_ok
			and bool(weapon_result.get("ok", false))
			and bool(reload_result.get("ok", false))
			and bool(respawn_result.get("ok", false))
			and bool(hud_result.get("ok", false))
		),
		"arena": "arena_downtown_01_art",
		"routes": routes,
		"traversal_routes_completed": routes_completed,
		"movement": movement,
		"weapons": weapon_result.get("weapons", {}),
		"dummy_hits": int(weapon_result.get("dummy_hits", 0)),
		"dummy_kills": int(weapon_result.get("dummy_kills", 0)),
		"smoke_volumes_spawned": int(weapon_result.get("smoke_volumes_spawned", 0)),
		"reload_interrupt": bool(reload_result.get("ok", false)),
		"death_respawn": bool(respawn_result.get("ok", false)),
		"hud": hud_result.get("fields", {}),
		"hud_text": hud_result.get("hud_text", {}),
	}

func run_p10a_visual_playtest_checks() -> Dictionary:
	var base_report: Dictionary = await run_p07_playtest_checks()
	return {
		"ok": bool(base_report.get("ok", false)),
		"base_playtest": base_report,
		"visual_walkthrough_actions": [
			"completed both traversal routes",
			"exercised assault rifle, handgun, knife, and smoke bomb",
			"verified dummy hit/kill feedback and HUD combat readouts",
			"verified death/respawn and match score HUD state",
		],
	}

func prepare_p10a_capture_view(view_name: String) -> Dictionary:
	if local_player == null or hud == null:
		return {"ok": false, "error": "P10A capture requires local player and HUD"}
	_reset_p10a_capture_state()
	match view_name:
		"blue_spawn":
			return _prepare_p10a_static_capture(view_name, {
				"position": Vector3(-32.0, 1.65, 22.0),
				"target": Vector3(-13.5, 1.45, 7.0),
			}, &"assault_rifle")
		"orange_spawn":
			return _prepare_p10a_static_capture(view_name, {
				"position": Vector3(34.0, 1.65, 18.0),
				"target": Vector3(13.5, 1.45, 5.0),
			}, &"assault_rifle")
		"mid_map":
			return _prepare_p10a_static_capture(view_name, {
				"position": Vector3(0.0, 7.4, 27.0),
				"target": Vector3(0.0, 1.2, 0.0),
			}, &"assault_rifle")
		"high_route":
			return _prepare_p10a_static_capture(view_name, {
				"position": Vector3(-22.0, 6.3, -23.0),
				"target": Vector3(-6.0, 5.8, -8.0),
			}, &"assault_rifle")
		"assault_rifle":
			return _prepare_p10a_static_capture(view_name, {
				"position": Vector3(-32.0, 1.8, 22.0),
				"target": Vector3(-7.2, 1.15, 8.0),
			}, &"assault_rifle")
		"primary_assault_rifle":
			return _prepare_p10a_static_capture(view_name, {
				"position": Vector3(-32.0, 1.8, 22.0),
				"target": Vector3(-7.2, 1.15, 8.0),
			}, &"assault_rifle")
		"shotgun":
			return _prepare_p10a_static_capture(view_name, {
				"position": Vector3(-32.0, 1.8, 22.0),
				"target": Vector3(-7.2, 1.15, 8.0),
			}, &"assault_rifle")
		"handgun":
			return _prepare_p10a_slot_capture(view_name, {
				"position": Vector3(-32.0, 1.8, 22.0),
				"target": Vector3(-7.2, 1.15, 8.0),
			}, &"secondary", &"handgun")
		"close_combat":
			return await _prepare_p10a_close_combat_capture()
		"smoke_combat_fx":
			return await _prepare_p10a_smoke_capture()
		"hud_under_combat":
			return await _prepare_p10a_hud_combat_capture()
		_:
			return {"ok": false, "error": "unknown P10A capture view '%s'" % view_name}

func _reset_p10a_capture_state() -> void:
	_clear_p10a_transient_fx()
	if local_player != null:
		local_player.view_model_root.visible = true
		local_player.camera.fov = 75.0
		local_player.set_physics_process(false)
	for dummy in get_tree().get_nodes_in_group("combat_dummies"):
		if dummy is Node3D:
			(dummy as Node3D).visible = true

func _prepare_p10a_static_capture(view_name: String, pose: Dictionary, weapon_id: StringName) -> Dictionary:
	_apply_local_player_capture_pose(pose, Vector3.ZERO, 0.0, 0.0)
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(weapon_id)
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "view": view_name, "error": select_result.get("error", "weapon select failed")}
	return {
		"ok": true,
		"view": view_name,
		"weapon_id": weapon_id,
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _prepare_p10a_slot_capture(view_name: String, pose: Dictionary, slot: StringName, expected_weapon_id: StringName) -> Dictionary:
	_apply_local_player_capture_pose(pose, Vector3.ZERO, 0.0, 0.0)
	var weapon_controller := local_player.get_weapon_controller()
	weapon_controller.set_loadout_definition(selected_loadout)
	var select_result: Dictionary = weapon_controller.select_slot_for_verification(slot)
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "view": view_name, "error": select_result.get("error", "slot select failed")}
	var active_summary := weapon_controller.get_active_summary()
	if StringName(str(active_summary.get("weapon_id", &""))) != expected_weapon_id:
		return {"ok": false, "view": view_name, "error": "expected %s but selected %s" % [String(expected_weapon_id), StringName(str(active_summary.get("weapon_id", &"")))]}
	return {
		"ok": true,
		"view": view_name,
		"weapon_id": expected_weapon_id,
		"slot": slot,
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _prepare_p10a_close_combat_capture() -> Dictionary:
	var dummy := _first_p10a_dummy()
	if dummy == null:
		return {"ok": false, "error": "P10A close combat found no dummy"}
	await _wait_for_p10a_dummy_ready(dummy)
	var target := dummy as Node3D
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": target.global_position + Vector3(0.0, 0.45, 1.85),
		"target": target.global_position + Vector3(0.0, 1.0, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"assault_rifle")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "view": "close_combat", "error": select_result.get("error", "assault rifle select failed")}
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	await _wait_p07_physics_frames(4)
	return {
		"ok": bool(fire_result.get("ok", false)),
		"view": "close_combat",
		"weapon_id": &"assault_rifle",
		"fire_result": fire_result,
		"dummy_health": _get_p07_dummy_health(dummy),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _prepare_p10a_smoke_capture() -> Dictionary:
	_clear_p10a_transient_fx()
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": Vector3(0.0, 1.0, 5.0),
		"target": Vector3(0.0, 0.45, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"smoke_bomb")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "view": "smoke_combat_fx", "error": select_result.get("error", "smoke select failed")}
	var state := weapon_controller.get_active_state()
	state.charges_current = 1
	state.cooldown_remaining_sec = 0.0
	var before_count := _count_p07_smoke_volumes()
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	await _wait_p07_physics_frames(90)
	var after_count := _count_p07_smoke_volumes()
	return {
		"ok": bool(fire_result.get("ok", false)) and after_count > before_count,
		"view": "smoke_combat_fx",
		"weapon_id": &"smoke_bomb",
		"fire_result": fire_result,
		"smoke_volumes_spawned": maxi(0, after_count - before_count),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _prepare_p10a_hud_combat_capture() -> Dictionary:
	var dummy := _p10a_dummy_by_index(3)
	if dummy == null:
		return {"ok": false, "error": "P10A HUD combat found no dummy"}
	await _wait_for_p10a_dummy_ready(dummy)
	var target := dummy as Node3D
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": target.global_position + Vector3(3.4, 1.0, 4.8),
		"target": target.global_position + Vector3(0.0, 1.0, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"assault_rifle")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "view": "hud_under_combat", "error": select_result.get("error", "rifle select failed")}
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	await _wait_p07_physics_frames(4)
	return {
		"ok": bool(fire_result.get("ok", false)),
		"view": "hud_under_combat",
		"weapon_id": &"assault_rifle",
		"fire_result": fire_result,
		"dummy_health": _get_p07_dummy_health(dummy),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _clear_p10a_transient_fx() -> void:
	for root in [projectiles_root, effects_root]:
		if root == null:
			continue
		for child in root.get_children():
			child.queue_free()

func _first_p10a_dummy() -> Node:
	for dummy in get_tree().get_nodes_in_group("combat_dummies"):
		if dummy is Node3D:
			return dummy
	return null

func _p10a_dummy_by_index(index: int) -> Node:
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if index >= 0 and index < dummies.size() and dummies[index] is Node3D:
		return dummies[index]
	return _first_p10a_dummy()

func _wait_for_p10a_dummy_ready(dummy: Node) -> void:
	for _index in range(100):
		if _get_p07_dummy_health(dummy) > 0.0:
			return
		await _wait_p07_physics_frames(1)

func run_p14_shotgun_checks() -> Dictionary:
	if local_player == null or hud == null:
		return {"ok": false, "error": "P14 shotgun checks require local player and HUD"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"shotgun")
	if not bool(select_result.get("ok", false)):
		return select_result
	var view_model: Dictionary = select_result.get("view_model", {})
	var view_summary: Dictionary = view_model.get("summary", {})
	var view_model_ok := (
		bool(view_model.get("has_view_model", false))
		and not bool(view_model.get("is_fallback", true))
		and bool(view_summary.get("has_mesh", false))
		and int(view_summary.get("vertex_count", 0)) > 0
		and String(view_summary.get("source_fbx_path", "")).ends_with("Shotgun.fbx")
		and String(view_summary.get("generated_glb_path", "")).ends_with("shotgun_from_fbx.glb")
		and bool(view_summary.get("material_override", false))
	)
	var tuning_report := get_p14_shotgun_tuning_report()
	var shotgun_tuning: Dictionary = tuning_report.get("shotgun", {})
	var tuning_ok := (
		int(shotgun_tuning.get("magazine_size", 0)) == 7
		and int(shotgun_tuning.get("reserve_ammo_max", 0)) == 14
		and int(shotgun_tuning.get("pellets_per_shot", 0)) == 10
		and is_equal_approx(float(shotgun_tuning.get("body_damage", 0.0)), 5.0)
		and is_equal_approx(float(shotgun_tuning.get("head_damage", 0.0)), 7.5)
		and is_equal_approx(float(shotgun_tuning.get("shot_cooldown_sec", 0.0)), 0.5)
		and is_equal_approx(float(shotgun_tuning.get("reload_time_sec", 0.0)), 5.0)
	)
	var shotgun_result: Dictionary = await _run_p14_shotgun_sequence(3, 1.8)
	var reload_result: Dictionary = weapon_controller.run_reload_interrupt_smoke_check()
	var hud_result: Dictionary = await _run_p14_shotgun_hud_check()
	return {
		"ok": (
			view_model_ok
			and tuning_ok
			and bool(shotgun_result.get("hit", false))
			and bool(shotgun_result.get("killed", false))
			and bool(reload_result.get("ok", false))
			and bool(hud_result.get("ok", false))
		),
		"weapon_id": "shotgun",
		"selectable_in_runtime": true,
		"view_model_ok": view_model_ok,
		"view_model": view_model,
		"tuning_ok": tuning_ok,
		"tuning": shotgun_tuning,
		"offline_use": shotgun_result,
		"reload_interrupt": bool(reload_result.get("ok", false)),
		"reload_result": reload_result,
		"hud": hud_result,
	}

func run_p14_shotgun_pulse() -> Dictionary:
	return await _run_p14_shotgun_sequence(1, 1.8)

func prepare_p14_shotgun_capture_view() -> Dictionary:
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"ok": false, "error": "P14 capture found no combat dummies"}
	var dummy := dummies[0]
	if not (dummy is Node3D):
		return {"ok": false, "error": "P14 capture dummy is not Node3D"}
	var target := dummy as Node3D
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": target.global_position + Vector3(3.0, 1.2, 5.8),
		"target": target.global_position + Vector3(0.0, 1.0, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"shotgun")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "shotgun select failed")}
	var definition := weapon_controller.get_active_definition()
	var state := weapon_controller.get_active_state()
	state.ammo_in_mag = definition.magazine_size
	state.reserve_ammo = definition.reserve_ammo_max
	state.cooldown_remaining_sec = 0.0
	state.is_reloading = false
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	return {
		"ok": bool(fire_result.get("ok", false)),
		"fire_result": fire_result,
		"dummy_health": _get_p07_dummy_health(dummy),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _run_p14_shotgun_hud_check() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"shotgun")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "shotgun select failed")}
	await _wait_p07_physics_frames(2)
	var hud_summary: Dictionary = hud.get_runtime_smoke_summary()
	var combat_text := String(hud_summary.get("combat_text", ""))
	return {
		"ok": combat_text.contains("Weapon: Shotgun") and combat_text.contains("Ammo:"),
		"hud_summary": hud_summary,
	}

func _run_p14_shotgun_sequence(max_shots: int, distance: float) -> Dictionary:
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"used": false, "hit": false, "killed": false, "error": "P14 found no combat dummies"}
	var dummy := dummies[0]
	if not (dummy is Node3D):
		return {"used": false, "hit": false, "killed": false, "error": "P14 dummy is not Node3D"}
	if _get_p07_dummy_health(dummy) <= 0.0:
		await _wait_p07_physics_frames(90)
	var target := dummy as Node3D
	var health_before := _get_p07_dummy_health(dummy)
	var shot_position := target.global_position + Vector3(0.0, 0.4, distance)
	_apply_local_player_capture_pose({
		"position": shot_position,
		"target": target.global_position + Vector3(0.0, 1.0, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"shotgun")
	if not bool(select_result.get("ok", false)):
		return {"used": false, "hit": false, "killed": false, "error": select_result.get("error", "shotgun select failed")}
	var definition := weapon_controller.get_active_definition()
	var shots_fired := 0
	for _index in range(max_shots):
		var state := weapon_controller.get_active_state()
		state.ammo_in_mag = definition.magazine_size
		state.reserve_ammo = definition.reserve_ammo_max
		state.cooldown_remaining_sec = 0.0
		state.is_reloading = false
		var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
		if not bool(fire_result.get("ok", false)):
			return {"used": false, "hit": false, "killed": false, "error": fire_result.get("error", "shotgun fire failed")}
		shots_fired += 1
		await _wait_p07_physics_frames(4)
		if _get_p07_dummy_health(dummy) <= 0.0:
			break
	var health_after := _get_p07_dummy_health(dummy)
	return {
		"used": true,
		"hit": health_after < health_before,
		"killed": health_after <= 0.0,
		"weapon_id": &"shotgun",
		"shots_fired": shots_fired,
		"health_before": health_before,
		"health_after": health_after,
		"view_model": weapon_controller.get_view_model_runtime_summary(),
	}

func run_p14_sniper_checks() -> Dictionary:
	if local_player == null or hud == null:
		return {"ok": false, "error": "P14 sniper checks require local player and HUD"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"sniper")
	if not bool(select_result.get("ok", false)):
		return select_result
	var view_model: Dictionary = select_result.get("view_model", {})
	var view_summary: Dictionary = view_model.get("summary", {})
	var view_model_ok := (
		bool(view_model.get("has_view_model", false))
		and not bool(view_model.get("is_fallback", true))
		and bool(view_summary.get("has_mesh", false))
		and int(view_summary.get("vertex_count", 0)) > 0
		and String(view_summary.get("source_fbx_path", "")).ends_with("SniperRifle.fbx")
		and String(view_summary.get("generated_glb_path", "")).ends_with("sniper_from_fbx.glb")
		and bool(view_summary.get("material_override", false))
	)
	var tuning_report := get_p14_sniper_tuning_report()
	var sniper_tuning: Dictionary = tuning_report.get("sniper", {})
	var tuning_ok := (
		int(sniper_tuning.get("magazine_size", 0)) == 1
		and int(sniper_tuning.get("reserve_ammo_max", 0)) == 9
		and int(sniper_tuning.get("pellets_per_shot", 0)) == 1
		and is_equal_approx(float(sniper_tuning.get("body_damage", 0.0)), 50.0)
		and is_equal_approx(float(sniper_tuning.get("head_damage", 0.0)), 100.0)
		and is_equal_approx(float(sniper_tuning.get("shot_cooldown_sec", 0.0)), 1.0)
		and is_equal_approx(float(sniper_tuning.get("reload_time_sec", 0.0)), 2.0)
	)
	var sniper_result: Dictionary = await _run_p14_sniper_sequence(2, 2.4)
	var reload_result: Dictionary = weapon_controller.run_reload_interrupt_smoke_check()
	var hud_result: Dictionary = await _run_p14_sniper_hud_check()
	return {
		"ok": (
			view_model_ok
			and tuning_ok
			and bool(sniper_result.get("hit", false))
			and bool(sniper_result.get("killed", false))
			and bool(reload_result.get("ok", false))
			and bool(hud_result.get("ok", false))
		),
		"weapon_id": "sniper",
		"selectable_in_runtime": true,
		"view_model_ok": view_model_ok,
		"view_model": view_model,
		"tuning_ok": tuning_ok,
		"tuning": sniper_tuning,
		"offline_use": sniper_result,
		"reload_interrupt": bool(reload_result.get("ok", false)),
		"reload_result": reload_result,
		"hud": hud_result,
	}

func run_p14_sniper_pulse() -> Dictionary:
	return await _run_p14_sniper_sequence(2, 2.4)

func prepare_p14_sniper_capture_view() -> Dictionary:
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"ok": false, "error": "P14 sniper capture found no combat dummies"}
	var dummy := dummies[0]
	if not (dummy is Node3D):
		return {"ok": false, "error": "P14 sniper capture dummy is not Node3D"}
	if _get_p07_dummy_health(dummy) <= 0.0:
		await _wait_p07_physics_frames(90)
	var target := dummy as Node3D
	var aim_height := 0.9
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": target.global_position + Vector3(0.0, 0.75, 2.4),
		"target": target.global_position + Vector3(0.0, aim_height, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"sniper")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "sniper select failed")}
	var definition := weapon_controller.get_active_definition()
	var state := weapon_controller.get_active_state()
	state.ammo_in_mag = definition.magazine_size
	state.reserve_ammo = definition.reserve_ammo_max
	state.cooldown_remaining_sec = 0.0
	state.is_reloading = false
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	return {
		"ok": bool(fire_result.get("ok", false)),
		"fire_result": fire_result,
		"dummy_health": _get_p07_dummy_health(dummy),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _run_p14_sniper_hud_check() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"sniper")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "sniper select failed")}
	await _wait_p07_physics_frames(2)
	var hud_summary: Dictionary = hud.get_runtime_smoke_summary()
	var combat_text := String(hud_summary.get("combat_text", ""))
	return {
		"ok": combat_text.contains("Weapon: Sniper") and combat_text.contains("Ammo:"),
		"hud_summary": hud_summary,
	}

func _run_p14_sniper_sequence(max_shots: int, distance: float) -> Dictionary:
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"used": false, "hit": false, "killed": false, "error": "P14 sniper found no combat dummies"}
	var dummy := dummies[0]
	if not (dummy is Node3D):
		return {"used": false, "hit": false, "killed": false, "error": "P14 sniper dummy is not Node3D"}
	if _get_p07_dummy_health(dummy) <= 0.0:
		await _wait_p07_physics_frames(90)
	var target := dummy as Node3D
	var health_before := _get_p07_dummy_health(dummy)
	var aim_height := 0.9
	var shot_position := target.global_position + Vector3(0.0, 0.75, distance)
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"sniper")
	if not bool(select_result.get("ok", false)):
		return {"used": false, "hit": false, "killed": false, "error": select_result.get("error", "sniper select failed")}
	var definition := weapon_controller.get_active_definition()
	var shots_fired := 0
	var shot_trace := []
	for _index in range(max_shots):
		_apply_local_player_capture_pose({
			"position": shot_position,
			"target": target.global_position + Vector3(0.0, aim_height, 0.0),
		}, Vector3.ZERO, 0.0, 0.0)
		var state := weapon_controller.get_active_state()
		state.ammo_in_mag = definition.magazine_size
		state.reserve_ammo = definition.reserve_ammo_max
		state.cooldown_remaining_sec = 0.0
		state.is_reloading = false
		var before_shot := _get_p07_dummy_health(dummy)
		var ray_probe := _probe_p14_camera_ray(definition.max_range_m)
		var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
		if not bool(fire_result.get("ok", false)):
			return {"used": false, "hit": false, "killed": false, "error": fire_result.get("error", "sniper fire failed")}
		shots_fired += 1
		await _wait_p07_physics_frames(4)
		var after_shot := _get_p07_dummy_health(dummy)
		shot_trace.append({
			"shot": shots_fired,
			"health_before": before_shot,
			"health_after": after_shot,
			"damage": maxf(0.0, before_shot - after_shot),
			"ray_probe": ray_probe,
		})
		if after_shot <= 0.0:
			break
	var health_after := _get_p07_dummy_health(dummy)
	return {
		"used": true,
		"hit": health_after < health_before,
		"killed": health_after <= 0.0,
		"weapon_id": &"sniper",
		"shots_fired": shots_fired,
		"health_before": health_before,
		"health_after": health_after,
		"shot_trace": shot_trace,
		"view_model": weapon_controller.get_view_model_runtime_summary(),
	}

func _probe_p14_camera_ray(max_range: float) -> Dictionary:
	var origin := local_player.camera.global_position
	var direction := (-local_player.camera.global_transform.basis.z).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_range)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [local_player.get_rid()]
	var hit := local_player.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"hit": false, "origin": origin, "direction": direction}
	var collider: Object = hit.get("collider", null)
	return {
		"hit": true,
		"origin": origin,
		"direction": direction,
		"position": hit.get("position", Vector3.ZERO),
		"collider_name": (collider as Node).name if collider is Node else "",
		"collider_class": collider.get_class() if collider != null else "",
		"collider_has_damage": collider.has_method("apply_damage") if collider != null else false,
	}

func run_p14_grenade_checks() -> Dictionary:
	if local_player == null or hud == null:
		return {"ok": false, "error": "P14 grenade checks require local player and HUD"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"grenade")
	if not bool(select_result.get("ok", false)):
		return select_result
	var view_model: Dictionary = select_result.get("view_model", {})
	var view_summary: Dictionary = view_model.get("summary", {})
	var view_model_ok := (
		bool(view_model.get("has_view_model", false))
		and not bool(view_model.get("is_fallback", true))
		and bool(view_summary.get("has_mesh", false))
		and int(view_summary.get("vertex_count", 0)) > 0
		and String(view_summary.get("viewmodel_kind", "")) == "grenade"
		and bool(view_summary.get("material_override", false))
	)
	var tuning_report := get_p14_grenade_tuning_report()
	var grenade_tuning: Dictionary = tuning_report.get("grenade", {})
	var tuning_ok := (
		int(grenade_tuning.get("charges_max", 0)) == 3
		and is_equal_approx(float(grenade_tuning.get("body_damage", 0.0)), 75.0)
		and is_equal_approx(float(grenade_tuning.get("head_damage", 0.0)), 75.0)
		and is_equal_approx(float(grenade_tuning.get("shot_cooldown_sec", 0.0)), 5.0)
		and is_equal_approx(float(grenade_tuning.get("effect_radius_m", 0.0)), 4.5)
		and is_equal_approx(float(grenade_tuning.get("projectile_speed_mps", 0.0)), 11.0)
		and String(grenade_tuning.get("projectile_scene_path", "")) == "res://scenes/weapons/projectiles/grenade_projectile.tscn"
	)
	var grenade_result: Dictionary = await _run_p14_grenade_sequence(2)
	var hud_result: Dictionary = await _run_p14_grenade_hud_check()
	return {
		"ok": (
			view_model_ok
			and tuning_ok
			and bool(grenade_result.get("hit", false))
			and bool(grenade_result.get("killed", false))
			and bool(hud_result.get("ok", false))
		),
		"weapon_id": "grenade",
		"selectable_in_runtime": true,
		"view_model_ok": view_model_ok,
		"view_model": view_model,
		"tuning_ok": tuning_ok,
		"tuning": grenade_tuning,
		"offline_use": grenade_result,
		"hud": hud_result,
	}

func run_p14_grenade_pulse() -> Dictionary:
	return await _run_p14_grenade_sequence(2)

func prepare_p14_grenade_capture_view() -> Dictionary:
	_clear_p14_grenade_transients()
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"ok": false, "error": "P14 grenade capture found no combat dummies"}
	var dummy := dummies[0]
	if not (dummy is Node3D):
		return {"ok": false, "error": "P14 grenade capture dummy is not Node3D"}
	if _get_p07_dummy_health(dummy) <= 0.0:
		await _wait_p07_physics_frames(90)
	var target := dummy as Node3D
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": target.global_position + Vector3(-1.1, 0.75, 4.6),
		"target": target.global_position + Vector3(0.0, 0.25, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"grenade")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "grenade select failed")}
	var definition := weapon_controller.get_active_definition()
	var state := weapon_controller.get_active_state()
	state.charges_current = definition.charges_max
	state.cooldown_remaining_sec = 0.0
	state.is_reloading = false
	var health_before := _get_p07_dummy_health(dummy)
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	var damage_report := await _wait_for_p14_grenade_damage(dummy, health_before, 90)
	var explosion_markers := _count_p14_grenade_explosion_markers()
	return {
		"ok": bool(fire_result.get("ok", false)) and bool(damage_report.get("hit", false)) and explosion_markers > 0,
		"fire_result": fire_result,
		"damage_report": damage_report,
		"dummy_health": _get_p07_dummy_health(dummy),
		"explosion_markers_after": explosion_markers,
		"active_projectiles_after": _count_p14_grenade_projectiles(),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _run_p14_grenade_hud_check() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"grenade")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "grenade select failed")}
	await _wait_p07_physics_frames(2)
	var hud_summary: Dictionary = hud.get_runtime_smoke_summary()
	var combat_text := String(hud_summary.get("combat_text", ""))
	return {
		"ok": combat_text.contains("Weapon: Grenade") and combat_text.contains("3 charges"),
		"hud_summary": hud_summary,
	}

func _run_p14_grenade_sequence(max_throws: int) -> Dictionary:
	_clear_p14_grenade_transients()
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"used": false, "hit": false, "killed": false, "error": "P14 grenade found no combat dummies"}
	var dummy := dummies[0]
	if not (dummy is Node3D):
		return {"used": false, "hit": false, "killed": false, "error": "P14 grenade dummy is not Node3D"}
	if _get_p07_dummy_health(dummy) <= 0.0:
		await _wait_p07_physics_frames(90)
	var target := dummy as Node3D
	var health_before := _get_p07_dummy_health(dummy)
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"grenade")
	if not bool(select_result.get("ok", false)):
		return {"used": false, "hit": false, "killed": false, "error": select_result.get("error", "grenade select failed")}
	var definition := weapon_controller.get_active_definition()
	var throws_fired := 0
	var throw_trace := []
	for _index in range(max_throws):
		_apply_local_player_capture_pose({
			"position": target.global_position + Vector3(0.0, 0.75, 2.4),
			"target": target.global_position + Vector3(0.0, 0.15, 0.0),
		}, Vector3.ZERO, 0.0, 0.0)
		var state := weapon_controller.get_active_state()
		state.charges_current = definition.charges_max
		state.cooldown_remaining_sec = 0.0
		state.is_reloading = false
		var before_throw := _get_p07_dummy_health(dummy)
		var projectile_count_before := _count_p14_grenade_projectiles()
		var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
		if not bool(fire_result.get("ok", false)):
			return {"used": false, "hit": false, "killed": false, "error": fire_result.get("error", "grenade fire failed")}
		throws_fired += 1
		var damage_report := await _wait_for_p14_grenade_damage(dummy, before_throw, 90)
		var after_throw := _get_p07_dummy_health(dummy)
		throw_trace.append({
			"throw": throws_fired,
			"health_before": before_throw,
			"health_after": after_throw,
			"damage": maxf(0.0, before_throw - after_throw),
			"projectiles_before": projectile_count_before,
			"projectiles_after": _count_p14_grenade_projectiles(),
			"explosion_markers": _count_p14_grenade_explosion_markers(),
			"damage_report": damage_report,
		})
		if after_throw <= 0.0:
			break
	var health_after := _get_p07_dummy_health(dummy)
	return {
		"used": true,
		"hit": health_after < health_before,
		"killed": health_after <= 0.0,
		"weapon_id": &"grenade",
		"throws_fired": throws_fired,
		"health_before": health_before,
		"health_after": health_after,
		"throw_trace": throw_trace,
		"view_model": weapon_controller.get_view_model_runtime_summary(),
	}

func _wait_for_p14_grenade_damage(dummy: Node, health_before: float, max_frames: int) -> Dictionary:
	var marker_seen := false
	for _index in range(max_frames):
		await _wait_p07_physics_frames(1)
		marker_seen = marker_seen or _count_p14_grenade_explosion_markers() > 0
		var current_health := _get_p07_dummy_health(dummy)
		if current_health < health_before:
			return {
				"hit": true,
				"health_before": health_before,
				"health_after": current_health,
				"marker_seen": marker_seen,
				"frames_waited": _index + 1,
			}
	return {
		"hit": false,
		"health_before": health_before,
		"health_after": _get_p07_dummy_health(dummy),
		"marker_seen": marker_seen,
		"frames_waited": max_frames,
	}

func _clear_p14_grenade_transients() -> void:
	for root in [projectiles_root, effects_root]:
		if root == null:
			continue
		for child in root.get_children():
			if String(child.name).begins_with("GrenadeProjectile") or String(child.name).begins_with("GrenadeExplosionMarker"):
				child.queue_free()

func _count_p14_grenade_projectiles() -> int:
	var count := 0
	for child in projectiles_root.get_children():
		if String(child.name).begins_with("GrenadeProjectile"):
			count += 1
	return count

func _count_p14_grenade_explosion_markers() -> int:
	var count := 0
	for child in effects_root.get_children():
		if String(child.name).begins_with("GrenadeExplosionMarker"):
			count += 1
	return count

func run_p14_flamethrower_checks() -> Dictionary:
	if local_player == null or hud == null:
		return {"ok": false, "error": "P14 flamethrower checks require local player and HUD"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"flamethrower")
	if not bool(select_result.get("ok", false)):
		return select_result
	var view_model: Dictionary = select_result.get("view_model", {})
	var view_summary: Dictionary = view_model.get("summary", {})
	var view_model_ok := (
		bool(view_model.get("has_view_model", false))
		and not bool(view_model.get("is_fallback", true))
		and bool(view_summary.get("has_mesh", false))
		and int(view_summary.get("vertex_count", 0)) > 0
		and String(view_summary.get("viewmodel_kind", "")) == "flamethrower"
		and bool(view_summary.get("material_override", false))
	)
	var tuning_report := get_p14_flamethrower_tuning_report()
	var flame_tuning: Dictionary = tuning_report.get("flamethrower", {})
	var tuning_ok := (
		int(flame_tuning.get("magazine_size", 0)) == 100
		and int(flame_tuning.get("reserve_ammo_max", -1)) == 0
		and is_equal_approx(float(flame_tuning.get("body_damage", 0.0)), 5.0)
		and is_equal_approx(float(flame_tuning.get("head_damage", 0.0)), 5.0)
		and is_equal_approx(float(flame_tuning.get("shot_cooldown_sec", 0.0)), 0.1)
		and is_equal_approx(float(flame_tuning.get("effect_duration_sec", 0.0)), 10.0)
		and is_equal_approx(float(flame_tuning.get("max_range_m", 0.0)), 12.0)
		and bool(flame_tuning.get("supports_hold_fire", false))
		and String(flame_tuning.get("alt_action_type", "")) == ""
		and is_equal_approx(float(flame_tuning.get("propulsion_force", 0.0)), 40.0)
	)
	var flame_result: Dictionary = await _run_p14_flamethrower_sequence(24)
	var propulsion_result: Dictionary = _run_p14_flamethrower_propulsion_check()
	var hud_result: Dictionary = await _run_p14_flamethrower_hud_check()
	return {
		"ok": (
			view_model_ok
			and tuning_ok
			and bool(flame_result.get("hit", false))
			and bool(flame_result.get("killed", false))
			and bool(propulsion_result.get("ok", false))
			and bool(hud_result.get("ok", false))
		),
		"weapon_id": "flamethrower",
		"selectable_in_runtime": true,
		"view_model_ok": view_model_ok,
		"view_model": view_model,
		"tuning_ok": tuning_ok,
		"tuning": flame_tuning,
		"offline_use": flame_result,
		"propulsion": propulsion_result,
		"hud": hud_result,
	}

func run_p14_flamethrower_pulse() -> Dictionary:
	return await _run_p14_flamethrower_sequence(24)

func prepare_p14_flamethrower_capture_view() -> Dictionary:
	_clear_p14_flamethrower_transients()
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"ok": false, "error": "P14 flamethrower capture found no combat dummies"}
	var dummy := dummies[0]
	if not (dummy is Node3D):
		return {"ok": false, "error": "P14 flamethrower capture dummy is not Node3D"}
	if _get_p07_dummy_health(dummy) <= 0.0:
		await _wait_p07_physics_frames(90)
	var target := dummy as Node3D
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": target.global_position + Vector3(0.0, 0.75, 2.0),
		"target": target.global_position + Vector3(0.0, 0.9, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"flamethrower")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "flamethrower select failed")}
	var definition := weapon_controller.get_active_definition()
	var state := weapon_controller.get_active_state()
	state.ammo_in_mag = definition.magazine_size
	state.cooldown_remaining_sec = 0.0
	state.is_reloading = false
	var health_before := _get_p07_dummy_health(dummy)
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	await _wait_p07_physics_frames(3)
	return {
		"ok": bool(fire_result.get("ok", false)) and _get_p07_dummy_health(dummy) < health_before and _count_p14_flame_bursts() > 0,
		"fire_result": fire_result,
		"health_before": health_before,
		"dummy_health": _get_p07_dummy_health(dummy),
		"flame_bursts_after": _count_p14_flame_bursts(),
		"impact_sparks_after": _count_p14_impact_sparks(),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _run_p14_flamethrower_hud_check() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"flamethrower")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "flamethrower select failed")}
	await _wait_p07_physics_frames(2)
	var hud_summary: Dictionary = hud.get_runtime_smoke_summary()
	var combat_text := String(hud_summary.get("combat_text", ""))
	return {
		"ok": combat_text.contains("Weapon: Flame Thrower") and combat_text.contains("Ammo: 100 / 0"),
		"hud_summary": hud_summary,
	}

func _run_p14_flamethrower_sequence(max_ticks: int) -> Dictionary:
	_clear_p14_flamethrower_transients()
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"used": false, "hit": false, "killed": false, "error": "P14 flamethrower found no combat dummies"}
	var dummy := dummies[0]
	if not (dummy is Node3D):
		return {"used": false, "hit": false, "killed": false, "error": "P14 flamethrower dummy is not Node3D"}
	if _get_p07_dummy_health(dummy) <= 0.0:
		await _wait_p07_physics_frames(90)
	var target := dummy as Node3D
	var health_before := _get_p07_dummy_health(dummy)
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"flamethrower")
	if not bool(select_result.get("ok", false)):
		return {"used": false, "hit": false, "killed": false, "error": select_result.get("error", "flamethrower select failed")}
	var definition := weapon_controller.get_active_definition()
	var ticks_fired := 0
	var damage_trace := []
	for _index in range(max_ticks):
		_apply_local_player_capture_pose({
			"position": target.global_position + Vector3(0.0, 0.75, 1.6),
			"target": target.global_position + Vector3(0.0, 0.9, 0.0),
		}, Vector3.ZERO, 0.0, 0.0)
		var state := weapon_controller.get_active_state()
		state.ammo_in_mag = definition.magazine_size
		state.cooldown_remaining_sec = 0.0
		state.is_reloading = false
		var before_tick := _get_p07_dummy_health(dummy)
		var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
		if not bool(fire_result.get("ok", false)):
			return {"used": false, "hit": false, "killed": false, "error": fire_result.get("error", "flamethrower fire failed")}
		ticks_fired += 1
		await _wait_p07_physics_frames(2)
		var after_tick := _get_p07_dummy_health(dummy)
		if after_tick < before_tick or ticks_fired <= 3:
			damage_trace.append({
				"tick": ticks_fired,
				"health_before": before_tick,
				"health_after": after_tick,
				"damage": maxf(0.0, before_tick - after_tick),
			})
		if after_tick <= 0.0:
			break
	var health_after := _get_p07_dummy_health(dummy)
	return {
		"used": true,
		"hit": health_after < health_before,
		"killed": health_after <= 0.0,
		"weapon_id": &"flamethrower",
		"ticks_fired": ticks_fired,
		"health_before": health_before,
		"health_after": health_after,
		"damage_trace": damage_trace,
		"flame_bursts_after": _count_p14_flame_bursts(),
		"impact_sparks_after": _count_p14_impact_sparks(),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
	}

func _run_p14_flamethrower_propulsion_check() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"flamethrower")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "flamethrower select failed")}
	local_player.velocity = Vector3.ZERO
	var ammo_before := int(weapon_controller.get_active_summary().get("ammo_in_mag", 0))
	var result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera, true)
	var propulsion: Dictionary = result.get("primary_fire_propulsion", {})
	var velocity_after: Vector3 = propulsion.get("velocity_after", Vector3.ZERO)
	result["ammo_before"] = ammo_before
	result["ammo_after"] = int(weapon_controller.get_active_summary().get("ammo_in_mag", 0))
	result["uses_primary_fire_fuel"] = bool(propulsion.get("uses_primary_fire_fuel", false))
	result["lift_velocity_ok"] = velocity_after.y >= 3.0
	var fire_direction: Vector3 = propulsion.get("fire_direction", Vector3.FORWARD)
	var horizontal_fire_direction := Vector3(fire_direction.x, 0.0, fire_direction.z).normalized()
	var horizontal_velocity := Vector3(velocity_after.x, 0.0, velocity_after.z)
	result["backward_recoil_ok"] = horizontal_velocity.dot(horizontal_fire_direction) < -0.25
	result["ok"] = (
		bool(result.get("ok", false))
		and bool(propulsion.get("ok", false))
		and bool(result.get("uses_primary_fire_fuel", false))
		and int(result.get("ammo_after", ammo_before)) < ammo_before
		and bool(result.get("lift_velocity_ok", false))
		and bool(result.get("backward_recoil_ok", false))
	)
	return result

func _clear_p14_flamethrower_transients() -> void:
	if effects_root != null:
		for child in effects_root.get_children():
			if String(child.name).begins_with("ImpactSpark"):
				child.queue_free()
	var weapon_controller := local_player.get_weapon_controller() if local_player != null else null
	if weapon_controller == null:
		return
	var view_summary: Dictionary = weapon_controller.get_view_model_runtime_summary()
	if not bool(view_summary.get("has_view_model", false)):
		return
	var view_model := weapon_controller.get_node_or_null("../HeadPivot/ViewModelRoot")
	if view_model == null:
		return
	for child in view_model.get_children():
		if String(child.name).begins_with("FlameBurst"):
			child.queue_free()

func _count_p14_flame_bursts() -> int:
	if local_player == null:
		return 0
	var view_model_root := local_player.get_node_or_null("HeadPivot/ViewModelRoot")
	if view_model_root == null:
		return 0
	var count := 0
	for child in view_model_root.get_children():
		if String(child.name).begins_with("FlameBurst"):
			count += 1
	return count

func _count_p14_impact_sparks() -> int:
	var count := 0
	for child in effects_root.get_children():
		if String(child.name).begins_with("ImpactSpark"):
			count += 1
	return count

func run_p14_lasso_checks() -> Dictionary:
	if local_player == null or hud == null:
		return {"ok": false, "error": "P14 lasso checks require local player and HUD"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"lasso")
	if not bool(select_result.get("ok", false)):
		return select_result
	var view_model: Dictionary = select_result.get("view_model", {})
	var view_summary: Dictionary = view_model.get("summary", {})
	var view_model_ok := (
		bool(view_model.get("has_view_model", false))
		and not bool(view_model.get("is_fallback", true))
		and bool(view_summary.get("has_mesh", false))
		and int(view_summary.get("vertex_count", 0)) > 0
		and String(view_summary.get("viewmodel_kind", "")) == "lasso"
		and bool(view_summary.get("material_override", false))
	)
	var tuning_report := get_p14_lasso_tuning_report()
	var lasso_tuning: Dictionary = tuning_report.get("lasso", {})
	var tuning_ok := (
		String(lasso_tuning.get("slot_type", "")) == "secondary"
		and String(lasso_tuning.get("fire_mode", "")) == "utility"
		and bool(lasso_tuning.get("is_hitscan", false))
		and int(lasso_tuning.get("magazine_size", -1)) == 0
		and int(lasso_tuning.get("reserve_ammo_max", -1)) == 0
		and is_equal_approx(float(lasso_tuning.get("body_damage", -1.0)), 0.0)
		and is_equal_approx(float(lasso_tuning.get("head_damage", -1.0)), 0.0)
		and is_equal_approx(float(lasso_tuning.get("shot_cooldown_sec", 0.0)), 5.0)
		and is_equal_approx(float(lasso_tuning.get("spread_degrees", 0.0)), 0.2)
		and is_equal_approx(float(lasso_tuning.get("max_range_m", 0.0)), 28.0)
		and String(lasso_tuning.get("alt_action_type", "")) == "pull"
		and is_equal_approx(float(lasso_tuning.get("propulsion_force", 0.0)), 14.0)
	)
	var lasso_result: Dictionary = await _run_p14_lasso_sequence(6.0)
	var hud_result: Dictionary = await _run_p14_lasso_hud_check()
	return {
		"ok": (
			view_model_ok
			and tuning_ok
			and bool(lasso_result.get("used", false))
			and bool(lasso_result.get("pulled", false))
			and bool(hud_result.get("ok", false))
		),
		"weapon_id": "lasso",
		"selectable_in_runtime": true,
		"view_model_ok": view_model_ok,
		"view_model": view_model,
		"tuning_ok": tuning_ok,
		"tuning": lasso_tuning,
		"offline_use": lasso_result,
		"hud": hud_result,
	}

func run_p14_lasso_pulse() -> Dictionary:
	return await _run_p14_lasso_sequence(6.0)

func prepare_p14_lasso_capture_view() -> Dictionary:
	_clear_p14_lasso_transients()
	var target := _spawn_p14_lasso_target(_get_p14_lasso_target_position())
	await _wait_p07_physics_frames(2)
	var target_position := target.global_position
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": target_position + Vector3(0.0, 0.0, 6.0),
		"target": target_position + Vector3(0.0, 0.9, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"lasso")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "lasso select failed")}
	var state := weapon_controller.get_active_state()
	state.cooldown_remaining_sec = 0.0
	state.is_reloading = false
	var velocity_before := target.velocity
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	await _wait_p07_physics_frames(3)
	var velocity_after := target.velocity
	var expected_pull := (local_player.global_position - target.global_position).normalized()
	var pulled := velocity_after.length() > 1.0 and velocity_after.normalized().dot(expected_pull) > 0.85
	return {
		"ok": bool(fire_result.get("ok", false)) and pulled and _count_p14_impact_sparks() > 0,
		"fire_result": fire_result,
		"pulled": pulled,
		"velocity_before": velocity_before,
		"velocity_after": velocity_after,
		"pull_alignment": velocity_after.normalized().dot(expected_pull) if velocity_after.length() > 0.0 else 0.0,
		"impact_sparks_after": _count_p14_impact_sparks(),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func _run_p14_lasso_hud_check() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"lasso")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "lasso select failed")}
	await _wait_p07_physics_frames(2)
	var hud_summary: Dictionary = hud.get_runtime_smoke_summary()
	var combat_text := String(hud_summary.get("combat_text", ""))
	return {
		"ok": combat_text.contains("Weapon: Lasso") and combat_text.contains("Ammo: 0 / 0"),
		"hud_summary": hud_summary,
	}

func _run_p14_lasso_sequence(distance: float) -> Dictionary:
	_clear_p14_lasso_transients()
	var target := _spawn_p14_lasso_target(_get_p14_lasso_target_position())
	await _wait_p07_physics_frames(2)
	var target_position_before := target.global_position
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": target.global_position + Vector3(0.0, 0.0, distance),
		"target": target.global_position + Vector3(0.0, 0.9, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"lasso")
	if not bool(select_result.get("ok", false)):
		return {"used": false, "pulled": false, "error": select_result.get("error", "lasso select failed")}
	var definition := weapon_controller.get_active_definition()
	var state := weapon_controller.get_active_state()
	state.cooldown_remaining_sec = 0.0
	state.is_reloading = false
	var velocity_before := target.velocity
	var ray_probe := _probe_p14_camera_ray(definition.max_range_m)
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	if not bool(fire_result.get("ok", false)):
		return {"used": false, "pulled": false, "error": fire_result.get("error", "lasso fire failed")}
	await _wait_p07_physics_frames(4)
	var velocity_after := target.velocity
	var expected_pull := (local_player.global_position - target.global_position).normalized()
	var pull_alignment := velocity_after.normalized().dot(expected_pull) if velocity_after.length() > 0.0 else 0.0
	var pulled := velocity_after.length() > 1.0 and pull_alignment > 0.85
	return {
		"used": true,
		"hit": pulled,
		"pulled": pulled,
		"killed": false,
		"weapon_id": &"lasso",
		"pulls_fired": 1,
		"target_position_before": target_position_before,
		"target_position_after": target.global_position,
		"velocity_before": velocity_before,
		"velocity_after": velocity_after,
		"pull_alignment": pull_alignment,
		"ray_probe": ray_probe,
		"impact_sparks_after": _count_p14_impact_sparks(),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
	}

func _get_p14_lasso_target_position() -> Vector3:
	return Vector3(0.0, 18.0, 0.0)

func _spawn_p14_lasso_target(target_position: Vector3) -> CharacterBody3D:
	_spawn_p14_lasso_stage(target_position)
	var target := CharacterBody3D.new()
	target.name = "P14LassoPullTarget_%d" % target.get_instance_id()
	target.set_meta("p14_lasso_transient", true)
	players_root.add_child(target)
	target.global_position = target_position
	target.collision_layer = 1
	target.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	shape_node.position = Vector3(0.0, 0.9, 0.0)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	shape_node.shape = shape
	target.add_child(shape_node)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "LassoPullTargetMesh"
	mesh_instance.position = Vector3(0.0, 0.9, 0.0)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.8
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.45, 0.16, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.95, 0.30, 0.08, 1.0)
	material.emission_energy_multiplier = 0.35
	mesh_instance.material_override = material
	target.add_child(mesh_instance)
	return target

func _spawn_p14_lasso_stage(target_position: Vector3) -> void:
	var stage_root := Node3D.new()
	stage_root.name = "P14LassoStageRoot_%d" % stage_root.get_instance_id()
	stage_root.set_meta("p14_lasso_transient", true)
	add_child(stage_root)
	stage_root.global_position = target_position

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
	floor_body.position = Vector3(0.0, -0.06, 3.0)
	stage_root.add_child(floor_body)

	var floor_shape_node := CollisionShape3D.new()
	floor_shape_node.name = "CollisionShape3D"
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(5.0, 0.12, 9.0)
	floor_shape_node.shape = floor_shape
	floor_body.add_child(floor_shape_node)

	var floor_mesh_instance := MeshInstance3D.new()
	floor_mesh_instance.name = "MeshInstance3D"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = floor_shape.size
	floor_mesh_instance.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.10, 0.18, 0.22, 1.0)
	floor_material.roughness = 0.75
	floor_mesh_instance.material_override = floor_material
	floor_body.add_child(floor_mesh_instance)

	var backplate := MeshInstance3D.new()
	backplate.name = "Backplate"
	backplate.position = Vector3(0.0, 1.45, -0.55)
	var backplate_mesh := BoxMesh.new()
	backplate_mesh.size = Vector3(4.0, 2.8, 0.12)
	backplate.mesh = backplate_mesh
	var backplate_material := StandardMaterial3D.new()
	backplate_material.albedo_color = Color(0.08, 0.14, 0.18, 1.0)
	backplate_material.emission_enabled = true
	backplate_material.emission = Color(0.02, 0.08, 0.10, 1.0)
	backplate_material.emission_energy_multiplier = 0.2
	backplate.material_override = backplate_material
	stage_root.add_child(backplate)

	var light := OmniLight3D.new()
	light.name = "KeyLight"
	light.position = Vector3(0.0, 3.5, 3.0)
	light.light_energy = 2.4
	light.omni_range = 9.0
	stage_root.add_child(light)

func _clear_p14_lasso_transients() -> void:
	if players_root != null:
		for child in players_root.get_children():
			if _is_p14_lasso_transient(child):
				child.queue_free()
	for child in get_children():
		if _is_p14_lasso_transient(child):
			child.queue_free()
	if effects_root != null:
		for child in effects_root.get_children():
			if String(child.name).begins_with("ImpactSpark"):
				child.queue_free()

func _is_p14_lasso_transient(node: Node) -> bool:
	return (
		bool(node.get_meta("p14_lasso_transient", false))
		or String(node.name).begins_with("P14Lasso")
		or node.has_node("LassoPullTargetMesh")
	)

func run_p14_lasso_network_check() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P14 lasso network check requires active host"}
	if _network_player_states.size() < 2:
		return {"ok": false, "pending": true, "error": "P14 lasso network check needs at least two players"}
	var shooter_peer_id := network_session.local_peer_id()
	var victim_peer_id := 0
	for peer_id in _network_player_states.keys():
		if int(peer_id) != shooter_peer_id:
			victim_peer_id = int(peer_id)
			break
	if victim_peer_id == 0:
		return {"ok": false, "pending": true, "error": "P14 lasso network check could not find victim"}
	var shooter_state := _ensure_network_player_state(shooter_peer_id)
	var victim_state := _ensure_network_player_state(victim_peer_id)
	shooter_state["team_id"] = 1
	victim_state["team_id"] = 2
	shooter_state["position"] = Vector3.ZERO
	shooter_state["velocity"] = Vector3.ZERO
	shooter_state["yaw"] = 0.0
	shooter_state["pitch"] = 0.0
	shooter_state["movement_state"] = &"grounded"
	shooter_state["health"] = 100.0
	shooter_state["is_alive"] = true
	shooter_state["spawn_protection_remaining_sec"] = 0.0
	victim_state["position"] = Vector3(0.0, 0.0, -12.0)
	victim_state["velocity"] = Vector3.ZERO
	victim_state["yaw"] = PI
	victim_state["pitch"] = 0.0
	victim_state["movement_state"] = &"grounded"
	victim_state["health"] = 100.0
	victim_state["is_alive"] = true
	victim_state["spawn_protection_remaining_sec"] = 0.0
	_network_player_states[shooter_peer_id] = shooter_state
	_network_player_states[victim_peer_id] = victim_state
	var score_before := match_director.blue_score
	var origin := Vector3(0.0, 0.9, 0.0)
	var direction := (Vector3(0.0, 0.9, -12.0) - origin).normalized()
	var lasso_definition: WeaponDefinition = _weapon_definitions[&"lasso"]
	var peer_weapon_states: Dictionary = _network_weapon_states[shooter_peer_id]
	var lasso_state: Dictionary = peer_weapon_states[String(&"lasso")]
	lasso_state["cooldown_remaining_sec"] = 0.0
	lasso_state["is_reloading"] = false
	peer_weapon_states[String(&"lasso")] = lasso_state
	_network_weapon_states[shooter_peer_id] = peer_weapon_states
	var victim_position_before: Vector3 = victim_state["position"]
	var victim_health_before := float(victim_state["health"])
	_process_authoritative_fire(shooter_peer_id, &"lasso", origin, direction, Vector3.ZERO)
	await _wait_p07_physics_frames(2)
	victim_state = _network_player_states[victim_peer_id]
	var victim_position_after: Vector3 = victim_state["position"]
	var victim_velocity_after: Vector3 = victim_state["velocity"]
	var current_weapon_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"lasso")]
	var pull_direction := (Vector3.ZERO - victim_position_before).normalized()
	var moved_toward_shooter := (victim_position_after - victim_position_before).dot(pull_direction) > 0.1
	var velocity_toward_shooter := victim_velocity_after.normalized().dot(pull_direction) > 0.85 if victim_velocity_after.length() > 0.0 else false
	var health_unchanged := is_equal_approx(float(victim_state["health"]), victim_health_before)
	var score_after := match_director.blue_score
	_send_authoritative_snapshot()
	return {
		"ok": moved_toward_shooter and velocity_toward_shooter and health_unchanged and score_after == score_before,
		"weapon_id": "lasso",
		"shooter_peer_id": shooter_peer_id,
		"victim_peer_id": victim_peer_id,
		"pulls_fired": 1,
		"victim_position_before": victim_position_before,
		"victim_position_after": victim_position_after,
		"victim_velocity_after": victim_velocity_after,
		"moved_toward_shooter": moved_toward_shooter,
		"velocity_toward_shooter": velocity_toward_shooter,
		"victim_health_before": victim_health_before,
		"victim_health_after": float(victim_state["health"]),
		"victim_alive": bool(victim_state["is_alive"]),
		"health_unchanged": health_unchanged,
		"body_damage": lasso_definition.body_damage,
		"head_damage": lasso_definition.head_damage,
		"shot_cooldown_sec": lasso_definition.shot_cooldown_sec,
		"max_range_m": lasso_definition.max_range_m,
		"alt_action_type": lasso_definition.alt_action_type,
		"propulsion_force": lasso_definition.propulsion_force,
		"cooldown_after": float(current_weapon_state.get("cooldown_remaining_sec", -1.0)),
		"score_before": score_before,
		"score_after": score_after,
		"team_counts": _build_network_team_counts(),
	}

func run_p14_redbull_checks() -> Dictionary:
	if local_player == null or hud == null:
		return {"ok": false, "error": "P14 redbull checks require local player and HUD"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"redbull")
	if not bool(select_result.get("ok", false)):
		return select_result
	var view_model: Dictionary = select_result.get("view_model", {})
	var view_summary: Dictionary = view_model.get("summary", {})
	var view_model_ok := (
		bool(view_model.get("has_view_model", false))
		and not bool(view_model.get("is_fallback", true))
		and bool(view_summary.get("has_mesh", false))
		and int(view_summary.get("vertex_count", 0)) > 0
		and String(view_summary.get("viewmodel_kind", "")) == "redbull"
		and bool(view_summary.get("material_override", false))
	)
	var tuning_report := get_p14_redbull_tuning_report()
	var redbull_tuning: Dictionary = tuning_report.get("redbull", {})
	var tuning_ok := (
		String(redbull_tuning.get("slot_type", "")) == "artillery"
		and String(redbull_tuning.get("fire_mode", "")) == "self_buff"
		and not bool(redbull_tuning.get("is_hitscan", true))
		and not bool(redbull_tuning.get("uses_projectile", true))
		and int(redbull_tuning.get("magazine_size", -1)) == 0
		and int(redbull_tuning.get("reserve_ammo_max", -1)) == 0
		and int(redbull_tuning.get("charges_max", -1)) == 2
		and is_equal_approx(float(redbull_tuning.get("body_damage", -1.0)), 0.0)
		and is_equal_approx(float(redbull_tuning.get("head_damage", -1.0)), 0.0)
		and is_equal_approx(float(redbull_tuning.get("shot_cooldown_sec", 0.0)), 0.5)
		and is_equal_approx(float(redbull_tuning.get("effect_duration_sec", 0.0)), 30.0)
		and String(redbull_tuning.get("alt_action_type", "")) == "speed_buff"
		and is_equal_approx(float(redbull_tuning.get("move_speed_multiplier", 0.0)), 1.5)
	)
	var redbull_result: Dictionary = await _run_p14_redbull_sequence()
	var hud_result: Dictionary = await _run_p14_redbull_hud_check()
	return {
		"ok": (
			view_model_ok
			and tuning_ok
			and bool(redbull_result.get("used", false))
			and bool(redbull_result.get("buff_active", false))
			and bool(redbull_result.get("charges_consumed", false))
			and bool(redbull_result.get("cooldown_applied", false))
			and bool(hud_result.get("ok", false))
		),
		"weapon_id": "redbull",
		"selectable_in_runtime": true,
		"view_model_ok": view_model_ok,
		"view_model": view_model,
		"tuning_ok": tuning_ok,
		"tuning": redbull_tuning,
		"offline_use": redbull_result,
		"hud": hud_result,
	}

func run_p14_redbull_pulse() -> Dictionary:
	return await _run_p14_redbull_sequence()

func prepare_p14_redbull_capture_view() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": Vector3(-32.0, 1.8, 22.0),
		"target": Vector3(-7.2, 1.15, 8.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var result: Dictionary = await _run_p14_redbull_sequence(false)
	await _wait_p07_physics_frames(4)
	result["ok"] = (
		bool(result.get("used", false))
		and bool(result.get("buff_active", false))
		and bool(result.get("charges_consumed", false))
		and bool(result.get("cooldown_applied", false))
	)
	result["view_model"] = weapon_controller.get_view_model_runtime_summary()
	result["hud_summary"] = hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {}
	return result

func _run_p14_redbull_hud_check() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"redbull")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "redbull select failed")}
	await _wait_p07_physics_frames(2)
	var hud_summary: Dictionary = hud.get_runtime_smoke_summary()
	var combat_text := String(hud_summary.get("combat_text", ""))
	return {
		"ok": combat_text.contains("Weapon: Redbull") and combat_text.contains("Ammo: 2 charges"),
		"hud_summary": hud_summary,
	}

func _run_p14_redbull_sequence(apply_capture_pose := true) -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	if apply_capture_pose:
		_apply_local_player_capture_pose({
			"position": Vector3(-32.0, 1.8, 22.0),
			"target": Vector3(-7.2, 1.15, 8.0),
		}, Vector3.ZERO, 0.0, 0.0)
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"redbull")
	if not bool(select_result.get("ok", false)):
		return {"used": false, "buff_active": false, "error": select_result.get("error", "redbull select failed")}
	var definition := weapon_controller.get_active_definition()
	var state := weapon_controller.get_active_state()
	state.charges_current = definition.charges_max
	state.cooldown_remaining_sec = 0.0
	state.is_reloading = false
	var speed_multiplier_before := weapon_controller.get_movement_speed_multiplier()
	var charges_before := state.charges_current
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera, true)
	if not bool(fire_result.get("ok", false)):
		return {"used": false, "buff_active": false, "error": fire_result.get("error", "redbull fire failed")}
	var active_summary := weapon_controller.get_active_summary()
	var speed_multiplier_after := weapon_controller.get_movement_speed_multiplier()
	var speed_buff_remaining := float(active_summary.get("speed_buff_remaining_sec", 0.0))
	var charges_after := int(active_summary.get("charges_current", -1))
	var cooldown_after := float(active_summary.get("cooldown_remaining_sec", -1.0))
	var buff_active := (
		is_equal_approx(speed_multiplier_after, definition.move_speed_multiplier)
		and speed_buff_remaining > 29.0
	)
	return {
		"used": true,
		"buff_active": buff_active,
		"killed": false,
		"weapon_id": &"redbull",
		"uses_fired": 1,
		"speed_multiplier_before": speed_multiplier_before,
		"speed_multiplier_after": speed_multiplier_after,
		"speed_buff_remaining_sec": speed_buff_remaining,
		"charges_before": charges_before,
		"charges_after": charges_after,
		"charges_consumed": charges_before == definition.charges_max and charges_after == definition.charges_max - 1,
		"cooldown_after": cooldown_after,
		"cooldown_applied": cooldown_after > 0.0 and cooldown_after <= definition.shot_cooldown_sec,
		"fire_result": fire_result,
		"view_model": weapon_controller.get_view_model_runtime_summary(),
	}

func run_p14_redbull_network_check() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P14 redbull network check requires active host"}
	if _network_player_states.size() < 2:
		return {"ok": false, "pending": true, "error": "P14 redbull network check needs at least two players"}
	var shooter_peer_id := network_session.local_peer_id()
	var victim_peer_id := 0
	for peer_id in _network_player_states.keys():
		if int(peer_id) != shooter_peer_id:
			victim_peer_id = int(peer_id)
			break
	if victim_peer_id == 0:
		return {"ok": false, "pending": true, "error": "P14 redbull network check could not find victim"}
	var shooter_state := _ensure_network_player_state(shooter_peer_id)
	var victim_state := _ensure_network_player_state(victim_peer_id)
	shooter_state["team_id"] = 1
	victim_state["team_id"] = 2
	shooter_state["position"] = Vector3.ZERO
	shooter_state["velocity"] = Vector3.ZERO
	shooter_state["yaw"] = 0.0
	shooter_state["pitch"] = 0.0
	shooter_state["movement_state"] = &"grounded"
	shooter_state["health"] = 100.0
	shooter_state["is_alive"] = true
	shooter_state["spawn_protection_remaining_sec"] = 0.0
	victim_state["position"] = Vector3(0.0, 0.0, -6.0)
	victim_state["velocity"] = Vector3.ZERO
	victim_state["yaw"] = PI
	victim_state["pitch"] = 0.0
	victim_state["movement_state"] = &"grounded"
	victim_state["health"] = 100.0
	victim_state["is_alive"] = true
	victim_state["spawn_protection_remaining_sec"] = 0.0
	_network_player_states[shooter_peer_id] = shooter_state
	_network_player_states[victim_peer_id] = victim_state

	var redbull_definition: WeaponDefinition = _weapon_definitions[&"redbull"]
	var local_sequence: Dictionary = await _run_p14_redbull_sequence(false)
	var peer_weapon_states: Dictionary = _network_weapon_states[shooter_peer_id]
	var redbull_state: Dictionary = peer_weapon_states[String(&"redbull")]
	redbull_state["charges_current"] = redbull_definition.charges_max
	redbull_state["cooldown_remaining_sec"] = 0.0
	redbull_state["is_reloading"] = false
	peer_weapon_states[String(&"redbull")] = redbull_state
	_network_weapon_states[shooter_peer_id] = peer_weapon_states

	var score_before := match_director.blue_score
	var victim_health_before := float(victim_state["health"])
	var charges_before := int(redbull_state["charges_current"])
	_process_authoritative_fire(shooter_peer_id, &"redbull", Vector3(0.0, 0.9, 0.0), Vector3.FORWARD, Vector3.ZERO)
	await _wait_p07_physics_frames(1)
	shooter_state = _network_player_states[shooter_peer_id]
	victim_state = _network_player_states[victim_peer_id]
	var current_weapon_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"redbull")]
	var charges_after := int(current_weapon_state.get("charges_current", -1))
	var cooldown_after := float(current_weapon_state.get("cooldown_remaining_sec", -1.0))
	var score_after := match_director.blue_score
	var health_unchanged := is_equal_approx(float(victim_state["health"]), victim_health_before)
	var charge_consumed := charges_before == redbull_definition.charges_max and charges_after == redbull_definition.charges_max - 1
	var cooldown_applied := cooldown_after > 0.0 and cooldown_after <= redbull_definition.shot_cooldown_sec
	_send_authoritative_snapshot()
	return {
		"ok": (
			bool(local_sequence.get("buff_active", false))
			and charge_consumed
			and cooldown_applied
			and health_unchanged
			and score_after == score_before
		),
		"weapon_id": "redbull",
		"shooter_peer_id": shooter_peer_id,
		"victim_peer_id": victim_peer_id,
		"uses_fired": 1,
		"local_buff": local_sequence,
		"charges_before": charges_before,
		"charges_after": charges_after,
		"charges_consumed": charge_consumed,
		"cooldown_after": cooldown_after,
		"cooldown_applied": cooldown_applied,
		"current_slot_after": shooter_state.get("current_slot", &""),
		"victim_health_before": victim_health_before,
		"victim_health_after": float(victim_state["health"]),
		"health_unchanged": health_unchanged,
		"victim_alive": bool(victim_state["is_alive"]),
		"body_damage": redbull_definition.body_damage,
		"head_damage": redbull_definition.head_damage,
		"charges_max": redbull_definition.charges_max,
		"shot_cooldown_sec": redbull_definition.shot_cooldown_sec,
		"effect_duration_sec": redbull_definition.effect_duration_sec,
		"alt_action_type": redbull_definition.alt_action_type,
		"move_speed_multiplier": redbull_definition.move_speed_multiplier,
		"score_before": score_before,
		"score_after": score_after,
		"team_counts": _build_network_team_counts(),
	}

func run_p14_portal_gun_checks() -> Dictionary:
	if local_player == null or hud == null:
		return {"ok": false, "error": "P14 portal gun checks require local player and HUD"}
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"portal_gun")
	if not bool(select_result.get("ok", false)):
		return select_result
	var view_model: Dictionary = select_result.get("view_model", {})
	var view_summary: Dictionary = view_model.get("summary", {})
	var view_model_ok := (
		bool(view_model.get("has_view_model", false))
		and not bool(view_model.get("is_fallback", true))
		and bool(view_summary.get("has_mesh", false))
		and int(view_summary.get("vertex_count", 0)) > 0
		and String(view_summary.get("viewmodel_kind", "")) == "portal_gun"
		and bool(view_summary.get("material_override", false))
	)
	var tuning_report := get_p14_portal_gun_tuning_report()
	var portal_tuning: Dictionary = tuning_report.get("portal_gun", {})
	var tuning_ok := (
		String(portal_tuning.get("slot_type", "")) == "secondary"
		and String(portal_tuning.get("fire_mode", "")) == "portal"
		and bool(portal_tuning.get("is_hitscan", false))
		and not bool(portal_tuning.get("uses_projectile", true))
		and int(portal_tuning.get("magazine_size", -1)) == 2
		and int(portal_tuning.get("reserve_ammo_max", -1)) == 0
		and is_equal_approx(float(portal_tuning.get("body_damage", -1.0)), 0.0)
		and is_equal_approx(float(portal_tuning.get("head_damage", -1.0)), 0.0)
		and is_equal_approx(float(portal_tuning.get("shot_cooldown_sec", 0.0)), 0.35)
		and is_equal_approx(float(portal_tuning.get("spread_degrees", -1.0)), 0.0)
		and is_equal_approx(float(portal_tuning.get("max_range_m", 0.0)), 80.0)
		and is_equal_approx(float(portal_tuning.get("effect_duration_sec", 0.0)), 60.0)
		and is_equal_approx(float(portal_tuning.get("effect_radius_m", 0.0)), 1.1)
		and String(portal_tuning.get("alt_action_type", "")) == "portal"
	)
	var portal_result: Dictionary = await _run_p14_portal_gun_sequence()
	var hud_result: Dictionary = await _run_p14_portal_gun_hud_check()
	return {
		"ok": (
			view_model_ok
			and tuning_ok
			and bool(portal_result.get("used", false))
			and bool(portal_result.get("placed_two_portals", false))
			and bool(portal_result.get("teleported", false))
			and bool(portal_result.get("momentum_preserved", false))
			and bool(portal_result.get("ammo_consumed", false))
			and bool(hud_result.get("ok", false))
		),
		"weapon_id": "portal_gun",
		"selectable_in_runtime": true,
		"view_model_ok": view_model_ok,
		"view_model": view_model,
		"tuning_ok": tuning_ok,
		"tuning": portal_tuning,
		"offline_use": portal_result,
		"hud": hud_result,
	}

func run_p14_portal_gun_pulse() -> Dictionary:
	return await _run_p14_portal_gun_sequence()

func prepare_p14_portal_gun_capture_view() -> Dictionary:
	var result: Dictionary = await _run_p14_portal_gun_sequence(false)
	var weapon_controller := local_player.get_weapon_controller()
	var stage := _get_p14_portal_stage_points()
	_apply_local_player_capture_pose({
		"position": stage.get("capture_position", Vector3.ZERO),
		"target": stage.get("capture_target", Vector3.ZERO),
	}, Vector3.ZERO, 0.0, 0.0)
	await _wait_p07_physics_frames(4)
	result["ok"] = (
		bool(result.get("used", false))
		and bool(result.get("placed_two_portals", false))
		and bool(result.get("teleported", false))
		and bool(result.get("momentum_preserved", false))
	)
	result["view_model"] = weapon_controller.get_view_model_runtime_summary()
	result["hud_summary"] = hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {}
	result["portal_summary"] = weapon_controller.get_portal_runtime_summary()
	return result

func _run_p14_portal_gun_hud_check() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"portal_gun")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "portal gun select failed")}
	await _wait_p07_physics_frames(2)
	var hud_summary: Dictionary = hud.get_runtime_smoke_summary()
	var combat_text := String(hud_summary.get("combat_text", ""))
	return {
		"ok": combat_text.contains("Weapon: Portal Gun") and combat_text.contains("Ammo: 2 / 0"),
		"hud_summary": hud_summary,
	}

func _run_p14_portal_gun_sequence(include_transport := true) -> Dictionary:
	_clear_p14_portal_gun_transients()
	var stage := _spawn_p14_portal_stage()
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"portal_gun")
	if not bool(select_result.get("ok", false)):
		return {"used": false, "placed_two_portals": false, "error": select_result.get("error", "portal gun select failed")}
	var definition := weapon_controller.get_active_definition()
	weapon_controller.reset_portals_for_verification()
	var state := weapon_controller.get_active_state()
	state.ammo_in_mag = definition.magazine_size
	state.reserve_ammo = definition.reserve_ammo_max
	state.cooldown_remaining_sec = 0.0
	state.is_reloading = false

	var first_fire := await _fire_p14_portal_at(stage.get("a_target", Vector3.ZERO), stage.get("a_shot_position", Vector3.ZERO))
	await _wait_p07_physics_frames(26)
	state.cooldown_remaining_sec = 0.0
	var second_fire := await _fire_p14_portal_at(stage.get("b_target", Vector3.ZERO), stage.get("b_shot_position", Vector3.ZERO))
	await _wait_p07_physics_frames(3)

	var active_summary := weapon_controller.get_active_summary()
	var portal_summary: Dictionary = weapon_controller.get_portal_runtime_summary()
	var ammo_after := int(active_summary.get("ammo_in_mag", -1))
	var placed_two := bool(portal_summary.get("both_active", false)) and int(portal_summary.get("marker_count", 0)) >= 2
	var teleported := false
	var momentum_preserved := false
	var transport_before := local_player.global_position
	var transport_after := local_player.global_position
	var velocity_before := local_player.velocity
	var velocity_after := local_player.velocity
	if include_transport and placed_two:
		var portal_a: Vector3 = portal_summary.get("a_position", Vector3.ZERO)
		var portal_b: Vector3 = portal_summary.get("b_position", Vector3.ZERO)
		var radius := float(portal_summary.get("effect_radius_m", definition.effect_radius_m))
		velocity_before = (portal_b - portal_a).normalized() * 12.0
		local_player.global_position = portal_a
		local_player.velocity = velocity_before
		transport_before = local_player.global_position
		teleported = weapon_controller.try_apply_portal_transport(local_player)
		transport_after = local_player.global_position
		velocity_after = local_player.velocity
		momentum_preserved = (
			teleported
			and velocity_after.is_equal_approx(velocity_before)
			and transport_after.distance_to(portal_b) <= radius + 0.2
		)
	return {
		"used": true,
		"placed_two_portals": placed_two,
		"teleported": teleported if include_transport else bool(portal_summary.get("both_active", false)),
		"momentum_preserved": momentum_preserved if include_transport else true,
		"killed": false,
		"weapon_id": &"portal_gun",
		"shots_fired": 2,
		"first_fire": first_fire,
		"second_fire": second_fire,
		"portal_summary": portal_summary,
		"ammo_before": definition.magazine_size,
		"ammo_after": ammo_after,
		"ammo_consumed": ammo_after == 0,
		"cooldown_after": float(active_summary.get("cooldown_remaining_sec", -1.0)),
		"transport_position_before": transport_before,
		"transport_position_after": transport_after,
		"velocity_before": velocity_before,
		"velocity_after": velocity_after,
		"impact_sparks_after": _count_p14_impact_sparks(),
		"view_model": weapon_controller.get_view_model_runtime_summary(),
	}

func _fire_p14_portal_at(target: Vector3, shot_position: Vector3) -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	_apply_local_player_capture_pose({
		"position": shot_position,
		"target": target,
	}, Vector3.ZERO, 0.0, 0.0)
	var definition := weapon_controller.get_active_definition()
	var ray_probe := _probe_p14_camera_ray(definition.max_range_m)
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera, true)
	return {
		"ok": bool(fire_result.get("ok", false)),
		"ray_probe": ray_probe,
		"fire_result": fire_result,
		"portal_summary": weapon_controller.get_portal_runtime_summary(),
	}

func _get_p14_portal_stage_points() -> Dictionary:
	var origin := Vector3(0.0, 18.0, 0.0)
	return {
		"origin": origin,
		"a_target": origin + Vector3(-1.45, 1.08, 0.0),
		"b_target": origin + Vector3(1.45, 1.08, 0.0),
		"a_shot_position": origin + Vector3(-1.45, 0.0, 6.0),
		"b_shot_position": origin + Vector3(1.45, 0.0, 6.0),
		"capture_position": origin + Vector3(0.0, 0.0, 6.6),
		"capture_target": origin + Vector3(0.0, 1.08, 0.0),
	}

func _spawn_p14_portal_stage() -> Dictionary:
	_clear_p14_portal_gun_transients()
	var points := _get_p14_portal_stage_points()
	var origin: Vector3 = points["origin"]
	var stage_root := Node3D.new()
	stage_root.name = "P14PortalStageRoot_%d" % stage_root.get_instance_id()
	stage_root.set_meta("p14_portal_transient", true)
	add_child(stage_root)
	stage_root.global_position = origin

	var floor_body := StaticBody3D.new()
	floor_body.name = "P14PortalStageFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
	floor_body.position = Vector3(0.0, -0.06, 3.2)
	stage_root.add_child(floor_body)
	var floor_shape_node := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(6.4, 0.12, 9.2)
	floor_shape_node.shape = floor_shape
	floor_body.add_child(floor_shape_node)
	var floor_mesh_instance := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = floor_shape.size
	floor_mesh_instance.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.10, 0.16, 0.22, 1.0)
	floor_material.roughness = 0.75
	floor_mesh_instance.material_override = floor_material
	floor_body.add_child(floor_mesh_instance)

	var wall_body := StaticBody3D.new()
	wall_body.name = "P14PortalStageWall"
	wall_body.collision_layer = 1
	wall_body.collision_mask = 1
	wall_body.position = Vector3(0.0, 1.08, -0.06)
	stage_root.add_child(wall_body)
	var wall_shape_node := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(4.8, 2.8, 0.12)
	wall_shape_node.shape = wall_shape
	wall_body.add_child(wall_shape_node)
	var wall_mesh_instance := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = wall_shape.size
	wall_mesh_instance.mesh = wall_mesh
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.07, 0.11, 0.15, 1.0)
	wall_material.emission_enabled = true
	wall_material.emission = Color(0.01, 0.04, 0.08, 1.0)
	wall_material.emission_energy_multiplier = 0.25
	wall_mesh_instance.material_override = wall_material
	wall_body.add_child(wall_mesh_instance)

	var light := OmniLight3D.new()
	light.name = "P14PortalStageKeyLight"
	light.position = Vector3(0.0, 3.5, 3.2)
	light.light_energy = 2.6
	light.omni_range = 9.0
	stage_root.add_child(light)
	return points

func _clear_p14_portal_gun_transients() -> void:
	if local_player != null:
		local_player.get_weapon_controller().reset_portals_for_verification()
	for child in get_children():
		if bool(child.get_meta("p14_portal_transient", false)) or String(child.name).begins_with("P14PortalStage"):
			child.queue_free()
	if effects_root != null:
		for child in effects_root.get_children():
			if String(child.name).begins_with("ImpactSpark") or String(child.name).begins_with("PortalMarker"):
				child.queue_free()

func run_p14_portal_gun_network_check() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P14 portal gun network check requires active host"}
	if _network_player_states.size() < 2:
		return {"ok": false, "pending": true, "error": "P14 portal gun network check needs at least two players"}
	var shooter_peer_id := network_session.local_peer_id()
	var victim_peer_id := 0
	for peer_id in _network_player_states.keys():
		if int(peer_id) != shooter_peer_id:
			victim_peer_id = int(peer_id)
			break
	if victim_peer_id == 0:
		return {"ok": false, "pending": true, "error": "P14 portal gun network check could not find victim"}
	var shooter_state := _ensure_network_player_state(shooter_peer_id)
	var victim_state := _ensure_network_player_state(victim_peer_id)
	shooter_state["team_id"] = 1
	victim_state["team_id"] = 2
	shooter_state["position"] = Vector3.ZERO
	shooter_state["velocity"] = Vector3.ZERO
	shooter_state["yaw"] = 0.0
	shooter_state["pitch"] = 0.0
	shooter_state["movement_state"] = &"grounded"
	shooter_state["health"] = 100.0
	shooter_state["is_alive"] = true
	shooter_state["spawn_protection_remaining_sec"] = 0.0
	victim_state["position"] = Vector3(0.0, 0.0, -6.0)
	victim_state["velocity"] = Vector3.ZERO
	victim_state["yaw"] = PI
	victim_state["pitch"] = 0.0
	victim_state["movement_state"] = &"grounded"
	victim_state["health"] = 100.0
	victim_state["is_alive"] = true
	victim_state["spawn_protection_remaining_sec"] = 0.0
	_network_player_states[shooter_peer_id] = shooter_state
	_network_player_states[victim_peer_id] = victim_state

	var freeze_before := _capture_freeze_remote_proxies
	_capture_freeze_remote_proxies = true
	var local_sequence: Dictionary = await _run_p14_portal_gun_sequence()
	_capture_freeze_remote_proxies = freeze_before
	var portal_definition: WeaponDefinition = _weapon_definitions[&"portal_gun"]
	var peer_weapon_states: Dictionary = _network_weapon_states[shooter_peer_id]
	var portal_state: Dictionary = peer_weapon_states[String(&"portal_gun")]
	portal_state["ammo_in_mag"] = portal_definition.magazine_size
	portal_state["reserve_ammo"] = portal_definition.reserve_ammo_max
	portal_state["cooldown_remaining_sec"] = 0.0
	portal_state["is_reloading"] = false
	peer_weapon_states[String(&"portal_gun")] = portal_state
	_network_weapon_states[shooter_peer_id] = peer_weapon_states

	var score_before := match_director.blue_score
	var victim_health_before := float(victim_state["health"])
	var ammo_before := int(portal_state["ammo_in_mag"])
	for index in range(2):
		_process_authoritative_fire(shooter_peer_id, &"portal_gun", Vector3(0.0, 0.9, 0.0), Vector3.FORWARD, Vector3.ZERO)
		await _wait_p07_physics_frames(1)
		if index == 0:
			portal_state = _network_weapon_states[shooter_peer_id][String(&"portal_gun")]
			portal_state["cooldown_remaining_sec"] = 0.0
			peer_weapon_states = _network_weapon_states[shooter_peer_id]
			peer_weapon_states[String(&"portal_gun")] = portal_state
			_network_weapon_states[shooter_peer_id] = peer_weapon_states
	shooter_state = _network_player_states[shooter_peer_id]
	victim_state = _network_player_states[victim_peer_id]
	var current_weapon_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"portal_gun")]
	var ammo_after := int(current_weapon_state.get("ammo_in_mag", -1))
	var cooldown_after := float(current_weapon_state.get("cooldown_remaining_sec", -1.0))
	var score_after := match_director.blue_score
	var health_unchanged := is_equal_approx(float(victim_state["health"]), victim_health_before)
	var ammo_consumed := ammo_before == portal_definition.magazine_size and ammo_after == 0
	_send_authoritative_snapshot()
	return {
		"ok": (
				bool(local_sequence.get("placed_two_portals", false))
				and bool(local_sequence.get("teleported", false))
				and bool(local_sequence.get("momentum_preserved", false))
				and bool(local_sequence.get("ammo_consumed", false))
				and ammo_consumed
				and health_unchanged
				and score_after == score_before
		),
		"weapon_id": "portal_gun",
		"shooter_peer_id": shooter_peer_id,
		"victim_peer_id": victim_peer_id,
		"shots_fired": 2,
		"local_portal": local_sequence,
		"ammo_before": ammo_before,
		"ammo_after": ammo_after,
		"ammo_consumed": ammo_consumed,
		"cooldown_after": cooldown_after,
		"current_slot_after": shooter_state.get("current_slot", &""),
		"victim_health_before": victim_health_before,
		"victim_health_after": float(victim_state["health"]),
		"health_unchanged": health_unchanged,
		"victim_alive": bool(victim_state["is_alive"]),
		"body_damage": portal_definition.body_damage,
		"head_damage": portal_definition.head_damage,
		"magazine_size": portal_definition.magazine_size,
		"reserve_ammo_max": portal_definition.reserve_ammo_max,
		"shot_cooldown_sec": portal_definition.shot_cooldown_sec,
		"max_range_m": portal_definition.max_range_m,
		"effect_duration_sec": portal_definition.effect_duration_sec,
		"effect_radius_m": portal_definition.effect_radius_m,
		"alt_action_type": portal_definition.alt_action_type,
		"score_before": score_before,
		"score_after": score_after,
		"team_counts": _build_network_team_counts(),
	}

func prepare_p07_combat_hud_capture() -> Dictionary:
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"ok": false, "error": "P07 combat HUD capture found no dummies"}
	var target := dummies[0] as Node3D
	var weapon_controller := local_player.get_weapon_controller()
	weapon_controller.reset_loadout()
	_apply_local_player_capture_pose({
		"position": target.global_position + Vector3(0.0, 0.4, 2.4),
		"target": target.global_position + Vector3(0.0, 1.0, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	weapon_controller.select_slot_for_verification(&"primary")
	await _wait_p07_physics_frames(2)
	weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	await _wait_p07_physics_frames(2)
	_apply_local_player_capture_pose({
		"position": target.global_position + Vector3(3.2, 1.45, 6.0),
		"target": target.global_position + Vector3(-0.8, 0.65, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	return {
		"ok": true,
		"hud_summary": hud.get_runtime_smoke_summary() if hud.has_method("get_runtime_smoke_summary") else {},
	}

func run_p08_multiplayer_checks() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P08 host checks require active server"}
	var remote_report := _build_p06_remote_report()
	var remote_ready := (
		int(remote_report.get("network_player_count", 0)) >= 2
		and int(remote_report.get("remote_proxy_count", 0)) >= 1
		and int(remote_report.get("humanoid_remote_count", 0)) >= 1
		and int(remote_report.get("fallback_remote_count", 0)) == 0
		and int(remote_report.get("synced_remote_count", 0)) >= 1
	)
	if not remote_ready:
		return {
			"ok": false,
			"pending": true,
			"same_arena": false,
			"host_can_see_remote_humanoid": false,
			"remote_movement_sync": false,
			"remote_report": remote_report,
		}
	var authority_result := run_network_authority_smoke_check()
	if not bool(authority_result.get("ok", false)):
		return {
			"ok": false,
			"error": authority_result.get("error", "P08 authoritative combat failed"),
			"same_arena": true,
			"host_can_see_remote_humanoid": true,
			"remote_movement_sync": true,
			"authoritative_result": authority_result,
			"remote_report": remote_report,
		}
	await _wait_p07_physics_frames(12)
	var final_remote_report := _build_p06_remote_report()
	var snapshot := _build_match_snapshot()
	return {
		"ok": true,
		"arena": "arena_downtown_01_art",
		"same_arena": true,
		"network_player_count": _network_player_states.size(),
		"host_peer_id": network_session.local_peer_id(),
		"host_can_see_remote_humanoid": int(final_remote_report.get("humanoid_remote_count", 0)) >= 1 and int(final_remote_report.get("fallback_remote_count", 0)) == 0,
		"remote_movement_sync": int(final_remote_report.get("synced_remote_count", 0)) >= 1,
		"authoritative_combat": true,
		"death_respawn": true,
		"authoritative_result": authority_result,
		"remote_report_before_combat": remote_report,
		"remote_report_after_combat": final_remote_report,
		"match_summary": {
			"phase": snapshot.get("phase", &""),
			"blue_score": snapshot.get("blue_score", 0),
			"orange_score": snapshot.get("orange_score", 0),
			"players": snapshot.get("players", []),
		},
	}

func run_p12_2v2_checks() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P12 host checks require active server"}
	var remote_report := _build_p06_remote_report()
	var team_counts := _build_network_team_counts()
	var remote_ready := (
		_network_player_states.size() >= 4
		and int(remote_report.get("remote_proxy_count", 0)) >= 3
		and int(remote_report.get("humanoid_remote_count", 0)) >= 3
		and int(remote_report.get("fallback_remote_count", 0)) == 0
		and int(remote_report.get("synced_remote_count", 0)) >= 3
	)
	if not remote_ready:
		return {
			"ok": false,
			"pending": true,
			"team_counts": team_counts,
			"remote_report": remote_report,
		}
	if int(team_counts.get(1, 0)) != 2 or int(team_counts.get(2, 0)) != 2:
		return {
			"ok": false,
			"error": "P12 expected 2v2 team assignment",
			"team_counts": team_counts,
			"remote_report": remote_report,
		}
	var spawn_report := _build_p12_spawn_report()
	if not bool(spawn_report.get("ok", false)):
		return {
			"ok": false,
			"error": "P12 spawn report failed",
			"team_counts": team_counts,
			"spawn_report": spawn_report,
			"remote_report": remote_report,
		}
	var authority_result := run_network_authority_smoke_check()
	if not bool(authority_result.get("ok", false)):
		return {
			"ok": false,
			"error": authority_result.get("error", "P12 authoritative combat failed"),
			"team_counts": team_counts,
			"spawn_report": spawn_report,
			"authoritative_result": authority_result,
			"remote_report": remote_report,
		}
	await _wait_p07_physics_frames(12)
	var snapshot := _build_match_snapshot()
	var final_team_counts := _build_network_team_counts()
	var final_remote_report := _build_p06_remote_report()
	return {
		"ok": true,
		"arena": "arena_downtown_01_art",
		"network_player_count": _network_player_states.size(),
		"host_peer_id": network_session.local_peer_id(),
		"team_counts": final_team_counts,
		"team_assignment_2v2": int(final_team_counts.get(1, 0)) == 2 and int(final_team_counts.get(2, 0)) == 2,
		"spawn_report": spawn_report,
		"remote_humanoid_count": int(final_remote_report.get("humanoid_remote_count", 0)),
		"fallback_remote_count": int(final_remote_report.get("fallback_remote_count", 0)),
		"synced_remote_count": int(final_remote_report.get("synced_remote_count", 0)),
		"authoritative_combat": true,
		"score_verified": int(snapshot.get("blue_score", 0)) + int(snapshot.get("orange_score", 0)) >= 1,
		"authoritative_result": authority_result,
		"match_summary": {
			"phase": snapshot.get("phase", &""),
			"blue_score": snapshot.get("blue_score", 0),
			"orange_score": snapshot.get("orange_score", 0),
			"players": snapshot.get("players", []),
		},
		"remote_report": final_remote_report,
	}

func run_p13_3v3_checks() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P13 host checks require active server"}
	const REQUIRED_PLAYERS := 6
	const REQUIRED_REMOTE_PLAYERS := 5
	const REQUIRED_PER_TEAM := 3
	var remote_report := _build_p06_remote_report()
	var team_counts := _build_network_team_counts()
	var remote_ready := (
		_network_player_states.size() >= REQUIRED_PLAYERS
		and int(remote_report.get("remote_proxy_count", 0)) >= REQUIRED_REMOTE_PLAYERS
		and int(remote_report.get("humanoid_remote_count", 0)) >= REQUIRED_REMOTE_PLAYERS
		and int(remote_report.get("fallback_remote_count", 0)) == 0
		and int(remote_report.get("synced_remote_count", 0)) >= REQUIRED_REMOTE_PLAYERS
	)
	if not remote_ready:
		return {
			"ok": false,
			"pending": true,
			"capacity_players": NetworkConstants.MAX_PLAYERS,
			"required_players": REQUIRED_PLAYERS,
			"team_counts": team_counts,
			"remote_report": remote_report,
		}
	if int(team_counts.get(1, 0)) != REQUIRED_PER_TEAM or int(team_counts.get(2, 0)) != REQUIRED_PER_TEAM:
		return {
			"ok": false,
			"error": "P13 expected 3v3 team assignment",
			"capacity_players": NetworkConstants.MAX_PLAYERS,
			"required_players": REQUIRED_PLAYERS,
			"team_counts": team_counts,
			"remote_report": remote_report,
		}
	var spawn_report := _build_network_spawn_report(REQUIRED_PLAYERS, REQUIRED_PER_TEAM)
	if not bool(spawn_report.get("ok", false)):
		return {
			"ok": false,
			"error": "P13 spawn capacity report failed",
			"capacity_players": NetworkConstants.MAX_PLAYERS,
			"required_players": REQUIRED_PLAYERS,
			"team_counts": team_counts,
			"spawn_report": spawn_report,
			"remote_report": remote_report,
		}
	var blue_score_result := _run_network_team_score_check(1, 2)
	if not bool(blue_score_result.get("ok", false)):
		return {
			"ok": false,
			"error": blue_score_result.get("error", "P13 blue team score check failed"),
			"capacity_players": NetworkConstants.MAX_PLAYERS,
			"required_players": REQUIRED_PLAYERS,
			"team_counts": team_counts,
			"spawn_report": spawn_report,
			"blue_score_result": blue_score_result,
			"remote_report": remote_report,
		}
	var orange_score_result := _run_network_team_score_check(2, 1)
	if not bool(orange_score_result.get("ok", false)):
		return {
			"ok": false,
			"error": orange_score_result.get("error", "P13 orange team score check failed"),
			"capacity_players": NetworkConstants.MAX_PLAYERS,
			"required_players": REQUIRED_PLAYERS,
			"team_counts": team_counts,
			"spawn_report": spawn_report,
			"blue_score_result": blue_score_result,
			"orange_score_result": orange_score_result,
			"remote_report": remote_report,
		}
	await _wait_p07_physics_frames(12)
	var snapshot := _build_match_snapshot()
	var final_team_counts := _build_network_team_counts()
	var final_remote_report := _build_p06_remote_report()
	var blue_score := int(snapshot.get("blue_score", 0))
	var orange_score := int(snapshot.get("orange_score", 0))
	return {
		"ok": true,
		"arena": "arena_downtown_01_art",
		"capacity_players": NetworkConstants.MAX_PLAYERS,
		"required_players": REQUIRED_PLAYERS,
		"network_player_count": _network_player_states.size(),
		"host_peer_id": network_session.local_peer_id(),
		"team_counts": final_team_counts,
		"team_assignment_3v3": int(final_team_counts.get(1, 0)) == 3 and int(final_team_counts.get(2, 0)) == 3,
		"spawn_report": spawn_report,
		"remote_humanoid_count": int(final_remote_report.get("humanoid_remote_count", 0)),
		"fallback_remote_count": int(final_remote_report.get("fallback_remote_count", 0)),
		"synced_remote_count": int(final_remote_report.get("synced_remote_count", 0)),
		"authoritative_combat": true,
		"team_score_verified": blue_score >= 1 and orange_score >= 1,
		"blue_score_result": blue_score_result,
		"orange_score_result": orange_score_result,
		"match_summary": {
			"phase": snapshot.get("phase", &""),
			"blue_score": blue_score,
			"orange_score": orange_score,
			"players": snapshot.get("players", []),
		},
		"remote_report": final_remote_report,
		"performance": _build_performance_report(),
	}

func prepare_p08_multiplayer_capture_view() -> Dictionary:
	var report := _build_p06_remote_report()
	if not bool(report.get("ok", false)):
		return report
	var proxy := _select_p06_capture_proxy()
	if proxy == null:
		return {"ok": false, "error": "no P08 remote proxy available for capture", "report": report}
	var remote_position := proxy.target_position
	if remote_position == Vector3.ZERO:
		remote_position = proxy.global_position
	var offset := Vector3(-4.0, 1.7, 5.2)
	if remote_position.x < 0.0:
		offset.x = -offset.x
	if remote_position.z > 0.0:
		offset.z = -offset.z
	_apply_local_player_capture_pose({
		"position": remote_position + offset,
		"target": remote_position + Vector3(0.0, 0.95, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	return {
		"ok": true,
		"report": report,
		"capture_peer_id": proxy.peer_id,
	}

func prepare_p10a_remote_player_capture_view() -> Dictionary:
	var report := _build_p06_remote_report()
	if not bool(report.get("ok", false)):
		return report
	var proxy := _select_p06_capture_proxy()
	if proxy == null:
		return {"ok": false, "error": "no P10A remote proxy available for capture", "report": report}
	_capture_freeze_remote_proxies = true
	for child in effects_root.get_children():
		child.queue_free()
	for dummy in get_tree().get_nodes_in_group("combat_dummies"):
		if dummy is Node3D:
			(dummy as Node3D).visible = false
	for child in get_children():
		if String(child.name).begins_with("P10ARemoteCapture"):
			child.queue_free()
	if active_map != null:
		active_map.visible = false
	var capture_floor_y := 18.0
	var remote_position := Vector3(0.0, capture_floor_y, 0.0)
	var state := _ensure_network_player_state(proxy.peer_id)
	state["position"] = remote_position
	state["velocity"] = Vector3.ZERO
	state["yaw"] = PI
	state["pitch"] = 0.0
	state["movement_state"] = &"grounded"
	state["is_alive"] = true
	state["health"] = 100.0
	proxy.scale = Vector3(1.45, 1.45, 1.45)
	proxy.interpolation_sec = 0.0
	proxy.global_position = remote_position
	proxy.rotation.y = PI
	proxy.apply_snapshot(remote_position, PI, 0.0, &"grounded", proxy.active_slot)
	proxy.apply_combat_state(int(state["team_id"]), 100.0, true)
	var capture_floor := MeshInstance3D.new()
	capture_floor.name = "P10ARemoteCaptureFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(7.0, 0.12, 4.2)
	capture_floor.mesh = floor_mesh
	capture_floor.position = Vector3(0.0, capture_floor_y - 0.08, 0.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.045, 0.055, 0.065, 1.0)
	floor_material.roughness = 0.84
	capture_floor.material_override = floor_material
	add_child(capture_floor)
	var capture_backplate := MeshInstance3D.new()
	capture_backplate.name = "P10ARemoteCaptureBackplate"
	var backplate_mesh := BoxMesh.new()
	backplate_mesh.size = Vector3(7.0, 2.8, 0.12)
	capture_backplate.mesh = backplate_mesh
	capture_backplate.position = Vector3(0.0, capture_floor_y + 1.25, -1.1)
	var backplate_material := StandardMaterial3D.new()
	backplate_material.albedo_color = Color(0.10, 0.055, 0.035, 1.0)
	backplate_material.emission_enabled = true
	backplate_material.emission = Color(1.0, 0.34, 0.10, 1.0)
	backplate_material.emission_energy_multiplier = 0.16
	capture_backplate.material_override = backplate_material
	add_child(capture_backplate)
	var capture_light := OmniLight3D.new()
	capture_light.name = "P10ARemoteCaptureLight"
	capture_light.light_energy = 7.0
	capture_light.omni_range = 16.0
	capture_light.position = Vector3(0.0, capture_floor_y + 4.5, 4.0)
	add_child(capture_light)
	_apply_local_player_capture_pose({
		"position": Vector3(0.0, capture_floor_y, 7.2),
		"target": remote_position + Vector3(0.0, 1.25, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	local_player.camera.fov = 62.0
	local_player.set_physics_process(false)
	_send_authoritative_snapshot()
	return {
		"ok": true,
		"report": _build_p06_remote_report(),
		"capture_peer_id": proxy.peer_id,
		"visible_remote_humanoid_count": 1,
		"team_readability_method": "orange humanoid with emissive chest/back/shoulder plates on a neutral capture floor",
	}

func prepare_p12_2v2_capture_view() -> Dictionary:
	var report := _build_p06_remote_report()
	if int(report.get("humanoid_remote_count", 0)) < 3 or int(report.get("fallback_remote_count", 0)) != 0:
		return {"ok": false, "error": "P12 expected three humanoid remote proxies", "report": report}
	_capture_freeze_remote_proxies = true
	var remote_peer_ids := []
	for peer_id in remote_proxies.keys():
		remote_peer_ids.append(int(peer_id))
	remote_peer_ids.sort()
	if remote_peer_ids.size() < 3:
		return {"ok": false, "error": "P12 expected three remote proxy ids", "report": report}
	for child in effects_root.get_children():
		child.queue_free()
	for dummy in get_tree().get_nodes_in_group("combat_dummies"):
		if dummy is Node3D:
			(dummy as Node3D).visible = false
	var capture_floor_y := 18.0
	var lineup_positions := [
		Vector3(-3.0, capture_floor_y, 0.0),
		Vector3(0.0, capture_floor_y, 0.0),
		Vector3(3.0, capture_floor_y, 0.0),
	]
	for index in range(3):
		var peer_id := int(remote_peer_ids[index])
		var proxy: RemotePlayerProxy = remote_proxies[peer_id]
		var state := _ensure_network_player_state(peer_id)
		var position: Vector3 = lineup_positions[index]
		state["position"] = position
		state["yaw"] = PI
		state["pitch"] = 0.0
		state["movement_state"] = &"grounded"
		state["is_alive"] = true
		state["health"] = 100.0
		proxy.scale = Vector3(1.5, 1.5, 1.5)
		proxy.interpolation_sec = 0.0
		proxy.global_position = position
		proxy.rotation.y = PI
		proxy.apply_snapshot(position, PI, 0.0, &"grounded", proxy.active_slot)
		proxy.apply_combat_state(int(state["team_id"]), 100.0, true)
	for child in get_children():
		if String(child.name).begins_with("P12Capture"):
			child.queue_free()
	if active_map != null:
		active_map.visible = false
	var capture_floor := MeshInstance3D.new()
	capture_floor.name = "P12CaptureFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(8.0, 0.12, 4.0)
	capture_floor.mesh = floor_mesh
	capture_floor.position = Vector3(0.0, capture_floor_y - 0.08, 0.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.08, 0.10, 0.12, 1.0)
	floor_material.roughness = 0.8
	capture_floor.material_override = floor_material
	add_child(capture_floor)
	var capture_light := OmniLight3D.new()
	capture_light.name = "P12CaptureLight"
	capture_light.light_energy = 6.0
	capture_light.omni_range = 18.0
	capture_light.position = Vector3(0.0, capture_floor_y + 5.0, 5.0)
	add_child(capture_light)
	_apply_local_player_capture_pose({
		"position": Vector3(0.0, capture_floor_y, 9.0),
		"target": Vector3(0.0, capture_floor_y + 1.35, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	local_player.camera.fov = 60.0
	local_player.view_model_root.visible = false
	local_player.set_physics_process(false)
	_send_authoritative_snapshot()
	return {
		"ok": true,
		"report": _build_p06_remote_report(),
		"visible_remote_humanoid_count": 3,
		"capture_peer_ids": remote_peer_ids.slice(0, 3),
	}

func prepare_p13_3v3_capture_view() -> Dictionary:
	var report := _build_p06_remote_report()
	if int(report.get("humanoid_remote_count", 0)) < 5 or int(report.get("fallback_remote_count", 0)) != 0:
		return {"ok": false, "error": "P13 expected five humanoid remote proxies", "report": report}
	_capture_freeze_remote_proxies = true
	var remote_peer_ids := []
	for peer_id in remote_proxies.keys():
		remote_peer_ids.append(int(peer_id))
	remote_peer_ids.sort()
	if remote_peer_ids.size() < 5:
		return {"ok": false, "error": "P13 expected five remote proxy ids", "report": report}
	for child in effects_root.get_children():
		child.queue_free()
	for dummy in get_tree().get_nodes_in_group("combat_dummies"):
		if dummy is Node3D:
			(dummy as Node3D).visible = false
	var capture_floor_y := 18.0
	var lineup_positions := [
		Vector3(-4.8, capture_floor_y, 0.0),
		Vector3(-2.4, capture_floor_y, 0.0),
		Vector3(0.0, capture_floor_y, 0.0),
		Vector3(2.4, capture_floor_y, 0.0),
		Vector3(4.8, capture_floor_y, 0.0),
	]
	for index in range(5):
		var peer_id := int(remote_peer_ids[index])
		var proxy: RemotePlayerProxy = remote_proxies[peer_id]
		var state := _ensure_network_player_state(peer_id)
		var position: Vector3 = lineup_positions[index]
		state["position"] = position
		state["yaw"] = PI
		state["pitch"] = 0.0
		state["movement_state"] = &"grounded"
		state["is_alive"] = true
		state["health"] = 100.0
		proxy.scale = Vector3(1.25, 1.25, 1.25)
		proxy.interpolation_sec = 0.0
		proxy.global_position = position
		proxy.rotation.y = PI
		proxy.apply_snapshot(position, PI, 0.0, &"grounded", proxy.active_slot)
		proxy.apply_combat_state(int(state["team_id"]), 100.0, true)
	for child in get_children():
		if String(child.name).begins_with("P13Capture"):
			child.queue_free()
	if active_map != null:
		active_map.visible = false
	var capture_floor := MeshInstance3D.new()
	capture_floor.name = "P13CaptureFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(12.0, 0.12, 4.0)
	capture_floor.mesh = floor_mesh
	capture_floor.position = Vector3(0.0, capture_floor_y - 0.08, 0.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.08, 0.10, 0.12, 1.0)
	floor_material.roughness = 0.8
	capture_floor.material_override = floor_material
	add_child(capture_floor)
	var capture_light := OmniLight3D.new()
	capture_light.name = "P13CaptureLight"
	capture_light.light_energy = 7.0
	capture_light.omni_range = 20.0
	capture_light.position = Vector3(0.0, capture_floor_y + 5.0, 5.5)
	add_child(capture_light)
	_apply_local_player_capture_pose({
		"position": Vector3(0.0, capture_floor_y, 10.5),
		"target": Vector3(0.0, capture_floor_y + 1.35, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	local_player.camera.fov = 68.0
	local_player.view_model_root.visible = false
	local_player.set_physics_process(false)
	_send_authoritative_snapshot()
	return {
		"ok": true,
		"report": _build_p06_remote_report(),
		"visible_remote_humanoid_count": 5,
		"capture_peer_ids": remote_peer_ids.slice(0, 5),
		"performance": _build_performance_report(),
	}

func get_p08_client_report() -> Dictionary:
	var remote_report := _build_p06_remote_report()
	var summary := get_runtime_smoke_summary()
	remote_report["same_arena"] = bool(summary.get("has_active_map", false)) and StringName(str(summary.get("match_phase", &""))) == &"playing"
	remote_report["client_can_see_remote_humanoid"] = int(remote_report.get("humanoid_remote_count", 0)) >= 1 and int(remote_report.get("fallback_remote_count", 0)) == 0
	remote_report["remote_movement_sync"] = int(remote_report.get("synced_remote_count", 0)) >= 1
	remote_report["network_player_count"] = int(summary.get("network_players", 0))
	remote_report["ok"] = (
		bool(remote_report.get("same_arena", false))
		and bool(remote_report.get("client_can_see_remote_humanoid", false))
		and bool(remote_report.get("remote_movement_sync", false))
		and int(summary.get("network_players", 0)) >= 2
	)
	return remote_report

func _apply_local_player_capture_pose(pose: Dictionary, fallback_position: Vector3, fallback_yaw: float, fallback_pitch: float) -> void:
	local_player.global_position = pose.get("position", fallback_position)
	local_player.velocity = Vector3.ZERO
	if pose.has("target"):
		var target: Vector3 = pose["target"]
		var eye_position := local_player.global_position + local_player.head_pivot.position
		var direction := (target - eye_position).normalized()
		local_player.yaw = atan2(-direction.x, -direction.z)
		local_player.pitch = asin(direction.y)
	else:
		local_player.yaw = float(pose.get("yaw", fallback_yaw))
		local_player.pitch = float(pose.get("pitch", fallback_pitch))
	local_player.rotation.y = local_player.yaw
	local_player.head_pivot.rotation.x = local_player.pitch
	local_player.camera.current = true
	local_player.force_update_transform()
	local_player.head_pivot.force_update_transform()
	local_player.camera.force_update_transform()

func _complete_p07_traversal_route(route_name: String, waypoints: Array) -> Dictionary:
	var visited := []
	for index in range(waypoints.size()):
		var waypoint: Vector3 = waypoints[index]
		var target := waypoint + Vector3.FORWARD
		if index < waypoints.size() - 1:
			target = waypoints[index + 1]
		_apply_local_player_capture_pose({
			"position": waypoint,
			"target": target + Vector3(0.0, 1.0, 0.0),
		}, Vector3.ZERO, 0.0, 0.0)
		visited.append(waypoint)
		await _wait_p07_physics_frames(6)
	var final_point: Vector3 = waypoints[waypoints.size() - 1]
	return {
		"name": route_name,
		"completed": local_player.global_position.distance_to(final_point) < 3.0,
		"waypoint_count": waypoints.size(),
		"final_position": local_player.global_position,
		"visited": visited,
	}

func _run_p07_weapon_checks() -> Dictionary:
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.size() < 3:
		return {"ok": false, "error": "P07 requires at least 3 combat dummies", "dummy_count": dummies.size()}
	var rifle_result: Dictionary = await _fire_p07_weapon_at_dummy(&"primary", dummies[0], 2.4)
	var handgun_result: Dictionary = await _fire_p07_weapon_at_dummy(&"secondary", dummies[1], 2.2)
	var knife_result: Dictionary = await _fire_p07_weapon_at_dummy(&"melee", dummies[2], 1.1)
	var smoke_result: Dictionary = await _use_p07_smoke_bomb()
	var dummy_hits := int(rifle_result.get("hit", false)) + int(handgun_result.get("hit", false)) + int(knife_result.get("hit", false))
	var dummy_kills := int(rifle_result.get("killed", false)) + int(handgun_result.get("killed", false)) + int(knife_result.get("killed", false))
	var weapons := {
		"assault_rifle": bool(rifle_result.get("used", false)),
		"handgun": bool(handgun_result.get("used", false)),
		"knife": bool(knife_result.get("used", false)),
		"smoke_bomb": bool(smoke_result.get("used", false)),
	}
	return {
		"ok": dummy_hits >= 3 and dummy_kills >= 1 and bool(smoke_result.get("used", false)),
		"weapons": weapons,
		"dummy_hits": dummy_hits,
		"dummy_kills": dummy_kills,
		"smoke_volumes_spawned": int(smoke_result.get("smoke_volumes_spawned", 0)),
		"details": [rifle_result, handgun_result, knife_result, smoke_result],
	}

func run_taser_gun_smoke_check() -> Dictionary:
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		var spawned_dummy := DummyTarget.new()
		spawned_dummy.name = "TaserGunSmokeDummy"
		players_root.add_child(spawned_dummy)
		spawned_dummy.global_position = Vector3(0.0, 18.0, 0.0)
		await _wait_p07_physics_frames(2)
		dummies = [spawned_dummy]
	var dummy := dummies[0]
	if not (dummy is Node3D):
		return {"ok": false, "error": "taser gun dummy is not Node3D"}
	var target := dummy as Node3D
	var weapon_controller := local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"taser_gun")
	if not bool(select_result.get("ok", false)):
		return {"ok": false, "error": select_result.get("error", "taser gun select failed")}
	var definition := weapon_controller.get_active_definition()
	var tuning_ok := (
		definition.slot_type == &"secondary"
		and definition.fire_mode == &"utility"
		and definition.alt_action_type == &"stun"
		and is_equal_approx(definition.effect_duration_sec, 2.0)
		and is_equal_approx(definition.shot_cooldown_sec, 5.0)
	)
	var health_before := _get_p07_dummy_health(dummy)
	var shot_position := target.global_position + Vector3(0.0, -0.62, 2.4)
	_apply_local_player_capture_pose({
		"position": shot_position,
		"target": target.global_position + Vector3(0.0, 1.0, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	await _wait_p07_physics_frames(2)
	var ray_origin := local_player.camera.global_position
	var ray_direction := (-local_player.camera.global_transform.basis.z).normalized()
	target.global_position = ray_origin + ray_direction * 2.4 - Vector3(0.0, 1.0, 0.0)
	target.force_update_transform()
	await _wait_p07_physics_frames(1)
	ray_origin = local_player.camera.global_position
	ray_direction = (-local_player.camera.global_transform.basis.z).normalized()
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * definition.max_range_m)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [local_player.get_rid()]
	var ray_probe := get_world_3d().direct_space_state.intersect_ray(query)
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera, true)
	await _wait_p07_physics_frames(3)
	var health_after := _get_p07_dummy_health(dummy)
	var stun_remaining := float(dummy.call("get_stun_remaining_sec")) if dummy.has_method("get_stun_remaining_sec") else 0.0
	var active_summary := weapon_controller.get_active_summary()
	var cooldown_after := float(active_summary.get("cooldown_remaining_sec", 0.0))
	return {
		"ok": (
			tuning_ok
			and bool(fire_result.get("ok", false))
			and stun_remaining > 1.75
			and is_equal_approx(health_before, health_after)
			and cooldown_after > 4.5
		),
		"weapon_id": "taser_gun",
		"tuning_ok": tuning_ok,
		"effect_duration_sec": definition.effect_duration_sec,
		"shot_cooldown_sec": definition.shot_cooldown_sec,
		"dummy_stun_remaining_sec": stun_remaining,
		"dummy_health_before": health_before,
		"dummy_health_after": health_after,
		"cooldown_after": cooldown_after,
		"ray_probe": {
			"hit": not ray_probe.is_empty(),
			"collider": String((ray_probe.get("collider") as Object).get("name")) if ray_probe.has("collider") and ray_probe["collider"] != null else "",
			"position": ray_probe.get("position", Vector3.ZERO),
			"origin": ray_origin,
			"direction": ray_direction,
			"target": target.global_position + Vector3(0.0, 1.0, 0.0),
		},
		"fire_result": fire_result,
	}

func _fire_p07_weapon_at_dummy(slot: StringName, dummy: Node, distance: float) -> Dictionary:
	if not (dummy is Node3D):
		return {"used": false, "hit": false, "killed": false, "error": "dummy is not Node3D"}
	var target := dummy as Node3D
	var health_before := _get_p07_dummy_health(dummy)
	var shot_position := target.global_position + Vector3(0.0, 0.35, distance)
	_apply_local_player_capture_pose({
		"position": shot_position,
		"target": target.global_position + Vector3(0.0, 1.0, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var weapon_controller := local_player.get_weapon_controller()
	var slot_result: Dictionary = weapon_controller.select_slot_for_verification(slot)
	await _wait_p07_physics_frames(2)
	if not bool(slot_result.get("ok", false)):
		return {"used": false, "hit": false, "killed": false, "slot": slot, "error": slot_result.get("error", "slot select failed")}
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	await _wait_p07_physics_frames(4)
	var health_after := _get_p07_dummy_health(dummy)
	return {
		"used": bool(fire_result.get("ok", false)),
		"hit": health_after < health_before,
		"killed": health_after <= 0.0,
		"slot": slot,
		"weapon_id": fire_result.get("weapon_id", &""),
		"health_before": health_before,
		"health_after": health_after,
	}

func _use_p07_smoke_bomb() -> Dictionary:
	var before_count := _count_p07_smoke_volumes()
	_apply_local_player_capture_pose({
		"position": Vector3(0.0, 1.0, 5.0),
		"target": Vector3(0.0, 0.2, 0.0),
	}, Vector3.ZERO, 0.0, 0.0)
	var weapon_controller := local_player.get_weapon_controller()
	var slot_result: Dictionary = weapon_controller.select_slot_for_verification(&"artillery")
	await _wait_p07_physics_frames(2)
	if not bool(slot_result.get("ok", false)):
		return {"used": false, "slot": &"artillery", "error": slot_result.get("error", "slot select failed")}
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(local_player.camera)
	await _wait_p07_physics_frames(150)
	var after_count := _count_p07_smoke_volumes()
	return {
		"used": bool(fire_result.get("ok", false)) and after_count > before_count,
		"slot": &"artillery",
		"weapon_id": fire_result.get("weapon_id", &""),
		"smoke_volumes_spawned": maxi(0, after_count - before_count),
	}

func _run_p07_hud_check() -> Dictionary:
	var weapon_controller := local_player.get_weapon_controller()
	weapon_controller.select_slot_for_verification(&"primary")
	await _wait_p07_physics_frames(2)
	var primary_summary: Dictionary = hud.get_runtime_smoke_summary()
	weapon_controller.select_slot_for_verification(&"artillery")
	await _wait_p07_physics_frames(2)
	var artillery_summary: Dictionary = hud.get_runtime_smoke_summary()
	var primary_combat := String(primary_summary.get("combat_text", ""))
	var artillery_combat := String(artillery_summary.get("combat_text", ""))
	var match_text := String(primary_summary.get("match_text", ""))
	var perf_text := String(primary_summary.get("perf_text", ""))
	var fields := {
		"health": primary_combat.contains("HP:"),
		"ammo": primary_combat.contains("Ammo:") and not primary_combat.contains("charges"),
		"charges": artillery_combat.contains("charges"),
		"active_slot": primary_combat.contains("Slot:"),
		"cooldown": primary_combat.contains("Cooldown:"),
		"timer": match_text.contains(":"),
		"score": match_text.contains("Blue") and match_text.contains("Orange"),
		"fps": perf_text.contains("FPS:"),
		"node_count": perf_text.contains("Nodes:"),
	}
	var ok := true
	for value in fields.values():
		ok = ok and bool(value)
	return {
		"ok": ok,
		"fields": fields,
		"hud_text": {
			"primary_combat": primary_combat,
			"artillery_combat": artillery_combat,
			"match": match_text,
			"perf": perf_text,
		},
	}

func _get_p07_dummy_health(dummy: Node) -> float:
	var value = dummy.get("current_health")
	if value == null:
		return -1.0
	return float(value)

func _count_p07_smoke_volumes() -> int:
	var count := 0
	for child in effects_root.get_children():
		if String(child.name).begins_with("SmokeVolume"):
			count += 1
	return count

func _wait_p07_physics_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await get_tree().physics_frame

func _build_p06_remote_report() -> Dictionary:
	var summaries: Array[Dictionary] = []
	var team_ids := {}
	var humanoid_count := 0
	var fallback_count := 0
	var synced_count := 0
	for proxy_variant in remote_proxies.values():
		var proxy := proxy_variant as RemotePlayerProxy
		if proxy == null:
			continue
		var summary: Dictionary = proxy.get_runtime_summary()
		summaries.append(summary)
		var proxy_team_id := int(summary.get("team_id", 0))
		if proxy_team_id > 0:
			team_ids[proxy_team_id] = true
		if bool(summary.get("has_humanoid_mesh", false)):
			humanoid_count += 1
		if bool(summary.get("uses_fallback_body", true)):
			fallback_count += 1
		if int(summary.get("snapshot_count", 0)) > 0:
			synced_count += 1
	var ok := remote_proxies.size() > 0 and humanoid_count > 0 and fallback_count == 0 and synced_count > 0
	return {
		"ok": ok,
		"remote_proxy_count": remote_proxies.size(),
		"network_player_count": _network_player_states.size(),
		"humanoid_remote_count": humanoid_count,
		"fallback_remote_count": fallback_count,
		"synced_remote_count": synced_count,
		"team_ids": team_ids.keys(),
		"team_readability_method": "team-specific humanoid assets without extra proxy marker plates",
		"remotes": summaries,
	}

func _select_p06_capture_proxy() -> RemotePlayerProxy:
	for proxy_variant in remote_proxies.values():
		var proxy := proxy_variant as RemotePlayerProxy
		if proxy == null:
			continue
		var summary: Dictionary = proxy.get_runtime_summary()
		if bool(summary.get("has_humanoid_mesh", false)) and int(summary.get("snapshot_count", 0)) > 0:
			return proxy
	return null

func _find_network_peer_by_team(team_id: int, excluded_peer_id := 0) -> int:
	for peer_id in _network_player_states.keys():
		if int(peer_id) == excluded_peer_id:
			continue
		var state: Dictionary = _network_player_states[peer_id]
		if int(state.get("team_id", 0)) == team_id:
			return int(peer_id)
	return 0

func _run_network_team_score_check(shooter_team_id: int, victim_team_id: int) -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "team score check requires active host"}
	var shooter_peer_id := _find_network_peer_by_team(shooter_team_id)
	var victim_peer_id := _find_network_peer_by_team(victim_team_id, shooter_peer_id)
	if shooter_peer_id == 0 or victim_peer_id == 0:
		return {
			"ok": false,
			"error": "team score check could not find shooter/victim peers",
			"shooter_team_id": shooter_team_id,
			"victim_team_id": victim_team_id,
			"team_counts": _build_network_team_counts(),
		}
	var score_before := match_director.blue_score if shooter_team_id == 1 else match_director.orange_score
	var far_index := 0
	for peer_id in _network_player_states.keys():
		if int(peer_id) == shooter_peer_id or int(peer_id) == victim_peer_id:
			continue
		var other_state: Dictionary = _network_player_states[peer_id]
		other_state["position"] = Vector3(36.0 + float(far_index * 3), 0.0, 36.0)
		other_state["health"] = 100.0
		other_state["is_alive"] = true
		other_state["spawn_protection_remaining_sec"] = 0.0
		far_index += 1
	var shooter_state := _ensure_network_player_state(shooter_peer_id)
	var victim_state := _ensure_network_player_state(victim_peer_id)
	shooter_state["position"] = Vector3.ZERO
	shooter_state["velocity"] = Vector3.ZERO
	shooter_state["yaw"] = 0.0
	shooter_state["pitch"] = 0.0
	shooter_state["movement_state"] = &"grounded"
	shooter_state["health"] = 100.0
	shooter_state["is_alive"] = true
	shooter_state["spawn_protection_remaining_sec"] = 0.0
	victim_state["position"] = Vector3(0.0, 0.0, -12.0)
	victim_state["velocity"] = Vector3.ZERO
	victim_state["yaw"] = PI
	victim_state["pitch"] = 0.0
	victim_state["movement_state"] = &"grounded"
	victim_state["health"] = 100.0
	victim_state["is_alive"] = true
	victim_state["spawn_protection_remaining_sec"] = 0.0
	_network_player_states[shooter_peer_id] = shooter_state
	_network_player_states[victim_peer_id] = victim_state
	var origin := Vector3(0.0, 0.9, 0.0)
	var direction := (Vector3(0.0, 0.9, -12.0) - origin).normalized()
	var rifle_definition: WeaponDefinition = _weapon_definitions[&"assault_rifle"]
	var shots_to_kill := ceili(float(victim_state["health"]) / rifle_definition.body_damage)
	for _index in range(shots_to_kill):
		var rifle_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"assault_rifle")]
		rifle_state["ammo_in_mag"] = rifle_definition.magazine_size
		rifle_state["reserve_ammo"] = rifle_definition.reserve_ammo_max
		rifle_state["cooldown_remaining_sec"] = 0.0
		rifle_state["is_reloading"] = false
		_process_authoritative_fire(shooter_peer_id, &"assault_rifle", origin, direction, Vector3.ZERO)
	var score_after := match_director.blue_score if shooter_team_id == 1 else match_director.orange_score
	var final_victim_state: Dictionary = _network_player_states[victim_peer_id]
	if bool(final_victim_state["is_alive"]) or float(final_victim_state["health"]) > 0.0:
		return {
			"ok": false,
			"error": "team score check did not kill victim",
			"shooter_peer_id": shooter_peer_id,
			"victim_peer_id": victim_peer_id,
			"victim_health": float(final_victim_state["health"]),
			"victim_alive": bool(final_victim_state["is_alive"]),
		}
	if score_after <= score_before:
		return {
			"ok": false,
			"error": "team score check did not increment team score",
			"shooter_peer_id": shooter_peer_id,
			"victim_peer_id": victim_peer_id,
			"score_before": score_before,
			"score_after": score_after,
		}
	_respawn_network_peer(victim_peer_id)
	return {
		"ok": true,
		"shooter_peer_id": shooter_peer_id,
		"victim_peer_id": victim_peer_id,
		"shooter_team_id": shooter_team_id,
		"victim_team_id": victim_team_id,
		"score_before": score_before,
		"score_after": score_after,
	}

func run_p14_shotgun_network_check() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P14 shotgun network check requires active host"}
	if _network_player_states.size() < 2:
		return {"ok": false, "pending": true, "error": "P14 shotgun network check needs at least two players"}
	var shooter_peer_id := network_session.local_peer_id()
	var victim_peer_id := 0
	for peer_id in _network_player_states.keys():
		if int(peer_id) != shooter_peer_id:
			victim_peer_id = int(peer_id)
			break
	if victim_peer_id == 0:
		return {"ok": false, "pending": true, "error": "P14 shotgun network check could not find victim"}
	var shooter_state := _ensure_network_player_state(shooter_peer_id)
	var victim_state := _ensure_network_player_state(victim_peer_id)
	shooter_state["team_id"] = 1
	victim_state["team_id"] = 2
	shooter_state["position"] = Vector3.ZERO
	shooter_state["velocity"] = Vector3.ZERO
	shooter_state["yaw"] = 0.0
	shooter_state["pitch"] = 0.0
	shooter_state["movement_state"] = &"grounded"
	shooter_state["health"] = 100.0
	shooter_state["is_alive"] = true
	shooter_state["spawn_protection_remaining_sec"] = 0.0
	victim_state["position"] = Vector3(0.0, 0.0, -1.8)
	victim_state["velocity"] = Vector3.ZERO
	victim_state["yaw"] = PI
	victim_state["pitch"] = 0.0
	victim_state["movement_state"] = &"grounded"
	victim_state["health"] = 100.0
	victim_state["is_alive"] = true
	victim_state["spawn_protection_remaining_sec"] = 0.0
	var score_before := match_director.blue_score
	var origin := Vector3(0.0, 0.9, 0.0)
	var direction := (Vector3(0.0, 0.9, -1.8) - origin).normalized()
	var shotgun_definition: WeaponDefinition = _weapon_definitions[&"shotgun"]
	var max_shots := shotgun_definition.magazine_size
	var initial_peer_weapon_states: Dictionary = _network_weapon_states[shooter_peer_id]
	var initial_shotgun_state: Dictionary = initial_peer_weapon_states[String(&"shotgun")]
	initial_shotgun_state["ammo_in_mag"] = shotgun_definition.magazine_size
	initial_shotgun_state["reserve_ammo"] = shotgun_definition.reserve_ammo_max
	initial_shotgun_state["cooldown_remaining_sec"] = 0.0
	initial_shotgun_state["is_reloading"] = false
	initial_peer_weapon_states[String(&"shotgun")] = initial_shotgun_state
	_network_weapon_states[shooter_peer_id] = initial_peer_weapon_states
	var shots_fired := 0
	var shot_trace := []
	for _index in range(max_shots):
		shooter_state["team_id"] = 1
		shooter_state["position"] = Vector3.ZERO
		shooter_state["velocity"] = Vector3.ZERO
		shooter_state["yaw"] = 0.0
		shooter_state["pitch"] = 0.0
		shooter_state["movement_state"] = &"grounded"
		shooter_state["is_alive"] = true
		shooter_state["spawn_protection_remaining_sec"] = 0.0
		victim_state["team_id"] = 2
		victim_state["position"] = Vector3(0.0, 0.0, -1.8)
		victim_state["velocity"] = Vector3.ZERO
		victim_state["yaw"] = PI
		victim_state["pitch"] = 0.0
		victim_state["movement_state"] = &"grounded"
		victim_state["spawn_protection_remaining_sec"] = 0.0
		_network_player_states[shooter_peer_id] = shooter_state
		_network_player_states[victim_peer_id] = victim_state
		var health_before_shot := float(victim_state["health"])
		_process_authoritative_fire(shooter_peer_id, &"shotgun", origin, direction, Vector3.ZERO)
		shots_fired += 1
		victim_state = _network_player_states[victim_peer_id]
		var current_weapon_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"shotgun")]
		shot_trace.append({
			"shot": shots_fired,
			"health_before": health_before_shot,
			"health_after": float(victim_state["health"]),
			"ammo_after": int(current_weapon_state.get("ammo_in_mag", -1)),
			"cooldown_after": float(current_weapon_state.get("cooldown_remaining_sec", -1.0)),
		})
		if not bool(victim_state["is_alive"]):
			break
		await _wait_p07_physics_frames(ceili(shotgun_definition.shot_cooldown_sec * 60.0) + 4)
	var score_after := match_director.blue_score
	if bool(victim_state["is_alive"]) or float(victim_state["health"]) > 0.0:
		return {
			"ok": false,
			"error": "authoritative shotgun did not kill victim",
			"shots_fired": shots_fired,
			"shot_trace": shot_trace,
			"victim_health": float(victim_state["health"]),
			"victim_alive": bool(victim_state["is_alive"]),
		}
	if score_after <= score_before:
		return {
			"ok": false,
			"error": "authoritative shotgun did not increment team score",
			"score_before": score_before,
			"score_after": score_after,
		}
	_respawn_network_peer(victim_peer_id)
	var final_victim_state: Dictionary = _network_player_states[victim_peer_id]
	_send_authoritative_snapshot()
	return {
		"ok": true,
		"weapon_id": "shotgun",
		"shooter_peer_id": shooter_peer_id,
		"victim_peer_id": victim_peer_id,
		"shots_fired": shots_fired,
		"shot_trace": shot_trace,
		"pellets_per_shot": shotgun_definition.pellets_per_shot,
		"score_before": score_before,
		"score_after": score_after,
		"victim_respawned": bool(final_victim_state["is_alive"]) and float(final_victim_state["health"]) >= 100.0,
		"team_counts": _build_network_team_counts(),
	}

func run_p14_sniper_network_check() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P14 sniper network check requires active host"}
	if _network_player_states.size() < 2:
		return {"ok": false, "pending": true, "error": "P14 sniper network check needs at least two players"}
	var shooter_peer_id := network_session.local_peer_id()
	var victim_peer_id := 0
	for peer_id in _network_player_states.keys():
		if int(peer_id) != shooter_peer_id:
			victim_peer_id = int(peer_id)
			break
	if victim_peer_id == 0:
		return {"ok": false, "pending": true, "error": "P14 sniper network check could not find victim"}
	var shooter_state := _ensure_network_player_state(shooter_peer_id)
	var victim_state := _ensure_network_player_state(victim_peer_id)
	shooter_state["team_id"] = 1
	victim_state["team_id"] = 2
	shooter_state["position"] = Vector3.ZERO
	shooter_state["velocity"] = Vector3.ZERO
	shooter_state["yaw"] = 0.0
	shooter_state["pitch"] = 0.0
	shooter_state["movement_state"] = &"grounded"
	shooter_state["health"] = 100.0
	shooter_state["is_alive"] = true
	shooter_state["spawn_protection_remaining_sec"] = 0.0
	victim_state["position"] = Vector3(0.0, 0.0, -18.0)
	victim_state["velocity"] = Vector3.ZERO
	victim_state["yaw"] = PI
	victim_state["pitch"] = 0.0
	victim_state["movement_state"] = &"grounded"
	victim_state["health"] = 100.0
	victim_state["is_alive"] = true
	victim_state["spawn_protection_remaining_sec"] = 0.0
	var score_before := match_director.blue_score
	var origin := Vector3(0.0, 0.9, 0.0)
	var direction := (Vector3(0.0, 0.9, -18.0) - origin).normalized()
	var sniper_definition: WeaponDefinition = _weapon_definitions[&"sniper"]
	var initial_peer_weapon_states: Dictionary = _network_weapon_states[shooter_peer_id]
	var initial_sniper_state: Dictionary = initial_peer_weapon_states[String(&"sniper")]
	initial_sniper_state["ammo_in_mag"] = sniper_definition.magazine_size
	initial_sniper_state["reserve_ammo"] = sniper_definition.reserve_ammo_max
	initial_sniper_state["cooldown_remaining_sec"] = 0.0
	initial_sniper_state["is_reloading"] = false
	initial_peer_weapon_states[String(&"sniper")] = initial_sniper_state
	_network_weapon_states[shooter_peer_id] = initial_peer_weapon_states
	var shots_fired := 0
	var shot_trace := []
	var max_shots := ceili(100.0 / sniper_definition.body_damage)
	for _index in range(max_shots):
		shooter_state["team_id"] = 1
		shooter_state["position"] = Vector3.ZERO
		shooter_state["velocity"] = Vector3.ZERO
		shooter_state["yaw"] = 0.0
		shooter_state["pitch"] = 0.0
		shooter_state["movement_state"] = &"grounded"
		shooter_state["is_alive"] = true
		shooter_state["spawn_protection_remaining_sec"] = 0.0
		victim_state["team_id"] = 2
		victim_state["position"] = Vector3(0.0, 0.0, -18.0)
		victim_state["velocity"] = Vector3.ZERO
		victim_state["yaw"] = PI
		victim_state["pitch"] = 0.0
		victim_state["movement_state"] = &"grounded"
		victim_state["spawn_protection_remaining_sec"] = 0.0
		_network_player_states[shooter_peer_id] = shooter_state
		_network_player_states[victim_peer_id] = victim_state
		var peer_weapon_states: Dictionary = _network_weapon_states[shooter_peer_id]
		var sniper_state: Dictionary = peer_weapon_states[String(&"sniper")]
		sniper_state["ammo_in_mag"] = sniper_definition.magazine_size
		sniper_state["reserve_ammo"] = sniper_definition.reserve_ammo_max
		sniper_state["cooldown_remaining_sec"] = 0.0
		sniper_state["is_reloading"] = false
		peer_weapon_states[String(&"sniper")] = sniper_state
		_network_weapon_states[shooter_peer_id] = peer_weapon_states
		var health_before_shot := float(victim_state["health"])
		_process_authoritative_fire(shooter_peer_id, &"sniper", origin, direction, Vector3.ZERO)
		shots_fired += 1
		await _wait_p07_physics_frames(4)
		victim_state = _network_player_states[victim_peer_id]
		var current_weapon_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"sniper")]
		shot_trace.append({
			"shot": shots_fired,
			"health_before": health_before_shot,
			"health_after": float(victim_state["health"]),
			"damage": maxf(0.0, health_before_shot - float(victim_state["health"])),
			"ammo_after": int(current_weapon_state.get("ammo_in_mag", -1)),
			"cooldown_after": float(current_weapon_state.get("cooldown_remaining_sec", -1.0)),
		})
		if not bool(victim_state["is_alive"]):
			break
	var score_after := match_director.blue_score
	if bool(victim_state["is_alive"]) or float(victim_state["health"]) > 0.0:
		return {
			"ok": false,
			"error": "authoritative sniper did not kill victim",
			"shots_fired": shots_fired,
			"shot_trace": shot_trace,
			"victim_health": float(victim_state["health"]),
			"victim_alive": bool(victim_state["is_alive"]),
		}
	if score_after <= score_before:
		return {
			"ok": false,
			"error": "authoritative sniper did not increment team score",
			"score_before": score_before,
			"score_after": score_after,
		}
	_respawn_network_peer(victim_peer_id)
	var final_victim_state: Dictionary = _network_player_states[victim_peer_id]
	_send_authoritative_snapshot()
	return {
		"ok": true,
		"weapon_id": "sniper",
		"shooter_peer_id": shooter_peer_id,
		"victim_peer_id": victim_peer_id,
		"shots_fired": shots_fired,
		"shot_trace": shot_trace,
		"magazine_size": sniper_definition.magazine_size,
		"reserve_ammo_max": sniper_definition.reserve_ammo_max,
		"pellets_per_shot": sniper_definition.pellets_per_shot,
		"body_damage": sniper_definition.body_damage,
		"head_damage": sniper_definition.head_damage,
		"score_before": score_before,
		"score_after": score_after,
		"victim_respawned": bool(final_victim_state["is_alive"]) and float(final_victim_state["health"]) >= 100.0,
		"team_counts": _build_network_team_counts(),
	}

func run_p14_grenade_network_check() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P14 grenade network check requires active host"}
	if _network_player_states.size() < 2:
		return {"ok": false, "pending": true, "error": "P14 grenade network check needs at least two players"}
	var shooter_peer_id := network_session.local_peer_id()
	var victim_peer_id := 0
	for peer_id in _network_player_states.keys():
		if int(peer_id) != shooter_peer_id:
			victim_peer_id = int(peer_id)
			break
	if victim_peer_id == 0:
		return {"ok": false, "pending": true, "error": "P14 grenade network check could not find victim"}
	var shooter_state := _ensure_network_player_state(shooter_peer_id)
	var victim_state := _ensure_network_player_state(victim_peer_id)
	shooter_state["team_id"] = 1
	victim_state["team_id"] = 2
	shooter_state["position"] = Vector3.ZERO
	shooter_state["velocity"] = Vector3.ZERO
	shooter_state["yaw"] = 0.0
	shooter_state["pitch"] = 0.0
	shooter_state["movement_state"] = &"grounded"
	shooter_state["health"] = 100.0
	shooter_state["is_alive"] = true
	shooter_state["spawn_protection_remaining_sec"] = 0.0
	victim_state["position"] = Vector3(0.0, 0.0, -11.0)
	victim_state["velocity"] = Vector3.ZERO
	victim_state["yaw"] = PI
	victim_state["pitch"] = 0.0
	victim_state["movement_state"] = &"grounded"
	victim_state["health"] = 100.0
	victim_state["is_alive"] = true
	victim_state["spawn_protection_remaining_sec"] = 0.0
	var score_before := match_director.blue_score
	var origin := Vector3(0.0, 0.9, 0.0)
	var direction := (Vector3(0.0, 0.9, -11.0) - origin).normalized()
	var grenade_definition: WeaponDefinition = _weapon_definitions[&"grenade"]
	var throws_needed := ceili(100.0 / (grenade_definition.body_damage * 0.5))
	var throws_fired := 0
	var throw_trace := []
	for _index in range(throws_needed):
		shooter_state["team_id"] = 1
		shooter_state["position"] = Vector3.ZERO
		shooter_state["velocity"] = Vector3.ZERO
		shooter_state["yaw"] = 0.0
		shooter_state["pitch"] = 0.0
		shooter_state["movement_state"] = &"grounded"
		shooter_state["is_alive"] = true
		shooter_state["spawn_protection_remaining_sec"] = 0.0
		victim_state["team_id"] = 2
		victim_state["position"] = Vector3(0.0, 0.0, -11.0)
		victim_state["velocity"] = Vector3.ZERO
		victim_state["yaw"] = PI
		victim_state["pitch"] = 0.0
		victim_state["movement_state"] = &"grounded"
		victim_state["spawn_protection_remaining_sec"] = 0.0
		_network_player_states[shooter_peer_id] = shooter_state
		_network_player_states[victim_peer_id] = victim_state
		var peer_weapon_states: Dictionary = _network_weapon_states[shooter_peer_id]
		var grenade_state: Dictionary = peer_weapon_states[String(&"grenade")]
		grenade_state["charges_current"] = grenade_definition.charges_max
		grenade_state["cooldown_remaining_sec"] = 0.0
		grenade_state["is_reloading"] = false
		peer_weapon_states[String(&"grenade")] = grenade_state
		_network_weapon_states[shooter_peer_id] = peer_weapon_states
		var health_before_throw := float(victim_state["health"])
		var landing_position := _estimate_throw_landing(origin, direction, Vector3.ZERO, grenade_definition)
		_process_authoritative_fire(shooter_peer_id, &"grenade", origin, direction, Vector3.ZERO)
		throws_fired += 1
		await _wait_p07_physics_frames(4)
		victim_state = _network_player_states[victim_peer_id]
		var current_weapon_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"grenade")]
		throw_trace.append({
			"throw": throws_fired,
			"health_before": health_before_throw,
			"health_after": float(victim_state["health"]),
			"damage": maxf(0.0, health_before_throw - float(victim_state["health"])),
			"landing_position": landing_position,
			"charges_after": int(current_weapon_state.get("charges_current", -1)),
			"cooldown_after": float(current_weapon_state.get("cooldown_remaining_sec", -1.0)),
		})
		if not bool(victim_state["is_alive"]):
			break
	var score_after := match_director.blue_score
	if bool(victim_state["is_alive"]) or float(victim_state["health"]) > 0.0:
		return {
			"ok": false,
			"error": "authoritative grenade did not kill victim",
			"throws_fired": throws_fired,
			"throw_trace": throw_trace,
			"victim_health": float(victim_state["health"]),
			"victim_alive": bool(victim_state["is_alive"]),
		}
	if score_after <= score_before:
		return {
			"ok": false,
			"error": "authoritative grenade did not increment team score",
			"score_before": score_before,
			"score_after": score_after,
		}
	_respawn_network_peer(victim_peer_id)
	var final_victim_state: Dictionary = _network_player_states[victim_peer_id]
	_send_authoritative_snapshot()
	return {
		"ok": true,
		"weapon_id": "grenade",
		"shooter_peer_id": shooter_peer_id,
		"victim_peer_id": victim_peer_id,
		"throws_fired": throws_fired,
		"throw_trace": throw_trace,
		"charges_max": grenade_definition.charges_max,
		"shot_cooldown_sec": grenade_definition.shot_cooldown_sec,
		"body_damage": grenade_definition.body_damage,
		"effect_radius_m": grenade_definition.effect_radius_m,
		"projectile_speed_mps": grenade_definition.projectile_speed_mps,
		"score_before": score_before,
		"score_after": score_after,
		"victim_respawned": bool(final_victim_state["is_alive"]) and float(final_victim_state["health"]) >= 100.0,
		"team_counts": _build_network_team_counts(),
	}

func run_p14_flamethrower_network_check() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "P14 flamethrower network check requires active host"}
	if _network_player_states.size() < 2:
		return {"ok": false, "pending": true, "error": "P14 flamethrower network check needs at least two players"}
	var shooter_peer_id := network_session.local_peer_id()
	var victim_peer_id := 0
	for peer_id in _network_player_states.keys():
		if int(peer_id) != shooter_peer_id:
			victim_peer_id = int(peer_id)
			break
	if victim_peer_id == 0:
		return {"ok": false, "pending": true, "error": "P14 flamethrower network check could not find victim"}
	var shooter_state := _ensure_network_player_state(shooter_peer_id)
	var victim_state := _ensure_network_player_state(victim_peer_id)
	shooter_state["team_id"] = 1
	victim_state["team_id"] = 2
	shooter_state["position"] = Vector3.ZERO
	shooter_state["velocity"] = Vector3.ZERO
	shooter_state["yaw"] = 0.0
	shooter_state["pitch"] = 0.0
	shooter_state["movement_state"] = &"grounded"
	shooter_state["health"] = 100.0
	shooter_state["is_alive"] = true
	shooter_state["spawn_protection_remaining_sec"] = 0.0
	victim_state["position"] = Vector3(0.0, 0.0, -1.4)
	victim_state["velocity"] = Vector3.ZERO
	victim_state["yaw"] = PI
	victim_state["pitch"] = 0.0
	victim_state["movement_state"] = &"grounded"
	victim_state["health"] = 100.0
	victim_state["is_alive"] = true
	victim_state["spawn_protection_remaining_sec"] = 0.0
	var score_before := match_director.blue_score
	var origin := Vector3(0.0, 0.9, 0.0)
	var direction := (Vector3(0.0, 0.9, -1.4) - origin).normalized()
	var flame_definition: WeaponDefinition = _weapon_definitions[&"flamethrower"]
	var ticks_fired := 0
	var tick_trace := []
	for _index in range(30):
		shooter_state["team_id"] = 1
		shooter_state["position"] = Vector3.ZERO
		shooter_state["velocity"] = Vector3.ZERO
		shooter_state["yaw"] = 0.0
		shooter_state["pitch"] = 0.0
		shooter_state["movement_state"] = &"grounded"
		shooter_state["is_alive"] = true
		shooter_state["spawn_protection_remaining_sec"] = 0.0
		victim_state["team_id"] = 2
		victim_state["position"] = Vector3(0.0, 0.0, -1.4)
		victim_state["velocity"] = Vector3.ZERO
		victim_state["yaw"] = PI
		victim_state["pitch"] = 0.0
		victim_state["movement_state"] = &"grounded"
		victim_state["spawn_protection_remaining_sec"] = 0.0
		_network_player_states[shooter_peer_id] = shooter_state
		_network_player_states[victim_peer_id] = victim_state
		var peer_weapon_states: Dictionary = _network_weapon_states[shooter_peer_id]
		var flame_state: Dictionary = peer_weapon_states[String(&"flamethrower")]
		flame_state["ammo_in_mag"] = flame_definition.magazine_size
		flame_state["reserve_ammo"] = flame_definition.reserve_ammo_max
		flame_state["cooldown_remaining_sec"] = 0.0
		flame_state["is_reloading"] = false
		peer_weapon_states[String(&"flamethrower")] = flame_state
		_network_weapon_states[shooter_peer_id] = peer_weapon_states
		var health_before_tick := float(victim_state["health"])
		_process_authoritative_fire(shooter_peer_id, &"flamethrower", origin, direction, Vector3.ZERO)
		ticks_fired += 1
		await _wait_p07_physics_frames(1)
		victim_state = _network_player_states[victim_peer_id]
		var current_weapon_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"flamethrower")]
		if float(victim_state["health"]) < health_before_tick or ticks_fired <= 3:
			tick_trace.append({
				"tick": ticks_fired,
				"health_before": health_before_tick,
				"health_after": float(victim_state["health"]),
				"damage": maxf(0.0, health_before_tick - float(victim_state["health"])),
				"ammo_after": int(current_weapon_state.get("ammo_in_mag", -1)),
				"cooldown_after": float(current_weapon_state.get("cooldown_remaining_sec", -1.0)),
			})
		if not bool(victim_state["is_alive"]):
			break
	var score_after := match_director.blue_score
	if bool(victim_state["is_alive"]) or float(victim_state["health"]) > 0.0:
		return {
			"ok": false,
			"error": "authoritative flamethrower did not kill victim",
			"ticks_fired": ticks_fired,
			"tick_trace": tick_trace,
			"victim_health": float(victim_state["health"]),
			"victim_alive": bool(victim_state["is_alive"]),
		}
	if score_after <= score_before:
		return {
			"ok": false,
			"error": "authoritative flamethrower did not increment team score",
			"score_before": score_before,
			"score_after": score_after,
		}
	_respawn_network_peer(victim_peer_id)
	var final_victim_state: Dictionary = _network_player_states[victim_peer_id]
	_send_authoritative_snapshot()
	return {
		"ok": true,
		"weapon_id": "flamethrower",
		"shooter_peer_id": shooter_peer_id,
		"victim_peer_id": victim_peer_id,
		"ticks_fired": ticks_fired,
		"tick_trace": tick_trace,
		"magazine_size": flame_definition.magazine_size,
		"body_damage": flame_definition.body_damage,
		"shot_cooldown_sec": flame_definition.shot_cooldown_sec,
		"max_range_m": flame_definition.max_range_m,
		"effect_duration_sec": flame_definition.effect_duration_sec,
		"propulsion_force": flame_definition.propulsion_force,
		"score_before": score_before,
		"score_after": score_after,
		"victim_respawned": bool(final_victim_state["is_alive"]) and float(final_victim_state["health"]) >= 100.0,
		"team_counts": _build_network_team_counts(),
	}

func run_network_authority_smoke_check() -> Dictionary:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return {"ok": false, "error": "network authority smoke requires active host"}
	if _network_player_states.size() < 2:
		return {"ok": false, "pending": true, "error": "network authority smoke requires at least two network players"}
	var shooter_peer_id := network_session.local_peer_id()
	var victim_peer_id := 0
	for peer_id in _network_player_states.keys():
		if int(peer_id) != shooter_peer_id:
			victim_peer_id = int(peer_id)
			break
	if victim_peer_id == 0:
		return {"ok": false, "pending": true, "error": "network authority smoke could not find victim peer"}
	var shooter_state := _ensure_network_player_state(shooter_peer_id)
	var victim_state := _ensure_network_player_state(victim_peer_id)
	shooter_state["team_id"] = 1
	victim_state["team_id"] = 2
	shooter_state["position"] = Vector3.ZERO
	victim_state["position"] = Vector3(0.0, 0.0, -12.0)
	victim_state["health"] = 100.0
	victim_state["is_alive"] = true
	victim_state["spawn_protection_remaining_sec"] = 0.0
	var origin := Vector3(0.0, 0.9, 0.0)
	var direction := (Vector3(0.0, 0.9, -12.0) - origin).normalized()
	var rifle_definition: WeaponDefinition = _weapon_definitions[&"assault_rifle"]
	var rifle_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"assault_rifle")]
	rifle_state["ammo_in_mag"] = rifle_definition.magazine_size
	rifle_state["reserve_ammo"] = rifle_definition.reserve_ammo_max
	rifle_state["is_reloading"] = false
	var shots_to_kill := ceili(float(victim_state["health"]) / rifle_definition.body_damage)
	for _index in range(shots_to_kill):
		rifle_state = _network_weapon_states[shooter_peer_id][String(&"assault_rifle")]
		rifle_state["cooldown_remaining_sec"] = 0.0
		_process_authoritative_fire(shooter_peer_id, &"assault_rifle", origin, direction, Vector3.ZERO)
	var final_victim_state: Dictionary = _network_player_states[victim_peer_id]
	var final_shooter_state: Dictionary = _network_player_states[shooter_peer_id]
	if bool(final_victim_state["is_alive"]) or float(final_victim_state["health"]) > 0.0:
		return {"ok": false, "error": "host-authoritative damage/death did not kill victim; health=%.1f alive=%s ammo=%d" % [float(final_victim_state["health"]), str(bool(final_victim_state["is_alive"])), int(rifle_state["ammo_in_mag"])]}
	if int(final_shooter_state["score"]) <= 0:
		return {"ok": false, "error": "host-authoritative score did not increment"}
	rifle_state = _network_weapon_states[shooter_peer_id][String(&"assault_rifle")]
	rifle_state["ammo_in_mag"] = 0
	rifle_state["reserve_ammo"] = 5
	rifle_state["cooldown_remaining_sec"] = 0.0
	rifle_state["is_reloading"] = false
	_process_authoritative_reload(shooter_peer_id, &"assault_rifle")
	rifle_state = _network_weapon_states[shooter_peer_id][String(&"assault_rifle")]
	if not bool(rifle_state["is_reloading"]):
		return {"ok": false, "error": "host-authoritative reload did not start"}
	_respawn_network_peer(victim_peer_id)
	final_victim_state = _network_player_states[victim_peer_id]
	if not bool(final_victim_state["is_alive"]) or float(final_victim_state["health"]) < 100.0:
		return {"ok": false, "error": "network respawn did not restore victim"}
	var smoke_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"smoke_bomb")]
	smoke_state["charges_current"] = 1
	smoke_state["cooldown_remaining_sec"] = 0.0
	_process_authoritative_fire(shooter_peer_id, &"smoke_bomb", origin, direction, Vector3.ZERO)
	var grenade_state: Dictionary = _network_weapon_states[shooter_peer_id][String(&"grenade")]
	grenade_state["charges_current"] = 1
	grenade_state["cooldown_remaining_sec"] = 0.0
	_process_authoritative_fire(shooter_peer_id, &"grenade", origin, direction, Vector3.ZERO)
	_send_authoritative_snapshot()
	return {"ok": true}

func _run_dummy_score_smoke_check() -> Dictionary:
	var dummies := get_tree().get_nodes_in_group("combat_dummies")
	if dummies.is_empty():
		return {"ok": false, "error": "offline smoke found no combat dummies"}
	var score_before := match_director.blue_score
	var event := DamageEvent.new()
	event.weapon_id = &"smoke_test"
	event.amount = 1000.0
	event.hit_position = Vector3.ZERO
	event.hit_normal = Vector3.UP
	var killed := false
	for dummy in dummies:
		if dummy.has_method("apply_damage"):
			killed = bool(dummy.apply_damage(event))
			if killed:
				break
	if not killed:
		return {"ok": false, "error": "offline smoke could not damage/kill dummy"}
	if match_director.blue_score <= score_before:
		return {"ok": false, "error": "dummy kill did not affect score"}
	return {"ok": true}

func _run_local_respawn_smoke_check() -> Dictionary:
	var health := local_player.get_health_component()
	health.spawn_protection_remaining_sec = 0.0
	var event := DamageEvent.new()
	event.weapon_id = &"smoke_test"
	event.amount = 1000.0
	event.hit_position = local_player.global_position
	event.hit_normal = Vector3.UP
	var killed := health.apply_damage(event)
	if not killed or health.is_alive:
		return {"ok": false, "error": "offline smoke could not kill local player"}
	match_director.respawn_player(local_player, 1)
	if not health.is_alive or health.current_health < health.max_health:
		return {"ok": false, "error": "offline respawn did not restore local player"}
	return {"ok": true}

func _run_hud_smoke_check() -> Dictionary:
	if hud == null or not hud.has_method("get_runtime_smoke_summary"):
		return {"ok": false, "error": "HUD smoke summary is missing"}
	var summary: Dictionary = hud.get_runtime_smoke_summary()
	var debug_text := String(summary.get("debug_text", ""))
	var combat_text := String(summary.get("combat_text", ""))
	var match_text := String(summary.get("match_text", ""))
	var perf_text := String(summary.get("perf_text", ""))
	if not debug_text.contains("Speed:") or not debug_text.contains("State:"):
		return {"ok": false, "error": "HUD debug readout missing movement state"}
	if not combat_text.contains("HP:") or not combat_text.contains("Ammo:") or not combat_text.contains("Cooldown:"):
		return {"ok": false, "error": "HUD combat readout missing core fields"}
	if not match_text.contains("Blue") or not match_text.contains("Orange"):
		return {"ok": false, "error": "HUD match readout missing team score"}
	if not perf_text.contains("FPS:") or not perf_text.contains("Nodes:"):
		return {"ok": false, "error": "HUD perf readout missing FPS/node count"}
	if not bool(summary.get("has_feedback_label", false)):
		return {"ok": false, "error": "HUD feedback label missing"}
	if not bool(summary.get("has_minimap", false)):
		return {"ok": false, "error": "HUD minimap missing"}
	if int(summary.get("minimap_target_count", 0)) < 1:
		return {"ok": false, "error": "HUD minimap has no enemy targets"}
	return {"ok": true}

func _run_art_layer_smoke_check() -> Dictionary:
	if active_map == null or not active_map.has_method("get_runtime_smoke_summary"):
		return {"ok": false, "error": "active map has no art smoke summary"}
	var summary: Dictionary = active_map.get_runtime_smoke_summary()
	if not bool(summary.get("has_blockout", false)):
		return {"ok": false, "error": "art map is missing gameplay blockout"}
	if not bool(summary.get("has_art_root", false)):
		return {"ok": false, "error": "art map is missing art root"}
	if int(summary.get("spawn_points", 0)) <= 0:
		return {"ok": false, "error": "art map exposes no spawn points"}
	var closure_report: Dictionary = summary.get("map_closure_report", {})
	if not bool(closure_report.get("ok", false)):
		return {"ok": false, "error": "map perimeter closure is incomplete: %s" % str(closure_report)}
	return {"ok": true}

func _spawn_map() -> void:
	active_map = ARENA_SCENE.instantiate()
	map_root.add_child(active_map)

func _configure_rooftop_environment() -> void:
	_rooftop_config = DEFAULT_ROOFTOP_CONFIG
	if active_map != null and active_map.has_method("get_rooftop_map_config"):
		var map_config: Resource = active_map.get_rooftop_map_config()
		if map_config != null:
			_rooftop_config = map_config
	if world_environment == null or world_environment.environment == null or _rooftop_config == null:
		return
	var environment := world_environment.environment
	environment.fog_enabled = true
	environment.fog_light_color = _rooftop_config.fog_color
	environment.fog_density = _rooftop_config.environment_fog_density
	environment.fog_height = _rooftop_config.fog_surface_y
	environment.fog_height_density = _rooftop_config.environment_fog_height_density
	_configure_rooftop_fog_visuals()

func _configure_rooftop_fog_visuals() -> void:
	if _rooftop_config == null:
		return
	if _rooftop_fog_visual_root != null:
		_rooftop_fog_visual_root.queue_free()
	_rooftop_fog_visual_root = Node3D.new()
	_rooftop_fog_visual_root.name = "LowGroundFogVisuals"
	map_root.add_child(_rooftop_fog_visual_root)

	var layer_count: int = maxi(1, int(_rooftop_config.fog_layer_count))
	var layer_spacing: float = maxf(0.05, float(_rooftop_config.fog_layer_spacing))
	var top_fade_alpha: float = clampf(float(_rooftop_config.fog_visual_top_fade_alpha), 0.0, 1.0)
	var base_alpha: float = clampf(float(_rooftop_config.fog_visual_layer_alpha), 0.0, 1.0)
	var center_y: float = float(_rooftop_config.fog_visual_center_y)
	var start_y := center_y - float(layer_count - 1) * layer_spacing * 0.5
	for index in range(layer_count):
		var normalized_height := 0.0
		if layer_count > 1:
			normalized_height = float(index) / float(layer_count - 1)
		var layer_alpha := lerpf(base_alpha, top_fade_alpha, normalized_height)
		_add_rooftop_fog_visual_layer(index, start_y + float(index) * layer_spacing, layer_alpha)

func _add_rooftop_fog_visual_layer(index: int, y: float, alpha: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "FogLayer%02d" % index
	mesh_instance.position = Vector3(0.0, y, 0.0)
	var plane := PlaneMesh.new()
	plane.size = _rooftop_config.fog_visual_size
	mesh_instance.mesh = plane
	var material := StandardMaterial3D.new()
	material.resource_name = "LowGroundFogLayerMaterial%02d" % index
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_color = Color(
		_rooftop_config.fog_color.r,
		_rooftop_config.fog_color.g,
		_rooftop_config.fog_color.b,
		clampf(alpha * float(_rooftop_config.fog_alpha), 0.0, 1.0)
	)
	mesh_instance.material_override = material
	_rooftop_fog_visual_root.add_child(mesh_instance)

func _spawn_local_player() -> void:
	local_player = PLAYER_SCENE.instantiate()
	local_player.get_node("WeaponController").set_loadout_definition(selected_loadout)
	players_root.add_child(local_player)
	local_player.global_position = Vector3(0.0, 2.2, 10.0)
	local_player.configure_gameplay_roots(projectiles_root, effects_root)
	local_player.get_weapon_controller().network_fire_requested.connect(_on_local_network_fire_requested)
	local_player.get_weapon_controller().network_reload_requested.connect(_on_local_network_reload_requested)
	local_player.get_weapon_controller().network_slot_changed.connect(_on_local_network_slot_changed)

func _spawn_balance_dummy() -> void:
	if local_player == null or players_root == null:
		return
	if _balance_dummy != null and is_instance_valid(_balance_dummy):
		_balance_dummy.queue_free()
	_balance_dummy = DummyTarget.new()
	_balance_dummy.name = "BalanceDamageDummy"
	_balance_dummy.display_name = "Balance Dummy"
	_balance_dummy.add_to_combat_group = false
	_balance_dummy.reset_delay_sec = 0.75
	players_root.add_child(_balance_dummy)
	_balance_dummy.add_to_group("balance_dummies")
	var forward := -local_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	_balance_dummy.global_position = _find_balance_dummy_floor_position(forward)
	_face_balance_dummy_toward_player()

func _find_balance_dummy_floor_position(forward: Vector3) -> Vector3:
	var right := forward.cross(Vector3.UP).normalized()
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	for distance_m in BALANCE_DUMMY_FORWARD_DISTANCES_M:
		for side_offset_m in BALANCE_DUMMY_SIDE_OFFSETS_M:
			var target_position := local_player.global_position + forward * float(distance_m) + right * float(side_offset_m)
			var hit := _raycast_balance_dummy_floor(target_position)
			if hit.is_empty():
				continue
			var hit_position: Vector3 = hit["position"]
			if absf(hit_position.y - local_player.global_position.y) <= 2.75:
				return hit_position
	var fallback_position := local_player.global_position + forward * 3.5
	var fallback_hit := _raycast_balance_dummy_floor(fallback_position)
	if not fallback_hit.is_empty():
		return fallback_hit["position"]
	return Vector3(fallback_position.x, local_player.global_position.y, fallback_position.z)

func _raycast_balance_dummy_floor(target_position: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(target_position + Vector3.UP * 8.0, target_position + Vector3.DOWN * 16.0)
	if local_player != null:
		query.exclude = [local_player.get_rid()]
	return space_state.intersect_ray(query)

func _face_balance_dummy_toward_player() -> void:
	if _balance_dummy == null or local_player == null:
		return
	var look_position := local_player.global_position
	look_position.y = _balance_dummy.global_position.y
	if _balance_dummy.global_position.distance_squared_to(look_position) <= 0.001:
		return
	_balance_dummy.look_at(look_position, Vector3.UP)

func _spawn_hud() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)
	if hud.has_method("bind_player"):
		hud.bind_player(local_player)
	if hud.has_method("bind_match_director"):
		hud.bind_match_director(match_director)
	if hud.has_method("bind_map_provider"):
		hud.bind_map_provider(self)

func get_hud_map_snapshot() -> Dictionary:
	if local_player == null:
		return {}
	var local_team_id := _get_local_team_id()
	return {
		"local_position": local_player.global_position,
		"local_yaw": local_player.rotation.y,
		"local_team_id": local_team_id,
		"range_m": 85.0,
		"enemies": _get_hud_map_enemies(local_team_id),
	}

func get_hud_player_stats_snapshot() -> Dictionary:
	var players := []
	var local_peer_id := network_session.local_peer_id() if network_session != null and network_session.is_active() else 1
	if (network_session != null and network_session.is_active()) or not _network_player_states.is_empty():
		for peer_id in _network_player_states.keys():
			var state: Dictionary = _network_player_states[peer_id]
			players.append({
				"peer_id": int(peer_id),
				"player_name": String(state.get("player_name", "Peer %d" % int(peer_id))),
				"team_id": int(state.get("team_id", 0)),
				"kills": int(state.get("kills", 0)),
				"deaths": int(state.get("deaths", 0)),
				"is_local": int(peer_id) == local_peer_id,
				"is_alive": bool(state.get("is_alive", false)),
			})
	else:
		players.append({
			"peer_id": 1,
			"player_name": _local_player_name,
			"team_id": 1,
			"kills": match_director.blue_score if match_director != null else 0,
			"deaths": 0,
			"is_local": true,
			"is_alive": local_player != null and local_player.get_health_component().is_alive,
		})
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_team := int(a.get("team_id", 0))
		var b_team := int(b.get("team_id", 0))
		if a_team != b_team:
			return a_team < b_team
		return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0))
	)
	return {"players": players}

func _get_local_team_id() -> int:
	if network_session != null and network_session.is_active():
		var local_peer_id := network_session.local_peer_id()
		if _network_player_states.has(local_peer_id):
			var state: Dictionary = _network_player_states[local_peer_id]
			return int(state.get("team_id", 1))
	return 1

func _get_hud_map_enemies(local_team_id: int) -> Array:
	var enemies := []
	if network_session != null and network_session.is_active():
		var local_peer_id := network_session.local_peer_id()
		for peer_id in _network_player_states.keys():
			if int(peer_id) == local_peer_id:
				continue
			var state: Dictionary = _network_player_states[peer_id]
			var team_id := int(state.get("team_id", 0))
			if team_id == local_team_id and not match_director.rules.friendly_fire:
				continue
			if not bool(state.get("is_alive", false)):
				continue
			enemies.append({
				"peer_id": int(peer_id),
				"team_id": team_id,
				"position": state.get("position", Vector3.ZERO),
			})
		return enemies
	_append_hud_map_dummy(enemies, _balance_dummy)
	for group_name in ["combat_dummies", "balance_dummies"]:
		for dummy in get_tree().get_nodes_in_group(group_name):
			if dummy == _balance_dummy:
				continue
			_append_hud_map_dummy(enemies, dummy)
	return enemies

func _append_hud_map_dummy(enemies: Array, dummy: Variant) -> void:
	if dummy == null or not is_instance_valid(dummy) or not (dummy is Node3D):
		return
	if dummy is DummyTarget and (dummy as DummyTarget).current_health <= 0.0:
		return
	enemies.append({
		"peer_id": 0,
		"team_id": 2,
		"position": (dummy as Node3D).global_position,
	})

func _start_offline_match() -> void:
	if active_map != null and active_map.has_method("get_spawn_points"):
		_arena_spawn_points = active_map.get_spawn_points()
	match_director.configure(local_player, _arena_spawn_points)

func _tick_rooftop_hazard() -> void:
	if _rooftop_config == null:
		return
	if network_session != null and network_session.is_active():
		if multiplayer.is_server():
			_tick_network_rooftop_hazard()
		return
	_tick_local_rooftop_hazard()

func _tick_local_rooftop_hazard() -> void:
	if local_player == null or not _is_local_player_on_lethal_low_ground():
		return
	var health := local_player.get_health_component()
	if health == null or not health.is_alive:
		return
	var event := DamageEvent.new()
	event.amount = _rooftop_config.lethal_damage
	event.source_peer_id = 0
	event.weapon_id = &"rooftop_fog"
	event.hit_position = local_player.global_position
	event.hit_normal = Vector3.UP
	health.spawn_protection_remaining_sec = 0.0
	health.apply_damage(event)

func _is_local_player_on_lethal_low_ground() -> bool:
	if local_player.global_position.y <= _rooftop_config.void_kill_height_y:
		return true
	return local_player.global_position.y <= _rooftop_config.ground_kill_height_y

func _tick_network_rooftop_hazard() -> void:
	for peer_id in _network_player_states.keys():
		var state: Dictionary = _network_player_states[peer_id]
		if not bool(state.get("is_alive", false)):
			continue
		var position: Vector3 = state.get("position", Vector3.ZERO)
		if position.y <= _rooftop_config.ground_kill_height_y:
			_register_network_environment_death(int(peer_id))

func _register_network_environment_death(peer_id: int) -> void:
	if not _network_player_states.has(peer_id):
		return
	var state: Dictionary = _network_player_states[peer_id]
	if not bool(state.get("is_alive", false)):
		return
	state["deaths"] = int(state.get("deaths", 0)) + 1
	state["health"] = 0.0
	state["is_alive"] = false
	state["spawn_protection_remaining_sec"] = 0.0
	state["respawn_remaining_sec"] = match_director.rules.respawn_delay_sec
	var team_id := int(state.get("team_id", 1))
	var scoring_team_id := 2 if team_id == 1 else 1
	match_director.record_kill(scoring_team_id)
	_apply_local_network_health_if_needed(peer_id)

func _bind_dummies() -> void:
	var kill_callback := Callable(self, "_on_dummy_killed")
	for dummy in get_tree().get_nodes_in_group("combat_dummies"):
		if dummy.has_signal("killed") and not dummy.is_connected(&"killed", kill_callback):
			dummy.connect(&"killed", kill_callback)

func _on_dummy_killed(_event: DamageEvent) -> void:
	match_director.record_kill(1)

func _bind_network_session() -> void:
	if _network_bound or network_session == null:
		return
	_network_bound = true
	network_session.peer_joined.connect(_on_network_peer_joined)
	network_session.peer_left.connect(_on_network_peer_left)
	network_session.connected_to_host.connect(_on_network_connected_to_host)
	network_session.hosting_started.connect(_on_network_hosting_started)
	network_session.session_closed.connect(_on_network_session_closed)
	if network_session.is_active():
		_activate_network_match()

func _update_network_sync(delta: float) -> void:
	if network_session == null or not network_session.is_active() or not network_session.is_connection_ready() or local_player == null:
		return
	if _capture_freeze_remote_proxies:
		return
	_update_local_network_state()
	_network_send_accum += delta
	var interval := 1.0 / NetworkConstants.SNAPSHOT_SEND_HZ
	if _network_send_accum < interval:
		return
	_network_send_accum = 0.0
	var active_slot := local_player.get_weapon_controller().active_slot
	if multiplayer.is_server():
		_send_player_transform_to_ready_peers(
			network_session.local_peer_id(),
			local_player.global_position,
			local_player.rotation.y,
			local_player.pitch,
			local_player.movement_state,
			active_slot
		)
		_send_authoritative_snapshot()
	else:
		submit_player_transform.rpc_id(
			1,
			local_player.global_position,
			local_player.rotation.y,
			local_player.pitch,
			local_player.movement_state,
			active_slot
		)

func _on_network_peer_joined(peer_id: int) -> void:
	if peer_id != network_session.local_peer_id():
		_ensure_remote_proxy(peer_id)
	if multiplayer.is_server():
		_ensure_network_player_state(peer_id)
		_respawn_network_peer(peer_id)
		_send_authoritative_snapshot()

func _on_network_peer_left(peer_id: int) -> void:
	_network_game_ready_peers.erase(peer_id)
	if remote_proxies.has(peer_id):
		remote_proxies[peer_id].queue_free()
		remote_proxies.erase(peer_id)

func _ensure_remote_proxy(peer_id: int) -> RemotePlayerProxy:
	if remote_proxies.has(peer_id):
		return remote_proxies[peer_id]
	var proxy: RemotePlayerProxy = REMOTE_PROXY_SCENE.instantiate()
	proxy.peer_id = peer_id
	proxy.set_player_name(String(_network_player_names.get(peer_id, "Peer %d" % peer_id)))
	proxy.name = "RemotePlayerProxy_%d" % peer_id
	players_root.add_child(proxy)
	remote_proxies[peer_id] = proxy
	return proxy

func _apply_remote_snapshot(peer_id: int, position: Vector3, yaw: float, pitch: float, state: StringName, slot: StringName) -> void:
	if network_session != null and peer_id == network_session.local_peer_id():
		return
	if _capture_freeze_remote_proxies and remote_proxies.has(peer_id):
		return
	var proxy := _ensure_remote_proxy(peer_id)
	proxy.apply_snapshot(position, yaw, pitch, state, slot)

func _load_network_weapon_definitions() -> void:
	for weapon_id in WeaponController.WEAPON_PATHS.keys():
		var definition: WeaponDefinition = load(WeaponController.WEAPON_PATHS[weapon_id])
		_weapon_definitions[weapon_id] = definition

func _activate_network_match() -> void:
	local_player.get_weapon_controller().set_multiplayer_combat_enabled(true)
	var peer_id := network_session.local_peer_id()
	_network_player_names[peer_id] = _local_player_name
	set_network_peer_scene_ready(peer_id, true)
	_ensure_network_player_state(peer_id)
	if multiplayer.is_server():
		_respawn_network_peer(peer_id)
		_send_authoritative_snapshot()
	elif network_session.is_connection_ready():
		submit_player_identity.rpc_id(1, _local_player_name)

func _on_network_hosting_started(_port: int) -> void:
	_activate_network_match()

func _on_network_connected_to_host() -> void:
	_activate_network_match()

func _on_network_session_closed() -> void:
	local_player.get_weapon_controller().set_multiplayer_combat_enabled(false)
	for proxy in remote_proxies.values():
		proxy.queue_free()
	remote_proxies.clear()
	_network_player_states.clear()
	_network_weapon_states.clear()
	_network_game_ready_peers.clear()

func _is_network_peer_scene_ready(peer_id: int) -> bool:
	if network_session == null or not network_session.is_active():
		return true
	if peer_id == network_session.local_peer_id():
		return true
	return bool(_network_game_ready_peers.get(peer_id, false))

func _ready_remote_peer_ids() -> Array:
	var peers := []
	if network_session == null or not network_session.is_active():
		return peers
	for peer_id_key in _network_player_states.keys():
		var peer_id := int(peer_id_key)
		if peer_id == network_session.local_peer_id():
			continue
		if _is_network_peer_scene_ready(peer_id):
			peers.append(peer_id)
	return peers

func _ensure_network_player_state(peer_id: int) -> Dictionary:
	if _network_player_states.has(peer_id):
		return _network_player_states[peer_id]
	var team_id := _assign_team_for_peer(peer_id)
	var local_peer_id := network_session.local_peer_id() if network_session != null and network_session.is_active() else 1
	var default_player_name := _local_player_name if peer_id == local_peer_id else "Peer %d" % peer_id
	var state := {
		"peer_id": peer_id,
		"player_name": _network_player_names.get(peer_id, default_player_name),
		"team_id": team_id,
		"selected_loadout_id": "default_v1",
		"is_ready": false,
		"is_alive": true,
		"kills": 0,
		"deaths": 0,
		"score": 0,
		"health": 100.0,
		"spawn_protection_remaining_sec": 0.0,
		"respawn_remaining_sec": -1.0,
		"current_slot": &"primary",
		"position": Vector3.ZERO,
		"velocity": Vector3.ZERO,
		"yaw": 0.0,
		"pitch": 0.0,
		"movement_state": &"airborne",
		"stun_remaining_sec": 0.0,
	}
	_network_player_states[peer_id] = state
	_network_player_names[peer_id] = String(state["player_name"])
	_network_weapon_states[peer_id] = _create_authoritative_weapon_states()
	return state

func _assign_team_for_peer(peer_id: int) -> int:
	if peer_id == 1:
		return 1
	var blue_count := 0
	var orange_count := 0
	for state in _network_player_states.values():
		if int(state["team_id"]) == 1:
			blue_count += 1
		elif int(state["team_id"]) == 2:
			orange_count += 1
	var max_per_team := match_director.rules.players_per_team
	if max_per_team > 0:
		if blue_count >= max_per_team and orange_count < max_per_team:
			return 2
		if orange_count >= max_per_team and blue_count < max_per_team:
			return 1
	return 1 if blue_count <= orange_count else 2

func _create_authoritative_weapon_states() -> Dictionary:
	var states := {}
	for weapon_id in _weapon_definitions.keys():
		var definition: WeaponDefinition = _weapon_definitions[weapon_id]
		states[String(weapon_id)] = {
			"ammo_in_mag": definition.magazine_size,
			"reserve_ammo": definition.reserve_ammo_max,
			"charges_current": definition.charges_max,
			"is_reloading": false,
			"reload_elapsed_sec": 0.0,
			"reload_remaining_sec": 0.0,
			"cooldown_remaining_sec": 0.0,
		}
	return states

func _update_local_network_state() -> void:
	var peer_id := network_session.local_peer_id()
	var state := _ensure_network_player_state(peer_id)
	state["position"] = local_player.global_position
	state["velocity"] = local_player.velocity
	state["yaw"] = local_player.rotation.y
	state["pitch"] = local_player.pitch
	state["movement_state"] = local_player.movement_state
	state["stun_remaining_sec"] = local_player.get_stun_remaining_sec()
	state["current_slot"] = local_player.get_weapon_controller().active_slot
	state["health"] = local_player.get_health_component().current_health
	state["is_alive"] = local_player.get_health_component().is_alive
	state["spawn_protection_remaining_sec"] = local_player.get_health_component().spawn_protection_remaining_sec

func _tick_network_status_effects(delta: float) -> void:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return
	for state in _network_player_states.values():
		var stun_remaining := maxf(0.0, float(state.get("stun_remaining_sec", 0.0)) - delta)
		state["stun_remaining_sec"] = stun_remaining
		if stun_remaining > 0.0 and bool(state["is_alive"]):
			state["velocity"] = Vector3.ZERO
			state["movement_state"] = &"stunned"

func _tick_network_weapon_states(delta: float) -> void:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return
	for peer_weapon_states in _network_weapon_states.values():
		for weapon_id_key in peer_weapon_states.keys():
			var weapon_state: Dictionary = peer_weapon_states[weapon_id_key]
			weapon_state["cooldown_remaining_sec"] = maxf(0.0, float(weapon_state["cooldown_remaining_sec"]) - delta)
			if bool(weapon_state["is_reloading"]):
				var definition: WeaponDefinition = _weapon_definitions[StringName(weapon_id_key)]
				weapon_state["reload_remaining_sec"] = maxf(0.0, float(weapon_state["reload_remaining_sec"]) - delta)
				weapon_state["reload_elapsed_sec"] = definition.reload_time_sec - float(weapon_state["reload_remaining_sec"])
				if float(weapon_state["reload_remaining_sec"]) <= 0.0:
					var missing := definition.magazine_size - int(weapon_state["ammo_in_mag"])
					var loaded := mini(missing, int(weapon_state["reserve_ammo"]))
					weapon_state["ammo_in_mag"] = int(weapon_state["ammo_in_mag"]) + loaded
					weapon_state["reserve_ammo"] = int(weapon_state["reserve_ammo"]) - loaded
					weapon_state["is_reloading"] = false
					weapon_state["reload_elapsed_sec"] = 0.0

func _tick_network_respawns(delta: float) -> void:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return
	for peer_id in _network_player_states.keys():
		var state: Dictionary = _network_player_states[peer_id]
		if bool(state["is_alive"]):
			state["spawn_protection_remaining_sec"] = maxf(0.0, float(state["spawn_protection_remaining_sec"]) - delta)
			continue
		state["respawn_remaining_sec"] = float(state["respawn_remaining_sec"]) - delta
		if float(state["respawn_remaining_sec"]) <= 0.0:
			_respawn_network_peer(peer_id)

func _respawn_network_peer(peer_id: int) -> void:
	var state := _ensure_network_player_state(peer_id)
	var team_id := int(state["team_id"])
	var spawn := _choose_network_spawn(team_id)
	var spawn_position := Vector3.ZERO
	var yaw := 0.0
	if spawn != null:
		spawn_position = spawn.global_position
		yaw = deg_to_rad(spawn.yaw_degrees)
	state["position"] = spawn_position
	state["velocity"] = Vector3.ZERO
	state["yaw"] = yaw
	state["pitch"] = 0.0
	state["movement_state"] = &"airborne"
	state["stun_remaining_sec"] = 0.0
	state["health"] = 100.0
	state["is_alive"] = true
	state["spawn_protection_remaining_sec"] = match_director.rules.spawn_protection_sec
	state["respawn_remaining_sec"] = -1.0
	_network_weapon_states[peer_id] = _create_authoritative_weapon_states()
	if network_session != null and peer_id == network_session.local_peer_id():
		local_player.global_position = spawn_position
		local_player.rotation.y = yaw
		local_player.yaw = yaw
		local_player.pitch = 0.0
		local_player.velocity = Vector3.ZERO
		local_player.set_stun_remaining_sec(0.0)
		local_player.get_health_component().force_network_state(100.0, true, match_director.rules.spawn_protection_sec)
		local_player.get_weapon_controller().apply_authoritative_weapon_states(_network_weapon_states[peer_id])
	_send_network_respawn_to_ready_peers(peer_id, spawn_position, yaw, team_id)

func _choose_network_spawn(team_id: int) -> SpawnPoint:
	var candidates: Array[SpawnPoint] = []
	for spawn in _arena_spawn_points:
		if spawn.is_enabled and spawn.team_id == team_id:
			candidates.append(spawn)
	if candidates.is_empty():
		return null
	return candidates.pick_random()

func _on_local_network_fire_requested(weapon_id: StringName, origin: Vector3, direction: Vector3, shooter_velocity: Vector3) -> void:
	if network_session == null or not network_session.is_active():
		return
	if multiplayer.is_server():
		_process_authoritative_fire(network_session.local_peer_id(), weapon_id, origin, direction, shooter_velocity)
	else:
		submit_fire_request.rpc_id(1, weapon_id, origin, direction, shooter_velocity)

func _on_local_network_reload_requested(weapon_id: StringName) -> void:
	if network_session == null or not network_session.is_active():
		return
	if multiplayer.is_server():
		_process_authoritative_reload(network_session.local_peer_id(), weapon_id)
	else:
		submit_reload_request.rpc_id(1, weapon_id)

func _on_local_network_slot_changed(slot: StringName) -> void:
	if network_session == null or not network_session.is_active():
		return
	if multiplayer.is_server():
		_process_authoritative_slot_change(network_session.local_peer_id(), slot)
	else:
		submit_slot_change.rpc_id(1, slot)

func _process_authoritative_reload(peer_id: int, weapon_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	_ensure_network_player_state(peer_id)
	var weapon_state: Dictionary = _network_weapon_states[peer_id][String(weapon_id)]
	var definition: WeaponDefinition = _weapon_definitions[weapon_id]
	if definition.magazine_size <= 0 or int(weapon_state["reserve_ammo"]) <= 0 or int(weapon_state["ammo_in_mag"]) >= definition.magazine_size:
		return
	weapon_state["is_reloading"] = true
	weapon_state["reload_elapsed_sec"] = 0.0
	weapon_state["reload_remaining_sec"] = definition.reload_time_sec

func _process_authoritative_slot_change(peer_id: int, slot: StringName) -> void:
	var state := _ensure_network_player_state(peer_id)
	state["current_slot"] = slot
	for weapon_state in _network_weapon_states[peer_id].values():
		weapon_state["is_reloading"] = false
		weapon_state["reload_elapsed_sec"] = 0.0
		weapon_state["reload_remaining_sec"] = 0.0

func _process_authoritative_fire(peer_id: int, weapon_id: StringName, origin: Vector3, direction: Vector3, shooter_velocity: Vector3) -> void:
	if not multiplayer.is_server() or match_director.match_phase != &"playing":
		return
	var shooter_state := _ensure_network_player_state(peer_id)
	if not bool(shooter_state["is_alive"]):
		return
	if not _weapon_definitions.has(weapon_id):
		return
	var definition: WeaponDefinition = _weapon_definitions[weapon_id]
	if not _try_consume_authoritative_fire(peer_id, definition):
		return
	shooter_state["current_slot"] = definition.slot_type
	if definition.uses_projectile:
		var landing_position := _estimate_throw_landing(origin, direction, shooter_velocity, definition)
		if definition.weapon_id == &"grenade":
			_apply_network_radius_damage(peer_id, landing_position, definition)
			_send_explosion_marker_to_ready_peers(landing_position, definition.effect_radius_m)
		else:
			_spawn_network_smoke(landing_position, definition.effect_duration_sec, definition.effect_radius_m)
			_send_smoke_volume_to_ready_peers(landing_position, definition.effect_duration_sec, definition.effect_radius_m)
		_send_authoritative_snapshot()
		return
	if definition.fire_mode == &"self_buff" or definition.fire_mode == &"portal":
		_send_authoritative_snapshot()
		return
	var pellets := maxi(1, definition.pellets_per_shot)
	for pellet_index in range(pellets):
		var pellet_direction := direction.normalized()
		if definition.is_hitscan and definition.spread_degrees > 0.0:
			pellet_direction = _apply_network_spread(pellet_direction, definition.spread_degrees)
		var hit := _find_network_player_hit(peer_id, origin, pellet_direction, definition.max_range_m)
		if hit.is_empty():
			continue
		if definition.fire_mode == &"utility":
			if definition.alt_action_type == &"pull":
				_apply_network_lasso(peer_id, int(hit["peer_id"]), definition)
			elif definition.alt_action_type == &"stun":
				_apply_network_stun(int(hit["peer_id"]), definition)
			continue
		var victim_peer_id := int(hit["peer_id"])
		var victim_state: Dictionary = _network_player_states[victim_peer_id]
		var damage := definition.head_damage if bool(hit["is_headshot"]) else definition.body_damage
		victim_state["health"] = maxf(0.0, float(victim_state["health"]) - damage)
		if float(victim_state["health"]) <= 0.0 and bool(victim_state["is_alive"]):
			_register_network_kill(peer_id, victim_peer_id)
		_apply_local_network_health_if_needed(victim_peer_id)
	_send_authoritative_snapshot()

func _try_consume_authoritative_fire(peer_id: int, definition: WeaponDefinition) -> bool:
	_ensure_network_player_state(peer_id)
	var weapon_state: Dictionary = _network_weapon_states[peer_id][String(definition.weapon_id)]
	if bool(weapon_state["is_reloading"]) or float(weapon_state["cooldown_remaining_sec"]) > 0.0:
		return false
	if definition.magazine_size > 0:
		if int(weapon_state["ammo_in_mag"]) <= 0:
			_process_authoritative_reload(peer_id, definition.weapon_id)
			return false
		weapon_state["ammo_in_mag"] = int(weapon_state["ammo_in_mag"]) - 1
	elif definition.charges_max > 0:
		if int(weapon_state["charges_current"]) <= 0:
			return false
		weapon_state["charges_current"] = int(weapon_state["charges_current"]) - 1
	weapon_state["cooldown_remaining_sec"] = definition.shot_cooldown_sec
	return true

func _find_network_player_hit(shooter_peer_id: int, origin: Vector3, direction: Vector3, max_range: float) -> Dictionary:
	var best_hit := {}
	var best_distance := max_range
	var ray_dir := direction.normalized()
	var shooter_team := int(_network_player_states[shooter_peer_id]["team_id"])
	for peer_id in _network_player_states.keys():
		if peer_id == shooter_peer_id:
			continue
		var state: Dictionary = _network_player_states[peer_id]
		if not bool(state["is_alive"]):
			continue
		if not match_director.rules.friendly_fire and int(state["team_id"]) == shooter_team:
			continue
		var target_position: Vector3 = state["position"]
		var hit := _intersect_player_capsule(origin, ray_dir, target_position, max_range)
		if hit.is_empty():
			continue
		if float(hit["distance"]) < best_distance:
			best_distance = float(hit["distance"])
			best_hit = {
				"peer_id": peer_id,
				"distance": best_distance,
				"is_headshot": bool(hit["is_headshot"]),
			}
	return best_hit

func _intersect_player_capsule(origin: Vector3, direction: Vector3, player_position: Vector3, max_range: float) -> Dictionary:
	var capsule_center := player_position + Vector3(0.0, 0.9, 0.0)
	var to_center := capsule_center - origin
	var distance_along := clampf(to_center.dot(direction), 0.0, max_range)
	var closest := origin + direction * distance_along
	var delta := capsule_center - closest
	var hit_radius := 0.48
	if delta.length() > hit_radius:
		return {}
	var local_hit_y := closest.y - player_position.y
	return {
		"distance": distance_along,
		"is_headshot": local_hit_y >= 1.35,
	}

func _register_network_kill(killer_peer_id: int, victim_peer_id: int) -> void:
	var killer_state: Dictionary = _network_player_states[killer_peer_id]
	var victim_state: Dictionary = _network_player_states[victim_peer_id]
	killer_state["kills"] = int(killer_state["kills"]) + 1
	killer_state["score"] = int(killer_state["score"]) + 1
	victim_state["deaths"] = int(victim_state["deaths"]) + 1
	victim_state["health"] = 0.0
	victim_state["is_alive"] = false
	victim_state["respawn_remaining_sec"] = match_director.rules.respawn_delay_sec
	match_director.record_kill(int(killer_state["team_id"]))

func _apply_local_network_health_if_needed(peer_id: int) -> void:
	if network_session == null or peer_id != network_session.local_peer_id():
		return
	var state: Dictionary = _network_player_states[peer_id]
	local_player.get_health_component().force_network_state(float(state["health"]), bool(state["is_alive"]), float(state["spawn_protection_remaining_sec"]))

func _apply_network_radius_damage(shooter_peer_id: int, position: Vector3, definition: WeaponDefinition) -> void:
	var shooter_team := int(_network_player_states[shooter_peer_id]["team_id"])
	for peer_id in _network_player_states.keys():
		var state: Dictionary = _network_player_states[peer_id]
		if not bool(state["is_alive"]):
			continue
		if peer_id != shooter_peer_id and not match_director.rules.friendly_fire and int(state["team_id"]) == shooter_team:
			continue
		var target_position: Vector3 = state["position"]
		var distance := target_position.distance_to(position)
		if distance > definition.effect_radius_m:
			continue
		var falloff := clampf(1.0 - (distance / definition.effect_radius_m), 0.25, 1.0)
		state["health"] = maxf(0.0, float(state["health"]) - definition.body_damage * falloff)
		if float(state["health"]) <= 0.0 and bool(state["is_alive"]):
			_register_network_kill(shooter_peer_id, peer_id)
		_apply_local_network_health_if_needed(peer_id)

func _apply_network_lasso(shooter_peer_id: int, victim_peer_id: int, definition: WeaponDefinition) -> void:
	var shooter_state: Dictionary = _network_player_states[shooter_peer_id]
	var victim_state: Dictionary = _network_player_states[victim_peer_id]
	var shooter_position: Vector3 = shooter_state["position"]
	var victim_position: Vector3 = victim_state["position"]
	var pull_direction := (shooter_position - victim_position).normalized()
	victim_state["position"] = victim_position + pull_direction * definition.propulsion_force * (1.0 / NetworkConstants.INPUT_SEND_HZ)
	victim_state["velocity"] = pull_direction * definition.propulsion_force

func _apply_network_stun(victim_peer_id: int, definition: WeaponDefinition) -> void:
	var victim_state: Dictionary = _network_player_states[victim_peer_id]
	victim_state["stun_remaining_sec"] = maxf(float(victim_state.get("stun_remaining_sec", 0.0)), definition.effect_duration_sec)
	victim_state["velocity"] = Vector3.ZERO
	victim_state["movement_state"] = &"stunned"
	if network_session != null and victim_peer_id == network_session.local_peer_id():
		local_player.apply_stun(definition.effect_duration_sec)

func _estimate_throw_landing(origin: Vector3, direction: Vector3, shooter_velocity: Vector3, definition: WeaponDefinition) -> Vector3:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() < 0.001:
		horizontal = -local_player.global_transform.basis.z
	horizontal = horizontal.normalized()
	var momentum_bonus := Vector3(shooter_velocity.x, 0.0, shooter_velocity.z) * 0.35
	var estimated := origin + horizontal * definition.projectile_speed_mps + momentum_bonus
	estimated.y = maxf(0.25, estimated.y - 1.2)
	return estimated

func _spawn_network_smoke(position: Vector3, duration: float, radius: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var smoke := SMOKE_VOLUME_SCENE.instantiate()
	if smoke.has_method("configure"):
		smoke.configure(duration, radius)
	effects_root.add_child(smoke)
	smoke.global_position = position
	if not smoke.has_method("configure") and smoke.has_method("set_lifetime"):
		smoke.set_lifetime(duration)
	if not smoke.has_method("configure") and smoke.has_method("set_radius"):
		smoke.set_radius(radius)

func _spawn_network_explosion_marker(position: Vector3, radius: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var marker := GRENADE_EXPLOSION_MARKER_SCENE.instantiate()
	effects_root.add_child(marker)
	marker.global_position = position
	if marker.has_method("setup"):
		marker.setup(radius)

func _apply_network_spread(direction: Vector3, spread_degrees: float) -> Vector3:
	var spread := deg_to_rad(spread_degrees)
	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(direction).normalized()
	var offset := right * randf_range(-spread, spread) + up * randf_range(-spread, spread)
	return (direction + offset).normalized()

func _build_match_snapshot() -> Dictionary:
	var players := []
	for peer_id in _network_player_states.keys():
		var state: Dictionary = _network_player_states[peer_id].duplicate(true)
		if _network_weapon_states.has(peer_id):
			state["weapon_states"] = _network_weapon_states[peer_id].duplicate(true)
		players.append(state)
	var summary := match_director.get_summary()
	summary["players"] = players
	return summary

func _send_authoritative_snapshot() -> void:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return
	var snapshot := _build_match_snapshot()
	for peer_id in _ready_remote_peer_ids():
		receive_match_snapshot.rpc_id(peer_id, snapshot)
	_apply_match_snapshot(snapshot)

func _send_authoritative_snapshot_to_peer(peer_id: int) -> void:
	if network_session == null or not network_session.is_active() or not multiplayer.is_server():
		return
	if peer_id == network_session.local_peer_id() or not _is_network_peer_scene_ready(peer_id):
		return
	receive_match_snapshot.rpc_id(peer_id, _build_match_snapshot())

func _send_player_transform_to_ready_peers(peer_id: int, position: Vector3, yaw: float, pitch: float, state: StringName, slot: StringName) -> void:
	for target_peer_id in _ready_remote_peer_ids():
		receive_player_transform.rpc_id(target_peer_id, peer_id, position, yaw, pitch, state, slot)

func _send_network_respawn_to_ready_peers(peer_id: int, position: Vector3, yaw: float, team_id: int) -> void:
	for target_peer_id in _ready_remote_peer_ids():
		receive_network_respawn.rpc_id(target_peer_id, peer_id, position, yaw, team_id)

func _send_current_respawn_to_peer(peer_id: int) -> void:
	if not _network_player_states.has(peer_id) or not _is_network_peer_scene_ready(peer_id):
		return
	var state: Dictionary = _network_player_states[peer_id]
	receive_network_respawn.rpc_id(
		peer_id,
		peer_id,
		state.get("position", Vector3.ZERO),
		float(state.get("yaw", 0.0)),
		int(state.get("team_id", 1))
	)

func _send_smoke_volume_to_ready_peers(position: Vector3, duration: float, radius: float) -> void:
	for peer_id in _ready_remote_peer_ids():
		receive_smoke_volume.rpc_id(peer_id, position, duration, radius)

func _send_explosion_marker_to_ready_peers(position: Vector3, radius: float) -> void:
	for peer_id in _ready_remote_peer_ids():
		receive_explosion_marker.rpc_id(peer_id, position, radius)

func _apply_match_snapshot(snapshot: Dictionary) -> void:
	match_director.apply_network_summary(snapshot)
	var local_peer_id := network_session.local_peer_id() if network_session != null and network_session.is_active() else 1
	for state in snapshot.get("players", []):
		var peer_id := int(state["peer_id"])
		state["player_name"] = _sanitize_player_name(String(state.get("player_name", "Peer %d" % peer_id)))
		_network_player_states[peer_id] = state
		_network_player_names[peer_id] = String(state["player_name"])
		if state.has("weapon_states"):
			_network_weapon_states[peer_id] = state["weapon_states"]
		if peer_id == local_peer_id:
			local_player.get_health_component().force_network_state(float(state["health"]), bool(state["is_alive"]), float(state["spawn_protection_remaining_sec"]))
			local_player.set_stun_remaining_sec(float(state.get("stun_remaining_sec", 0.0)))
			if state.has("weapon_states"):
				local_player.get_weapon_controller().apply_authoritative_weapon_states(state["weapon_states"])
		else:
			var proxy := _ensure_remote_proxy(peer_id)
			proxy.set_player_name(String(state["player_name"]))
			var proxy_position: Vector3 = state["position"]
			var proxy_state := StringName(str(state["movement_state"]))
			var proxy_slot := StringName(str(state["current_slot"]))
			proxy.apply_snapshot(proxy_position, float(state["yaw"]), float(state["pitch"]), proxy_state, proxy_slot)
			proxy.apply_combat_state(int(state["team_id"]), float(state["health"]), bool(state["is_alive"]))

@rpc("any_peer", "unreliable")
func submit_player_transform(position: Vector3, yaw: float, pitch: float, state: StringName, slot: StringName) -> void:
	if not multiplayer.is_server():
		return
	if _capture_freeze_remote_proxies:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	var player_state := _ensure_network_player_state(sender)
	if float(player_state.get("stun_remaining_sec", 0.0)) > 0.0:
		return
	player_state["position"] = position
	player_state["yaw"] = yaw
	player_state["pitch"] = pitch
	player_state["movement_state"] = state
	player_state["current_slot"] = slot
	_apply_remote_snapshot(sender, position, yaw, pitch, state, slot)
	_send_player_transform_to_ready_peers(sender, position, yaw, pitch, state, slot)

@rpc("any_peer", "reliable")
func submit_player_identity(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	var sanitized := _sanitize_player_name(player_name)
	_network_player_names[sender] = sanitized
	var state := _ensure_network_player_state(sender)
	state["player_name"] = sanitized
	if remote_proxies.has(sender):
		(remote_proxies[sender] as RemotePlayerProxy).set_player_name(sanitized)
	_send_authoritative_snapshot()

@rpc("authority", "unreliable")
func receive_player_transform(peer_id: int, position: Vector3, yaw: float, pitch: float, state: StringName, slot: StringName) -> void:
	_apply_remote_snapshot(peer_id, position, yaw, pitch, state, slot)

@rpc("any_peer", "reliable")
func submit_fire_request(weapon_id: StringName, origin: Vector3, direction: Vector3, shooter_velocity: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		_process_authoritative_fire(sender, weapon_id, origin, direction, shooter_velocity)

@rpc("any_peer", "reliable")
func submit_reload_request(weapon_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		_process_authoritative_reload(sender, weapon_id)

@rpc("any_peer", "reliable")
func submit_slot_change(slot: StringName) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		_process_authoritative_slot_change(sender, slot)

@rpc("authority", "reliable")
func receive_match_snapshot(snapshot: Dictionary) -> void:
	_apply_match_snapshot(snapshot)

@rpc("authority", "reliable")
func receive_network_respawn(peer_id: int, position: Vector3, yaw: float, team_id: int) -> void:
	var local_peer_id := network_session.local_peer_id() if network_session != null and network_session.is_active() else 1
	if peer_id == local_peer_id:
		local_player.global_position = position
		local_player.rotation.y = yaw
		local_player.yaw = yaw
		local_player.pitch = 0.0
		local_player.velocity = Vector3.ZERO
		local_player.get_health_component().force_network_state(100.0, true, match_director.rules.spawn_protection_sec)
	else:
		var proxy := _ensure_remote_proxy(peer_id)
		proxy.apply_snapshot(position, yaw, 0.0, &"airborne", proxy.active_slot)
		proxy.apply_combat_state(team_id, 100.0, true)

@rpc("authority", "reliable")
func receive_smoke_volume(position: Vector3, duration: float, radius: float) -> void:
	if multiplayer.is_server():
		return
	_spawn_network_smoke(position, duration, radius)

@rpc("authority", "reliable")
func receive_explosion_marker(position: Vector3, radius: float) -> void:
	if multiplayer.is_server():
		return
	_spawn_network_explosion_marker(position, radius)
