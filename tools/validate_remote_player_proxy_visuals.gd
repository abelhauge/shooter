extends SceneTree

const REMOTE_PROXY_SCENE := preload("res://scenes/player/remote_player_proxy.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/remote_player_proxy_visuals.png"
const STATES_OUTPUT_PATH := "res://docs/verification/screenshots/remote_player_proxy_animation_states.png"

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)

	var proxy := _create_proxy(world, 2, 2, Vector3.ZERO, &"grounded", &"primary")

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
	if not _validate_proxy_summary(summary, "idle"):
		return
	if String(summary.get("active_animation", "")) != "Idle_Gun_Pointing":
		_fail("idle proxy did not play expected rig idle animation: %s" % str(summary))
		return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var idle_error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		if idle_error != OK:
			_fail("could not save screenshot %s: %s" % [OUTPUT_PATH, error_string(idle_error)])
			return

	var state_world := Node3D.new()
	root.add_child(state_world)
	world.visible = false
	var idle_proxy := _create_proxy(state_world, 3, 1, Vector3(-1.45, 0.0, 0.0), &"grounded", &"primary")
	var run_proxy := _create_proxy(state_world, 4, 2, Vector3(0.0, 0.0, 0.0), &"grounded", &"primary")
	var airborne_proxy := _create_proxy(state_world, 5, 2, Vector3(1.45, 0.0, 0.0), &"airborne", &"secondary")
	run_proxy.apply_snapshot(Vector3(0.0, 0.0, -0.6), 0.0, 0.0, &"grounded", &"primary")

	camera.reparent(state_world, false)
	camera.position = Vector3(0.0, 1.25, -4.8)
	camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	light.reparent(state_world, false)

	for _index in range(45):
		await process_frame

	var idle_summary := idle_proxy.get_runtime_summary()
	var run_summary := run_proxy.get_runtime_summary()
	var airborne_summary := airborne_proxy.get_runtime_summary()
	if not _validate_proxy_summary(idle_summary, "state-idle"):
		return
	if not _validate_proxy_summary(run_summary, "state-run"):
		return
	if not _validate_proxy_summary(airborne_summary, "state-airborne"):
		return
	if String(idle_summary.get("active_animation", "")) != "Idle_Gun_Pointing":
		_fail("state idle proxy did not stay in Idle_Gun_Pointing animation: %s" % str(idle_summary))
		return
	if String(run_summary.get("active_animation", "")) != "Run":
		_fail("run proxy did not play Run animation: %s" % str(run_summary))
		return
	if String(airborne_summary.get("active_animation", "")) != "Roll":
		_fail("airborne proxy did not play Roll jump fallback animation: %s" % str(airborne_summary))
		return

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(STATES_OUTPUT_PATH))
		if error != OK:
			_fail("could not save screenshot %s: %s" % [STATES_OUTPUT_PATH, error_string(error)])
			return
		print("REMOTE_PROXY_VISUALS_PASS screenshot=%s states_screenshot=%s summary=%s states=%s" % [OUTPUT_PATH, STATES_OUTPUT_PATH, str(summary), str([idle_summary, run_summary, airborne_summary])])
	else:
		print("REMOTE_PROXY_VISUALS_PASS screenshot=skipped-headless summary=%s states=%s" % [str(summary), str([idle_summary, run_summary, airborne_summary])])
	quit(0)

func _create_proxy(world: Node3D, peer_id: int, team_id: int, position: Vector3, state: StringName, slot: StringName) -> RemotePlayerProxy:
	var proxy: RemotePlayerProxy = REMOTE_PROXY_SCENE.instantiate()
	proxy.peer_id = peer_id
	proxy.position = position
	world.add_child(proxy)
	proxy.global_position = position
	proxy.apply_combat_state(team_id, 100.0, true)
	proxy.apply_snapshot(position, 0.0, 0.0, state, slot)
	return proxy

func _validate_proxy_summary(summary: Dictionary, label: String) -> bool:
	if bool(summary.get("uses_fallback_body", true)):
		_fail("%s proxy is still using fallback capsule body: %s" % [label, str(summary)])
		return false
	if bool(summary.get("uses_fallback_weapon_box", true)):
		_fail("%s proxy is still using fallback weapon box: %s" % [label, str(summary)])
		return false
	if bool(summary.get("has_team_marker_plates", true)):
		_fail("%s proxy still has extra team marker plates: %s" % [label, str(summary)])
		return false
	if not bool(summary.get("has_humanoid_mesh", false)):
		_fail("%s proxy did not load humanoid mesh: %s" % [label, str(summary)])
		return false
	if not bool(summary.get("has_remote_weapon_asset", false)):
		_fail("%s proxy did not load real remote weapon asset: %s" % [label, str(summary)])
		return false
	if not bool(summary.get("remote_weapon_attached_to_avatar", false)):
		_fail("%s proxy weapon is not attached to avatar rig: %s" % [label, str(summary)])
		return false
	if String(summary.get("remote_weapon_attachment_name", "")) != "Wrist.R":
		_fail("%s proxy weapon is not attached to Wrist.R: %s" % [label, str(summary)])
		return false
	if not bool(summary.get("has_animation_player", false)) or String(summary.get("active_animation", "")) == "":
		_fail("%s proxy did not use character rig animations: %s" % [label, str(summary)])
		return false
	if absf(float(summary.get("avatar_yaw_correction_degrees", 0.0)) - 180.0) > 0.1:
		_fail("%s proxy missing 180 degree avatar facing correction: %s" % [label, str(summary)])
		return false
	return true

func _fail(message: String) -> void:
	push_error("Remote proxy visual validation failed: %s" % message)
	quit(1)
