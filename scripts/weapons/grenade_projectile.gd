extends Area3D

const EXPLOSION_MARKER_SCENE := preload("res://scenes/fx/grenade_explosion_marker.tscn")

var velocity := Vector3.ZERO
var projectile_gravity := 24.0
var gravity_scale := 1.0
var damage := 75.0
var radius := 4.5
var weapon_id: StringName = &"grenade"
var _effects_root: Node3D
var _last_position := Vector3.ZERO

func setup(initial_velocity: Vector3, definition: WeaponDefinition, effects_root: Node3D) -> void:
	velocity = initial_velocity
	gravity_scale = definition.projectile_gravity_scale
	damage = definition.body_damage
	radius = definition.effect_radius_m
	weapon_id = definition.weapon_id
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
		_explode(hit["position"])
		queue_free()
		return
	global_position = next_position
	_last_position = global_position

func _explode(position: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, position)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hits := space.intersect_shape(params, 32)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider == null or not collider.has_method("apply_damage"):
			continue
		var collider_position := position
		if collider is Node3D:
			collider_position = (collider as Node3D).global_position
		var distance := position.distance_to(collider_position)
		var falloff := clampf(1.0 - (distance / radius), 0.25, 1.0)
		var event := DamageEvent.new()
		event.weapon_id = weapon_id
		event.amount = damage * falloff
		event.hit_position = collider_position
		event.hit_normal = (collider_position - position).normalized()
		collider.apply_damage(event)
	_spawn_explosion_marker(position)

func _spawn_explosion_marker(position: Vector3) -> void:
	var parent := _effects_root if _effects_root != null else get_tree().current_scene
	var marker := EXPLOSION_MARKER_SCENE.instantiate()
	parent.add_child(marker)
	marker.global_position = position
	if marker.has_method("setup"):
		marker.setup(radius)
