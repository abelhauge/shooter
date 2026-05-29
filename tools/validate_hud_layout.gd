extends SceneTree

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const SCREENSHOT_PATH := "res://docs/verification/screenshots/hud_crosshair_fullscreen_check.png"
const TRUE_FULLSCREEN_SCREENSHOT_PATH := "res://docs/verification/screenshots/hud_crosshair_true_fullscreen_check.png"
const VIEWPORT_SIZES := [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(1440, 900),
]

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	for viewport_size in VIEWPORT_SIZES:
		var result := await _validate_viewport_size(viewport_size)
		if not bool(result.get("ok", false)):
			push_error("HUD layout validation failed: %s" % str(result))
			quit(1)
			return
	var fullscreen_result := {"ok": true, "skipped": true}
	if DisplayServer.get_name() != "headless":
		fullscreen_result = await _validate_true_fullscreen()
		if not bool(fullscreen_result.get("ok", false)):
			push_error("HUD fullscreen layout validation failed: %s" % str(fullscreen_result))
			quit(1)
			return
	print("HUD_LAYOUT_VALIDATION_PASS sizes=%s screenshot=%s fullscreen=%s" % [
		str(VIEWPORT_SIZES),
		SCREENSHOT_PATH,
		str(fullscreen_result),
	])
	quit(0)

func _validate_viewport_size(viewport_size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var hud := HUD_SCENE.instantiate()
	viewport.add_child(hud)
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

	var hud_root := hud.get_node_or_null("HudRoot") as Control
	var crosshair_root := hud.get_node_or_null("HudRoot/CrosshairRoot") as Control
	if hud_root == null or crosshair_root == null:
		viewport.queue_free()
		return {
			"ok": false,
			"viewport_size": viewport_size,
			"error": "missing HudRoot or CrosshairRoot",
		}

	var expected_center := Vector2(viewport_size) * 0.5
	var actual_center := crosshair_root.get_global_transform_with_canvas().origin
	var center_delta := actual_center - expected_center
	var ok := center_delta.length() <= 0.5
	if viewport_size == Vector2i(1920, 1080) and DisplayServer.get_name() != "headless":
		var error := viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
		if error != OK:
			ok = false
			center_delta = Vector2.INF
	viewport.queue_free()
	return {
		"ok": ok,
		"viewport_size": viewport_size,
		"hud_root_size": hud_root.size,
		"expected_center": expected_center,
		"actual_center": actual_center,
		"center_delta": center_delta,
	}

func _validate_true_fullscreen() -> Dictionary:
	var previous_mode := DisplayServer.window_get_mode()
	var previous_size := DisplayServer.window_get_size()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var hud := HUD_SCENE.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var crosshair_root := hud.get_node_or_null("HudRoot/CrosshairRoot") as Control
	var viewport_size := root.get_visible_rect().size
	var expected_center := viewport_size * 0.5
	var actual_center := Vector2.INF
	var center_delta := Vector2.INF
	var ok := crosshair_root != null
	if crosshair_root != null:
		actual_center = crosshair_root.get_global_transform_with_canvas().origin
		center_delta = actual_center - expected_center
		ok = center_delta.length() <= 0.5
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(TRUE_FULLSCREEN_SCREENSHOT_PATH))
	if error != OK:
		ok = false

	hud.queue_free()
	await process_frame
	DisplayServer.window_set_mode(previous_mode)
	if previous_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(previous_size)
	return {
		"ok": ok,
		"viewport_size": viewport_size,
		"expected_center": expected_center,
		"actual_center": actual_center,
		"center_delta": center_delta,
		"screenshot": TRUE_FULLSCREEN_SCREENSHOT_PATH,
	}
