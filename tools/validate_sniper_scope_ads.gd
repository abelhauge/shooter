extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	Input.action_release(FpsInputActions.FIRE_PRIMARY)
	Input.action_release(FpsInputActions.FIRE_SECONDARY)
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(16):
		await process_frame
	if game.local_player == null or game.hud == null:
		_fail("sniper ADS validation missing local player or HUD")
		return
	var weapon_controller: WeaponController = game.local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"sniper")
	if not bool(select_result.get("ok", false)):
		_fail("sniper ADS validation could not select sniper: %s" % str(select_result))
		return
	var state := weapon_controller.get_active_state()
	state.is_reloading = false
	state.cooldown_remaining_sec = 0.0
	state.ammo_in_mag = weapon_controller.get_active_definition().magazine_size
	var default_fov: float = game.local_player.camera.fov
	Input.action_press(FpsInputActions.FIRE_SECONDARY)
	for _index in range(18):
		await physics_frame
	for _index in range(4):
		await process_frame
	var scope_summary := weapon_controller.get_sniper_scope_summary()
	var hud_summary: Dictionary = game.hud.get_runtime_smoke_summary()
	var scoped_fov: float = game.local_player.camera.fov
	if float(scope_summary.get("scope_progress", 0.0)) < 0.95:
		_fail("sniper ADS did not reach full scope: %s" % str(scope_summary))
		return
	if not bool(hud_summary.get("sniper_scope_visible", false)):
		_fail("sniper ADS HUD overlay was not visible: %s" % str(hud_summary))
		return
	if bool(hud_summary.get("crosshair_visible", true)):
		_fail("sniper ADS did not hide the normal crosshair: %s" % str(hud_summary))
		return
	if scoped_fov >= default_fov * 0.55:
		_fail("sniper ADS did not zoom enough: default=%.2f scoped=%.2f" % [default_fov, scoped_fov])
		return
	if float(scope_summary.get("sensitivity_multiplier", 1.0)) > 0.45:
		_fail("sniper ADS sensitivity multiplier too high: %s" % str(scope_summary))
		return
	var ammo_before := state.ammo_in_mag
	Input.action_press(FpsInputActions.FIRE_PRIMARY)
	await physics_frame
	Input.action_release(FpsInputActions.FIRE_PRIMARY)
	for _index in range(4):
		await physics_frame
	var ammo_after := state.ammo_in_mag
	Input.action_release(FpsInputActions.FIRE_SECONDARY)
	for _index in range(18):
		await physics_frame
	for _index in range(4):
		await process_frame
	var post_scope_summary := weapon_controller.get_sniper_scope_summary()
	var post_hud_summary: Dictionary = game.hud.get_runtime_smoke_summary()
	var restored_fov: float = game.local_player.camera.fov
	if ammo_after != ammo_before - 1:
		_fail("sniper ADS release did not fire one shot: ammo_before=%d ammo_after=%d" % [ammo_before, ammo_after])
		return
	if float(post_scope_summary.get("scope_progress", 1.0)) > 0.05:
		_fail("sniper ADS did not lower scope after release: %s" % str(post_scope_summary))
		return
	if bool(post_hud_summary.get("sniper_scope_visible", true)):
		_fail("sniper ADS HUD overlay stayed visible after release: %s" % str(post_hud_summary))
		return
	if not bool(post_hud_summary.get("crosshair_visible", false)):
		_fail("sniper ADS did not restore normal crosshair after release: %s" % str(post_hud_summary))
		return
	if absf(restored_fov - default_fov) > 0.5:
		_fail("sniper ADS did not restore FOV: default=%.2f restored=%.2f" % [default_fov, restored_fov])
		return
	print("SNIPER_SCOPE_ADS_PASS scoped_fov=%.2f restored_fov=%.2f sensitivity=%.2f" % [
		scoped_fov,
		restored_fov,
		float(scope_summary.get("sensitivity_multiplier", 1.0)),
	])
	quit(0)

func _fail(message: String) -> void:
	Input.action_release(FpsInputActions.FIRE_PRIMARY)
	Input.action_release(FpsInputActions.FIRE_SECONDARY)
	push_error(message)
	quit(1)
