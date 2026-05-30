extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var player = game.get("local_player")
	if player == null:
		_fail("missing local player")
		return
	var weapon_controller = player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"flamethrower")
	if not bool(select_result.get("ok", false)):
		_fail("could not select flamethrower: %s" % str(select_result))
		return
	player.velocity = Vector3.ZERO
	var ammo_before := int(weapon_controller.get_active_summary().get("ammo_in_mag", 0))
	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(player.camera, true)
	var ammo_after := int(weapon_controller.get_active_summary().get("ammo_in_mag", 0))
	var propulsion: Dictionary = fire_result.get("primary_fire_propulsion", {})
	var velocity_after: Vector3 = propulsion.get("velocity_after", Vector3.ZERO)
	if not bool(fire_result.get("ok", false)):
		_fail("primary fire failed: %s" % str(fire_result))
		return
	if ammo_after >= ammo_before:
		_fail("flamethrower primary propulsion did not consume fuel: before=%d after=%d" % [ammo_before, ammo_after])
		return
	if (
		not bool(propulsion.get("uses_primary_fire_fuel", false))
		or velocity_after.y < 1.5
		or velocity_after.y > 2.4
	):
		_fail("flamethrower primary propulsion outside tuned lift range: %s" % str(propulsion))
		return
	var fire_direction: Vector3 = propulsion.get("fire_direction", Vector3.FORWARD)
	var horizontal_fire_direction := Vector3(fire_direction.x, 0.0, fire_direction.z).normalized()
	var horizontal_velocity := Vector3(velocity_after.x, 0.0, velocity_after.z)
	if horizontal_velocity.length() > 2.0:
		_fail("flamethrower primary recoil outside tuned horizontal range: %s" % str(propulsion))
		return
	if horizontal_velocity.dot(horizontal_fire_direction) >= -0.25:
		_fail("flamethrower forward shot should recoil backward, not forward: %s" % str(propulsion))
		return
	if String(weapon_controller.get_active_definition().alt_action_type) != "":
		_fail("flamethrower should not use secondary-fire alt action")
		return
	print("FLAMETHROWER_PRIMARY_PROPULSION_PASS ammo_before=%d ammo_after=%d velocity_after=%s" % [
		ammo_before,
		ammo_after,
		str(velocity_after),
	])
	quit(0)

func _fail(message: String) -> void:
	push_error("Flamethrower primary propulsion validation failed: %s" % message)
	quit(1)
