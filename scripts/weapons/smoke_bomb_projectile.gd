extends Area3D

const SMOKE_VOLUME_SCENE := preload("res://scenes/fx/smoke_volume.tscn")

var velocity := Vector3.ZERO
var projectile_gravity := 24.0
var gravity_scale := 1.0
var effect_duration_sec := 8.0
var effect_radius_m := 2.4
var _effects_root: Node3D
var _last_position := Vector3.ZERO

func setup(initial_velocity: Vector3, definition: WeaponDefinition, effects_root: Node3D) -> void:
	velocity = initial_velocity
	gravity_scale = definition.projectile_gravity_scale
	effect_duration_sec = definition.effect_duration_sec
	effect_radius_m = definition.effect_radius_m
	_effects_root = effects_root
	_last_position = global_position

func _ready() -> void:
	_last_position = global_position

func _physics_process(delta: float) -> void:
	velocity.y -= projectile_gravity * gravity_scale * delta
	var next_position := global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(_last_position, next_position)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_spawn_smoke(hit["position"])
		queue_free()
		return
	global_position = next_position
	_last_position = global_position

func _spawn_smoke(position: Vector3) -> void:
	var parent := _effects_root if _effects_root != null else get_tree().current_scene
	var smoke := SMOKE_VOLUME_SCENE.instantiate()
	if smoke.has_method("configure"):
		smoke.configure(effect_duration_sec, effect_radius_m)
	parent.add_child(smoke)
	smoke.global_position = position
	if not smoke.has_method("configure") and smoke.has_method("set_lifetime"):
		smoke.set_lifetime(effect_duration_sec)
	if not smoke.has_method("configure") and smoke.has_method("set_radius"):
		smoke.set_radius(effect_radius_m)
