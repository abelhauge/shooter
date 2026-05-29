extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(16):
		await process_frame
	if not game.has_method("run_taser_gun_smoke_check"):
		_fail("game scene has no taser gun smoke hook")
		return
	var report: Dictionary = await game.run_taser_gun_smoke_check()
	if not bool(report.get("ok", false)):
		_fail("taser gun smoke failed: %s" % str(report))
		return
	print("TASER_GUN_PASS stun=%.2f cooldown=%.2f health_before=%.1f health_after=%.1f" % [
		float(report.get("dummy_stun_remaining_sec", 0.0)),
		float(report.get("cooldown_after", 0.0)),
		float(report.get("dummy_health_before", -1.0)),
		float(report.get("dummy_health_after", -1.0)),
	])
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
