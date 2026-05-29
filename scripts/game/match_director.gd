class_name MatchDirector
extends Node

signal match_state_changed(summary: Dictionary)
signal player_respawned(player: PlayerController)

@export var rules: MatchRulesDefinition = preload("res://data/match/team_skirmish_v1.tres")

var match_phase: StringName = &"waiting"
var remaining_time_sec := 0.0
var blue_score := 0
var orange_score := 0
var winning_team_id := 0

var _local_player: PlayerController
var _spawn_points: Array[SpawnPoint] = []
var _respawn_remaining := -1.0

func configure(local_player: PlayerController, spawn_points: Array[SpawnPoint]) -> void:
	_local_player = local_player
	_spawn_points = spawn_points
	if not _local_player.get_health_component().died.is_connected(_on_local_player_died):
		_local_player.get_health_component().died.connect(_on_local_player_died)
	start_match()

func start_match() -> void:
	match_phase = &"playing"
	remaining_time_sec = rules.time_limit_sec
	blue_score = 0
	orange_score = 0
	winning_team_id = 0
	_respawn_remaining = -1.0
	respawn_player(_local_player, 1)
	_emit_summary()

func _physics_process(delta: float) -> void:
	if match_phase != &"playing":
		return
	remaining_time_sec = maxf(0.0, remaining_time_sec - delta)
	if remaining_time_sec <= 0.0:
		_finish_match()
		return
	if _respawn_remaining >= 0.0:
		_respawn_remaining -= delta
		if _respawn_remaining <= 0.0:
			respawn_player(_local_player, 1)
			_respawn_remaining = -1.0
	_emit_summary()

func record_kill(scoring_team_id: int) -> void:
	if match_phase != &"playing":
		return
	if scoring_team_id == 1:
		blue_score += 1
	elif scoring_team_id == 2:
		orange_score += 1
	if blue_score >= rules.score_limit or orange_score >= rules.score_limit:
		_finish_match()
	else:
		_emit_summary()

func respawn_player(player: PlayerController, team_id: int) -> void:
	if player == null:
		return
	if player == _local_player:
		_respawn_remaining = -1.0
	var spawn := _choose_spawn(team_id)
	if spawn != null:
		spawn.apply_to_player(player)
	player.get_health_component().spawn_protection_duration_sec = rules.spawn_protection_sec
	player.get_health_component().reset_health(true)
	player.get_weapon_controller().reset_loadout()
	player_respawned.emit(player)
	_emit_summary()

func get_summary() -> Dictionary:
	return {
		"phase": match_phase,
		"remaining_time_sec": remaining_time_sec,
		"blue_score": blue_score,
		"orange_score": orange_score,
		"score_limit": rules.score_limit,
		"winning_team_id": winning_team_id,
	}

func apply_network_summary(summary: Dictionary) -> void:
	match_phase = summary.get("phase", match_phase)
	remaining_time_sec = float(summary.get("remaining_time_sec", remaining_time_sec))
	blue_score = int(summary.get("blue_score", blue_score))
	orange_score = int(summary.get("orange_score", orange_score))
	winning_team_id = int(summary.get("winning_team_id", winning_team_id))
	_emit_summary()

func _choose_spawn(team_id: int) -> SpawnPoint:
	var candidates: Array[SpawnPoint] = []
	for spawn in _spawn_points:
		if spawn.is_enabled and spawn.team_id == team_id:
			candidates.append(spawn)
	if candidates.is_empty():
		return null
	return candidates.pick_random()

func _on_local_player_died(_event: DamageEvent) -> void:
	if match_phase != &"playing":
		return
	orange_score += 1
	_respawn_remaining = rules.respawn_delay_sec
	if orange_score >= rules.score_limit:
		_finish_match()
	else:
		_emit_summary()

func _finish_match() -> void:
	match_phase = &"results"
	if blue_score > orange_score:
		winning_team_id = 1
	elif orange_score > blue_score:
		winning_team_id = 2
	else:
		winning_team_id = 0
	_emit_summary()

func _emit_summary() -> void:
	match_state_changed.emit(get_summary())
