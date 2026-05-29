extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	var game := GAME_ROOT_SCENE.instantiate()
	game.set_dev_balance_dummy_enabled(true)
	root.add_child(game)
	for _index in range(18):
		await physics_frame
	var dummy := _find_balance_dummy()
	if dummy == null:
		_fail("balance dummy missing")
		return
	var weapon_controller: WeaponController = game.local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"assault_rifle")
	if not bool(select_result.get("ok", false)):
		_fail("could not select assault rifle: %s" % str(select_result))
		return

	dummy.call("reset_target")
	var offline_result := await _fire_rifle_burst_at_dummy(game, weapon_controller, dummy, false)
	if not bool(offline_result.get("damaged", false)):
		_fail("offline assault rifle did no dummy damage: %s" % str(offline_result))
		return
	if not bool(offline_result.get("feedback_count_ok", false)):
		_fail("offline assault rifle did not trigger feedback per shot: %s" % str(offline_result))
		return

	dummy.call("reset_target")
	var multiplayer_result := await _fire_rifle_burst_at_dummy(game, weapon_controller, dummy, true)
	if not bool(multiplayer_result.get("damaged", false)):
		_fail("multiplayer-enabled assault rifle did no dummy damage: %s" % str(multiplayer_result))
		return
	if not bool(multiplayer_result.get("feedback_count_ok", false)):
		_fail("multiplayer-enabled assault rifle did not trigger feedback per shot: %s" % str(multiplayer_result))
		return

	print("ASSAULT_RIFLE_DAMAGE_PASS offline=%s multiplayer=%s" % [str(offline_result), str(multiplayer_result)])
	quit(0)

func _find_balance_dummy() -> Node3D:
	var dummies := get_nodes_in_group("balance_dummies")
	if dummies.is_empty() or not (dummies[0] is Node3D):
		return null
	return dummies[0] as Node3D

func _fire_rifle_burst_at_dummy(game: Node, weapon_controller: WeaponController, dummy: Node3D, multiplayer_enabled: bool) -> Dictionary:
	weapon_controller.set_multiplayer_combat_enabled(multiplayer_enabled)
	var definition := weapon_controller.get_active_definition()
	var state := weapon_controller.get_active_state()
	state.is_reloading = false
	state.cooldown_remaining_sec = 0.0
	state.ammo_in_mag = definition.magazine_size
	var target := dummy.global_position + Vector3(0.0, 0.78, 0.0)
	var camera_position := target + Vector3(0.0, 0.0, 2.35)
	game.call("_apply_local_player_capture_pose", {
		"position": camera_position - Vector3(0.0, game.local_player.head_pivot.position.y, 0.0),
		"target": target,
	}, Vector3.ZERO, 0.0, 0.0)
	for _index in range(2):
		await physics_frame
	var health_before := float(dummy.get("current_health"))
	var feedback_before := weapon_controller.get_fire_feedback_count_for_verification()
	var fire_results := []
	for _shot in range(3):
		state.cooldown_remaining_sec = 0.0
		fire_results.append(weapon_controller.call("_try_fire_active_weapon", definition, state, game.local_player.camera))
		for _index in range(2):
			await physics_frame
	var health_after := float(dummy.get("current_health"))
	var feedback_after := weapon_controller.get_fire_feedback_count_for_verification()
	return {
		"multiplayer_enabled": multiplayer_enabled,
		"damaged": health_after < health_before,
		"feedback_count_ok": feedback_after - feedback_before == 3,
		"feedback_before": feedback_before,
		"feedback_after": feedback_after,
		"health_before": health_before,
		"health_after": health_after,
		"fire_results": fire_results,
	}

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
