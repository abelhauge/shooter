extends SceneTree

const LOBBY_SCENE := preload("res://scenes/frontend/lobby_menu.tscn")

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	OS.set_environment("SHOOTER_DISABLE_NETWORK_SETTINGS", "1")
	root.size = Vector2i(1280, 720)
	var lobby: LobbyMenu = LOBBY_SCENE.instantiate()
	root.add_child(lobby)

	for _index in range(8):
		await process_frame

	if not lobby.smoke_has_manual_network_fields():
		push_error("Manual network validation failed: missing Host IP/password controls")
		quit(1)
		return
	if lobby.smoke_get_host_action_label() != "Start":
		push_error("Manual network validation failed: host label=%s" % lobby.smoke_get_host_action_label())
		quit(1)
		return
	if lobby.smoke_get_join_action_label() != "Join IP":
		push_error("Manual network validation failed: join label=%s" % lobby.smoke_get_join_action_label())
		quit(1)
		return
	if lobby.smoke_get_status().contains("Public IP"):
		push_error("Manual network validation failed: lobby still references public IP: %s" % lobby.smoke_get_status())
		quit(1)
		return
	print("MANUAL_NETWORK_FIELDS_PASS status=%s" % lobby.smoke_get_status())
	quit(0)
