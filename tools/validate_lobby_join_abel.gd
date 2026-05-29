extends SceneTree

const LOBBY_SCENE := preload("res://scenes/frontend/lobby_menu.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/lobby_join_abel_button.png"
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

	var join_abel_button := _find_button_by_text(lobby, "Join Abel")
	if join_abel_button == null:
		_fail("Join Abel button was not found")
		return
	if not join_abel_button.visible:
		_fail("Join Abel button is not visible")
		return

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		if error != OK:
			_fail("could not save screenshot %s: %s" % [OUTPUT_PATH, error_string(error)])
			return

	lobby.smoke_press_join_abel()
	if _join_event.is_empty():
		_fail("Join Abel did not emit join_requested")
		return
	if String(_join_event.get("address", "")) != EXPECTED_ADDRESS:
		_fail("Join Abel emitted wrong address: %s" % str(_join_event))
		return
	if int(_join_event.get("port", 0)) != NetworkConstants.DEFAULT_PORT:
		_fail("Join Abel emitted wrong port: %s" % str(_join_event))
		return

	print("LOBBY_JOIN_ABEL_PASS screenshot=%s address=%s port=%d" % [OUTPUT_PATH if DisplayServer.get_name() != "headless" else "skipped-headless", EXPECTED_ADDRESS, NetworkConstants.DEFAULT_PORT])
	quit(0)

func _on_join_requested(address: String, port: int, loadout: Dictionary) -> void:
	_join_event = {
		"address": address,
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
	push_error("Lobby Join Abel validation failed: %s" % message)
	quit(1)
