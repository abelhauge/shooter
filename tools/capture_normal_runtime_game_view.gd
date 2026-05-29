extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/normal_runtime_no_generated_artifacts.png"

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(16):
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Normal runtime capture failed: %s" % error_string(error))
		quit(1)
		return
	print("NORMAL_RUNTIME_CAPTURED %s" % OUTPUT_PATH)
	quit(0)
