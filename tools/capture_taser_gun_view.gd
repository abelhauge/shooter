extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/taser_gun_viewmodel.png"

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(16):
		await process_frame
	var weapon_controller: WeaponController = game.local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"taser_gun")
	if not bool(select_result.get("ok", false)):
		push_error("Taser gun capture failed to select weapon: %s" % str(select_result))
		quit(1)
		return
	for _index in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Taser gun capture failed: %s" % error_string(error))
		quit(1)
		return
	print("TASER_GUN_CAPTURED %s" % OUTPUT_PATH)
	quit(0)
