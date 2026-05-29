extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	var default_game := GAME_ROOT_SCENE.instantiate()
	root.add_child(default_game)
	for _index in range(10):
		await physics_frame
	var default_summary: Dictionary = default_game.get_runtime_smoke_summary()
	if bool(default_summary.get("has_balance_dummy", false)):
		_fail("balance dummy spawned in default game: %s" % str(default_summary))
		return
	default_game.queue_free()
	for _index in range(2):
		await process_frame

	var dev_game := GAME_ROOT_SCENE.instantiate()
	dev_game.set_dev_balance_dummy_enabled(true)
	root.add_child(dev_game)
	for _index in range(10):
		await physics_frame
	var dev_summary: Dictionary = dev_game.get_runtime_smoke_summary()
	if not bool(dev_summary.get("has_balance_dummy", false)):
		_fail("balance dummy missing when dev flag is enabled: %s" % str(dev_summary))
		return
	dev_game.set_dev_balance_dummy_enabled(false)
	for _index in range(2):
		await process_frame
	var disabled_summary: Dictionary = dev_game.get_runtime_smoke_summary()
	if bool(disabled_summary.get("has_balance_dummy", false)):
		_fail("balance dummy was not removed after disabling dev flag: %s" % str(disabled_summary))
		return
	print("DEV_BALANCE_DUMMY_SCOPE_PASS default=false dev=true disabled=false")
	quit(0)

func _fail(message: String) -> void:
	push_error("Dev balance dummy scope validation failed: %s" % message)
	quit(1)
