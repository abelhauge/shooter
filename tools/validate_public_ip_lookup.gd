extends SceneTree

const LOBBY_SCENE := preload("res://scenes/frontend/lobby_menu.tscn")
const EXPECTED_HOST_IP := "203.0.113.77"

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	root.size = Vector2i(1280, 720)
	var lobby: LobbyMenu = LOBBY_SCENE.instantiate()
	root.add_child(lobby)

	var deadline_msec := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline_msec:
		await process_frame
		var label := lobby.smoke_get_public_action_label()
		if label == "Start":
			print("PUBLIC_IP_LOOKUP_PASS label=%s status=%s debug=%s" % [
				label,
				lobby.smoke_get_status(),
				lobby.smoke_get_public_ip_lookup_debug(),
			])
			quit(0)
			return
		if (label == "Join" or label == "Venter på Host") and not lobby.smoke_get_status().contains("Checking public IP"):
			break

	push_error("Public IP lookup validation failed: label=%s status=%s expected=%s" % [
		lobby.smoke_get_public_action_label(),
		lobby.smoke_get_status(),
		EXPECTED_HOST_IP,
	])
	quit(1)
