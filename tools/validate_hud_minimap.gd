extends SceneTree

const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/hud_enemy_minimap.png"

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	root.size = Vector2i(1280, 720)
	var game := GAME_ROOT_SCENE.instantiate()
	game.set_dev_balance_dummy_enabled(true)
	root.add_child(game)
	for _index in range(20):
		await process_frame

	if game.hud == null or not game.hud.has_method("get_runtime_smoke_summary"):
		push_error("HUD minimap validation failed: missing HUD summary")
		quit(1)
		return
	var summary: Dictionary = game.hud.get_runtime_smoke_summary()
	if not bool(summary.get("has_minimap", false)):
		push_error("HUD minimap validation failed: minimap missing")
		quit(1)
		return
	if int(summary.get("minimap_target_count", 0)) < 1:
		push_error("HUD minimap validation failed: no enemy target on map: %s" % str(summary))
		quit(1)
		return
	var minimap := game.hud.get_node_or_null("HudRoot/EnemyMiniMap") as Control
	if minimap == null:
		push_error("HUD minimap validation failed: EnemyMiniMap node missing")
		quit(1)
		return
	var viewport_size := root.get_visible_rect().size
	var map_rect := Rect2(minimap.get_global_transform_with_canvas().origin, minimap.size)
	var expected_top_right := viewport_size.x - map_rect.end.x <= 20.0 and map_rect.position.y >= 90.0
	if not expected_top_right:
		push_error("HUD minimap validation failed: unexpected placement %s viewport=%s" % [str(map_rect), str(viewport_size)])
		quit(1)
		return

	if DisplayServer.get_name() == "headless":
		print("HUD_MINIMAP_VALIDATION_PASS targets=%d range=%.1f screenshot=skipped-headless" % [
			int(summary.get("minimap_target_count", 0)),
			float(summary.get("minimap_range_m", 0.0)),
		])
		quit(0)
		return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("HUD minimap validation failed to save screenshot: %s" % error_string(error))
		quit(1)
		return
	print("HUD_MINIMAP_VALIDATION_PASS targets=%d range=%.1f screenshot=%s" % [
		int(summary.get("minimap_target_count", 0)),
		float(summary.get("minimap_range_m", 0.0)),
		OUTPUT_PATH,
	])
	quit(0)
