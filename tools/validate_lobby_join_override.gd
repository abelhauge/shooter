extends SceneTree

const LOBBY_SCENE := preload("res://scenes/frontend/lobby_menu.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/lobby_manual_join_override.png"
const EXPECTED_ADDRESS := "203.0.113.77"
const EXPECTED_PASSWORD := "override-pass"

var _join_event := {}

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	OS.set_environment("SHOOTER_DISABLE_NETWORK_SETTINGS", "1")
	root.size = Vector2i(1280, 720)
	var lobby: LobbyMenu = LOBBY_SCENE.instantiate()
	root.add_child(lobby)
	lobby.join_requested.connect(_on_join_requested)

	for _index in range(4):
		await process_frame

	lobby.smoke_enable_public_join_override()
	if not lobby.smoke_has_manual_network_fields():
		_fail("join override did not show manual network fields")
		return
	if not lobby.smoke_get_status().contains("Host IP"):
		_fail("join override did not prompt for Host IP: %s" % lobby.smoke_get_status())
		return
	lobby.smoke_set_host_address(EXPECTED_ADDRESS)
	lobby.smoke_set_match_password(EXPECTED_PASSWORD)

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		if error != OK:
			_fail("could not save screenshot %s: %s" % [OUTPUT_PATH, error_string(error)])
			return

	lobby.smoke_press_join_ip()
	if _join_event.is_empty():
		_fail("Join override did not emit join_requested")
		return
	if String(_join_event.get("address", "")) != EXPECTED_ADDRESS:
		_fail("Join override emitted wrong address: %s" % str(_join_event))
		return
	if String(_join_event.get("password", "")) != EXPECTED_PASSWORD:
		_fail("Join override emitted wrong password: %s" % str(_join_event))
		return

	print("LOBBY_JOIN_OVERRIDE_PASS screenshot=%s address=%s" % [
		OUTPUT_PATH if DisplayServer.get_name() != "headless" else "skipped-headless",
		EXPECTED_ADDRESS,
	])
	quit(0)

func _on_join_requested(address: String, port: int, password: String, loadout: Dictionary) -> void:
	_join_event = {
		"address": address,
		"port": port,
		"password": password,
		"loadout": loadout,
	}

func _fail(message: String) -> void:
	push_error("Lobby join override validation failed: %s" % message)
	quit(1)
