extends SceneTree

const REMOTE_PROXY_SCENE := preload("res://scenes/player/remote_player_proxy.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/remote_player_proxy_visuals.png"

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)

	var proxy: RemotePlayerProxy = REMOTE_PROXY_SCENE.instantiate()
	proxy.peer_id = 2
	world.add_child(proxy)
	proxy.global_position = Vector3.ZERO
	proxy.apply_combat_state(2, 100.0, true)
	proxy.apply_snapshot(Vector3.ZERO, 0.0, 0.0, &"grounded", &"primary")

	var camera := Camera3D.new()
	camera.name = "ValidationCamera"
	camera.position = Vector3(0.0, 1.25, -4.2)
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)

	var light := DirectionalLight3D.new()
	light.name = "ValidationKeyLight"
	light.rotation_degrees = Vector3(-48.0, 28.0, 0.0)
	light.light_energy = 2.0
	world.add_child(light)

	for _index in range(30):
		await process_frame

	var summary := proxy.get_runtime_summary()
	if bool(summary.get("uses_fallback_body", true)):
		_fail("remote proxy is still using fallback capsule body: %s" % str(summary))
		return
	if bool(summary.get("uses_fallback_weapon_box", true)):
		_fail("remote proxy is still using fallback weapon box: %s" % str(summary))
		return
	if bool(summary.get("has_team_marker_plates", true)):
		_fail("remote proxy still has extra team marker plates: %s" % str(summary))
		return
	if not bool(summary.get("has_humanoid_mesh", false)):
		_fail("remote proxy did not load humanoid mesh: %s" % str(summary))
		return
	if not bool(summary.get("has_remote_weapon_asset", false)):
		_fail("remote proxy did not load real remote weapon asset: %s" % str(summary))
		return
	if not bool(summary.get("has_animation_player", false)) or String(summary.get("active_animation", "")) == "":
		_fail("remote proxy did not use character rig animations: %s" % str(summary))
		return
	if absf(float(summary.get("avatar_yaw_correction_degrees", 0.0)) - 180.0) > 0.1:
		_fail("remote proxy missing 180 degree avatar facing correction: %s" % str(summary))
		return

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		if error != OK:
			_fail("could not save screenshot %s: %s" % [OUTPUT_PATH, error_string(error)])
			return
		print("REMOTE_PROXY_VISUALS_PASS screenshot=%s summary=%s" % [OUTPUT_PATH, str(summary)])
	else:
		print("REMOTE_PROXY_VISUALS_PASS screenshot=skipped-headless summary=%s" % str(summary))
	quit(0)

func _fail(message: String) -> void:
	push_error("Remote proxy visual validation failed: %s" % message)
	quit(1)
