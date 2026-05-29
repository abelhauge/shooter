extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(18):
		await physics_frame
	var dummy := _find_balance_dummy()
	if dummy == null:
		_fail("balance dummy was not spawned")
		return
	if dummy.is_in_group("combat_dummies"):
		_fail("balance dummy should not be in combat score dummy group")
		return
	var weapon_controller: WeaponController = game.local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"sniper")
	if not bool(select_result.get("ok", false)):
		_fail("could not select sniper: %s" % str(select_result))
		return
	var head_result := await _fire_sniper_at(game, weapon_controller, dummy, dummy.global_position + Vector3(0.0, 1.58, 0.0))
	if not bool(head_result.get("ok", false)) or float(dummy.get("current_health")) > 0.0:
		_fail("sniper headshot did not kill balance dummy: result=%s health=%.1f" % [str(head_result), float(dummy.get("current_health"))])
		return
	dummy.call("reset_target")
	var body_result := await _fire_sniper_at(game, weapon_controller, dummy, dummy.global_position + Vector3(0.0, 0.62, 0.0))
	var body_health := float(dummy.get("current_health"))
	if not bool(body_result.get("ok", false)) or absf(body_health - 50.0) > 0.1:
		_fail("sniper body shot should leave dummy at 50 HP: result=%s health=%.1f" % [str(body_result), body_health])
		return
	print("BALANCE_DUMMY_HEADSHOT_PASS head_killed=true body_health=%.1f" % body_health)
	quit(0)

func _find_balance_dummy() -> Node3D:
	var dummies := get_nodes_in_group("balance_dummies")
	if dummies.is_empty() or not (dummies[0] is Node3D):
		return null
	return dummies[0] as Node3D

func _fire_sniper_at(game: Node, weapon_controller: WeaponController, dummy: Node3D, target: Vector3) -> Dictionary:
	var definition := weapon_controller.get_active_definition()
	var state := weapon_controller.get_active_state()
	state.is_reloading = false
	state.cooldown_remaining_sec = 0.0
	state.ammo_in_mag = definition.magazine_size
	var camera_position := target + Vector3(0.0, 0.0, 4.0)
	game.call("_apply_local_player_capture_pose", {
		"position": camera_position - Vector3(0.0, game.local_player.head_pivot.position.y, 0.0),
		"target": target,
	}, Vector3.ZERO, 0.0, 0.0)
	for _index in range(2):
		await physics_frame
	return weapon_controller.fire_active_weapon_for_verification(game.local_player.camera, true)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
