extends SceneTree

const ARENA_SCENE := preload("res://scenes/maps/art/arena_downtown_01_art.tscn")
const GAME_ROOT_SCENE := preload("res://scenes/game/game_root.tscn")

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	var arena := ARENA_SCENE.instantiate()
	root.add_child(arena)
	for _index in range(12):
		await process_frame

	var config: Resource = arena.get_rooftop_map_config()
	if config == null:
		_fail("arena has no rooftop config")
		return
	var spawns: Array[SpawnPoint] = arena.get_spawn_points()
	if spawns.size() < 8:
		_fail("rooftop map exposes too few spawn points: %d" % spawns.size())
		return
	var team_counts := {}
	for spawn in spawns:
		team_counts[spawn.team_id] = int(team_counts.get(spawn.team_id, 0)) + 1
		if spawn.global_position.y <= float(config.fog_surface_y) + 0.5:
			_fail("spawn %s is inside or too close to rooftop fog: y=%.2f fog=%.2f" % [spawn.name, spawn.global_position.y, float(config.fog_surface_y)])
			return
	if int(team_counts.get(1, 0)) < 4 or int(team_counts.get(2, 0)) < 4:
		_fail("rooftop spawn teams need at least 4 each: %s" % str(team_counts))
		return
	arena.queue_free()

	var game := GAME_ROOT_SCENE.instantiate()
	root.add_child(game)
	for _index in range(12):
		await process_frame
	if game.world_environment == null or game.world_environment.environment == null or not game.world_environment.environment.fog_enabled:
		_fail("game world environment fog is not enabled")
		return
	var environment: Environment = game.world_environment.environment
	if environment.fog_density < 0.004:
		_fail("rooftop fog density is too low to read as a bottom fog layer: %.4f" % environment.fog_density)
		return
	if environment.fog_height < 0.6:
		_fail("rooftop fog height is too low to cover low-ground building bases: %.2f" % environment.fog_height)
		return
	if environment.fog_height_density < 8.0:
		_fail("rooftop fog height falloff is too soft near roof height: %.2f" % environment.fog_height_density)
		return
	var fog_visual_root := game.get_node_or_null("MapRoot/LowGroundFogVisuals")
	if fog_visual_root == null:
		_fail("game has no low-ground fog visual root")
		return
	if fog_visual_root.get_child_count() < int(config.fog_layer_count):
		_fail("low-ground fog visual layer count is too low: %d expected %d" % [fog_visual_root.get_child_count(), int(config.fog_layer_count)])
		return
	if game.local_player == null:
		_fail("game has no local player")
		return
	if game.local_player.global_position.y <= float(config.fog_surface_y) + 0.5:
		_fail("local player did not spawn above rooftop fog: y=%.2f fog=%.2f" % [game.local_player.global_position.y, float(config.fog_surface_y)])
		return

	var health: HealthComponent = game.local_player.get_health_component()
	game.local_player.global_position = Vector3(0.0, 0.0, 0.0)
	game.local_player.velocity = Vector3(0.0, -20.0, 0.0)
	health.spawn_protection_remaining_sec = 0.0
	for _index in range(16):
		await physics_frame
	if health.is_alive:
		_fail("local player survived lethal low-ground contact")
		return

	print("ROOFTOP_MAP_CONTRACT_PASS spawns=%d team_counts=%s ground_kill_height=%.2f low_ground_test_y=%.2f fog_density=%.4f fog_height=%.2f fog_height_density=%.2f fog_visual_layers=%d fog_enabled=true" % [
		spawns.size(),
		str(team_counts),
		float(config.ground_kill_height_y),
		game.local_player.global_position.y,
		environment.fog_density,
		environment.fog_height,
		environment.fog_height_density,
		fog_visual_root.get_child_count(),
	])
	quit(0)

func _fail(message: String) -> void:
	push_error("Rooftop map contract failed: %s" % message)
	quit(1)
