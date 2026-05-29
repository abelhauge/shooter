extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/smoke_bomb_larger_volume.png"

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(16):
		await process_frame

	if game.local_player == null:
		push_error("Smoke bomb capture failed: missing local player")
		quit(1)
		return
	var weapon_controller = game.local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"smoke_bomb")
	if not bool(select_result.get("ok", false)):
		push_error("Smoke bomb capture failed: %s" % str(select_result))
		quit(1)
		return
	if game.has_method("_apply_local_player_capture_pose"):
		game.call("_apply_local_player_capture_pose", {
			"position": Vector3(0.0, 1.0, 5.0),
			"target": Vector3(0.0, 0.35, 0.0),
		}, Vector3.ZERO, 0.0, 0.0)

	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(game.local_player.camera)
	if not bool(fire_result.get("ok", false)):
		push_error("Smoke bomb capture fire failed: %s" % str(fire_result))
		quit(1)
		return
	var smoke := await _wait_for_smoke_volume(game, 240)
	if smoke == null:
		push_error("Smoke bomb capture failed: no smoke volume spawned")
		quit(1)
		return
	for _index in range(45):
		await physics_frame
	game.local_player.global_position = smoke.global_position + Vector3(0.0, 6.0, 9.0)
	game.local_player.velocity = Vector3.ZERO
	game.local_player.look_at(smoke.global_position + Vector3(0.0, 1.8, 0.0), Vector3.UP)
	game.local_player.yaw = game.local_player.rotation.y
	game.local_player.pitch = deg_to_rad(-24.0)
	game.local_player.head_pivot.rotation.x = game.local_player.pitch
	game.local_player.get_health_component().force_network_state(100.0, true, 3.0)
	game.local_player.movement_state = &"grounded"
	game.local_player.set_physics_process(false)
	for _index in range(8):
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Smoke bomb capture failed: %s" % error_string(error))
		quit(1)
		return
	print("SMOKE_BOMB_CAPTURED %s" % OUTPUT_PATH)
	quit(0)

func _wait_for_smoke_volume(game: Node, max_frames: int) -> Node:
	for _index in range(max_frames):
		if game.effects_root != null:
			for child in game.effects_root.get_children():
				if String(child.name).begins_with("SmokeVolume"):
					return child
		await physics_frame
	return null
