extends SceneTree

const GAME_SCENE := preload("res://scenes/game/game_root.tscn")
const OUTPUT_PATH := "res://docs/verification/screenshots/player_identity_hud.png"

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	root.size = Vector2i(1280, 720)
	var game := GAME_SCENE.instantiate()
	game.set_local_player_name("Abel")
	root.add_child(game)

	for _index in range(24):
		await process_frame

	game.smoke_seed_remote_player_for_hud(4242, "Rival", 2, 3, 1)

	for _index in range(18):
		await process_frame

	var summary: Dictionary = game.hud.get_runtime_smoke_summary()
	var players_text := String(summary.get("players_text", ""))
	if not players_text.contains("Abel") or not players_text.contains("Rival") or not players_text.contains("3/1"):
		push_error("Player identity HUD validation failed: %s" % players_text)
		quit(1)
		return

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		if error != OK:
			push_error("Player identity HUD screenshot failed: %s" % error_string(error))
			quit(1)
			return

	print("PLAYER_IDENTITY_HUD_PASS players=%s screenshot=%s" % [
		players_text.replace("\n", " | "),
		OUTPUT_PATH if DisplayServer.get_name() != "headless" else "skipped-headless",
	])
	quit(0)
