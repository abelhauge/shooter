extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/rooftop_low_ground_fog.png"

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(16):
		await process_frame

	if game.local_player == null:
		push_error("Rooftop fog capture failed: no local player")
		quit(1)
		return

	game.local_player.global_position = Vector3(0.0, 12.5, 28.0)
	game.local_player.velocity = Vector3.ZERO
	game.local_player.yaw = 0.0
	game.local_player.pitch = deg_to_rad(-33.0)
	game.local_player.rotation.y = game.local_player.yaw
	game.local_player.head_pivot.rotation.x = game.local_player.pitch
	game.local_player.set_physics_process(false)
	for _index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Rooftop fog capture failed: %s" % error_string(error))
		quit(1)
		return
	print("ROOFTOP_FOG_CAPTURED %s" % OUTPUT_PATH)
	quit(0)
