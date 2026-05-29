extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const SMOKE_DEFINITION := preload("res://data/weapons/smoke_bomb.tres")

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(16):
		await process_frame

	if game.local_player == null:
		_fail("missing local player")
		return
	var weapon_controller = game.local_player.get_weapon_controller()
	var select_result: Dictionary = weapon_controller.select_weapon_for_verification(&"smoke_bomb")
	if not bool(select_result.get("ok", false)):
		_fail("could not select smoke bomb: %s" % str(select_result))
		return
	if game.has_method("_apply_local_player_capture_pose"):
		game.call("_apply_local_player_capture_pose", {
			"position": Vector3(0.0, 1.0, 5.0),
			"target": Vector3(0.0, 0.35, 0.0),
		}, Vector3.ZERO, 0.0, 0.0)

	var fire_result: Dictionary = weapon_controller.fire_active_weapon_for_verification(game.local_player.camera)
	if not bool(fire_result.get("ok", false)):
		_fail("smoke bomb fire failed: %s" % str(fire_result))
		return

	var smoke := await _wait_for_smoke_volume(game, 240)
	if smoke == null:
		_fail("smoke bomb did not spawn a smoke volume")
		return
	for _index in range(45):
		await physics_frame

	var summary := _smoke_summary(smoke)
	var radius := float(summary.get("radius", 0.0))
	var lifetime_sec := float(summary.get("lifetime_sec", 0.0))
	var growth_time_sec := float(summary.get("growth_time_sec", 999.0))
	var smoke_scale: Vector3 = summary.get("scale", Vector3.ZERO)
	if radius < 3.95:
		_fail("smoke radius is too small: %.2f" % radius)
		return
	if lifetime_sec < 13.9:
		_fail("smoke lifetime is too short: %.2f" % lifetime_sec)
		return
	if growth_time_sec > 0.75:
		_fail("smoke growth is too slow: %.2f" % growth_time_sec)
		return
	if smoke_scale.x < 1.0:
		_fail("smoke did not grow to full readable size quickly: %s" % str(summary))
		return

	print("SMOKE_BOMB_TUNING_PASS radius=%.2f lifetime=%.2f growth=%.2f scale=%s definition_radius=%.2f definition_lifetime=%.2f" % [
		radius,
		lifetime_sec,
		growth_time_sec,
		str(smoke_scale),
		SMOKE_DEFINITION.effect_radius_m,
		SMOKE_DEFINITION.effect_duration_sec,
	])
	quit(0)

func _wait_for_smoke_volume(game: Node, max_frames: int) -> Node:
	for _index in range(max_frames):
		var smoke := _first_smoke_volume(game)
		if smoke != null:
			return smoke
		await physics_frame
	return null

func _first_smoke_volume(game: Node) -> Node:
	if game.effects_root == null:
		return null
	for child in game.effects_root.get_children():
		if String(child.name).begins_with("SmokeVolume"):
			return child
	return null

func _smoke_summary(smoke: Node) -> Dictionary:
	if smoke.has_method("get_runtime_summary"):
		return smoke.get_runtime_summary()
	return {}

func _fail(message: String) -> void:
	push_error("Smoke bomb tuning validation failed: %s" % message)
	quit(1)
