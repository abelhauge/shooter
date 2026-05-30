extends SceneTree

const LOBBY_SCENE := preload("res://scenes/frontend/lobby_menu.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/lobby_host_public_ip.png"
const EXPECTED_PUBLIC_IP := "203.0.113.42"
const EXPECTED_PASSWORD := "host-pass"

var _host_event := {}

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	OS.set_environment("SHOOTER_DISABLE_NETWORK_SETTINGS", "1")
	root.size = Vector2i(1280, 720)
	var lobby: LobbyMenu = LOBBY_SCENE.instantiate()
	lobby.set_host_lobby_mode(true)
	root.add_child(lobby)
	lobby.host_requested.connect(_on_host_requested)

	for _index in range(4):
		await process_frame

	lobby.smoke_force_public_ip(EXPECTED_PUBLIC_IP)
	lobby.smoke_set_match_password(EXPECTED_PASSWORD)
	if not lobby.smoke_is_host_lobby_mode():
		_fail("host lobby mode was not enabled")
		return
	var public_ip_text := lobby.smoke_get_public_ip_text()
	if not public_ip_text.contains("Public IP") or not public_ip_text.contains(EXPECTED_PUBLIC_IP):
		_fail("host lobby did not show public IP: %s" % public_ip_text)
		return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		if error != OK:
			_fail("could not save screenshot %s: %s" % [OUTPUT_PATH, error_string(error)])
			return

	lobby.smoke_press_host(NetworkConstants.DEFAULT_PORT)
	if _host_event.is_empty():
		_fail("host lobby did not emit host_requested")
		return
	if String(_host_event.get("password", "")) != EXPECTED_PASSWORD:
		_fail("host lobby emitted wrong password: %s" % str(_host_event))
		return

	print("LOBBY_HOST_PUBLIC_IP_PASS screenshot=%s public_ip=%s" % [
		OUTPUT_PATH if DisplayServer.get_name() != "headless" else "skipped-headless",
		public_ip_text,
	])
	quit(0)

func _on_host_requested(port: int, password: String, loadout: Dictionary) -> void:
	_host_event = {
		"port": port,
		"password": password,
		"loadout": loadout,
	}

func _fail(message: String) -> void:
	push_error("Lobby host public IP validation failed: %s" % message)
	quit(1)
