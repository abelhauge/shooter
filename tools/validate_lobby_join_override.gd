extends SceneTree

const LOBBY_SCENE := preload("res://scenes/frontend/lobby_menu.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/lobby_public_join_override.png"
const EXPECTED_ADDRESS := "203.0.113.77"

var _join_event := {}

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	root.size = Vector2i(1280, 720)
	var lobby: LobbyMenu = LOBBY_SCENE.instantiate()
	root.add_child(lobby)
	lobby.join_requested.connect(_on_join_requested)

	for _index in range(4):
		await process_frame

	lobby.smoke_enable_public_join_override()
	if lobby.smoke_get_public_action_label() != "Join":
		_fail("join override did not show Join: %s" % lobby.smoke_get_public_action_label())
		return

	lobby.smoke_force_public_ip(EXPECTED_ADDRESS)
	if lobby.smoke_get_public_action_label() != "Join":
		_fail("Abel public IP overrode join override: %s" % lobby.smoke_get_public_action_label())
		return

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		if error != OK:
			_fail("could not save screenshot %s: %s" % [OUTPUT_PATH, error_string(error)])
			return

	lobby.smoke_press_public_action()
	if _join_event.is_empty():
		_fail("Join override did not emit join_requested")
		return
	if String(_join_event.get("address", "")) != EXPECTED_ADDRESS:
		_fail("Join override emitted wrong address: %s" % str(_join_event))
		return

	print("LOBBY_JOIN_OVERRIDE_PASS screenshot=%s address=%s" % [
		OUTPUT_PATH if DisplayServer.get_name() != "headless" else "skipped-headless",
		EXPECTED_ADDRESS,
	])
	quit(0)

func _on_join_requested(address: String, port: int, loadout: Dictionary) -> void:
	_join_event = {
		"address": address,
		"port": port,
		"loadout": loadout,
	}

func _fail(message: String) -> void:
	push_error("Lobby join override validation failed: %s" % message)
	quit(1)
