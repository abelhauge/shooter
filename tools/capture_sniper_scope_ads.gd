extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/sniper_scope_ads.png"

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	Input.action_release(FpsInputActions.FIRE_PRIMARY)
	Input.action_release(FpsInputActions.FIRE_SECONDARY)
	root.size = Vector2i(1280, 720)
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(16):
		await process_frame
	if game.local_player == null or game.hud == null:
		push_error("Sniper scope capture failed: missing local player or HUD")
		quit(1)
		return
	game.local_player.get_health_component().force_network_state(100.0, true, 3.0)
	game.local_player.movement_state = &"grounded"
	var weapon_controller: WeaponController = game.local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"sniper")
	if not bool(select_result.get("ok", false)):
		push_error("Sniper scope capture failed selecting sniper: %s" % str(select_result))
		quit(1)
		return
	Input.action_press(FpsInputActions.FIRE_SECONDARY)
	for _index in range(18):
		await physics_frame
	for _index in range(8):
		await process_frame
	var scope_summary := weapon_controller.get_sniper_scope_summary()
	var hud_summary: Dictionary = game.hud.get_runtime_smoke_summary()
	if not bool(scope_summary.get("scope_visible", false)) or not bool(hud_summary.get("sniper_scope_visible", false)):
		Input.action_release(FpsInputActions.FIRE_SECONDARY)
		push_error("Sniper scope capture failed: scope not visible before screenshot weapon=%s hud=%s" % [str(scope_summary), str(hud_summary)])
		quit(1)
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	Input.action_release(FpsInputActions.FIRE_SECONDARY)
	if error != OK:
		push_error("Sniper scope capture failed saving %s: %s" % [OUTPUT_PATH, error_string(error)])
		quit(1)
		return
	print("SNIPER_SCOPE_ADS_CAPTURED %s" % OUTPUT_PATH)
	quit(0)
