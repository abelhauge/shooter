extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const OUTPUT_DIR := "res://docs/verification/screenshots/weapon_visual_qa"

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(16):
		await process_frame
	if game.local_player == null:
		push_error("Shotgun/sniper viewmodel capture failed: missing local player")
		quit(1)
		return
	game.local_player.get_health_component().force_network_state(100.0, true, 3.0)
	game.local_player.movement_state = &"grounded"
	var weapon_controller: WeaponController = game.local_player.get_weapon_controller()
	var screenshots := {}
	for weapon_id in [&"shotgun", &"sniper"]:
		var select_result: Dictionary = weapon_controller.select_weapon_for_verification(weapon_id)
		if not bool(select_result.get("ok", false)):
			push_error("Shotgun/sniper viewmodel capture failed selecting %s: %s" % [String(weapon_id), str(select_result)])
			quit(1)
			return
		for _index in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var output_path := "%s/%s.png" % [OUTPUT_DIR, String(weapon_id)]
		var image := root.get_texture().get_image()
		var error := image.save_png(ProjectSettings.globalize_path(output_path))
		if error != OK:
			push_error("Shotgun/sniper viewmodel capture failed saving %s: %s" % [output_path, error_string(error)])
			quit(1)
			return
		screenshots[String(weapon_id)] = output_path
	print("SHOTGUN_SNIPER_VIEWMODELS_CAPTURED %s" % str(screenshots))
	quit(0)
