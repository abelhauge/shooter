extends Node

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const LOBBY_MENU_SCENE := preload("res://scenes/frontend/lobby_menu.tscn")
const P05A_WEAPON_CAPTURE_ORDER := [
	&"assault_rifle",
	&"handgun",
	&"shotgun",
	&"sniper",
	&"knife",
	&"smoke_bomb",
	&"grenade",
	&"flamethrower",
	&"lasso",
	&"taser_gun",
	&"redbull",
	&"portal_gun",
]
const P05A_FEEDBACK_CAPTURE_WEAPONS := [&"assault_rifle", &"handgun", &"shotgun"]
const P05A_ASSET_BACKED_WEAPONS := [
	&"assault_rifle",
	&"handgun",
	&"shotgun",
	&"sniper",
	&"knife",
	&"smoke_bomb",
	&"grenade",
	&"flamethrower",
	&"lasso",
	&"taser_gun",
	&"redbull",
	&"portal_gun",
]
const P10A_OFFLINE_SCREENSHOTS := [
	{"view": "blue_spawn", "file": "blue_spawn"},
	{"view": "orange_spawn", "file": "orange_spawn"},
	{"view": "mid_map", "file": "mid_map"},
	{"view": "high_route", "file": "high_route"},
	{"view": "close_combat", "file": "close_combat"},
	{"view": "smoke_combat_fx", "file": "smoke_combat_fx"},
	{"view": "assault_rifle", "file": "assault_rifle"},
	{"view": "primary_assault_rifle", "file": "primary_assault_rifle"},
	{"view": "handgun", "file": "handgun"},
	{"view": "hud_under_combat", "file": "hud_under_combat"},
]
const P10A_OFFLINE_PLAYTEST_DURATION_SEC := 900.0
const P10A_MULTIPLAYER_PLAYTEST_DURATION_SEC := 300.0
const P11_PLAYTEST_DURATION_SEC := 1200.0
const P14_WEAPON_PLAYTEST_DURATION_SEC := 300.0

var _active_scene: Node
var _network_session: NetworkSession
var _lobby_ready_by_peer: Dictionary = {}
var _game_scene_ready_by_peer: Dictionary = {}
var _selected_loadout: LoadoutDefinition = preload("res://data/loadouts/default_v1_loadout.tres")
var _smoke_test := ""
var _smoke_expected_peers := 0
var _smoke_host := "127.0.0.1"
var _smoke_port := NetworkConstants.DEFAULT_PORT
var _smoke_timeout_sec := 8.0
var _smoke_elapsed_sec := 0.0
var _smoke_active := false
var _smoke_started_match := false
var _smoke_ready_sent := false
var _smoke_connected_to_host := false
var _smoke_weapon_checked := false
var _smoke_pause_checked := false
var _smoke_offline_system_checked := false
var _smoke_all_weapons_checked := false
var _smoke_network_authority_checked := false
var _smoke_connected_hold_sec := 0.0
var _smoke_client_hold_sec := 1.0
var _smoke_disable_heartbeat := false
var _smoke_heartbeat_timeout_peer_id := 0
var _p06_driver_pose_requested := false
var _p06_driver_pose_applied := false
var _p07_duration_sec := 600.0
var _p10a_offline_duration_sec := P10A_OFFLINE_PLAYTEST_DURATION_SEC
var _p10a_multiplayer_duration_sec := P10A_MULTIPLAYER_PLAYTEST_DURATION_SEC
var _p11_duration_sec := P11_PLAYTEST_DURATION_SEC
var _p14_duration_sec := P14_WEAPON_PLAYTEST_DURATION_SEC
var _p08_host_address := "127.0.0.1"
var _p08_port := NetworkConstants.DEFAULT_PORT
var _p08_timeout_sec := 30.0
var _p08_client_hold_sec := 18.0
var _network_arg_requested_host := false
var _network_arg_requested_join := false
var _force_lobby_join_override := false
var _startup_host_lobby_mode := false
var _startup_lobby_status := ""
var _startup_host_address := ""
var _network_password := ""
var _authenticated_peer_ids: Dictionary = {1: true}
var _pending_auth_by_peer: Dictionary = {}
var _client_password_accepted := false
var _heartbeat_send_elapsed_sec := 0.0
var _heartbeat_timeout_sec := NetworkConstants.HEARTBEAT_TIMEOUT_SEC
var _heartbeat_last_seen_msec_by_peer: Dictionary = {}
var _heartbeat_timed_out_peer_ids: Dictionary = {}
var _verification_capture := ""
var _dev_balance_dummy_enabled_for_next_game := false
var _local_player_name := "Player"
var _lobby_player_names_by_peer: Dictionary = {1: "Player"}
var _pending_match_start_by_peer: Dictionary = {}
var _persistent_host_requested := false
var _headless_host_ready_printed := false

func _ready() -> void:
	_parse_smoke_args()
	_apply_startup_window_mode()
	_network_session = NetworkSession.new()
	_network_session.name = "NetworkSession"
	add_child(_network_session)
	_bind_network_session()
	var has_network_args := _apply_network_args()
	if has_network_args and _network_arg_requested_host:
		_load_game_root()
	else:
		_load_lobby()
	if _smoke_test != "":
		call_deferred("_begin_smoke_test")
	elif _verification_capture != "":
		call_deferred("_begin_verification_capture")

func _process(delta: float) -> void:
	_tick_network_heartbeat(delta)
	if _smoke_active:
		_tick_smoke_test(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(FpsInputActions.PAUSE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _apply_startup_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _load_game_root() -> void:
	var game_root := GAME_ROOT_SCENE.instantiate()
	game_root.name = "GameRoot"
	_clear_active_scene()
	_active_scene = game_root
	if _active_scene.has_method("set_local_player_name"):
		_active_scene.set_local_player_name(_local_player_name)
	if _active_scene.has_method("set_network_player_names"):
		_active_scene.set_network_player_names(_lobby_player_names_by_peer)
	if _active_scene.has_method("set_authorized_network_peer_ids"):
		_active_scene.set_authorized_network_peer_ids(_authenticated_peer_ids)
	if _active_scene.has_method("set_selected_loadout"):
		_active_scene.set_selected_loadout(_selected_loadout)
	if _active_scene.has_method("set_dev_balance_dummy_enabled"):
		_active_scene.set_dev_balance_dummy_enabled(_dev_balance_dummy_enabled_for_next_game)
	if _active_scene.has_method("set_persistent_host_enabled"):
		_active_scene.set_persistent_host_enabled(_persistent_host_requested)
	if _active_scene.has_method("set_network_session"):
		_active_scene.set_network_session(_network_session)
	add_child(_active_scene)
	_push_game_scene_readiness_to_active_scene()
	if _network_session != null and _network_session.is_active():
		if multiplayer.is_server():
			_mark_game_scene_ready(_network_session.local_peer_id(), true)
		else:
			call_deferred("_notify_host_game_scene_ready")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _load_lobby() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var lobby: LobbyMenu = LOBBY_MENU_SCENE.instantiate()
	lobby.name = "LobbyMenu"
	_clear_active_scene()
	_active_scene = lobby
	if _startup_host_lobby_mode and lobby.has_method("set_host_lobby_mode"):
		lobby.set_host_lobby_mode(true)
	add_child(lobby)
	lobby.offline_requested.connect(_on_lobby_offline_requested)
	lobby.host_requested.connect(_on_lobby_host_requested)
	lobby.join_requested.connect(_on_lobby_join_requested)
	lobby.ready_requested.connect(_on_lobby_ready_requested)
	lobby.start_requested.connect(_on_lobby_start_requested)
	if _startup_host_address != "" and lobby.has_method("set_manual_host_address"):
		lobby.set_manual_host_address(_startup_host_address)
	if _network_password != "" and lobby.has_method("set_match_password"):
		lobby.set_match_password(_network_password)
	if _force_lobby_join_override and lobby.has_method("set_public_join_override"):
		lobby.set_public_join_override(true)
	if _startup_lobby_status != "":
		lobby.set_status(_startup_lobby_status)
	if _network_session != null:
		_network_session.start_lan_discovery()
		_refresh_lobby_lan_hosts()

func _clear_active_scene() -> void:
	if _active_scene != null:
		if _active_scene.get_parent() == self:
			remove_child(_active_scene)
		_active_scene.queue_free()
		_active_scene = null

func _apply_network_args() -> bool:
	var args := OS.get_cmdline_user_args()
	var requested_host := false
	var join_address := ""
	var port := NetworkConstants.DEFAULT_PORT
	var env_password := OS.get_environment("SHOOTER_MATCH_PASSWORD").strip_edges()
	if env_password != "":
		_network_password = env_password
	for arg in args:
		if arg == "--host":
			requested_host = true
		elif arg == "--join":
			_force_lobby_join_override = true
		elif arg.begins_with("--join="):
			join_address = arg.trim_prefix("--join=")
			_startup_host_address = join_address
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--name="):
			_local_player_name = _sanitize_player_name(arg.trim_prefix("--name="))
			_lobby_player_names_by_peer[1] = _local_player_name
		elif arg.begins_with("--password="):
			_network_password = arg.trim_prefix("--password=").strip_edges()
	if not requested_host and join_address == "" and not _force_lobby_join_override and _should_auto_host_headless():
		requested_host = true
		if _local_player_name == "Player":
			_local_player_name = "Headless Host"
	var direct_host_requested := requested_host and _should_direct_host_from_args()
	if requested_host and not direct_host_requested:
		_startup_host_lobby_mode = true
		_startup_lobby_status = "Choose loadout, enter match password, then press Start."
		return false
	if _network_password == "" and (direct_host_requested or join_address != ""):
		_startup_lobby_status = "Enter a match password before hosting or joining."
		if join_address != "":
			_force_lobby_join_override = true
		if DisplayServer.get_name() == "headless" and _should_auto_host_headless():
			printerr("MATCH_PASSWORD_REQUIRED use --password=<password> or SHOOTER_MATCH_PASSWORD for headless hosting")
			get_tree().quit(1)
		return false
	if direct_host_requested:
		_network_arg_requested_host = true
		if DisplayServer.get_name() == "headless" and _smoke_test == "" and _verification_capture == "":
			_persistent_host_requested = true
		_game_scene_ready_by_peer.clear()
		_headless_host_ready_printed = false
		_lobby_player_names_by_peer = {1: _local_player_name}
		_authenticated_peer_ids = {1: true}
		_pending_auth_by_peer.clear()
		_reset_heartbeat_state()
		_client_password_accepted = false
		_network_session.host(port)
		return true
	elif join_address != "":
		_network_arg_requested_join = true
		_game_scene_ready_by_peer.clear()
		_lobby_player_names_by_peer = {1: _local_player_name}
		_authenticated_peer_ids.clear()
		_pending_auth_by_peer.clear()
		_reset_heartbeat_state()
		_client_password_accepted = false
		_network_session.join(join_address, port)
		return true
	elif _force_lobby_join_override:
		_startup_lobby_status = "Enter Host IP and match password, then press Join IP."
	return false

func _should_auto_host_headless() -> bool:
	return DisplayServer.get_name() == "headless" and _smoke_test == "" and _verification_capture == ""

func _should_direct_host_from_args() -> bool:
	if _smoke_test == "host-lobby":
		return false
	return DisplayServer.get_name() == "headless" or _smoke_test != "" or _verification_capture != ""

func _parse_smoke_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--smoke-test="):
			_smoke_test = arg.trim_prefix("--smoke-test=")
		elif arg.begins_with("--smoke-expected-peers="):
			_smoke_expected_peers = int(arg.trim_prefix("--smoke-expected-peers="))
		elif arg.begins_with("--smoke-host="):
			_smoke_host = arg.trim_prefix("--smoke-host=")
		elif arg.begins_with("--smoke-port="):
			_smoke_port = int(arg.trim_prefix("--smoke-port="))
		elif arg.begins_with("--smoke-timeout-sec="):
			_smoke_timeout_sec = float(arg.trim_prefix("--smoke-timeout-sec="))
		elif arg.begins_with("--smoke-client-hold-sec="):
			_smoke_client_hold_sec = maxf(0.1, float(arg.trim_prefix("--smoke-client-hold-sec=")))
		elif arg == "--smoke-disable-heartbeat":
			_smoke_disable_heartbeat = true
		elif arg.begins_with("--smoke-heartbeat-timeout-sec="):
			_heartbeat_timeout_sec = maxf(0.5, float(arg.trim_prefix("--smoke-heartbeat-timeout-sec=")))
		elif arg.begins_with("--verification-capture="):
			_verification_capture = arg.trim_prefix("--verification-capture=")
		elif arg == "--p06-driver-pose":
			_p06_driver_pose_requested = true
		elif arg.begins_with("--p07-duration-sec="):
			_p07_duration_sec = float(arg.trim_prefix("--p07-duration-sec="))
		elif arg.begins_with("--p10a-duration-sec="):
			_p10a_offline_duration_sec = float(arg.trim_prefix("--p10a-duration-sec="))
		elif arg.begins_with("--p10a-multiplayer-duration-sec="):
			_p10a_multiplayer_duration_sec = float(arg.trim_prefix("--p10a-multiplayer-duration-sec="))
		elif arg.begins_with("--p10a-host="):
			_p08_host_address = arg.trim_prefix("--p10a-host=")
		elif arg.begins_with("--p10a-port="):
			_p08_port = int(arg.trim_prefix("--p10a-port="))
		elif arg.begins_with("--p10a-timeout-sec="):
			_p08_timeout_sec = float(arg.trim_prefix("--p10a-timeout-sec="))
		elif arg.begins_with("--p11-duration-sec="):
			_p11_duration_sec = float(arg.trim_prefix("--p11-duration-sec="))
		elif arg.begins_with("--p14-duration-sec="):
			_p14_duration_sec = float(arg.trim_prefix("--p14-duration-sec="))
		elif arg.begins_with("--p08-host="):
			_p08_host_address = arg.trim_prefix("--p08-host=")
		elif arg.begins_with("--p08-port="):
			_p08_port = int(arg.trim_prefix("--p08-port="))
		elif arg.begins_with("--p08-timeout-sec="):
			_p08_timeout_sec = float(arg.trim_prefix("--p08-timeout-sec="))
		elif arg.begins_with("--p08-client-hold-sec="):
			_p08_client_hold_sec = float(arg.trim_prefix("--p08-client-hold-sec="))
		elif arg.begins_with("--p12-host="):
			_p08_host_address = arg.trim_prefix("--p12-host=")
		elif arg.begins_with("--p12-port="):
			_p08_port = int(arg.trim_prefix("--p12-port="))
		elif arg.begins_with("--p12-timeout-sec="):
			_p08_timeout_sec = float(arg.trim_prefix("--p12-timeout-sec="))
		elif arg.begins_with("--p12-client-hold-sec="):
			_p08_client_hold_sec = float(arg.trim_prefix("--p12-client-hold-sec="))
		elif arg.begins_with("--p13-host="):
			_p08_host_address = arg.trim_prefix("--p13-host=")
		elif arg.begins_with("--p13-port="):
			_p08_port = int(arg.trim_prefix("--p13-port="))
		elif arg.begins_with("--p13-timeout-sec="):
			_p08_timeout_sec = float(arg.trim_prefix("--p13-timeout-sec="))
		elif arg.begins_with("--p13-client-hold-sec="):
			_p08_client_hold_sec = float(arg.trim_prefix("--p13-client-hold-sec="))
		elif arg.begins_with("--p14-host="):
			_p08_host_address = arg.trim_prefix("--p14-host=")
		elif arg.begins_with("--p14-port="):
			_p08_port = int(arg.trim_prefix("--p14-port="))
		elif arg.begins_with("--p14-timeout-sec="):
			_p08_timeout_sec = float(arg.trim_prefix("--p14-timeout-sec="))
		elif arg.begins_with("--p14-client-hold-sec="):
			_p08_client_hold_sec = float(arg.trim_prefix("--p14-client-hold-sec="))

func _begin_verification_capture() -> void:
	print("VERIFICATION_CAPTURE_START %s" % _verification_capture)
	if _verification_capture == "p01":
		await _capture_p01_baseline()
	elif _verification_capture == "lan-discovery-lobby":
		await _capture_lan_discovery_lobby()
	elif _verification_capture == "p03":
		await _capture_p03_environment_asset_proof()
	elif _verification_capture == "p04":
		await _capture_p04_arena_dressing()
	elif _verification_capture == "p05":
		await _capture_p05_weapon_viewmodels()
	elif _verification_capture == "p05a":
		await _capture_p05a_weapon_visual_qa()
	elif _verification_capture == "p06":
		await _capture_p06_remote_humanoid()
	elif _verification_capture == "p07":
		await _capture_p07_offline_playability()
	elif _verification_capture == "p10a-before":
		await _capture_p10a_offline_visual_polish("before", false)
	elif _verification_capture == "p10a-after":
		await _capture_p10a_offline_visual_polish("after", true)
	elif _verification_capture == "p10a-host":
		await _capture_p10a_host_visual_polish()
	elif _verification_capture == "p10a-client":
		await _capture_p10a_client_visual_polish()
	elif _verification_capture == "p11":
		await _capture_p11_core_combat_tuning()
	elif _verification_capture == "p08-host":
		await _capture_p08_host()
	elif _verification_capture == "p08-client":
		await _capture_p08_client()
	elif _verification_capture == "p12-host":
		await _capture_p12_host()
	elif _verification_capture == "p12-client":
		await _capture_p12_client()
	elif _verification_capture == "p13-host":
		await _capture_p13_host()
	elif _verification_capture == "p13-client":
		await _capture_p13_client()
	elif _verification_capture == "p14-shotgun":
		await _capture_p14_shotgun_pass()
	elif _verification_capture == "p14-shotgun-host":
		await _capture_p14_shotgun_host()
	elif _verification_capture == "p14-shotgun-client":
		await _capture_p14_shotgun_client()
	elif _verification_capture == "p14-sniper":
		await _capture_p14_sniper_pass()
	elif _verification_capture == "p14-sniper-host":
		await _capture_p14_sniper_host()
	elif _verification_capture == "p14-sniper-client":
		await _capture_p14_sniper_client()
	elif _verification_capture == "p14-grenade":
		await _capture_p14_grenade_pass()
	elif _verification_capture == "p14-grenade-host":
		await _capture_p14_grenade_host()
	elif _verification_capture == "p14-grenade-client":
		await _capture_p14_grenade_client()
	elif _verification_capture == "p14-flamethrower":
		await _capture_p14_flamethrower_pass()
	elif _verification_capture == "p14-flamethrower-host":
		await _capture_p14_flamethrower_host()
	elif _verification_capture == "p14-flamethrower-client":
		await _capture_p14_flamethrower_client()
	elif _verification_capture == "p14-lasso":
		await _capture_p14_lasso_pass()
	elif _verification_capture == "p14-lasso-host":
		await _capture_p14_lasso_host()
	elif _verification_capture == "p14-lasso-client":
		await _capture_p14_lasso_client()
	elif _verification_capture == "p14-redbull":
		await _capture_p14_redbull_pass()
	elif _verification_capture == "p14-redbull-host":
		await _capture_p14_redbull_host()
	elif _verification_capture == "p14-redbull-client":
		await _capture_p14_redbull_client()
	elif _verification_capture == "p14-portal-gun":
		await _capture_p14_portal_gun_pass()
	elif _verification_capture == "p14-portal-gun-host":
		await _capture_p14_portal_gun_host()
	elif _verification_capture == "p14-portal-gun-client":
		await _capture_p14_portal_gun_client()
	elif _verification_capture == "p23":
		await _capture_p23_city_asset_level_designer()
	else:
		printerr("VERIFICATION_CAPTURE_FAIL unknown capture '%s'" % _verification_capture)
		get_tree().quit(1)

func _capture_p01_baseline() -> void:
	await _wait_for_render_frames(3)
	var lobby_result := _save_viewport_png("res://docs/verification/screenshots/p01_lobby_baseline.png")
	if lobby_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL lobby screenshot: %s" % error_string(lobby_result))
		get_tree().quit(1)
		return
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL expected lobby before offline start")
		get_tree().quit(1)
		return
	(_active_scene as LobbyMenu).smoke_press_offline()
	await _wait_for_render_frames(8)
	var spawn_result := _save_viewport_png("res://docs/verification/screenshots/p01_spawn_baseline.png")
	if spawn_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL spawn screenshot: %s" % error_string(spawn_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_PASS p01")
	get_tree().quit(0)

func _capture_lan_discovery_lobby() -> void:
	await _wait_for_render_frames(8)
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL lan-discovery-lobby expected lobby scene")
		get_tree().quit(1)
		return
	var screenshot_result := _save_viewport_png("res://docs/verification/screenshots/lan_discovery_lobby.png")
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL lan-discovery-lobby screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_PASS lan-discovery-lobby")
	get_tree().quit(0)

func _capture_p03_environment_asset_proof() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p03 expected lobby before offline start")
		get_tree().quit(1)
		return
	(_active_scene as LobbyMenu).smoke_press_offline()
	await _wait_for_render_frames(10)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p03 game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("prepare_p03_capture_view"):
		printerr("VERIFICATION_CAPTURE_FAIL p03 game scene has no capture view hook")
		get_tree().quit(1)
		return
	var capture_setup: Dictionary = _active_scene.prepare_p03_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p03 %s" % str(capture_setup.get("error", "capture setup failed")))
		get_tree().quit(1)
		return
	var manifest: Array = capture_setup.get("manifest", [])
	if manifest.size() < 10:
		printerr("VERIFICATION_CAPTURE_FAIL p03 expected at least 10 asset manifest entries, got %d" % manifest.size())
		get_tree().quit(1)
		return
	for item in manifest:
		print("VERIFICATION_CAPTURE_ASSET %s %s" % [str(item.get("source_file", "")), str(item.get("node_path", ""))])
	await _wait_for_render_frames(6)
	var screenshot_result := _save_viewport_png("res://docs/verification/screenshots/p03_environment_asset_proof.png")
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p03 screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_PASS p03")
	get_tree().quit(0)

func _capture_p04_arena_dressing() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p04 expected lobby before offline start")
		get_tree().quit(1)
		return
	(_active_scene as LobbyMenu).smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p04 game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("get_p04_dressing_report") or not _active_scene.has_method("get_p04_dressing_manifest"):
		printerr("VERIFICATION_CAPTURE_FAIL p04 game scene has no dressing report hook")
		get_tree().quit(1)
		return
	var report: Dictionary = _active_scene.get_p04_dressing_report()
	var manifest: Array = _active_scene.get_p04_dressing_manifest()
	if manifest.size() < 20:
		printerr("VERIFICATION_CAPTURE_FAIL p04 expected at least 20 dressing instances, got %d" % manifest.size())
		get_tree().quit(1)
		return
	if int(report.get("landmark_count", 0)) < 4:
		printerr("VERIFICATION_CAPTURE_FAIL p04 expected at least 4 landmarks, got %d" % int(report.get("landmark_count", 0)))
		get_tree().quit(1)
		return
	if int(report.get("playable_support_count", 0)) < 8:
		printerr("VERIFICATION_CAPTURE_FAIL p04 expected at least 8 playable-space art supports, got %d" % int(report.get("playable_support_count", 0)))
		get_tree().quit(1)
		return
	if int(report.get("traversal_route_count", 0)) < 2:
		printerr("VERIFICATION_CAPTURE_FAIL p04 expected at least 2 art-supported traversal routes, got %d" % int(report.get("traversal_route_count", 0)))
		get_tree().quit(1)
		return
	if int(report.get("enabled_art_collision_objects", 0)) != 0:
		printerr("VERIFICATION_CAPTURE_FAIL p04 dressing art has enabled collision objects: %d" % int(report.get("enabled_art_collision_objects", 0)))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_REPORT_P04 instances=%d landmarks=%d playable_support=%d traversal_routes=%d enabled_art_collision_objects=%d routes=%s" % [
		manifest.size(),
		int(report.get("landmark_count", 0)),
		int(report.get("playable_support_count", 0)),
		int(report.get("traversal_route_count", 0)),
		int(report.get("enabled_art_collision_objects", 0)),
		str(report.get("traversal_routes", [])),
	])
	for item in manifest:
		print("VERIFICATION_CAPTURE_ASSET_P04 %s %s tags=%s route=%s" % [
			str(item.get("source_file", "")),
			str(item.get("node_path", "")),
			str(item.get("tags", [])),
			str(item.get("route", "")),
		])
	if not _active_scene.has_method("prepare_p04_capture_view"):
		printerr("VERIFICATION_CAPTURE_FAIL p04 game scene has no capture view hook")
		get_tree().quit(1)
		return
	var views := [
		{"name": "blue_spawn", "path": "res://docs/verification/screenshots/p04_blue_spawn.png"},
		{"name": "orange_spawn", "path": "res://docs/verification/screenshots/p04_orange_spawn.png"},
		{"name": "mid_map", "path": "res://docs/verification/screenshots/p04_mid_map.png"},
		{"name": "traversal_route", "path": "res://docs/verification/screenshots/p04_traversal_route.png"},
	]
	for view in views:
		var view_name := String(view["name"])
		var capture_setup: Dictionary = _active_scene.prepare_p04_capture_view(view_name)
		if not bool(capture_setup.get("ok", false)):
			printerr("VERIFICATION_CAPTURE_FAIL p04 %s" % str(capture_setup.get("error", "capture setup failed")))
			get_tree().quit(1)
			return
		await _wait_for_render_frames(6)
		var screenshot_result := _save_viewport_png(String(view["path"]))
		if screenshot_result != OK:
			printerr("VERIFICATION_CAPTURE_FAIL p04 %s screenshot: %s" % [view_name, error_string(screenshot_result)])
			get_tree().quit(1)
			return
	print("VERIFICATION_CAPTURE_PASS p04")
	get_tree().quit(0)

func _capture_p23_city_asset_level_designer() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p23 expected lobby before offline start")
		get_tree().quit(1)
		return
	(_active_scene as LobbyMenu).smoke_press_offline()
	await _wait_process_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p23 game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p23_level_designer_checks"):
		printerr("VERIFICATION_CAPTURE_FAIL p23 game scene has no P23 level designer hooks")
		get_tree().quit(1)
		return
	var report: Dictionary = await _active_scene.run_p23_level_designer_checks()
	if not _validate_p23_level_designer_report(report):
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_REPORT_P23 %s" % JSON.stringify(report))
	print("VERIFICATION_CAPTURE_PASS p23")
	get_tree().quit(0)

func _validate_p23_level_designer_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p23 report failed: %s" % str(report))
		return false
	var p23_report: Dictionary = report.get("p23_report", {})
	var placement_count := int(p23_report.get("placement_count", 0))
	if int(p23_report.get("stable_name_count", 0)) < placement_count:
		printerr("VERIFICATION_CAPTURE_FAIL p23 unstable placement names: %s" % str(p23_report))
		return false
	if not p23_report.get("missing_sources", []).is_empty():
		printerr("VERIFICATION_CAPTURE_FAIL p23 missing placement sources: %s" % str(p23_report))
		return false
	if not p23_report.get("source_pack_paths", []).is_empty():
		printerr("VERIFICATION_CAPTURE_FAIL p23 uses source_packs: %s" % str(p23_report))
		return false
	return true

func _capture_p05_weapon_viewmodels() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p05 expected lobby before offline start")
		get_tree().quit(1)
		return
	(_active_scene as LobbyMenu).smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p05 game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("prepare_p05_capture_view"):
		printerr("VERIFICATION_CAPTURE_FAIL p05 game scene has no weapon capture hook")
		get_tree().quit(1)
		return
	var rifle_result: Dictionary = _active_scene.prepare_p05_capture_view(&"primary", true)
	if not _validate_p05_view_model(rifle_result, "Rifle.fbx"):
		return
	print("VERIFICATION_CAPTURE_VIEWMODEL_P05 rifle %s" % str(rifle_result.get("view_model", {})))
	await _wait_for_render_frames(1)
	var rifle_screenshot := _save_viewport_png("res://docs/verification/screenshots/p05_rifle_viewmodel.png")
	if rifle_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p05 rifle screenshot: %s" % error_string(rifle_screenshot))
		get_tree().quit(1)
		return
	var handgun_result: Dictionary = _active_scene.prepare_p05_capture_view(&"secondary", false)
	if not _validate_p05_view_model(handgun_result, "Pistol.fbx"):
		return
	print("VERIFICATION_CAPTURE_VIEWMODEL_P05 handgun %s" % str(handgun_result.get("view_model", {})))
	await _wait_for_render_frames(4)
	var handgun_screenshot := _save_viewport_png("res://docs/verification/screenshots/p05_handgun_viewmodel.png")
	if handgun_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p05 handgun screenshot: %s" % error_string(handgun_screenshot))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_PASS p05")
	get_tree().quit(0)

func _capture_p05a_weapon_visual_qa() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p05a expected lobby before offline start")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	var lobby_options := _validate_lobby_weapon_options(lobby)
	if not bool(lobby_options.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p05a %s" % str(lobby_options.get("error", "lobby weapon options failed")))
		get_tree().quit(1)
		return
	lobby.smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p05a game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("prepare_p05a_weapon_capture"):
		printerr("VERIFICATION_CAPTURE_FAIL p05a game scene has no weapon visual QA hook")
		get_tree().quit(1)
		return
	var report := []
	var rejected_shotgun_image := _load_optional_image("res://docs/verification/screenshots/weapon_visual_qa/shotgun.png")
	for weapon_id in P05A_WEAPON_CAPTURE_ORDER:
		var capture_result: Dictionary = _active_scene.prepare_p05a_weapon_capture(weapon_id, false)
		if not _validate_p05a_capture_result(capture_result, weapon_id, false):
			return
		print("VERIFICATION_CAPTURE_VIEWMODEL_P05A %s %s" % [String(weapon_id), str(capture_result.get("view_model", {}))])
		await _wait_for_render_frames(6)
		var screenshot_path := "res:/" + "/docs/verification/screenshots/weapon_visual_qa/" + String(weapon_id) + ".png"
		var screenshot_result := _save_viewport_png(screenshot_path)
		if screenshot_result != OK:
			printerr("VERIFICATION_CAPTURE_FAIL p05a %s screenshot: %s" % [String(weapon_id), error_string(screenshot_result)])
			get_tree().quit(1)
			return
		var activation_result: Dictionary = _active_scene.prepare_p05a_weapon_capture(weapon_id, true)
		if not _validate_p05a_capture_result(activation_result, weapon_id, true):
			return
		var feedback_screenshot_path := ""
		if P05A_FEEDBACK_CAPTURE_WEAPONS.has(weapon_id):
			await _wait_for_render_frames(2)
			feedback_screenshot_path = "res:/" + "/docs/verification/screenshots/weapon_visual_qa/" + String(weapon_id) + "_feedback.png"
			var feedback_screenshot_result := _save_viewport_png(feedback_screenshot_path)
			if feedback_screenshot_result != OK:
				printerr("VERIFICATION_CAPTURE_FAIL p05a %s feedback screenshot: %s" % [String(weapon_id), error_string(feedback_screenshot_result)])
				get_tree().quit(1)
				return
		if weapon_id == &"shotgun" and rejected_shotgun_image != null:
			var before_after_result := _save_p05a_before_after(
				rejected_shotgun_image,
				screenshot_path,
				"res://docs/verification/screenshots/weapon_visual_qa/shotgun_before_after.png"
			)
			if before_after_result != OK:
				printerr("VERIFICATION_CAPTURE_FAIL p05a shotgun before/after: %s" % error_string(before_after_result))
				get_tree().quit(1)
				return
		report.append({
			"weapon_id": String(weapon_id),
			"slot": String(capture_result.get("slot", &"")),
			"screenshot": screenshot_path,
			"feedback_screenshot": feedback_screenshot_path,
			"view_model": capture_result.get("view_model", {}),
			"fire_result": activation_result.get("fire_result", {}),
		})
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P05A %s" % str({"ok": true, "weapon_count": report.size(), "weapons": report}))
	print("VERIFICATION_CAPTURE_PASS p05a")
	get_tree().quit(0)

func _validate_p05_view_model(result: Dictionary, expected_fbx_suffix: String) -> bool:
	if not bool(result.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p05 %s" % str(result.get("error", "viewmodel setup failed")))
		get_tree().quit(1)
		return false
	var view_model: Dictionary = result.get("view_model", {})
	if not bool(view_model.get("has_view_model", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p05 missing active viewmodel")
		get_tree().quit(1)
		return false
	if bool(view_model.get("is_fallback", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p05 active viewmodel is fallback: %s" % str(view_model))
		get_tree().quit(1)
		return false
	var summary: Dictionary = view_model.get("summary", {})
	var source_fbx_path := String(summary.get("source_fbx_path", ""))
	if not source_fbx_path.ends_with(expected_fbx_suffix):
		printerr("VERIFICATION_CAPTURE_FAIL p05 expected %s source, got %s" % [expected_fbx_suffix, source_fbx_path])
		get_tree().quit(1)
		return false
	if int(summary.get("vertex_count", 0)) <= 0:
		printerr("VERIFICATION_CAPTURE_FAIL p05 viewmodel has no mesh vertices: %s" % str(summary))
		get_tree().quit(1)
		return false
	return true

func _validate_p05a_capture_result(result: Dictionary, weapon_id: StringName, require_fire: bool) -> bool:
	if not bool(result.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p05a %s %s" % [String(weapon_id), str(result.get("error", "weapon visual QA setup failed"))])
		get_tree().quit(1)
		return false
	var view_model: Dictionary = result.get("view_model", {})
	if not bool(view_model.get("has_view_model", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p05a %s missing active viewmodel" % String(weapon_id))
		get_tree().quit(1)
		return false
	if bool(view_model.get("is_fallback", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p05a %s active viewmodel is generic fallback: %s" % [String(weapon_id), str(view_model)])
		get_tree().quit(1)
		return false
	var summary: Dictionary = view_model.get("summary", {})
	if not bool(summary.get("has_mesh", false)) or int(summary.get("vertex_count", 0)) <= 0:
		printerr("VERIFICATION_CAPTURE_FAIL p05a %s viewmodel has no mesh vertices: %s" % [String(weapon_id), str(summary)])
		get_tree().quit(1)
		return false
	if P05A_ASSET_BACKED_WEAPONS.has(weapon_id):
		var source_fbx_path := String(summary.get("source_fbx_path", ""))
		var generated_glb_path := String(summary.get("generated_glb_path", ""))
		if source_fbx_path == "" or generated_glb_path == "":
			printerr("VERIFICATION_CAPTURE_FAIL p05a %s expected asset-backed GLB viewmodel: %s" % [String(weapon_id), str(summary)])
			get_tree().quit(1)
			return false
		if not bool(summary.get("has_curated_materials", false)):
			printerr("VERIFICATION_CAPTURE_FAIL p05a %s expected source materials or curated material palette: %s" % [String(weapon_id), str(summary)])
			get_tree().quit(1)
			return false
	else:
		if String(summary.get("source_asset_path", "")) == "":
			printerr("VERIFICATION_CAPTURE_FAIL p05a %s expected asset-backed viewmodel summary: %s" % [String(weapon_id), str(summary)])
			get_tree().quit(1)
			return false
	if require_fire:
		var fire_result: Dictionary = result.get("fire_result", {})
		if not bool(fire_result.get("ok", false)):
			printerr("VERIFICATION_CAPTURE_FAIL p05a %s fire/activation failed: %s" % [String(weapon_id), str(fire_result)])
			get_tree().quit(1)
			return false
	return true

func _load_optional_image(path: String) -> Image:
	var absolute_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		return null
	var image := Image.new()
	var error := image.load(absolute_path)
	if error != OK:
		return null
	return image

func _save_p05a_before_after(before_image: Image, after_path: String, output_path: String) -> Error:
	var after_image := Image.new()
	var after_error := after_image.load(ProjectSettings.globalize_path(after_path))
	if after_error != OK:
		return after_error
	before_image.convert(Image.FORMAT_RGBA8)
	after_image.convert(Image.FORMAT_RGBA8)
	before_image.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	after_image.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	var combined := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	combined.fill(Color(0.03, 0.035, 0.04, 1.0))
	combined.blit_rect(before_image, Rect2i(Vector2i.ZERO, before_image.get_size()), Vector2i(0, 180))
	combined.blit_rect(after_image, Rect2i(Vector2i.ZERO, after_image.get_size()), Vector2i(640, 180))
	var absolute_output := ProjectSettings.globalize_path(output_path)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	if dir_error != OK:
		return dir_error
	return combined.save_png(absolute_output)


func _capture_p06_remote_humanoid() -> void:
	await _wait_for_render_frames(6)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p06 game scene did not become ready")
		get_tree().quit(1)
		return
	if _network_session == null or not _network_session.is_active():
		printerr("VERIFICATION_CAPTURE_FAIL p06 expected active network match; launch with --host or --join")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("get_p06_remote_report") or not _active_scene.has_method("prepare_p06_capture_view"):
		printerr("VERIFICATION_CAPTURE_FAIL p06 game scene has no remote humanoid capture hook")
		get_tree().quit(1)
		return
	if _network_session.is_client and _active_scene.has_method("prepare_p06_driver_pose"):
		var driver_pose: Dictionary = _active_scene.prepare_p06_driver_pose()
		if not bool(driver_pose.get("ok", false)):
			printerr("VERIFICATION_CAPTURE_FAIL p06 client driver pose failed: %s" % str(driver_pose.get("error", "unknown error")))
			get_tree().quit(1)
			return
	var capture_setup := {}
	var last_report := {}
	for _index in range(160):
		last_report = _active_scene.get_p06_remote_report()
		if _p06_report_is_ready(last_report):
			await get_tree().create_timer(1.0).timeout
			capture_setup = _active_scene.prepare_p06_capture_view()
			if bool(capture_setup.get("ok", false)):
				break
		await _wait_for_render_frames(1)
		await get_tree().create_timer(0.05).timeout
	if capture_setup.is_empty():
		printerr("VERIFICATION_CAPTURE_FAIL p06 timed out waiting for humanoid remote proxy: %s" % str(last_report))
		get_tree().quit(1)
		return
	var report: Dictionary = capture_setup.get("report", {})
	if not _validate_p06_remote_report(report):
		return
	print("VERIFICATION_CAPTURE_REMOTE_P06 %s" % str(report))
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p06_remote_humanoid.png"
	if _network_session.is_client:
		screenshot_path = "res://docs/verification/screenshots" + "/p06_remote_humanoid_client_blue.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p06 screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.5).timeout
	print("VERIFICATION_CAPTURE_PASS p06")
	get_tree().quit(0)

func _p06_report_is_ready(report: Dictionary) -> bool:
	return (
		int(report.get("remote_proxy_count", 0)) >= 1
		and int(report.get("humanoid_remote_count", 0)) >= 1
		and int(report.get("fallback_remote_count", 0)) == 0
		and int(report.get("synced_remote_count", 0)) >= 1
	)

func _validate_p06_remote_report(report: Dictionary) -> bool:
	if not _p06_report_is_ready(report):
		printerr("VERIFICATION_CAPTURE_FAIL p06 remote report not ready: %s" % str(report))
		get_tree().quit(1)
		return false
	var remotes: Array = report.get("remotes", [])
	var has_allowed_source := false
	for remote in remotes:
		var remote_summary: Dictionary = remote
		var source_path := String(remote_summary.get("source_asset_path", ""))
		if source_path.contains("ultimate_modular_men_pack/Individual Characters/glTF/") and not source_path.ends_with("King.gltf"):
			has_allowed_source = true
		if bool(remote_summary.get("debug_label_visible", true)):
			printerr("VERIFICATION_CAPTURE_FAIL p06 debug label is visible on remote: %s" % str(remote_summary))
			get_tree().quit(1)
			return false
	if not has_allowed_source:
		printerr("VERIFICATION_CAPTURE_FAIL p06 no allowed Modular Men humanoid source in report: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("team_readability_method", "")) == "":
		printerr("VERIFICATION_CAPTURE_FAIL p06 missing team-readability method")
		get_tree().quit(1)
		return false
	return true

func _capture_p07_offline_playability() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p07 expected lobby before offline start")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	(_active_scene as LobbyMenu).smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p07 game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p07_playtest_checks") or not _active_scene.has_method("prepare_p07_combat_hud_capture"):
		printerr("VERIFICATION_CAPTURE_FAIL p07 game scene has no playtest hooks")
		get_tree().quit(1)
		return
	var checks: Dictionary = await _active_scene.run_p07_playtest_checks()
	if not bool(checks.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p07 checks failed: %s" % str(checks))
		get_tree().quit(1)
		return
	var capture_setup: Dictionary = await _active_scene.prepare_p07_combat_hud_capture()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p07 combat HUD capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p07_combat_hud.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p07 screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	var next_progress_sec := 60.0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p07_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P07 elapsed_sec=%.1f target_sec=%.1f" % [elapsed_sec, _p07_duration_sec])
			next_progress_sec += 60.0
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := checks.duplicate(true)
	report["duration_sec"] = duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["screenshot"] = screenshot_path
	if not _validate_p07_report(report):
		return
	print("VERIFICATION_PLAYTEST_REPORT_P07 %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p07")
	get_tree().quit(0)

func _capture_p10a_offline_visual_polish(prefix: String, require_full_duration: bool) -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p10a expected lobby before offline start")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	await _wait_for_render_frames(4)
	var screenshots := []
	var lobby_screenshot_path := _p10a_screenshot_path(prefix, "lobby")
	var lobby_screenshot := _save_viewport_png(lobby_screenshot_path)
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p10a lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	screenshots.append(lobby_screenshot_path)
	(_active_scene as LobbyMenu).smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p10a game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("prepare_p10a_capture_view"):
		printerr("VERIFICATION_CAPTURE_FAIL p10a game scene has no visual-polish capture hook")
		get_tree().quit(1)
		return
	var playtest_report := {"ok": true, "skipped": not require_full_duration}
	if require_full_duration:
		if not _active_scene.has_method("run_p10a_visual_playtest_checks"):
			printerr("VERIFICATION_CAPTURE_FAIL p10a game scene has no visual-polish playtest hook")
			get_tree().quit(1)
			return
		playtest_report = await _active_scene.run_p10a_visual_playtest_checks()
		if not bool(playtest_report.get("ok", false)):
			printerr("VERIFICATION_CAPTURE_FAIL p10a playtest checks failed: %s" % str(playtest_report))
			get_tree().quit(1)
			return
	var capture_reports := []
	for view in P10A_OFFLINE_SCREENSHOTS:
		var view_name := String(view["view"])
		var capture_setup: Dictionary = await _active_scene.prepare_p10a_capture_view(view_name)
		if not bool(capture_setup.get("ok", false)):
			printerr("VERIFICATION_CAPTURE_FAIL p10a %s capture setup failed: %s" % [view_name, str(capture_setup)])
			get_tree().quit(1)
			return
		await _wait_for_render_frames(8)
		var screenshot_path := _p10a_screenshot_path(prefix, String(view["file"]))
		var screenshot_result := _save_viewport_png(screenshot_path)
		if screenshot_result != OK:
			printerr("VERIFICATION_CAPTURE_FAIL p10a %s screenshot: %s" % [view_name, error_string(screenshot_result)])
			get_tree().quit(1)
			return
		screenshots.append(screenshot_path)
		capture_reports.append({
			"view": view_name,
			"screenshot": screenshot_path,
			"capture_setup": capture_setup,
		})
	var next_progress_sec := 60.0
	while require_full_duration and (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p10a_offline_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P10A_OFFLINE elapsed_sec=%.1f target_sec=%.1f" % [
				elapsed_sec,
				_p10a_offline_duration_sec,
			])
			next_progress_sec += 60.0
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := {
		"ok": true,
		"prefix": prefix,
		"duration_sec": duration_sec,
		"duration_target_sec": _p10a_offline_duration_sec if require_full_duration else 0.0,
		"started_at": started_text,
		"ended_at": ended_text,
		"screenshot_count": screenshots.size(),
		"screenshots": screenshots,
		"capture_reports": capture_reports,
		"playtest_report": playtest_report,
	}
	if not _validate_p10a_offline_report(report, require_full_duration):
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_PLAYTEST_REPORT_P10A_OFFLINE %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p10a-%s" % prefix)
	get_tree().quit(0)

func _capture_p10a_host_visual_polish() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p10a-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	print("VERIFICATION_CAPTURE_FLOW_P10A host_press_host_private_match port=%d expected_players=2" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(2)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p10a-host timed out waiting for ready client: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P10A host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p10a-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p08_multiplayer_checks") or not _active_scene.has_method("prepare_p08_multiplayer_capture_view"):
		printerr("VERIFICATION_CAPTURE_FAIL p10a-host game scene has no multiplayer visual hooks")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p08_multiplayer_checks()
		if bool(report.get("ok", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p10a_multiplayer_report(report, "host-initial"):
		return
	var next_progress_sec := 60.0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p10a_multiplayer_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P10A_HOST elapsed_sec=%.1f target_sec=%.1f" % [
				elapsed_sec,
				_p10a_multiplayer_duration_sec,
			])
			next_progress_sec += 60.0
	var capture_setup: Dictionary = {}
	if _active_scene.has_method("prepare_p10a_remote_player_capture_view"):
		capture_setup = _active_scene.prepare_p10a_remote_player_capture_view()
	else:
		capture_setup = _active_scene.prepare_p08_multiplayer_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p10a-host remote capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	await _wait_for_render_frames(12)
	var remote_screenshot_path := _p10a_screenshot_path("after", "remote_player")
	var remote_screenshot := _save_viewport_png(remote_screenshot_path)
	if remote_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p10a-host remote screenshot: %s" % error_string(remote_screenshot))
		get_tree().quit(1)
		return
	var ended_text := Time.get_datetime_string_from_system(true)
	report["duration_sec"] = float(Time.get_ticks_msec() - started_msec) / 1000.0
	report["duration_target_sec"] = _p10a_multiplayer_duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["remote_screenshot"] = remote_screenshot_path
	report["remote_capture_setup"] = capture_setup
	if not _validate_p10a_multiplayer_report(report, "host-final"):
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p10a-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_PLAYTEST_REPORT_P10A_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p10a-host")
	get_tree().quit(0)

func _capture_p10a_client_visual_polish() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p10a-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	print("VERIFICATION_CAPTURE_FLOW_P10A client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p10a-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P10A client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p10a-client game scene did not become ready")
		get_tree().quit(1)
		return
	if _active_scene.has_method("prepare_p06_driver_pose"):
		var driver_pose: Dictionary = _active_scene.prepare_p06_driver_pose()
		if not bool(driver_pose.get("ok", false)):
			printerr("VERIFICATION_CAPTURE_FAIL p10a-client driver pose failed: %s" % str(driver_pose))
			get_tree().quit(1)
			return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	var hold_sec := _p10a_multiplayer_duration_sec + 10.0
	var next_progress_sec := 60.0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < hold_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P10A_CLIENT elapsed_sec=%.1f target_sec=%.1f" % [
				elapsed_sec,
				hold_sec,
			])
			next_progress_sec += 60.0
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p10a-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	if duration_sec < P10A_MULTIPLAYER_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p10a-client duration below %.0f sec: %.2f" % [
			P10A_MULTIPLAYER_PLAYTEST_DURATION_SEC,
			duration_sec,
		])
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_PLAYTEST_REPORT_P10A_CLIENT %s" % str({
		"ok": true,
		"duration_sec": duration_sec,
		"duration_target_sec": _p10a_multiplayer_duration_sec,
		"started_at": started_text,
		"ended_at": Time.get_datetime_string_from_system(true),
		"disconnect_cleanup": cleanup_report,
	}))
	print("VERIFICATION_CAPTURE_PASS p10a-client")
	get_tree().quit(0)

func _p10a_screenshot_path(prefix: String, file_stem: String) -> String:
	return "res:/" + "/docs/verification/screenshots/p10a_visual_polish/%s_%s.png" % [prefix, file_stem]

func _validate_p10a_offline_report(report: Dictionary, require_full_duration: bool) -> bool:
	if int(report.get("screenshot_count", 0)) < 11:
		printerr("VERIFICATION_CAPTURE_FAIL p10a expected at least 11 offline screenshots, got %d" % int(report.get("screenshot_count", 0)))
		get_tree().quit(1)
		return false
	if require_full_duration and float(report.get("duration_sec", 0.0)) < P10A_OFFLINE_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p10a offline duration below %.0f sec: %.2f" % [
			P10A_OFFLINE_PLAYTEST_DURATION_SEC,
			float(report.get("duration_sec", 0.0)),
		])
		get_tree().quit(1)
		return false
	var playtest: Dictionary = report.get("playtest_report", {})
	if require_full_duration and not bool(playtest.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p10a offline playtest failed: %s" % str(playtest))
		get_tree().quit(1)
		return false
	return true

func _validate_p10a_multiplayer_report(report: Dictionary, context: String) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p10a-%s multiplayer report failed: %s" % [context, str(report)])
		get_tree().quit(1)
		return false
	if not bool(report.get("host_can_see_remote_humanoid", false)) or not bool(report.get("remote_movement_sync", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p10a-%s remote visual criteria failed: %s" % [context, str(report)])
		get_tree().quit(1)
		return false
	if context == "host-final" and float(report.get("duration_sec", 0.0)) < P10A_MULTIPLAYER_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p10a-host duration below %.0f sec: %.2f" % [
			P10A_MULTIPLAYER_PLAYTEST_DURATION_SEC,
			float(report.get("duration_sec", 0.0)),
		])
		get_tree().quit(1)
		return false
	return true

func _capture_p11_core_combat_tuning() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p11 expected lobby before offline start")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	(_active_scene as LobbyMenu).smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p11 game scene did not become ready")
		get_tree().quit(1)
		return
	if (
		not _active_scene.has_method("run_p07_playtest_checks")
		or not _active_scene.has_method("prepare_p07_combat_hud_capture")
		or not _active_scene.has_method("get_p11_weapon_tuning_report")
	):
		printerr("VERIFICATION_CAPTURE_FAIL p11 game scene has no combat tuning hooks")
		get_tree().quit(1)
		return
	var checks: Dictionary = await _active_scene.run_p07_playtest_checks()
	if not bool(checks.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p11 checks failed: %s" % str(checks))
		get_tree().quit(1)
		return
	var tuning_report: Dictionary = _active_scene.get_p11_weapon_tuning_report()
	if not bool(tuning_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p11 tuning report failed: %s" % str(tuning_report))
		get_tree().quit(1)
		return
	var capture_setup: Dictionary = await _active_scene.prepare_p07_combat_hud_capture()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p11 combat HUD capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p11_core_combat_tuning.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p11 screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	var next_progress_sec := 120.0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p11_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P11 elapsed_sec=%.1f target_sec=%.1f" % [elapsed_sec, _p11_duration_sec])
			next_progress_sec += 120.0
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := checks.duplicate(true)
	report["duration_sec"] = duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["screenshot"] = screenshot_path
	report["weapon_tuning"] = tuning_report.get("core_weapons", {})
	if not _validate_p11_report(report):
		return
	print("VERIFICATION_PLAYTEST_REPORT_P11 %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p11")
	get_tree().quit(0)

func _validate_p11_report(report: Dictionary) -> bool:
	if float(report.get("duration_sec", 0.0)) < P11_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p11 duration below %.0f sec: %.2f" % [P11_PLAYTEST_DURATION_SEC, float(report.get("duration_sec", 0.0))])
		get_tree().quit(1)
		return false
	if not _validate_p07_report(report):
		return false
	var tuning: Dictionary = report.get("weapon_tuning", {})
	for weapon_id in ["assault_rifle", "handgun", "knife", "smoke_bomb"]:
		if not tuning.has(weapon_id):
			printerr("VERIFICATION_CAPTURE_FAIL p11 tuning report missing %s: %s" % [weapon_id, str(tuning)])
			get_tree().quit(1)
			return false
	return true

func _validate_p07_report(report: Dictionary) -> bool:
	if float(report.get("duration_sec", 0.0)) < 600.0:
		printerr("VERIFICATION_CAPTURE_FAIL p07 duration below 600 sec: %.2f" % float(report.get("duration_sec", 0.0)))
		get_tree().quit(1)
		return false
	if int(report.get("traversal_routes_completed", 0)) < 2:
		printerr("VERIFICATION_CAPTURE_FAIL p07 fewer than 2 traversal routes completed: %s" % str(report.get("routes", [])))
		get_tree().quit(1)
		return false
	var movement: Dictionary = report.get("movement", {})
	for required_movement in ["jump", "slide", "slide_jump", "wallrun", "wall_jump"]:
		if not bool(movement.get(required_movement, false)):
			printerr("VERIFICATION_CAPTURE_FAIL p07 movement missing %s: %s" % [required_movement, str(movement)])
			get_tree().quit(1)
			return false
	var weapons: Dictionary = report.get("weapons", {})
	for required_weapon in ["assault_rifle", "handgun", "knife", "smoke_bomb"]:
		if not bool(weapons.get(required_weapon, false)):
			printerr("VERIFICATION_CAPTURE_FAIL p07 weapon missing %s: %s" % [required_weapon, str(weapons)])
			get_tree().quit(1)
			return false
	if not bool(report.get("reload_interrupt", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p07 reload interrupt missing")
		get_tree().quit(1)
		return false
	if int(report.get("dummy_hits", 0)) < 3 or int(report.get("dummy_kills", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p07 dummy hit/kill criteria failed: hits=%d kills=%d" % [int(report.get("dummy_hits", 0)), int(report.get("dummy_kills", 0))])
		get_tree().quit(1)
		return false
	if not bool(report.get("death_respawn", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p07 death/respawn missing")
		get_tree().quit(1)
		return false
	var hud: Dictionary = report.get("hud", {})
	for required_field in ["health", "ammo", "charges", "active_slot", "cooldown", "timer", "score", "fps", "node_count"]:
		if not bool(hud.get(required_field, false)):
			printerr("VERIFICATION_CAPTURE_FAIL p07 HUD missing %s: %s" % [required_field, str(hud)])
			get_tree().quit(1)
			return false
	return true

func _capture_p08_host() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p08-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	print("VERIFICATION_CAPTURE_FLOW_P08 host_press_host_private_match port=%d" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_p08_for_host_lobby_ready()
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p08-host timed out waiting for hosted lobby with ready client: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	await _wait_for_render_frames(8)
	var lobby_screenshot := _save_viewport_png("res://docs/verification/screenshots" + "/p08_lobby_host_join.png")
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p08-host lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P08 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p08-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p08_multiplayer_checks") or not _active_scene.has_method("prepare_p08_multiplayer_capture_view"):
		printerr("VERIFICATION_CAPTURE_FAIL p08-host game scene has no P08 hooks")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p08_multiplayer_checks()
		if bool(report.get("ok", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p08_host_report(report):
		return
	var capture_setup: Dictionary = _active_scene.prepare_p08_multiplayer_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p08-host capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	await _wait_for_render_frames(12)
	var gameplay_screenshot := _save_viewport_png("res://docs/verification/screenshots" + "/p08_multiplayer_remote_player.png")
	if gameplay_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p08-host gameplay screenshot: %s" % error_string(gameplay_screenshot))
		get_tree().quit(1)
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p08-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P08_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p08-host")
	get_tree().quit(0)

func _capture_p08_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p08-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	print("VERIFICATION_CAPTURE_FLOW_P08 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p08-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P08 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p08-client game scene did not become ready")
		get_tree().quit(1)
		return
	if _active_scene.has_method("prepare_p06_driver_pose"):
		var driver_pose: Dictionary = _active_scene.prepare_p06_driver_pose()
		if not bool(driver_pose.get("ok", false)):
			printerr("VERIFICATION_CAPTURE_FAIL p08-client driver pose failed: %s" % str(driver_pose))
			get_tree().quit(1)
			return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		if _active_scene.has_method("get_p08_client_report"):
			report = _active_scene.get_p08_client_report()
		elif _active_scene.has_method("get_p06_remote_report"):
			report = _active_scene.get_p06_remote_report()
		if bool(report.get("ok", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p08-client remote report not ready: %s" % str(report))
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p08-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P08_CLIENT %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p08-client")
	get_tree().quit(0)

func _capture_p12_host() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p12-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	print("VERIFICATION_CAPTURE_FLOW_P12 host_press_host_private_match port=%d expected_players=4" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(4)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p12-host timed out waiting for 2v2 ready lobby: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	await _wait_for_render_frames(8)
	var lobby_screenshot := _save_viewport_png("res://docs/verification/screenshots" + "/p12_lobby_2v2.png")
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p12-host lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P12 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p12-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p12_2v2_checks") or not _active_scene.has_method("prepare_p12_2v2_capture_view"):
		printerr("VERIFICATION_CAPTURE_FAIL p12-host game scene has no P12 hooks")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p12_2v2_checks()
		if bool(report.get("ok", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p12_host_report(report):
		return
	var capture_setup: Dictionary = _active_scene.prepare_p12_2v2_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p12-host capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	report["capture_setup"] = capture_setup
	await _wait_for_render_frames(12)
	var gameplay_screenshot := _save_viewport_png("res://docs/verification/screenshots" + "/p12_2v2_remote_players.png")
	if gameplay_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p12-host gameplay screenshot: %s" % error_string(gameplay_screenshot))
		get_tree().quit(1)
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p12-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P12_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p12-host")
	get_tree().quit(0)

func _capture_p12_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p12-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	print("VERIFICATION_CAPTURE_FLOW_P12 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p12-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P12 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p12-client game scene did not become ready")
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p12-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P12_CLIENT %s" % str({"ok": true, "disconnect_cleanup": cleanup_report}))
	print("VERIFICATION_CAPTURE_PASS p12-client")
	get_tree().quit(0)

func _capture_p13_host() -> void:
	const P13_REQUIRED_PLAYERS := 6
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p13-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	print("VERIFICATION_CAPTURE_FLOW_P13 host_press_host_private_match port=%d expected_players=%d" % [_p08_port, P13_REQUIRED_PLAYERS])
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(P13_REQUIRED_PLAYERS)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p13-host timed out waiting for 3v3 ready lobby: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	await _wait_for_render_frames(8)
	var lobby_screenshot := _save_viewport_png("res://docs/verification/screenshots" + "/p13_lobby_3v3.png")
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p13-host lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P13 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p13-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p13_3v3_checks") or not _active_scene.has_method("prepare_p13_3v3_capture_view"):
		printerr("VERIFICATION_CAPTURE_FAIL p13-host game scene has no P13 hooks")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p13_3v3_checks()
		if bool(report.get("ok", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p13_host_report(report):
		return
	var capture_setup: Dictionary = _active_scene.prepare_p13_3v3_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p13-host capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	report["capture_setup"] = capture_setup
	await _wait_for_render_frames(12)
	var gameplay_screenshot := _save_viewport_png("res://docs/verification/screenshots" + "/p13_3v3_perf.png")
	if gameplay_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p13-host gameplay screenshot: %s" % error_string(gameplay_screenshot))
		get_tree().quit(1)
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p13-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P13_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p13-host")
	get_tree().quit(0)

func _capture_p13_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p13-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	print("VERIFICATION_CAPTURE_FLOW_P13 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p13-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P13 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p13-client game scene did not become ready")
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p13-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P13_CLIENT %s" % str({"ok": true, "disconnect_cleanup": cleanup_report}))
	print("VERIFICATION_CAPTURE_PASS p13-client")
	get_tree().quit(0)

func _capture_p14_shotgun_pass() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	var lobby_options := _validate_lobby_weapon_options(lobby)
	if not bool(lobby_options.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun %s" % str(lobby_options.get("error", "lobby weapon options failed")))
		get_tree().quit(1)
		return
	if not lobby.smoke_select_loadout(&"shotgun", &"handgun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun could not select shotgun lobby loadout")
		get_tree().quit(1)
		return
	await _wait_for_render_frames(4)
	var lobby_screenshot_path := "res://docs/verification/screenshots" + "/p14_shotgun_lobby.png"
	var lobby_screenshot := _save_viewport_png(lobby_screenshot_path)
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	lobby.smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun game scene did not become ready")
		get_tree().quit(1)
		return
	if (
		not _active_scene.has_method("run_p14_shotgun_checks")
		or not _active_scene.has_method("run_p14_shotgun_pulse")
		or not _active_scene.has_method("prepare_p14_shotgun_capture_view")
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun game scene has no P14 shotgun hooks")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	var checks: Dictionary = await _active_scene.run_p14_shotgun_checks()
	if not bool(checks.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun checks failed: %s" % str(checks))
		get_tree().quit(1)
		return
	var next_pulse_sec := 10.0
	var next_progress_sec := 60.0
	var pulse_count := 0
	var pulse_hits := 0
	var pulse_kills := 0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p14_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_pulse_sec:
			var pulse: Dictionary = await _active_scene.run_p14_shotgun_pulse()
			pulse_count += 1
			if bool(pulse.get("hit", false)):
				pulse_hits += 1
			if bool(pulse.get("killed", false)):
				pulse_kills += 1
			if not bool(pulse.get("used", false)) or not bool(pulse.get("hit", false)):
				printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun pulse failed: %s" % str(pulse))
				get_tree().quit(1)
				return
			next_pulse_sec += 10.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P14 elapsed_sec=%.1f target_sec=%.1f pulses=%d hits=%d kills=%d" % [
				elapsed_sec,
				_p14_duration_sec,
				pulse_count,
				pulse_hits,
				pulse_kills,
			])
			next_progress_sec += 60.0
	print("VERIFICATION_CAPTURE_FLOW_P14 shotgun_capture_setup")
	var capture_setup: Dictionary = await _active_scene.prepare_p14_shotgun_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 shotgun_capture_setup_ready")
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p14_shotgun_playtest.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 shotgun_screenshot_saved")
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := checks.duplicate(true)
	report["duration_sec"] = duration_sec
	report["duration_target_sec"] = _p14_duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["lobby_selectable"] = true
	report["lobby_loadout"] = {
		"primary": "shotgun",
		"secondary": "handgun",
		"melee": "knife",
		"artillery": "smoke_bomb",
	}
	report["lobby_screenshot"] = lobby_screenshot_path
	report["screenshot"] = screenshot_path
	report["pulse_count"] = pulse_count
	report["pulse_hits"] = pulse_hits
	report["pulse_kills"] = pulse_kills
	report["capture_setup"] = capture_setup
	if not _validate_p14_shotgun_report(report):
		return
	print("VERIFICATION_PLAYTEST_REPORT_P14_SHOTGUN %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-shotgun")
	get_tree().quit(0)

func _capture_p14_shotgun_host() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"shotgun", &"handgun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host could not select shotgun lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=%d expected_players=2" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(2)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host timed out waiting for ready client: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p14_shotgun_network_check"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host game scene has no P14 network hook")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p14_shotgun_network_check()
		if bool(report.get("ok", false)):
			break
		if not bool(report.get("pending", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p14_shotgun_network_report(report):
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_SHOTGUN_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-shotgun-host")
	get_tree().quit(0)

func _capture_p14_shotgun_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"shotgun", &"handgun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-client could not select shotgun lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-client game scene did not become ready")
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_SHOTGUN_CLIENT %s" % str({
		"ok": true,
		"weapon_id": "shotgun",
		"disconnect_cleanup": cleanup_report,
	}))
	print("VERIFICATION_CAPTURE_PASS p14-shotgun-client")
	get_tree().quit(0)

func _validate_p14_shotgun_report(report: Dictionary) -> bool:
	if float(report.get("duration_sec", 0.0)) < P14_WEAPON_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun duration below %.0f sec: %.2f" % [
			P14_WEAPON_PLAYTEST_DURATION_SEC,
			float(report.get("duration_sec", 0.0)),
		])
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "shotgun" or not bool(report.get("lobby_selectable", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun lobby/weapon selection failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("view_model_ok", false)) or not bool(report.get("tuning_ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun viewmodel/tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var offline_use: Dictionary = report.get("offline_use", {})
	if not bool(offline_use.get("used", false)) or not bool(offline_use.get("hit", false)) or not bool(offline_use.get("killed", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun offline use failed: %s" % str(offline_use))
		get_tree().quit(1)
		return false
	if not bool(report.get("reload_interrupt", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun reload interrupt missing")
		get_tree().quit(1)
		return false
	var hud: Dictionary = report.get("hud", {})
	if not bool(hud.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun HUD check failed: %s" % str(hud))
		get_tree().quit(1)
		return false
	if int(report.get("pulse_count", 0)) < 1 or int(report.get("pulse_hits", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun pulse criteria failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var capture_setup: Dictionary = report.get("capture_setup", {})
	if not bool(capture_setup.get("ok", false)) or String(report.get("screenshot", "")) == "" or String(report.get("lobby_screenshot", "")) == "":
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun screenshot/capture setup missing: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _validate_p14_shotgun_network_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "shotgun":
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host wrong weapon report: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("shots_fired", 0)) <= 0 or int(report.get("pellets_per_shot", 0)) != 10:
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host shotgun shot data failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("score_after", 0)) <= int(report.get("score_before", 0)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host score did not increment: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("victim_respawned", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-shotgun-host victim did not respawn: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _capture_p14_sniper_pass() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	var lobby_options := _validate_lobby_weapon_options(lobby)
	if not bool(lobby_options.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper %s" % str(lobby_options.get("error", "lobby weapon options failed")))
		get_tree().quit(1)
		return
	if not lobby.smoke_select_loadout(&"sniper", &"handgun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper could not select sniper lobby loadout")
		get_tree().quit(1)
		return
	await _wait_for_render_frames(4)
	var lobby_screenshot_path := "res://docs/verification/screenshots" + "/p14_sniper_lobby.png"
	var lobby_screenshot := _save_viewport_png(lobby_screenshot_path)
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	lobby.smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper game scene did not become ready")
		get_tree().quit(1)
		return
	if (
		not _active_scene.has_method("run_p14_sniper_checks")
		or not _active_scene.has_method("run_p14_sniper_pulse")
		or not _active_scene.has_method("prepare_p14_sniper_capture_view")
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper game scene has no P14 sniper hooks")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	var checks: Dictionary = await _active_scene.run_p14_sniper_checks()
	if not bool(checks.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper checks failed: %s" % str(checks))
		get_tree().quit(1)
		return
	var next_pulse_sec := 10.0
	var next_progress_sec := 60.0
	var pulse_count := 0
	var pulse_hits := 0
	var pulse_kills := 0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p14_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_pulse_sec:
			var pulse: Dictionary = await _active_scene.run_p14_sniper_pulse()
			pulse_count += 1
			if bool(pulse.get("hit", false)):
				pulse_hits += 1
			if bool(pulse.get("killed", false)):
				pulse_kills += 1
			if not bool(pulse.get("used", false)) or not bool(pulse.get("hit", false)):
				printerr("VERIFICATION_CAPTURE_FAIL p14-sniper pulse failed: %s" % str(pulse))
				get_tree().quit(1)
				return
			next_pulse_sec += 10.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P14_SNIPER elapsed_sec=%.1f target_sec=%.1f pulses=%d hits=%d kills=%d" % [
				elapsed_sec,
				_p14_duration_sec,
				pulse_count,
				pulse_hits,
				pulse_kills,
			])
			next_progress_sec += 60.0
	print("VERIFICATION_CAPTURE_FLOW_P14 sniper_capture_setup")
	var capture_setup: Dictionary = await _active_scene.prepare_p14_sniper_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 sniper_capture_setup_ready")
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p14_sniper_playtest.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 sniper_screenshot_saved")
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := checks.duplicate(true)
	report["duration_sec"] = duration_sec
	report["duration_target_sec"] = _p14_duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["lobby_selectable"] = true
	report["lobby_loadout"] = {
		"primary": "sniper",
		"secondary": "handgun",
		"melee": "knife",
		"artillery": "smoke_bomb",
	}
	report["lobby_screenshot"] = lobby_screenshot_path
	report["screenshot"] = screenshot_path
	report["pulse_count"] = pulse_count
	report["pulse_hits"] = pulse_hits
	report["pulse_kills"] = pulse_kills
	report["capture_setup"] = capture_setup
	if not _validate_p14_sniper_report(report):
		return
	print("VERIFICATION_PLAYTEST_REPORT_P14_SNIPER %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-sniper")
	get_tree().quit(0)

func _capture_p14_sniper_host() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"sniper", &"handgun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host could not select sniper lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=%d expected_players=2" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(2)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host timed out waiting for ready client: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p14_sniper_network_check"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host game scene has no P14 sniper network hook")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p14_sniper_network_check()
		if bool(report.get("ok", false)):
			break
		if not bool(report.get("pending", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p14_sniper_network_report(report):
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_SNIPER_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-sniper-host")
	get_tree().quit(0)

func _capture_p14_sniper_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"sniper", &"handgun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-client could not select sniper lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-client game scene did not become ready")
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_SNIPER_CLIENT %s" % str({
		"ok": true,
		"weapon_id": "sniper",
		"disconnect_cleanup": cleanup_report,
	}))
	print("VERIFICATION_CAPTURE_PASS p14-sniper-client")
	get_tree().quit(0)

func _validate_p14_sniper_report(report: Dictionary) -> bool:
	if float(report.get("duration_sec", 0.0)) < P14_WEAPON_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper duration below %.0f sec: %.2f" % [
			P14_WEAPON_PLAYTEST_DURATION_SEC,
			float(report.get("duration_sec", 0.0)),
		])
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "sniper" or not bool(report.get("lobby_selectable", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper lobby/weapon selection failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("view_model_ok", false)) or not bool(report.get("tuning_ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper viewmodel/tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var offline_use: Dictionary = report.get("offline_use", {})
	if not bool(offline_use.get("used", false)) or not bool(offline_use.get("hit", false)) or not bool(offline_use.get("killed", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper offline use failed: %s" % str(offline_use))
		get_tree().quit(1)
		return false
	if not bool(report.get("reload_interrupt", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper reload interrupt missing")
		get_tree().quit(1)
		return false
	var hud: Dictionary = report.get("hud", {})
	if not bool(hud.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper HUD check failed: %s" % str(hud))
		get_tree().quit(1)
		return false
	if int(report.get("pulse_count", 0)) < 1 or int(report.get("pulse_hits", 0)) < 1 or int(report.get("pulse_kills", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper pulse criteria failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var capture_setup: Dictionary = report.get("capture_setup", {})
	if not bool(capture_setup.get("ok", false)) or String(report.get("screenshot", "")) == "" or String(report.get("lobby_screenshot", "")) == "":
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper screenshot/capture setup missing: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _validate_p14_sniper_network_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "sniper":
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host wrong weapon report: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("shots_fired", 0)) != 2 or int(report.get("pellets_per_shot", 0)) != 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host sniper shot data failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("body_damage", 0.0)), 50.0) or not is_equal_approx(float(report.get("head_damage", 0.0)), 100.0):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host damage tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("score_after", 0)) <= int(report.get("score_before", 0)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host score did not increment: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("victim_respawned", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-sniper-host victim did not respawn: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _capture_p14_grenade_pass() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	var lobby_options := _validate_lobby_weapon_options(lobby)
	if not bool(lobby_options.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade %s" % str(lobby_options.get("error", "lobby weapon options failed")))
		get_tree().quit(1)
		return
	if not lobby.smoke_select_loadout(&"assault_rifle", &"handgun", &"knife", &"grenade"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade could not select grenade lobby loadout")
		get_tree().quit(1)
		return
	await _wait_for_render_frames(4)
	var lobby_screenshot_path := "res://docs/verification/screenshots" + "/p14_grenade_lobby.png"
	var lobby_screenshot := _save_viewport_png(lobby_screenshot_path)
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	lobby.smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade game scene did not become ready")
		get_tree().quit(1)
		return
	if (
		not _active_scene.has_method("run_p14_grenade_checks")
		or not _active_scene.has_method("run_p14_grenade_pulse")
		or not _active_scene.has_method("prepare_p14_grenade_capture_view")
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade game scene has no P14 grenade hooks")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	var checks: Dictionary = await _active_scene.run_p14_grenade_checks()
	if not bool(checks.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade checks failed: %s" % str(checks))
		get_tree().quit(1)
		return
	var next_pulse_sec := 10.0
	var next_progress_sec := 60.0
	var pulse_count := 0
	var pulse_hits := 0
	var pulse_kills := 0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p14_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_pulse_sec:
			var pulse: Dictionary = await _active_scene.run_p14_grenade_pulse()
			pulse_count += 1
			if bool(pulse.get("hit", false)):
				pulse_hits += 1
			if bool(pulse.get("killed", false)):
				pulse_kills += 1
			if not bool(pulse.get("used", false)) or not bool(pulse.get("hit", false)):
				printerr("VERIFICATION_CAPTURE_FAIL p14-grenade pulse failed: %s" % str(pulse))
				get_tree().quit(1)
				return
			next_pulse_sec += 10.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P14_GRENADE elapsed_sec=%.1f target_sec=%.1f pulses=%d hits=%d kills=%d" % [
				elapsed_sec,
				_p14_duration_sec,
				pulse_count,
				pulse_hits,
				pulse_kills,
			])
			next_progress_sec += 60.0
	print("VERIFICATION_CAPTURE_FLOW_P14 grenade_capture_setup")
	var capture_setup: Dictionary = await _active_scene.prepare_p14_grenade_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 grenade_capture_setup_ready")
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p14_grenade_playtest.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 grenade_screenshot_saved")
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := checks.duplicate(true)
	report["duration_sec"] = duration_sec
	report["duration_target_sec"] = _p14_duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["lobby_selectable"] = true
	report["lobby_loadout"] = {
		"primary": "assault_rifle",
		"secondary": "handgun",
		"melee": "knife",
		"artillery": "grenade",
	}
	report["lobby_screenshot"] = lobby_screenshot_path
	report["screenshot"] = screenshot_path
	report["pulse_count"] = pulse_count
	report["pulse_hits"] = pulse_hits
	report["pulse_kills"] = pulse_kills
	report["capture_setup"] = capture_setup
	if not _validate_p14_grenade_report(report):
		return
	print("VERIFICATION_PLAYTEST_REPORT_P14_GRENADE %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-grenade")
	get_tree().quit(0)

func _capture_p14_grenade_host() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"assault_rifle", &"handgun", &"knife", &"grenade"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host could not select grenade lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=%d expected_players=2" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(2)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host timed out waiting for ready client: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p14_grenade_network_check"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host game scene has no P14 grenade network hook")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p14_grenade_network_check()
		if bool(report.get("ok", false)):
			break
		if not bool(report.get("pending", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p14_grenade_network_report(report):
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_GRENADE_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-grenade-host")
	get_tree().quit(0)

func _capture_p14_grenade_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"assault_rifle", &"handgun", &"knife", &"grenade"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-client could not select grenade lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-client game scene did not become ready")
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_GRENADE_CLIENT %s" % str({
		"ok": true,
		"weapon_id": "grenade",
		"disconnect_cleanup": cleanup_report,
	}))
	print("VERIFICATION_CAPTURE_PASS p14-grenade-client")
	get_tree().quit(0)

func _validate_p14_grenade_report(report: Dictionary) -> bool:
	if float(report.get("duration_sec", 0.0)) < P14_WEAPON_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade duration below %.0f sec: %.2f" % [
			P14_WEAPON_PLAYTEST_DURATION_SEC,
			float(report.get("duration_sec", 0.0)),
		])
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "grenade" or not bool(report.get("lobby_selectable", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade lobby/weapon selection failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("view_model_ok", false)) or not bool(report.get("tuning_ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade viewmodel/tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var offline_use: Dictionary = report.get("offline_use", {})
	if not bool(offline_use.get("used", false)) or not bool(offline_use.get("hit", false)) or not bool(offline_use.get("killed", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade offline use failed: %s" % str(offline_use))
		get_tree().quit(1)
		return false
	var hud: Dictionary = report.get("hud", {})
	if not bool(hud.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade HUD check failed: %s" % str(hud))
		get_tree().quit(1)
		return false
	if int(report.get("pulse_count", 0)) < 1 or int(report.get("pulse_hits", 0)) < 1 or int(report.get("pulse_kills", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade pulse criteria failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var capture_setup: Dictionary = report.get("capture_setup", {})
	if not bool(capture_setup.get("ok", false)) or int(capture_setup.get("explosion_markers_after", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade screenshot/capture setup missing explosion: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("screenshot", "")) == "" or String(report.get("lobby_screenshot", "")) == "":
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade screenshot paths missing: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _validate_p14_grenade_network_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "grenade":
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host wrong weapon report: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("throws_fired", 0)) != 2 or int(report.get("charges_max", 0)) != 3:
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host grenade throw data failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("body_damage", 0.0)), 75.0) or not is_equal_approx(float(report.get("effect_radius_m", 0.0)), 4.5):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host damage/radius tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("score_after", 0)) <= int(report.get("score_before", 0)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host score did not increment: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("victim_respawned", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-grenade-host victim did not respawn: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _capture_p14_flamethrower_pass() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	var lobby_options := _validate_lobby_weapon_options(lobby)
	if not bool(lobby_options.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower %s" % str(lobby_options.get("error", "lobby weapon options failed")))
		get_tree().quit(1)
		return
	if not lobby.smoke_select_loadout(&"flamethrower", &"handgun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower could not select flamethrower lobby loadout")
		get_tree().quit(1)
		return
	await _wait_for_render_frames(4)
	var lobby_screenshot_path := "res://docs/verification/screenshots" + "/p14_flamethrower_lobby.png"
	var lobby_screenshot := _save_viewport_png(lobby_screenshot_path)
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	lobby.smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower game scene did not become ready")
		get_tree().quit(1)
		return
	if (
		not _active_scene.has_method("run_p14_flamethrower_checks")
		or not _active_scene.has_method("run_p14_flamethrower_pulse")
		or not _active_scene.has_method("prepare_p14_flamethrower_capture_view")
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower game scene has no P14 flamethrower hooks")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	var checks: Dictionary = await _active_scene.run_p14_flamethrower_checks()
	if not bool(checks.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower checks failed: %s" % str(checks))
		get_tree().quit(1)
		return
	var next_pulse_sec := 10.0
	var next_progress_sec := 60.0
	var pulse_count := 0
	var pulse_hits := 0
	var pulse_kills := 0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p14_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_pulse_sec:
			var pulse: Dictionary = await _active_scene.run_p14_flamethrower_pulse()
			pulse_count += 1
			if bool(pulse.get("hit", false)):
				pulse_hits += 1
			if bool(pulse.get("killed", false)):
				pulse_kills += 1
			if not bool(pulse.get("used", false)) or not bool(pulse.get("hit", false)):
				printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower pulse failed: %s" % str(pulse))
				get_tree().quit(1)
				return
			next_pulse_sec += 10.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P14_FLAMETHROWER elapsed_sec=%.1f target_sec=%.1f pulses=%d hits=%d kills=%d" % [
				elapsed_sec,
				_p14_duration_sec,
				pulse_count,
				pulse_hits,
				pulse_kills,
			])
			next_progress_sec += 60.0
	print("VERIFICATION_CAPTURE_FLOW_P14 flamethrower_capture_setup")
	var capture_setup: Dictionary = await _active_scene.prepare_p14_flamethrower_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 flamethrower_capture_setup_ready")
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p14_flamethrower_playtest.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 flamethrower_screenshot_saved")
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := checks.duplicate(true)
	report["duration_sec"] = duration_sec
	report["duration_target_sec"] = _p14_duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["lobby_selectable"] = true
	report["lobby_loadout"] = {
		"primary": "flamethrower",
		"secondary": "handgun",
		"melee": "knife",
		"artillery": "smoke_bomb",
	}
	report["lobby_screenshot"] = lobby_screenshot_path
	report["screenshot"] = screenshot_path
	report["pulse_count"] = pulse_count
	report["pulse_hits"] = pulse_hits
	report["pulse_kills"] = pulse_kills
	report["capture_setup"] = capture_setup
	if not _validate_p14_flamethrower_report(report):
		return
	print("VERIFICATION_PLAYTEST_REPORT_P14_FLAMETHROWER %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-flamethrower")
	get_tree().quit(0)

func _capture_p14_flamethrower_host() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"flamethrower", &"handgun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host could not select flamethrower lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=%d expected_players=2" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(2)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host timed out waiting for ready client: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p14_flamethrower_network_check"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host game scene has no P14 flamethrower network hook")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p14_flamethrower_network_check()
		if bool(report.get("ok", false)):
			break
		if not bool(report.get("pending", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p14_flamethrower_network_report(report):
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_FLAMETHROWER_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-flamethrower-host")
	get_tree().quit(0)

func _capture_p14_flamethrower_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"flamethrower", &"handgun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-client could not select flamethrower lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-client game scene did not become ready")
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_FLAMETHROWER_CLIENT %s" % str({
		"ok": true,
		"weapon_id": "flamethrower",
		"disconnect_cleanup": cleanup_report,
	}))
	print("VERIFICATION_CAPTURE_PASS p14-flamethrower-client")
	get_tree().quit(0)

func _validate_p14_flamethrower_report(report: Dictionary) -> bool:
	if float(report.get("duration_sec", 0.0)) < P14_WEAPON_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower duration below %.0f sec: %.2f" % [
			P14_WEAPON_PLAYTEST_DURATION_SEC,
			float(report.get("duration_sec", 0.0)),
		])
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "flamethrower" or not bool(report.get("lobby_selectable", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower lobby/weapon selection failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("view_model_ok", false)) or not bool(report.get("tuning_ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower viewmodel/tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var offline_use: Dictionary = report.get("offline_use", {})
	if not bool(offline_use.get("used", false)) or not bool(offline_use.get("hit", false)) or not bool(offline_use.get("killed", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower offline use failed: %s" % str(offline_use))
		get_tree().quit(1)
		return false
	var propulsion: Dictionary = report.get("propulsion", {})
	if not bool(propulsion.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower propulsion failed: %s" % str(propulsion))
		get_tree().quit(1)
		return false
	var hud: Dictionary = report.get("hud", {})
	if not bool(hud.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower HUD check failed: %s" % str(hud))
		get_tree().quit(1)
		return false
	if int(report.get("pulse_count", 0)) < 1 or int(report.get("pulse_hits", 0)) < 1 or int(report.get("pulse_kills", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower pulse criteria failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var capture_setup: Dictionary = report.get("capture_setup", {})
	if not bool(capture_setup.get("ok", false)) or int(capture_setup.get("flame_bursts_after", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower screenshot/capture setup missing flame: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("screenshot", "")) == "" or String(report.get("lobby_screenshot", "")) == "":
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower screenshot paths missing: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _validate_p14_flamethrower_network_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "flamethrower":
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host wrong weapon report: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("ticks_fired", 0)) <= 0 or int(report.get("ticks_fired", 0)) > 30:
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host flame tick data failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("body_damage", 0.0)), 5.0) or not is_equal_approx(float(report.get("max_range_m", 0.0)), 12.0):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host damage/range tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("score_after", 0)) <= int(report.get("score_before", 0)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host score did not increment: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("victim_respawned", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-flamethrower-host victim did not respawn: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _capture_p14_lasso_pass() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	var lobby_options := _validate_lobby_weapon_options(lobby)
	if not bool(lobby_options.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso %s" % str(lobby_options.get("error", "lobby weapon options failed")))
		get_tree().quit(1)
		return
	if not lobby.smoke_select_loadout(&"assault_rifle", &"lasso", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso could not select lasso lobby loadout")
		get_tree().quit(1)
		return
	await _wait_for_render_frames(4)
	var lobby_screenshot_path := "res://docs/verification/screenshots" + "/p14_lasso_lobby.png"
	var lobby_screenshot := _save_viewport_png(lobby_screenshot_path)
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	lobby.smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso game scene did not become ready")
		get_tree().quit(1)
		return
	if (
		not _active_scene.has_method("run_p14_lasso_checks")
		or not _active_scene.has_method("run_p14_lasso_pulse")
		or not _active_scene.has_method("prepare_p14_lasso_capture_view")
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso game scene has no P14 lasso hooks")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	var checks: Dictionary = await _active_scene.run_p14_lasso_checks()
	if not bool(checks.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso checks failed: %s" % str(checks))
		get_tree().quit(1)
		return
	var next_pulse_sec := 10.0
	var next_progress_sec := 60.0
	var pulse_count := 0
	var pulse_pulls := 0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p14_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_pulse_sec:
			var pulse: Dictionary = await _active_scene.run_p14_lasso_pulse()
			pulse_count += 1
			if bool(pulse.get("pulled", false)):
				pulse_pulls += 1
			if not bool(pulse.get("used", false)) or not bool(pulse.get("pulled", false)):
				printerr("VERIFICATION_CAPTURE_FAIL p14-lasso pulse failed: %s" % str(pulse))
				get_tree().quit(1)
				return
			next_pulse_sec += 10.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P14_LASSO elapsed_sec=%.1f target_sec=%.1f pulses=%d pulls=%d" % [
				elapsed_sec,
				_p14_duration_sec,
				pulse_count,
				pulse_pulls,
			])
			next_progress_sec += 60.0
	print("VERIFICATION_CAPTURE_FLOW_P14 lasso_capture_setup")
	var capture_setup: Dictionary = await _active_scene.prepare_p14_lasso_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 lasso_capture_setup_ready")
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p14_lasso_playtest.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 lasso_screenshot_saved")
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := checks.duplicate(true)
	report["duration_sec"] = duration_sec
	report["duration_target_sec"] = _p14_duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["lobby_selectable"] = true
	report["lobby_loadout"] = {
		"primary": "assault_rifle",
		"secondary": "lasso",
		"melee": "knife",
		"artillery": "smoke_bomb",
	}
	report["lobby_screenshot"] = lobby_screenshot_path
	report["screenshot"] = screenshot_path
	report["pulse_count"] = pulse_count
	report["pulse_pulls"] = pulse_pulls
	report["capture_setup"] = capture_setup
	if not _validate_p14_lasso_report(report):
		return
	print("VERIFICATION_PLAYTEST_REPORT_P14_LASSO %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-lasso")
	get_tree().quit(0)

func _capture_p14_lasso_host() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"assault_rifle", &"lasso", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host could not select lasso lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=%d expected_players=2" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(2)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host timed out waiting for ready client: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p14_lasso_network_check"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host game scene has no P14 lasso network hook")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p14_lasso_network_check()
		if bool(report.get("ok", false)):
			break
		if not bool(report.get("pending", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p14_lasso_network_report(report):
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_LASSO_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-lasso-host")
	get_tree().quit(0)

func _capture_p14_lasso_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"assault_rifle", &"lasso", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-client could not select lasso lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-client game scene did not become ready")
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_LASSO_CLIENT %s" % str({
		"ok": true,
		"weapon_id": "lasso",
		"disconnect_cleanup": cleanup_report,
	}))
	print("VERIFICATION_CAPTURE_PASS p14-lasso-client")
	get_tree().quit(0)

func _validate_p14_lasso_report(report: Dictionary) -> bool:
	if float(report.get("duration_sec", 0.0)) < P14_WEAPON_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso duration below %.0f sec: %.2f" % [
			P14_WEAPON_PLAYTEST_DURATION_SEC,
			float(report.get("duration_sec", 0.0)),
		])
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "lasso" or not bool(report.get("lobby_selectable", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso lobby/weapon selection failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("view_model_ok", false)) or not bool(report.get("tuning_ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso viewmodel/tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var offline_use: Dictionary = report.get("offline_use", {})
	if not bool(offline_use.get("used", false)) or not bool(offline_use.get("pulled", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso offline use failed: %s" % str(offline_use))
		get_tree().quit(1)
		return false
	var hud: Dictionary = report.get("hud", {})
	if not bool(hud.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso HUD check failed: %s" % str(hud))
		get_tree().quit(1)
		return false
	if int(report.get("pulse_count", 0)) < 1 or int(report.get("pulse_pulls", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso pulse criteria failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var capture_setup: Dictionary = report.get("capture_setup", {})
	if not bool(capture_setup.get("ok", false)) or int(capture_setup.get("impact_sparks_after", 0)) < 1 or not bool(capture_setup.get("pulled", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso screenshot/capture setup missing pull feedback: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("screenshot", "")) == "" or String(report.get("lobby_screenshot", "")) == "":
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso screenshot paths missing: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _validate_p14_lasso_network_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "lasso":
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host wrong weapon report: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("pulls_fired", 0)) != 1 or not bool(report.get("moved_toward_shooter", false)) or not bool(report.get("velocity_toward_shooter", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host pull data failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("body_damage", -1.0)), 0.0) or not bool(report.get("health_unchanged", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host damage invariants failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("shot_cooldown_sec", 0.0)), 5.0) or not is_equal_approx(float(report.get("max_range_m", 0.0)), 28.0):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host cooldown/range tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("alt_action_type", "")) != "pull" or not is_equal_approx(float(report.get("propulsion_force", 0.0)), 14.0):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host pull tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("score_after", 0)) != int(report.get("score_before", -1)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-lasso-host score changed despite zero damage: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _capture_p14_redbull_pass() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	var lobby_options := _validate_lobby_weapon_options(lobby)
	if not bool(lobby_options.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull %s" % str(lobby_options.get("error", "lobby weapon options failed")))
		get_tree().quit(1)
		return
	if not lobby.smoke_select_loadout(&"assault_rifle", &"handgun", &"knife", &"redbull"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull could not select redbull lobby loadout")
		get_tree().quit(1)
		return
	await _wait_for_render_frames(4)
	var lobby_screenshot_path := "res://docs/verification/screenshots" + "/p14_redbull_lobby.png"
	var lobby_screenshot := _save_viewport_png(lobby_screenshot_path)
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	lobby.smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull game scene did not become ready")
		get_tree().quit(1)
		return
	if (
		not _active_scene.has_method("run_p14_redbull_checks")
		or not _active_scene.has_method("run_p14_redbull_pulse")
		or not _active_scene.has_method("prepare_p14_redbull_capture_view")
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull game scene has no P14 redbull hooks")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	var checks: Dictionary = await _active_scene.run_p14_redbull_checks()
	if not bool(checks.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull checks failed: %s" % str(checks))
		get_tree().quit(1)
		return
	var next_pulse_sec := 10.0
	var next_progress_sec := 60.0
	var pulse_count := 0
	var pulse_buffs := 0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p14_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_pulse_sec:
			var pulse: Dictionary = await _active_scene.run_p14_redbull_pulse()
			pulse_count += 1
			if bool(pulse.get("buff_active", false)):
				pulse_buffs += 1
			if (
				not bool(pulse.get("used", false))
				or not bool(pulse.get("buff_active", false))
				or not bool(pulse.get("charges_consumed", false))
				or not bool(pulse.get("cooldown_applied", false))
			):
				printerr("VERIFICATION_CAPTURE_FAIL p14-redbull pulse failed: %s" % str(pulse))
				get_tree().quit(1)
				return
			next_pulse_sec += 10.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P14_REDBULL elapsed_sec=%.1f target_sec=%.1f pulses=%d buffs=%d" % [
				elapsed_sec,
				_p14_duration_sec,
				pulse_count,
				pulse_buffs,
			])
			next_progress_sec += 60.0
	print("VERIFICATION_CAPTURE_FLOW_P14 redbull_capture_setup")
	var capture_setup: Dictionary = await _active_scene.prepare_p14_redbull_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 redbull_capture_setup_ready")
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p14_redbull_playtest.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 redbull_screenshot_saved")
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := checks.duplicate(true)
	report["duration_sec"] = duration_sec
	report["duration_target_sec"] = _p14_duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["lobby_selectable"] = true
	report["lobby_loadout"] = {
		"primary": "assault_rifle",
		"secondary": "handgun",
		"melee": "knife",
		"artillery": "redbull",
	}
	report["lobby_screenshot"] = lobby_screenshot_path
	report["screenshot"] = screenshot_path
	report["pulse_count"] = pulse_count
	report["pulse_buffs"] = pulse_buffs
	report["capture_setup"] = capture_setup
	if not _validate_p14_redbull_report(report):
		return
	print("VERIFICATION_PLAYTEST_REPORT_P14_REDBULL %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-redbull")
	get_tree().quit(0)

func _capture_p14_redbull_host() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"assault_rifle", &"handgun", &"knife", &"redbull"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host could not select redbull lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=%d expected_players=2" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(2)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host timed out waiting for ready client: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p14_redbull_network_check"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host game scene has no P14 redbull network hook")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p14_redbull_network_check()
		if bool(report.get("ok", false)):
			break
		if not bool(report.get("pending", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p14_redbull_network_report(report):
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_REDBULL_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-redbull-host")
	get_tree().quit(0)

func _capture_p14_redbull_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"assault_rifle", &"handgun", &"knife", &"redbull"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-client could not select redbull lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-client game scene did not become ready")
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_REDBULL_CLIENT %s" % str({
		"ok": true,
		"weapon_id": "redbull",
		"disconnect_cleanup": cleanup_report,
	}))
	print("VERIFICATION_CAPTURE_PASS p14-redbull-client")
	get_tree().quit(0)

func _validate_p14_redbull_report(report: Dictionary) -> bool:
	if float(report.get("duration_sec", 0.0)) < P14_WEAPON_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull duration below %.0f sec: %.2f" % [
			P14_WEAPON_PLAYTEST_DURATION_SEC,
			float(report.get("duration_sec", 0.0)),
		])
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "redbull" or not bool(report.get("lobby_selectable", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull lobby/weapon selection failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("view_model_ok", false)) or not bool(report.get("tuning_ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull viewmodel/tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var offline_use: Dictionary = report.get("offline_use", {})
	if (
		not bool(offline_use.get("used", false))
		or not bool(offline_use.get("buff_active", false))
		or not bool(offline_use.get("charges_consumed", false))
		or not bool(offline_use.get("cooldown_applied", false))
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull offline use failed: %s" % str(offline_use))
		get_tree().quit(1)
		return false
	var hud: Dictionary = report.get("hud", {})
	if not bool(hud.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull HUD check failed: %s" % str(hud))
		get_tree().quit(1)
		return false
	if int(report.get("pulse_count", 0)) < 1 or int(report.get("pulse_buffs", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull pulse criteria failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var capture_setup: Dictionary = report.get("capture_setup", {})
	if (
		not bool(capture_setup.get("ok", false))
		or not bool(capture_setup.get("buff_active", false))
		or not bool(capture_setup.get("charges_consumed", false))
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull screenshot/capture setup missing buff feedback: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("screenshot", "")) == "" or String(report.get("lobby_screenshot", "")) == "":
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull screenshot paths missing: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _validate_p14_redbull_network_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "redbull":
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host wrong weapon report: %s" % str(report))
		get_tree().quit(1)
		return false
	var local_buff: Dictionary = report.get("local_buff", {})
	if not bool(local_buff.get("buff_active", false)) or not is_equal_approx(float(local_buff.get("speed_multiplier_after", 0.0)), 1.5):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host local buff failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("uses_fired", 0)) != 1 or not bool(report.get("charges_consumed", false)) or not bool(report.get("cooldown_applied", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host use data failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("body_damage", -1.0)), 0.0) or not bool(report.get("health_unchanged", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host damage invariants failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("charges_max", 0)) != 2 or not is_equal_approx(float(report.get("shot_cooldown_sec", 0.0)), 0.5):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host charges/cooldown tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("effect_duration_sec", 0.0)), 30.0) or not is_equal_approx(float(report.get("move_speed_multiplier", 0.0)), 1.5):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host buff tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("alt_action_type", "")) != "speed_buff":
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host alt action tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("score_after", 0)) != int(report.get("score_before", -1)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-redbull-host score changed despite zero damage: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _capture_p14_portal_gun_pass() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	var lobby_options := _validate_lobby_weapon_options(lobby)
	if not bool(lobby_options.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun %s" % str(lobby_options.get("error", "lobby weapon options failed")))
		get_tree().quit(1)
		return
	if not lobby.smoke_select_loadout(&"assault_rifle", &"portal_gun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun could not select portal gun lobby loadout")
		get_tree().quit(1)
		return
	await _wait_for_render_frames(4)
	var lobby_screenshot_path := "res://docs/verification/screenshots" + "/p14_portal_gun_lobby.png"
	var lobby_screenshot := _save_viewport_png(lobby_screenshot_path)
	if lobby_screenshot != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun lobby screenshot: %s" % error_string(lobby_screenshot))
		get_tree().quit(1)
		return
	lobby.smoke_press_offline()
	await _wait_for_render_frames(12)
	if not _is_game_scene_ready():
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun game scene did not become ready")
		get_tree().quit(1)
		return
	if (
		not _active_scene.has_method("run_p14_portal_gun_checks")
		or not _active_scene.has_method("run_p14_portal_gun_pulse")
		or not _active_scene.has_method("prepare_p14_portal_gun_capture_view")
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun game scene has no P14 portal gun hooks")
		get_tree().quit(1)
		return
	var started_msec := Time.get_ticks_msec()
	var started_text := Time.get_datetime_string_from_system(true)
	var checks: Dictionary = await _active_scene.run_p14_portal_gun_checks()
	if not bool(checks.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun checks failed: %s" % str(checks))
		get_tree().quit(1)
		return
	var next_pulse_sec := 10.0
	var next_progress_sec := 60.0
	var pulse_count := 0
	var pulse_portals := 0
	var pulse_transports := 0
	while (float(Time.get_ticks_msec() - started_msec) / 1000.0) < _p14_duration_sec:
		await get_tree().create_timer(1.0).timeout
		var elapsed_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_sec >= next_pulse_sec:
			var pulse: Dictionary = await _active_scene.run_p14_portal_gun_pulse()
			pulse_count += 1
			if bool(pulse.get("placed_two_portals", false)):
				pulse_portals += 1
			if bool(pulse.get("teleported", false)):
				pulse_transports += 1
			if (
				not bool(pulse.get("used", false))
				or not bool(pulse.get("placed_two_portals", false))
				or not bool(pulse.get("teleported", false))
				or not bool(pulse.get("momentum_preserved", false))
				or not bool(pulse.get("ammo_consumed", false))
			):
				printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun pulse failed: %s" % str(pulse))
				get_tree().quit(1)
				return
			next_pulse_sec += 10.0
		if elapsed_sec >= next_progress_sec:
			print("VERIFICATION_CAPTURE_PROGRESS_P14_PORTAL_GUN elapsed_sec=%.1f target_sec=%.1f pulses=%d portals=%d transports=%d" % [
				elapsed_sec,
				_p14_duration_sec,
				pulse_count,
				pulse_portals,
				pulse_transports,
			])
			next_progress_sec += 60.0
	print("VERIFICATION_CAPTURE_FLOW_P14 portal_gun_capture_setup")
	var capture_setup: Dictionary = await _active_scene.prepare_p14_portal_gun_capture_view()
	if not bool(capture_setup.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun capture setup failed: %s" % str(capture_setup))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 portal_gun_capture_setup_ready")
	await _wait_for_render_frames(8)
	var screenshot_path := "res://docs/verification/screenshots" + "/p14_portal_gun_playtest.png"
	var screenshot_result := _save_viewport_png(screenshot_path)
	if screenshot_result != OK:
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun screenshot: %s" % error_string(screenshot_result))
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 portal_gun_screenshot_saved")
	var ended_text := Time.get_datetime_string_from_system(true)
	var duration_sec := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := checks.duplicate(true)
	report["duration_sec"] = duration_sec
	report["duration_target_sec"] = _p14_duration_sec
	report["started_at"] = started_text
	report["ended_at"] = ended_text
	report["lobby_selectable"] = true
	report["lobby_loadout"] = {
		"primary": "assault_rifle",
		"secondary": "portal_gun",
		"melee": "knife",
		"artillery": "smoke_bomb",
	}
	report["lobby_screenshot"] = lobby_screenshot_path
	report["screenshot"] = screenshot_path
	report["pulse_count"] = pulse_count
	report["pulse_portals"] = pulse_portals
	report["pulse_transports"] = pulse_transports
	report["capture_setup"] = capture_setup
	if not _validate_p14_portal_gun_report(report):
		return
	print("VERIFICATION_PLAYTEST_REPORT_P14_PORTAL_GUN %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-portal-gun")
	get_tree().quit(0)

func _capture_p14_portal_gun_host() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"assault_rifle", &"portal_gun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host could not select portal gun lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_host_private_match port=%d expected_players=2" % _p08_port)
	lobby.smoke_press_host(_p08_port)
	var host_lobby_ready := await _wait_for_host_lobby_ready_count(2)
	if not host_lobby_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host timed out waiting for ready client: %s" % _p08_lobby_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 host_press_start_match")
	lobby.smoke_press_start()
	var host_game_ready := await _wait_p08_for_game_scene()
	if not host_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host game scene did not become ready")
		get_tree().quit(1)
		return
	if not _active_scene.has_method("run_p14_portal_gun_network_check"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host game scene has no P14 portal gun network hook")
		get_tree().quit(1)
		return
	var report := {}
	for _index in range(int(_p08_timeout_sec * 10.0)):
		report = await _active_scene.run_p14_portal_gun_network_check()
		if bool(report.get("ok", false)):
			break
		if not bool(report.get("pending", false)):
			break
		await get_tree().create_timer(0.1).timeout
	if not _validate_p14_portal_gun_network_report(report):
		return
	var cleanup_report := await _run_p08_disconnect_cleanup()
	report["disconnect_cleanup"] = cleanup_report
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_PORTAL_GUN_HOST %s" % str(report))
	print("VERIFICATION_CAPTURE_PASS p14-portal-gun-host")
	get_tree().quit(0)

func _capture_p14_portal_gun_client() -> void:
	if not (_active_scene is LobbyMenu):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-client expected lobby scene")
		get_tree().quit(1)
		return
	var lobby := _active_scene as LobbyMenu
	if not lobby.smoke_select_loadout(&"assault_rifle", &"portal_gun", &"knife", &"smoke_bomb"):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-client could not select portal gun lobby loadout")
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_join_by_ip host=%s port=%d" % [_p08_host_address, _p08_port])
	lobby.smoke_press_join(_p08_host_address, _p08_port)
	var client_connected := await _wait_p08_for_client_connection()
	if not client_connected:
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-client timed out connecting to host: %s" % _p08_connection_state_summary())
		get_tree().quit(1)
		return
	print("VERIFICATION_CAPTURE_FLOW_P14 client_press_ready")
	lobby.smoke_press_ready()
	var client_game_ready := await _wait_p08_for_game_scene()
	if not client_game_ready:
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-client game scene did not become ready")
		get_tree().quit(1)
		return
	await get_tree().create_timer(_p08_client_hold_sec).timeout
	var cleanup_report := await _run_p08_disconnect_cleanup()
	if not bool(cleanup_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-client disconnect cleanup failed: %s" % str(cleanup_report))
		get_tree().quit(1)
		return
	await _cleanup_active_scene_for_capture()
	print("VERIFICATION_CAPTURE_REPORT_P14_PORTAL_GUN_CLIENT %s" % str({
		"ok": true,
		"weapon_id": "portal_gun",
		"disconnect_cleanup": cleanup_report,
	}))
	print("VERIFICATION_CAPTURE_PASS p14-portal-gun-client")
	get_tree().quit(0)

func _validate_p14_portal_gun_report(report: Dictionary) -> bool:
	if float(report.get("duration_sec", 0.0)) < P14_WEAPON_PLAYTEST_DURATION_SEC:
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun duration below %.0f sec: %.2f" % [
			P14_WEAPON_PLAYTEST_DURATION_SEC,
			float(report.get("duration_sec", 0.0)),
		])
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "portal_gun" or not bool(report.get("lobby_selectable", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun lobby/weapon selection failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("view_model_ok", false)) or not bool(report.get("tuning_ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun viewmodel/tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var offline_use: Dictionary = report.get("offline_use", {})
	if (
		not bool(offline_use.get("used", false))
		or not bool(offline_use.get("placed_two_portals", false))
		or not bool(offline_use.get("teleported", false))
		or not bool(offline_use.get("momentum_preserved", false))
		or not bool(offline_use.get("ammo_consumed", false))
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun offline use failed: %s" % str(offline_use))
		get_tree().quit(1)
		return false
	var hud: Dictionary = report.get("hud", {})
	if not bool(hud.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun HUD check failed: %s" % str(hud))
		get_tree().quit(1)
		return false
	if int(report.get("pulse_count", 0)) < 1 or int(report.get("pulse_portals", 0)) < 1 or int(report.get("pulse_transports", 0)) < 1:
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun pulse criteria failed: %s" % str(report))
		get_tree().quit(1)
		return false
	var capture_setup: Dictionary = report.get("capture_setup", {})
	if (
		not bool(capture_setup.get("ok", false))
		or not bool(capture_setup.get("placed_two_portals", false))
		or int(capture_setup.get("impact_sparks_after", 0)) < 1
	):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun screenshot/capture setup missing portal feedback: %s" % str(report))
		get_tree().quit(1)
		return false
	var portal_summary: Dictionary = capture_setup.get("portal_summary", {})
	if not bool(portal_summary.get("both_active", false)) or int(portal_summary.get("marker_count", 0)) < 2:
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun screenshot portal markers missing: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("screenshot", "")) == "" or String(report.get("lobby_screenshot", "")) == "":
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun screenshot paths missing: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _validate_p14_portal_gun_network_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if String(report.get("weapon_id", "")) != "portal_gun":
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host wrong weapon report: %s" % str(report))
		get_tree().quit(1)
		return false
	var local_portal: Dictionary = report.get("local_portal", {})
	if not bool(local_portal.get("placed_two_portals", false)) or not bool(local_portal.get("teleported", false)) or not bool(local_portal.get("momentum_preserved", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host local portal failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("shots_fired", 0)) != 2 or not bool(report.get("ammo_consumed", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host shot/ammo data failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("body_damage", -1.0)), 0.0) or not bool(report.get("health_unchanged", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host damage invariants failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("magazine_size", 0)) != 2 or not is_equal_approx(float(report.get("shot_cooldown_sec", 0.0)), 0.35):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host ammo/cooldown tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("max_range_m", 0.0)), 80.0) or not is_equal_approx(float(report.get("effect_radius_m", 0.0)), 1.1):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host range/radius tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not is_equal_approx(float(report.get("effect_duration_sec", 0.0)), 60.0) or String(report.get("alt_action_type", "")) != "portal":
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host duration/action tuning failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("score_after", 0)) != int(report.get("score_before", -1)):
		printerr("VERIFICATION_CAPTURE_FAIL p14-portal-gun-host score changed despite zero damage: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _wait_p08_for_host_lobby_ready() -> bool:
	return await _wait_for_host_lobby_ready_count(2)

func _wait_for_host_lobby_ready_count(expected_peer_count: int) -> bool:
	for _index in range(int(_p08_timeout_sec * 10.0)):
		if _network_session != null and _network_session.is_hosting and _lobby_ready_by_peer.size() >= expected_peer_count:
			var all_ready := true
			for ready in _lobby_ready_by_peer.values():
				all_ready = all_ready and bool(ready)
			if all_ready:
				return true
		await get_tree().create_timer(0.1).timeout
	return false

func _wait_p08_for_client_connection() -> bool:
	for _index in range(int(_p08_timeout_sec * 10.0)):
		if _network_session != null and _network_session.is_client and _network_session.is_connection_ready():
			return true
		await get_tree().create_timer(0.1).timeout
	return false

func _wait_p08_for_game_scene() -> bool:
	for _index in range(int(_p08_timeout_sec * 10.0)):
		if _is_game_scene_ready():
			return true
		await _wait_for_render_frames(1)
		await get_tree().create_timer(0.1).timeout
	return false

func _p08_lobby_state_summary() -> String:
	return "hosting=%s ready_by_peer=%s active_scene=%s" % [
		str(_network_session != null and _network_session.is_hosting),
		str(_lobby_ready_by_peer),
		str(_active_scene),
	]

func _p08_connection_state_summary() -> String:
	var status := -1
	var status_name := "no_peer"
	if _network_session != null and _network_session.multiplayer.multiplayer_peer != null:
		status = _network_session.multiplayer.multiplayer_peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			status_name = "disconnected"
		elif status == MultiplayerPeer.CONNECTION_CONNECTING:
			status_name = "connecting"
		elif status == MultiplayerPeer.CONNECTION_CONNECTED:
			status_name = "connected"
	return "is_client=%s is_connected_to_host=%s status=%s(%d)" % [
		str(_network_session != null and _network_session.is_client),
		str(_network_session != null and _network_session.is_connected_to_host),
		status_name,
		status,
	]

func _validate_p08_host_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p08-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	for required in ["same_arena", "host_can_see_remote_humanoid", "remote_movement_sync", "authoritative_combat", "death_respawn"]:
		if not bool(report.get(required, false)):
			printerr("VERIFICATION_CAPTURE_FAIL p08-host missing %s: %s" % [required, str(report)])
			get_tree().quit(1)
			return false
	return true

func _validate_p12_host_report(report: Dictionary) -> bool:
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p12-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("network_player_count", 0)) < 4:
		printerr("VERIFICATION_CAPTURE_FAIL p12-host expected 4 players: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("team_assignment_2v2", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p12-host missing 2v2 team assignment: %s" % str(report.get("team_counts", {})))
		get_tree().quit(1)
		return false
	if int(report.get("remote_humanoid_count", 0)) < 3 or int(report.get("fallback_remote_count", 0)) != 0:
		printerr("VERIFICATION_CAPTURE_FAIL p12-host remote humanoid criteria failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("score_verified", false)) or not bool(report.get("authoritative_combat", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p12-host score/combat missing: %s" % str(report))
		get_tree().quit(1)
		return false
	var spawn_report: Dictionary = report.get("spawn_report", {})
	if not bool(spawn_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p12-host spawn report failed: %s" % str(spawn_report))
		get_tree().quit(1)
		return false
	return true

func _validate_p13_host_report(report: Dictionary) -> bool:
	const P13_REQUIRED_PLAYERS := 6
	if not bool(report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p13-host report failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("capacity_players", 0)) < P13_REQUIRED_PLAYERS:
		printerr("VERIFICATION_CAPTURE_FAIL p13-host capacity too low: %s" % str(report))
		get_tree().quit(1)
		return false
	if int(report.get("network_player_count", 0)) < P13_REQUIRED_PLAYERS:
		printerr("VERIFICATION_CAPTURE_FAIL p13-host expected 6 players: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("team_assignment_3v3", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p13-host missing 3v3 team assignment: %s" % str(report.get("team_counts", {})))
		get_tree().quit(1)
		return false
	if int(report.get("remote_humanoid_count", 0)) < 5 or int(report.get("fallback_remote_count", 0)) != 0:
		printerr("VERIFICATION_CAPTURE_FAIL p13-host remote humanoid criteria failed: %s" % str(report))
		get_tree().quit(1)
		return false
	if not bool(report.get("team_score_verified", false)) or not bool(report.get("authoritative_combat", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p13-host team score/combat missing: %s" % str(report))
		get_tree().quit(1)
		return false
	var spawn_report: Dictionary = report.get("spawn_report", {})
	if not bool(spawn_report.get("ok", false)):
		printerr("VERIFICATION_CAPTURE_FAIL p13-host spawn report failed: %s" % str(spawn_report))
		get_tree().quit(1)
		return false
	var spawn_capacity: Dictionary = spawn_report.get("spawn_capacity_by_team", {})
	if int(spawn_capacity.get(1, 0)) < 3 or int(spawn_capacity.get(2, 0)) < 3:
		printerr("VERIFICATION_CAPTURE_FAIL p13-host spawn capacity too low: %s" % str(spawn_report))
		get_tree().quit(1)
		return false
	var performance: Dictionary = report.get("performance", {})
	if int(performance.get("node_count", 0)) <= 0:
		printerr("VERIFICATION_CAPTURE_FAIL p13-host missing perf readout: %s" % str(report))
		get_tree().quit(1)
		return false
	return true

func _run_p08_disconnect_cleanup() -> Dictionary:
	if _network_session != null and _network_session.is_active():
		_network_session.close()
	await _wait_for_render_frames(8)
	var remote_count := -1
	if _active_scene != null and _active_scene.has_method("get_runtime_smoke_summary"):
		var summary: Dictionary = _active_scene.get_runtime_smoke_summary()
		remote_count = int(summary.get("remote_proxies", -1))
	return {
		"ok": _network_session == null or not _network_session.is_active(),
		"network_active": _network_session != null and _network_session.is_active(),
		"remote_proxies_after_close": remote_count,
	}

func _wait_for_render_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _save_viewport_png(path: String) -> Error:
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_dir := absolute_path.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_error != OK:
		return dir_error
	var image := get_viewport().get_texture().get_image()
	return image.save_png(absolute_path)

func _cleanup_active_scene_for_capture() -> void:
	if _network_session != null and _network_session.is_active():
		_network_session.close()
		await _wait_for_render_frames(4)
	if _active_scene != null:
		_active_scene.queue_free()
		_active_scene = null
	await _wait_for_render_frames(12)

func _cleanup_active_scene_for_smoke() -> void:
	if _network_session != null and _network_session.is_active():
		_network_session.close()
		await _wait_process_frames(4)
	if _active_scene != null:
		_active_scene.queue_free()
		_active_scene = null
	await _wait_process_frames(12)

func _wait_process_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await get_tree().process_frame

func _begin_smoke_test() -> void:
	_smoke_active = true
	_smoke_elapsed_sec = 0.0
	print("SMOKE_START %s" % _smoke_test)
	if _smoke_test == "offline":
		if not (_active_scene is LobbyMenu):
			_finish_smoke_failure("offline smoke expected lobby scene")
			return
		(_active_scene as LobbyMenu).smoke_press_offline()
	elif _smoke_test == "network-game":
		if _network_session == null or not _network_session.is_active():
			_finish_smoke_failure("network-game smoke expected --host or --join")
	elif _smoke_test == "heartbeat-timeout-host":
		if _network_session == null or not _network_session.is_hosting:
			_finish_smoke_failure("heartbeat-timeout-host smoke expected --host")
	elif _smoke_test == "lobby-host":
		if not (_active_scene is LobbyMenu):
			_finish_smoke_failure("lobby-host smoke expected lobby scene")
			return
		(_active_scene as LobbyMenu).smoke_press_host(_smoke_port)
	elif _smoke_test == "lobby-client":
		if not (_active_scene is LobbyMenu):
			_finish_smoke_failure("lobby-client smoke expected lobby scene")
			return
		(_active_scene as LobbyMenu).smoke_press_join(_smoke_host, _smoke_port)
	elif _smoke_test == "lan-discovery-host":
		if not (_active_scene is LobbyMenu):
			_finish_smoke_failure("lan-discovery-host smoke expected lobby scene")
			return
		(_active_scene as LobbyMenu).smoke_press_host(_smoke_port)
	elif _smoke_test == "lan-discovery-client":
		if not (_active_scene is LobbyMenu):
			_finish_smoke_failure("lan-discovery-client smoke expected lobby scene")
			return
	elif _smoke_test == "lobby-validation":
		if not (_active_scene is LobbyMenu):
			_finish_smoke_failure("lobby-validation smoke expected lobby scene")
			return
		var lobby := _active_scene as LobbyMenu
		lobby.smoke_press_join("", _smoke_port)
		if not lobby.smoke_get_status().contains("Enter a host IP address"):
			_finish_smoke_failure("empty-IP lobby validation did not show useful status")
			return
		_finish_smoke_success("empty-IP lobby validation status works")
	elif _smoke_test == "join-override-lobby":
		if not (_active_scene is LobbyMenu):
			_finish_smoke_failure("join-override-lobby smoke expected lobby scene")
			return
		if not _force_lobby_join_override:
			_finish_smoke_failure("join-override-lobby smoke expected bare --join argument")
			return
		var lobby := _active_scene as LobbyMenu
		if not lobby.smoke_has_manual_network_fields():
			_finish_smoke_failure("--join override lobby is missing manual host/password controls")
			return
		if not lobby.smoke_get_status().contains("Host IP"):
			_finish_smoke_failure("--join override did not prompt for Host IP: %s" % lobby.smoke_get_status())
			return
		_finish_smoke_success("bare --join opens manual Host IP/password join prompt")
	elif _smoke_test == "host-lobby":
		if not (_active_scene is LobbyMenu):
			_finish_smoke_failure("host-lobby smoke expected lobby scene")
			return
		if _network_session != null and _network_session.is_active():
			_finish_smoke_failure("bare --host should not start a network session before pressing Start")
			return
		var lobby := _active_scene as LobbyMenu
		if not lobby.smoke_has_manual_network_fields():
			_finish_smoke_failure("--host lobby is missing manual network/password controls")
			return
		if not lobby.smoke_is_host_lobby_mode():
			_finish_smoke_failure("--host lobby did not enter host mode")
			return
		if not lobby.smoke_get_public_ip_text().contains("Public IP"):
			_finish_smoke_failure("--host lobby did not show public IP/share label: %s" % lobby.smoke_get_public_ip_text())
			return
		if not lobby.smoke_get_status().contains("press Start") and not lobby.smoke_get_status().contains("Press Start"):
			_finish_smoke_failure("--host lobby did not prompt for Start: %s" % lobby.smoke_get_status())
			return
		_finish_smoke_success("bare --host opens lobby without password prompt or auto-start")
	elif _smoke_test == "weapons":
		if not (_active_scene is LobbyMenu):
			_finish_smoke_failure("weapons smoke expected lobby scene")
			return
		var lobby := _active_scene as LobbyMenu
		var lobby_options := _validate_lobby_weapon_options(lobby)
		if not bool(lobby_options.get("ok", false)):
			_finish_smoke_failure(str(lobby_options.get("error", "lobby weapon options failed")))
			return
		if not lobby.smoke_select_loadout(&"assault_rifle", &"portal_gun", &"knife", &"grenade"):
			_finish_smoke_failure("could not select extended smoke loadout in lobby")
			return
		lobby.smoke_press_offline()
	else:
		_finish_smoke_failure("unknown smoke test '%s'" % _smoke_test)

func _tick_smoke_test(delta: float) -> void:
	_smoke_elapsed_sec += delta
	if _smoke_elapsed_sec >= _smoke_timeout_sec:
		_finish_smoke_failure("smoke test timed out after %.2f sec%s" % [_smoke_timeout_sec, _smoke_runtime_summary_suffix()])
		return
	if _smoke_test == "offline":
		_tick_offline_smoke()
	elif _smoke_test == "network-game":
		_tick_network_game_smoke(delta)
	elif _smoke_test == "heartbeat-timeout-host":
		_tick_heartbeat_timeout_host_smoke()
	elif _smoke_test == "lobby-host":
		_tick_lobby_host_smoke()
	elif _smoke_test == "lobby-client":
		_tick_lobby_client_smoke(delta)
	elif _smoke_test == "lan-discovery-host":
		_tick_lan_discovery_host_smoke()
	elif _smoke_test == "lan-discovery-client":
		_tick_lan_discovery_client_smoke(delta)
	elif _smoke_test == "weapons":
		_tick_weapons_smoke()

func _tick_offline_smoke() -> void:
	if not _is_game_scene_ready():
		return
	if not _smoke_pause_checked:
		var pause_result := _run_pause_smoke_check()
		if not bool(pause_result.get("ok", false)):
			_finish_smoke_failure(str(pause_result.get("error", "pause smoke failed")))
			return
		_smoke_pause_checked = true
	if _run_game_smoke_checks(0, false):
		if not _smoke_offline_system_checked:
			var offline_result: Dictionary = _active_scene.run_offline_system_smoke_check()
			if not bool(offline_result.get("ok", false)):
				_finish_smoke_failure(str(offline_result.get("error", "offline systems smoke failed")))
				return
			_smoke_offline_system_checked = true
		_finish_smoke_success("offline game scene, movement/combat/HUD/match/art smoke passed")

func _smoke_runtime_summary_suffix() -> String:
	if _active_scene == null or not _active_scene.has_method("get_runtime_smoke_summary"):
		return ""
	var summary: Dictionary = _active_scene.get_runtime_smoke_summary()
	return " summary=%s" % str({
		"network_players": summary.get("network_players", "n/a"),
		"remote_proxies": summary.get("remote_proxies", "n/a"),
		"team_counts": summary.get("team_counts", {}),
		"match_phase": summary.get("match_phase", "n/a"),
		"authenticated": _authenticated_peer_ids.keys(),
		"ready": _lobby_ready_by_peer.keys(),
		"scene_ready": _game_scene_ready_by_peer.keys(),
	})

func _tick_network_game_smoke(delta: float) -> void:
	if not _is_game_scene_ready():
		return
	if _network_session == null or not _network_session.is_active():
		_finish_smoke_failure("network session closed before smoke completed")
		return
	if _network_arg_requested_join:
		if not _network_session.is_client:
			_finish_smoke_failure("join network session stopped before smoke completed")
			return
		if _network_session.is_connection_ready():
			_smoke_connected_to_host = true
		if not _smoke_connected_to_host:
			return
		if not _apply_p06_driver_pose_if_requested():
			return
		_smoke_connected_hold_sec += delta
		if _smoke_connected_hold_sec < _smoke_client_hold_sec:
			return
		if _run_game_smoke_checks(2, false):
			_finish_smoke_success("network client connected and game scene ready")
		return
	if _network_arg_requested_host and not _network_session.is_hosting:
		_finish_smoke_failure("host network session stopped before smoke completed")
		return
	if _smoke_expected_peers > 0 and _smoke_network_authority_checked:
		if _smoke_elapsed_sec < _smoke_host_min_runtime_sec():
			return
		_finish_smoke_success("network host has %d expected peer(s)" % _smoke_expected_peers)
		return
	var min_players := _smoke_expected_peers + 1 if _smoke_expected_peers > 0 else 1
	if _run_game_smoke_checks(min_players, false):
		if _smoke_expected_peers > 0 and not _smoke_network_authority_checked:
			var authority_result: Dictionary = _active_scene.run_network_authority_smoke_check()
			if bool(authority_result.get("pending", false)):
				return
			if not bool(authority_result.get("ok", false)):
				_finish_smoke_failure(str(authority_result.get("error", "network authority smoke failed")))
				return
			_smoke_network_authority_checked = true
		if _smoke_expected_peers > 0 and _smoke_elapsed_sec < _smoke_host_min_runtime_sec():
			return
		_finish_smoke_success("network host has %d expected peer(s)" % _smoke_expected_peers)

func _tick_heartbeat_timeout_host_smoke() -> void:
	if _network_session == null or not _network_session.is_hosting:
		_finish_smoke_failure("heartbeat timeout host session stopped before smoke completed")
		return
	if _smoke_heartbeat_timeout_peer_id <= 0:
		return
	var peer_id := _smoke_heartbeat_timeout_peer_id
	if _authenticated_peer_ids.has(peer_id) or _lobby_ready_by_peer.has(peer_id) or _game_scene_ready_by_peer.has(peer_id):
		return
	if _active_scene != null and _active_scene.has_method("smoke_has_network_peer") and _active_scene.smoke_has_network_peer(peer_id):
		return
	_finish_smoke_success("peer %d timed out and was removed" % peer_id)

func _tick_lobby_host_smoke() -> void:
	if _network_session == null or not _network_session.is_hosting:
		return
	if not _smoke_started_match:
		if _is_game_scene_ready():
			_smoke_started_match = true
		else:
			if _lobby_ready_by_peer.size() < _smoke_expected_peers + 1:
				return
			for ready in _lobby_ready_by_peer.values():
				if not bool(ready):
					return
			_smoke_started_match = true
			if _active_scene is LobbyMenu:
				(_active_scene as LobbyMenu).smoke_press_start()
			else:
				_on_lobby_start_requested()
			return
	if not _is_game_scene_ready():
		return
	if _smoke_expected_peers > 0 and _smoke_network_authority_checked:
		if _smoke_elapsed_sec < _smoke_host_min_runtime_sec():
			return
		_finish_smoke_success("lobby host started match with %d expected peer(s)" % _smoke_expected_peers)
		return
	var min_players := _smoke_expected_peers + 1 if _smoke_expected_peers > 0 else 1
	if _run_game_smoke_checks(min_players, false):
		if _smoke_expected_peers > 0 and not _smoke_network_authority_checked:
			var authority_result: Dictionary = _active_scene.run_network_authority_smoke_check()
			if bool(authority_result.get("pending", false)):
				return
			if not bool(authority_result.get("ok", false)):
				_finish_smoke_failure(str(authority_result.get("error", "network authority smoke failed")))
				return
			_smoke_network_authority_checked = true
		if _smoke_expected_peers > 0 and _smoke_elapsed_sec < _smoke_host_min_runtime_sec():
			return
		_finish_smoke_success("lobby host started match with %d expected peer(s)" % _smoke_expected_peers)

func _tick_lobby_client_smoke(delta: float) -> void:
	if _network_session == null or not _network_session.is_client:
		return
	if _network_session.is_connection_ready():
		_smoke_connected_to_host = true
	if _smoke_connected_to_host and not _client_password_accepted:
		return
	if _smoke_connected_to_host and not _smoke_ready_sent:
		_smoke_ready_sent = true
		if _active_scene is LobbyMenu:
			(_active_scene as LobbyMenu).smoke_press_ready()
		else:
			_on_lobby_ready_requested()
	if not _is_game_scene_ready():
		return
	_smoke_connected_hold_sec += delta
	if _smoke_connected_hold_sec < _smoke_client_hold_sec:
		return
	if _run_game_smoke_checks(2, false):
		_finish_smoke_success("lobby client joined, readied, and entered game")

func _tick_lan_discovery_host_smoke() -> void:
	if _network_session == null or not _network_session.is_hosting:
		return
	if _lobby_ready_by_peer.size() < _smoke_expected_peers + 1:
		return
	for peer_id in _lobby_ready_by_peer.keys():
		if not bool(_lobby_ready_by_peer[peer_id]):
			return
		var typed_peer_id := int(peer_id)
		if typed_peer_id == 1:
			continue
		if not _is_peer_authenticated(typed_peer_id):
			return
	_smoke_connected_hold_sec += get_process_delta_time()
	if _smoke_connected_hold_sec < 1.0:
		return
	_finish_smoke_success("LAN discovery host advertised and received %d ready peer(s)" % _smoke_expected_peers)

func _tick_lan_discovery_client_smoke(_delta: float) -> void:
	if _network_session == null:
		return
	if _network_session.is_connection_ready():
		_smoke_connected_to_host = true
	if _smoke_connected_to_host and _is_game_scene_ready():
		_smoke_connected_hold_sec += get_process_delta_time()
		if _smoke_connected_hold_sec >= 1.5:
			_finish_smoke_success("LAN discovery client joined discovered host and entered game")
		return
	if _smoke_connected_to_host:
		if not _client_password_accepted:
			return
		if not _smoke_ready_sent:
			_smoke_ready_sent = true
			if _active_scene is LobbyMenu:
				(_active_scene as LobbyMenu).smoke_press_ready()
			else:
				_on_lobby_ready_requested()
		return
	if not (_active_scene is LobbyMenu):
		return
	var lobby := _active_scene as LobbyMenu
	if lobby.smoke_get_lan_host_count() <= 0:
		return
	if not lobby.smoke_press_join_lan(0):
		_finish_smoke_failure("LAN discovery found a host but could not join it")

func _tick_weapons_smoke() -> void:
	if not _is_game_scene_ready():
		return
	if _run_game_smoke_checks(0, false):
		if not _smoke_all_weapons_checked:
			var all_weapons_result: Dictionary = _active_scene.run_all_weapons_smoke_check(true)
			if not bool(all_weapons_result.get("ok", false)):
				_finish_smoke_failure(str(all_weapons_result.get("error", "all-weapons smoke failed")))
				return
			_smoke_all_weapons_checked = true
		_finish_smoke_success("lobby options and all weapon resources fired without runtime errors")

func _is_game_scene_ready() -> bool:
	return _active_scene != null and _active_scene.has_method("get_runtime_smoke_summary")

func _run_game_smoke_checks(min_network_players: int, include_weapon_fire: bool) -> bool:
	var summary: Dictionary = _active_scene.get_runtime_smoke_summary()
	if not bool(summary.get("has_local_player", false)):
		_finish_smoke_failure("game scene has no local player")
		return false
	if not bool(summary.get("has_hud", false)):
		_finish_smoke_failure("game scene has no HUD")
		return false
	if int(summary.get("spawn_points", 0)) <= 0:
		_finish_smoke_failure("game scene has no spawn points")
		return false
	if StringName(str(summary.get("match_phase", &""))) != &"playing":
		_finish_smoke_failure("match is not playing")
		return false
	if min_network_players > 0:
		if int(summary.get("network_players", 0)) < min_network_players:
			return false
		if min_network_players > 1 and int(summary.get("remote_proxies", 0)) < 1:
			return false
		if not _team_counts_are_sane(summary.get("team_counts", {}), min_network_players):
			_finish_smoke_failure("network team assignment is not sane: %s" % str(summary.get("team_counts", {})))
			return false
	if include_weapon_fire and not _smoke_weapon_checked:
		var weapon_summary: Dictionary = _active_scene.run_runtime_smoke_check(true)
		if not bool(weapon_summary.get("ok", false)):
			_finish_smoke_failure(str(weapon_summary.get("error", "weapon smoke failed")))
			return false
		_smoke_weapon_checked = true
	return true

func _team_counts_are_sane(team_counts: Dictionary, min_network_players: int) -> bool:
	if min_network_players <= 1:
		return true
	var blue := int(team_counts.get(1, 0))
	var orange := int(team_counts.get(2, 0))
	if blue + orange < min_network_players:
		return false
	return abs(blue - orange) <= 1

func _smoke_host_min_runtime_sec() -> float:
	return maxf(3.0, 2.5 + float(_smoke_expected_peers))

func _run_pause_smoke_check() -> Dictionary:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return {"ok": false, "error": "game did not capture mouse"}
	var event := InputEventAction.new()
	event.action = FpsInputActions.PAUSE
	event.pressed = true
	_unhandled_input(event)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return {"ok": false, "error": "pause did not release mouse"}
	_unhandled_input(event)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return {"ok": false, "error": "second pause did not recapture mouse"}
	return {"ok": true}

func _apply_p06_driver_pose_if_requested() -> bool:
	if not _p06_driver_pose_requested:
		return true
	if not _is_game_scene_ready():
		return false
	if not _active_scene.has_method("prepare_p06_driver_pose"):
		_finish_smoke_failure("P06 driver pose requested, but game scene has no driver hook")
		return false
	var driver_pose: Dictionary = _active_scene.prepare_p06_driver_pose()
	if not bool(driver_pose.get("ok", false)):
		_finish_smoke_failure("P06 driver pose failed: %s" % str(driver_pose.get("error", "unknown error")))
		return false
	_p06_driver_pose_applied = true
	return true

func _validate_lobby_weapon_options(lobby: LobbyMenu) -> Dictionary:
	var options := lobby.smoke_get_slot_weapon_ids()
	var expected_by_slot := {
		"primary": [&"assault_rifle", &"shotgun", &"sniper", &"flamethrower"],
		"secondary": [&"handgun", &"portal_gun", &"lasso", &"taser_gun"],
		"melee": [&"knife"],
		"artillery": [&"smoke_bomb", &"grenade", &"redbull"],
	}
	for slot in expected_by_slot.keys():
		if not options.has(slot):
			return {"ok": false, "error": "lobby weapon options missing slot %s" % slot}
		var found: Array = options[slot]
		for weapon_id in expected_by_slot[slot]:
			if not found.has(weapon_id):
				return {"ok": false, "error": "lobby slot %s missing %s" % [slot, String(weapon_id)]}
	return {"ok": true}

func _finish_smoke_success(message: String) -> void:
	if not _smoke_active:
		return
	_smoke_active = false
	call_deferred("_finish_smoke_success_after_cleanup", message)

func _finish_smoke_success_after_cleanup(message: String) -> void:
	await _cleanup_active_scene_for_smoke()
	print("SMOKE_PASS %s: %s" % [_smoke_test, message])
	get_tree().quit(0)

func _finish_smoke_failure(message: String) -> void:
	if not _smoke_active:
		return
	_smoke_active = false
	printerr("SMOKE_FAIL %s: %s" % [_smoke_test, message])
	get_tree().quit(1)

func _bind_network_session() -> void:
	_network_session.hosting_started.connect(_on_network_hosting_started)
	_network_session.connected_to_host.connect(_on_network_connected_to_host)
	_network_session.connection_failed.connect(_on_network_connection_failed)
	_network_session.peer_joined.connect(_on_network_peer_joined)
	_network_session.peer_left.connect(_on_network_peer_left)
	_network_session.session_closed.connect(_on_network_session_closed)
	_network_session.lan_hosts_changed.connect(_on_lan_hosts_changed)

func _on_lobby_offline_requested(loadout: Dictionary) -> void:
	_apply_selected_loadout(loadout)
	_dev_balance_dummy_enabled_for_next_game = true
	_network_session.close()
	_load_game_root()

func _on_lobby_host_requested(port: int, password: String, loadout: Dictionary) -> void:
	_apply_selected_loadout(loadout)
	_dev_balance_dummy_enabled_for_next_game = false
	_network_password = password.strip_edges()
	if _network_password == "":
		_set_lobby_status("Enter a match password before hosting.", false, false)
		return
	_game_scene_ready_by_peer.clear()
	_authenticated_peer_ids = {1: true}
	_pending_auth_by_peer.clear()
	_reset_heartbeat_state()
	_client_password_accepted = false
	var error := _network_session.host(port)
	if error == OK:
		_lobby_ready_by_peer = {1: true}
		_lobby_player_names_by_peer = {1: _local_player_name}
		start_network_match.rpc()
		_load_game_root()

func _on_lobby_join_requested(address: String, port: int, password: String, loadout: Dictionary) -> void:
	_apply_selected_loadout(loadout)
	_dev_balance_dummy_enabled_for_next_game = false
	if address == "":
		_set_lobby_status("Enter a host IP address before joining.", false, false)
		return
	_network_password = password.strip_edges()
	if _network_password == "":
		_set_lobby_status("Enter the match password before joining.", false, false)
		return
	_game_scene_ready_by_peer.clear()
	_authenticated_peer_ids.clear()
	_pending_auth_by_peer.clear()
	_reset_heartbeat_state()
	_client_password_accepted = false
	var error := _network_session.join(address, port)
	if error == OK:
		_set_lobby_status("Connecting to %s:%d..." % [address, port], false, false)

func _on_lobby_ready_requested() -> void:
	if _network_session.is_hosting:
		_lobby_ready_by_peer[1] = true
		_lobby_player_names_by_peer[1] = _local_player_name
		_set_lobby_status(_build_lobby_status_text(), false, true)
	elif _network_session.is_client:
		submit_lobby_ready.rpc_id(1, true, _local_player_name)

func _on_lobby_start_requested() -> void:
	if not multiplayer.is_server():
		_set_lobby_status("Only the host can start the match.", _network_session.is_client, false)
		return
	_game_scene_ready_by_peer.clear()
	start_network_match.rpc()
	_load_game_root()

func _on_network_hosting_started(port: int) -> void:
	_lobby_ready_by_peer = {1: true}
	_lobby_player_names_by_peer[1] = _local_player_name
	_set_lobby_status("Hosting on port %d. Starting game..." % port, false, false)

func _on_network_connected_to_host() -> void:
	_smoke_connected_to_host = true
	_set_lobby_status("Connected. Sending match password...", false, false)
	_send_join_password_to_host()

func _on_network_connection_failed(reason: String) -> void:
	if _verification_capture.begins_with("p08"):
		print("VERIFICATION_CAPTURE_NETWORK_P08 connection_failed reason=%s %s" % [reason, _p08_connection_state_summary()])
	if _active_scene is LobbyMenu:
		_set_lobby_status(reason, false, false)
	else:
		_set_lobby_status(reason, false, false)
	call_deferred("_restart_lan_discovery_if_lobby")

func _on_network_peer_joined(peer_id: int) -> void:
	if multiplayer.is_server():
		_pending_auth_by_peer[peer_id] = true
		_lobby_player_names_by_peer[peer_id] = "Pending %d" % peer_id
		_set_lobby_status("Peer %d connected. Waiting for match password." % peer_id, false, false)
		return

func _accept_authenticated_peer(peer_id: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	_pending_auth_by_peer.erase(peer_id)
	_authenticated_peer_ids[peer_id] = true
	_touch_peer_heartbeat(peer_id)
	var sanitized_name := _sanitize_player_name(player_name)
	if sanitized_name == "":
		sanitized_name = "Peer %d" % peer_id
	_lobby_player_names_by_peer[peer_id] = sanitized_name
	_push_authenticated_peers_to_active_scene()
	if _active_scene != null and _active_scene.has_method("authorize_network_peer"):
		_active_scene.authorize_network_peer(peer_id, sanitized_name)
	if multiplayer.is_server():
		var match_in_progress := _active_scene != null and not (_active_scene is LobbyMenu)
		_lobby_ready_by_peer[peer_id] = match_in_progress
		_game_scene_ready_by_peer.erase(peer_id)
		if match_in_progress:
			_queue_or_send_match_start_to_peer(peer_id)
		else:
			_set_lobby_status(_build_lobby_status_text(), false, true)

func _queue_or_send_match_start_to_peer(peer_id: int) -> void:
	if not _is_host_game_ready():
		_pending_match_start_by_peer[peer_id] = true
		return
	call_deferred("_send_match_start_to_peer", peer_id)

func _send_match_start_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _network_session == null or not _network_session.is_hosting:
		return
	if not _is_peer_authenticated(peer_id):
		return
	if not _is_host_game_ready():
		_pending_match_start_by_peer[peer_id] = true
		return
	if peer_id <= 0 or _lobby_ready_by_peer.has(peer_id) == false:
		return
	_pending_match_start_by_peer.erase(peer_id)
	start_network_match.rpc_id(peer_id)

func _on_network_peer_left(peer_id: int) -> void:
	_remove_network_peer_state(peer_id, "left")

func _remove_network_peer_state(peer_id: int, reason := "left") -> void:
	if peer_id <= 0:
		return
	_lobby_ready_by_peer.erase(peer_id)
	_lobby_player_names_by_peer.erase(peer_id)
	_authenticated_peer_ids.erase(peer_id)
	_pending_auth_by_peer.erase(peer_id)
	_heartbeat_last_seen_msec_by_peer.erase(peer_id)
	_heartbeat_timed_out_peer_ids.erase(peer_id)
	_push_authenticated_peers_to_active_scene()
	_mark_game_scene_ready(peer_id, false)
	if _active_scene != null and _active_scene.has_method("remove_network_peer"):
		_active_scene.remove_network_peer(peer_id)
	if reason == "heartbeat_timeout":
		_smoke_heartbeat_timeout_peer_id = peer_id
		print("NETWORK_HEARTBEAT_TIMEOUT peer_id=%d timeout_sec=%.2f" % [peer_id, _heartbeat_timeout_sec])
	_set_lobby_status(_build_lobby_status_text(), false, multiplayer.is_server())

func _on_network_session_closed() -> void:
	_game_scene_ready_by_peer.clear()
	_pending_match_start_by_peer.clear()
	_pending_auth_by_peer.clear()
	_reset_heartbeat_state()
	_client_password_accepted = false
	_authenticated_peer_ids = {1: true}
	_push_authenticated_peers_to_active_scene()

func _on_lan_hosts_changed(_hosts: Array) -> void:
	_refresh_lobby_lan_hosts()

func _refresh_lobby_lan_hosts() -> void:
	if not (_active_scene is LobbyMenu) or _network_session == null:
		return
	(_active_scene as LobbyMenu).set_lan_hosts(_network_session.get_lan_hosts())

func _restart_lan_discovery_if_lobby() -> void:
	if _active_scene is LobbyMenu and _network_session != null and not _network_session.is_active():
		_network_session.start_lan_discovery()
		_refresh_lobby_lan_hosts()

func _set_lobby_status(text: String, show_ready: bool, show_start: bool) -> void:
	if _active_scene is LobbyMenu:
		var lobby: LobbyMenu = _active_scene
		lobby.set_status(text)
		lobby.set_network_controls(show_ready, show_start)

func _push_authenticated_peers_to_active_scene() -> void:
	if _active_scene != null and _active_scene.has_method("set_authorized_network_peer_ids"):
		_active_scene.set_authorized_network_peer_ids(_authenticated_peer_ids)

func _reset_heartbeat_state() -> void:
	_heartbeat_send_elapsed_sec = 0.0
	_heartbeat_last_seen_msec_by_peer.clear()
	_heartbeat_timed_out_peer_ids.clear()
	_smoke_heartbeat_timeout_peer_id = 0

func _tick_network_heartbeat(delta: float) -> void:
	if _network_session == null or not _network_session.is_active():
		return
	if _network_session.is_client:
		if _smoke_disable_heartbeat or not _client_password_accepted or not _network_session.is_connection_ready():
			return
		_heartbeat_send_elapsed_sec += delta
		if _heartbeat_send_elapsed_sec < NetworkConstants.HEARTBEAT_SEND_INTERVAL_SEC:
			return
		_heartbeat_send_elapsed_sec = 0.0
		submit_peer_heartbeat.rpc_id(1)
	elif _network_session.is_hosting and multiplayer.is_server():
		_expire_stale_heartbeats()

func _touch_peer_heartbeat(peer_id: int) -> void:
	if peer_id <= 0 or not multiplayer.is_server():
		return
	_heartbeat_last_seen_msec_by_peer[peer_id] = Time.get_ticks_msec()
	_heartbeat_timed_out_peer_ids.erase(peer_id)

func _expire_stale_heartbeats() -> void:
	if _heartbeat_timeout_sec <= 0.0:
		return
	var now_msec := Time.get_ticks_msec()
	var timeout_msec := int(_heartbeat_timeout_sec * 1000.0)
	for peer_id_key in _authenticated_peer_ids.keys():
		var peer_id := int(peer_id_key)
		if peer_id == 1 or _heartbeat_timed_out_peer_ids.has(peer_id):
			continue
		var last_seen_msec := int(_heartbeat_last_seen_msec_by_peer.get(peer_id, now_msec))
		if not _heartbeat_last_seen_msec_by_peer.has(peer_id):
			_heartbeat_last_seen_msec_by_peer[peer_id] = last_seen_msec
			continue
		if now_msec - last_seen_msec < timeout_msec:
			continue
		_heartbeat_timed_out_peer_ids[peer_id] = true
		_remove_network_peer_state(peer_id, "heartbeat_timeout")
		call_deferred("_disconnect_peer_after_timeout", peer_id)

func _disconnect_peer_after_timeout(peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)

func _build_lobby_status_text() -> String:
	var ready_count := 0
	for ready in _lobby_ready_by_peer.values():
		if bool(ready):
			ready_count += 1
	var pending_count := _pending_auth_by_peer.size()
	var suffix := " Pending password: %d." % pending_count if pending_count > 0 else ""
	return "Lobby peers: %d. Ready: %d. Host can start when ready.%s" % [_lobby_ready_by_peer.size(), ready_count, suffix]

func _apply_selected_loadout(loadout: Dictionary) -> void:
	_local_player_name = _sanitize_player_name(String(loadout.get("player_name", _local_player_name)))
	_lobby_player_names_by_peer[1] = _local_player_name
	var base := LoadoutDefinition.new()
	_selected_loadout = base.duplicate_with_slots(
		StringName(str(loadout.get("primary", &"assault_rifle"))),
		StringName(str(loadout.get("secondary", &"handgun"))),
		StringName(str(loadout.get("melee", &"knife"))),
		StringName(str(loadout.get("artillery", &"smoke_bomb")))
	)

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

func _is_peer_authenticated(peer_id: int) -> bool:
	return bool(_authenticated_peer_ids.get(peer_id, false))

func _send_join_password_to_host() -> void:
	if _network_session == null or not _network_session.is_client or not _network_session.is_connection_ready():
		return
	if _network_password == "":
		_set_lobby_status("Enter the match password before joining.", false, false)
		return
	submit_join_password.rpc_id(1, _network_password, _local_player_name)

func _disconnect_peer_after_rejection(peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)

@rpc("any_peer", "reliable")
func submit_join_password(password: String, player_name := "") -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if _network_password == "" or password.strip_edges() != _network_password:
		_pending_auth_by_peer.erase(sender)
		_authenticated_peer_ids.erase(sender)
		_lobby_ready_by_peer.erase(sender)
		_lobby_player_names_by_peer.erase(sender)
		_heartbeat_last_seen_msec_by_peer.erase(sender)
		_heartbeat_timed_out_peer_ids.erase(sender)
		_push_authenticated_peers_to_active_scene()
		join_password_rejected.rpc_id(sender, "Invalid match password.")
		call_deferred("_disconnect_peer_after_rejection", sender)
		return
	join_password_accepted.rpc_id(sender)
	_accept_authenticated_peer(sender, player_name)

@rpc("any_peer", "unreliable")
func submit_peer_heartbeat() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not _is_peer_authenticated(sender):
		return
	_touch_peer_heartbeat(sender)

@rpc("authority", "reliable")
func join_password_accepted() -> void:
	_client_password_accepted = true
	_set_lobby_status("Password accepted. Waiting for host to be ready...", false, false)
	if _is_game_scene_ready():
		call_deferred("_notify_host_game_scene_ready")

@rpc("authority", "reliable")
func join_password_rejected(reason := "Invalid match password.") -> void:
	_client_password_accepted = false
	_set_lobby_status(reason, false, false)
	if _network_session != null:
		_network_session.close()

@rpc("any_peer", "reliable")
func submit_lobby_ready(is_ready: bool, player_name := "") -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if not _is_peer_authenticated(sender):
		return
	_touch_peer_heartbeat(sender)
	_lobby_ready_by_peer[sender] = is_ready
	_lobby_player_names_by_peer[sender] = _sanitize_player_name(player_name)
	if _active_scene != null and not (_active_scene is LobbyMenu):
		_queue_or_send_match_start_to_peer(sender)
		return
	_set_lobby_status(_build_lobby_status_text(), false, true)

@rpc("authority", "reliable")
func start_network_match() -> void:
	_game_scene_ready_by_peer.clear()
	_load_game_root()

@rpc("any_peer", "reliable")
func submit_game_scene_ready(player_name := "") -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if not _is_peer_authenticated(sender):
		return
	_touch_peer_heartbeat(sender)
	_lobby_player_names_by_peer[sender] = _sanitize_player_name(player_name)
	_mark_game_scene_ready(sender, true)

func _notify_host_game_scene_ready() -> void:
	if _network_session == null or not _network_session.is_client or not _network_session.is_connection_ready():
		return
	if not _client_password_accepted:
		return
	if not _is_game_scene_ready():
		return
	submit_game_scene_ready.rpc_id(1, _local_player_name)

func _mark_game_scene_ready(peer_id: int, is_ready: bool) -> void:
	if peer_id <= 0:
		return
	if is_ready:
		_game_scene_ready_by_peer[peer_id] = true
	else:
		_game_scene_ready_by_peer.erase(peer_id)
		_pending_match_start_by_peer.erase(peer_id)
	if _active_scene != null and _active_scene.has_method("set_network_peer_scene_ready"):
		_active_scene.set_network_peer_scene_ready(peer_id, is_ready)
	if _is_host_peer(peer_id) and is_ready:
		if _network_session != null and _network_session.is_hosting:
			_network_session.start_lan_advertising(_network_session.listen_port, "in_game")
			_print_headless_host_ready_once()
		_flush_pending_match_starts()

func _print_headless_host_ready_once() -> void:
	if not _persistent_host_requested or _headless_host_ready_printed:
		return
	if _network_session == null:
		return
	_headless_host_ready_printed = true
	print("HEADLESS_HOST_READY mode=true_headless port=%d capacity=%d join_mid_game=true persistent=true" % [
		_network_session.listen_port,
		NetworkConstants.MAX_PLAYERS,
	])

func _is_host_peer(peer_id: int) -> bool:
	if _network_session == null or not _network_session.is_active():
		return peer_id == 1
	return peer_id == _network_session.local_peer_id() and multiplayer.is_server()

func _is_host_game_ready() -> bool:
	if _network_session == null or not _network_session.is_active() or not multiplayer.is_server():
		return false
	return bool(_game_scene_ready_by_peer.get(_network_session.local_peer_id(), false))

func _flush_pending_match_starts() -> void:
	if not _is_host_game_ready():
		return
	for peer_id in _pending_match_start_by_peer.keys():
		_send_match_start_to_peer(int(peer_id))

func _push_game_scene_readiness_to_active_scene() -> void:
	if _active_scene == null or not _active_scene.has_method("set_network_peer_scene_ready"):
		return
	for peer_id in _game_scene_ready_by_peer.keys():
		_active_scene.set_network_peer_scene_ready(int(peer_id), bool(_game_scene_ready_by_peer[peer_id]))
