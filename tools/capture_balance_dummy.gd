extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/balance_dummy_head_target.png"

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(18):
		await physics_frame
	var dummy := _find_balance_dummy()
	if dummy == null:
		push_error("Balance dummy capture failed: missing balance dummy")
		quit(1)
		return
	var weapon_controller: WeaponController = game.local_player.get_weapon_controller()
	weapon_controller.select_weapon_for_verification(&"sniper")
	var target := dummy.global_position + Vector3(0.0, 1.30, 0.0)
	game.call("_apply_local_player_capture_pose", {
		"position": dummy.global_position + Vector3(0.0, 0.15, 6.0),
		"target": target,
	}, Vector3.ZERO, 0.0, 0.0)
	for _index in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Balance dummy capture failed saving %s: %s" % [OUTPUT_PATH, error_string(error)])
		quit(1)
		return
	print("BALANCE_DUMMY_CAPTURED %s" % OUTPUT_PATH)
	quit(0)

func _find_balance_dummy() -> Node3D:
	var dummies := get_nodes_in_group("balance_dummies")
	if dummies.is_empty() or not (dummies[0] is Node3D):
		return null
	return dummies[0] as Node3D
