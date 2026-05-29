class_name HealthComponent
extends Node

signal damaged(event: DamageEvent, current_health: float)
signal died(event: DamageEvent)
signal reset(current_health: float)

@export var max_health := 100.0
@export var spawn_protection_duration_sec := 1.0

var current_health := 100.0
var is_alive := true
var spawn_protection_remaining_sec := 0.0
var last_damage_source_peer_id := 0
var last_damage_weapon_id: StringName

func _ready() -> void:
	reset_health(false)

func _physics_process(delta: float) -> void:
	if spawn_protection_remaining_sec > 0.0:
		spawn_protection_remaining_sec = maxf(0.0, spawn_protection_remaining_sec - delta)

func reset_health(with_spawn_protection := true) -> void:
	current_health = max_health
	is_alive = true
	last_damage_source_peer_id = 0
	last_damage_weapon_id = &""
	spawn_protection_remaining_sec = spawn_protection_duration_sec if with_spawn_protection else 0.0
	reset.emit(current_health)

func force_network_state(health: float, alive: bool, protection_remaining := 0.0) -> void:
	current_health = clampf(health, 0.0, max_health)
	is_alive = alive
	spawn_protection_remaining_sec = maxf(0.0, protection_remaining)

func apply_damage(event: DamageEvent) -> bool:
	if not is_alive or spawn_protection_remaining_sec > 0.0:
		return false
	current_health = maxf(0.0, current_health - event.amount)
	last_damage_source_peer_id = event.source_peer_id
	last_damage_weapon_id = event.weapon_id
	damaged.emit(event, current_health)
	if current_health <= 0.0:
		is_alive = false
		died.emit(event)
		return true
	return false
