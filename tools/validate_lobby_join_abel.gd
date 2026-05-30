extends SceneTree

const LOBBY_SCENE := preload("res://scenes/frontend/lobby_menu.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/lobby_public_join_button.png"
const EXPECTED_ADDRESS := "203.0.113.77"

var _join_event := {}
var _host_event := {}

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	root.size = Vector2i(1280, 720)
	var lobby: LobbyMenu = LOBBY_SCENE.instantiate()
	root.add_child(lobby)
	lobby.join_requested.connect(_on_join_requested)
	lobby.host_requested.connect(_on_host_requested)

	for _index in range(4):
		await process_frame

	lobby.smoke_force_public_ip("203.0.113.77")
	var join_button := _find_button_by_text(lobby, "Join")
	if join_button == null:
		_fail("Join button was not found")
		return
	if not join_button.visible:
		_fail("Join button is not visible")
		return

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		if error != OK:
			_fail("could not save screenshot %s: %s" % [OUTPUT_PATH, error_string(error)])
			return

	lobby.smoke_press_public_action()
	if _join_event.is_empty():
		_fail("Join did not emit join_requested")
		return
	if String(_join_event.get("address", "")) != EXPECTED_ADDRESS:
		_fail("Join emitted wrong address: %s" % str(_join_event))
		return
	if int(_join_event.get("port", 0)) != NetworkConstants.DEFAULT_PORT:
		_fail("Join emitted wrong port: %s" % str(_join_event))
		return

	lobby.smoke_force_public_ip(EXPECTED_ADDRESS)
	if lobby.smoke_get_public_action_label() != "Host game":
		_fail("Abel public IP did not switch button to Host game")
		return
	lobby.smoke_press_public_action()
	if _host_event.is_empty():
		_fail("Host game did not emit host_requested")
		return
	if int(_host_event.get("port", 0)) != NetworkConstants.DEFAULT_PORT:
		_fail("Host game emitted wrong port: %s" % str(_host_event))
		return

	print("LOBBY_PUBLIC_IP_ROUTING_PASS screenshot=%s address=%s port=%d" % [OUTPUT_PATH if DisplayServer.get_name() != "headless" else "skipped-headless", EXPECTED_ADDRESS, NetworkConstants.DEFAULT_PORT])
	quit(0)

func _on_join_requested(address: String, port: int, loadout: Dictionary) -> void:
	_join_event = {
		"address": address,
		"port": port,
		"loadout": loadout,
	}

func _on_host_requested(port: int, loadout: Dictionary) -> void:
	_host_event = {
		"port": port,
		"loadout": loadout,
	}

func _find_button_by_text(root_node: Node, text: String) -> Button:
	if root_node is Button and (root_node as Button).text == text:
		return root_node as Button
	for child in root_node.get_children():
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null

func _fail(message: String) -> void:
	push_error("Lobby public IP routing validation failed: %s" % message)
	quit(1)
