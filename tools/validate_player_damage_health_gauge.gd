extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const SCREENSHOT_PATH := "res://docs/verification/screenshots/player_damage_health_gauge.png"

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	root.size = Vector2i(1280, 720)
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(18):
		await physics_frame
	if game.local_player == null:
		_fail("local player missing")
		return
	if game.hud == null:
		_fail("HUD missing")
		return

	var health: HealthComponent = game.local_player.get_health_component()
	health.spawn_protection_remaining_sec = 0.0
	var event := DamageEvent.new()
	event.amount = 37.0
	event.weapon_id = &"validation_hit"
	event.hit_position = game.local_player.global_position + Vector3(0.0, 0.9, 0.0)
	event.hit_normal = Vector3.FORWARD
	var killed: bool = game.local_player.apply_damage(event)
	for _index in range(4):
		await process_frame
	var summary: Dictionary = game.hud.get_runtime_smoke_summary()
	var gauge_text := String(summary.get("health_gauge_text", ""))
	var gauge_width := float(summary.get("health_gauge_value", 0.0))
	if killed:
		_fail("37 damage should not kill the player")
		return
	if absf(health.current_health - 63.0) > 0.01:
		_fail("player health did not drop to 63 after damage: %.2f" % health.current_health)
		return
	if not bool(summary.get("has_health_gauge", false)):
		_fail("HUD health gauge missing")
		return
	if not gauge_text.contains("63") or gauge_width <= 0.0 or gauge_width >= 270.0:
		_fail("HUD health gauge did not reflect damage: text=%s width=%.2f" % [gauge_text, gauge_width])
		return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
		if error != OK:
			_fail("could not save screenshot %s: %s" % [SCREENSHOT_PATH, error_string(error)])
			return
	print("PLAYER_DAMAGE_HEALTH_GAUGE_PASS health=%.1f gauge=%s width=%.1f screenshot=%s" % [
		health.current_health,
		gauge_text,
		gauge_width,
		SCREENSHOT_PATH if DisplayServer.get_name() != "headless" else "skipped-headless",
	])
	quit(0)

func _fail(message: String) -> void:
	push_error("Player damage health gauge validation failed: %s" % message)
	quit(1)
