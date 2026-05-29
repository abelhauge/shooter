class_name DummyTarget
extends StaticBody3D

signal killed(event: DamageEvent)

const HEAD_CENTER_Y := 1.58
const HEAD_RADIUS := 0.24
const BODY_CENTER_Y := 0.78
const BODY_HEIGHT := 1.38
const BODY_RADIUS := 0.34

@export var max_health := 100.0
@export var reset_delay_sec := 1.25
@export var display_name := "Dummy"
@export var add_to_combat_group := true

var current_health := 100.0
var _reset_remaining := 0.0
var _stun_remaining_sec := 0.0
var _hit_feedback_remaining := 0.0
var _last_damage_amount := 0.0
var _last_hit_was_headshot := false
var _label: Label3D
var _body_material := StandardMaterial3D.new()
var _head_material := StandardMaterial3D.new()

func _ready() -> void:
	if add_to_combat_group:
		add_to_group("combat_dummies")
	current_health = max_health
	_build_visuals()
	_update_visuals()

func _physics_process(delta: float) -> void:
	_stun_remaining_sec = maxf(0.0, _stun_remaining_sec - delta)
	_hit_feedback_remaining = maxf(0.0, _hit_feedback_remaining - delta)
	if _reset_remaining > 0.0:
		_reset_remaining -= delta
		if _reset_remaining <= 0.0:
			reset_target()
	_update_visuals()

func apply_damage(event: DamageEvent) -> bool:
	if _reset_remaining > 0.0:
		return false
	if not event.is_headshot and is_headshot_position(event.hit_position):
		event.is_headshot = true
	current_health = maxf(0.0, current_health - event.amount)
	_last_damage_amount = event.amount
	_last_hit_was_headshot = event.is_headshot
	_hit_feedback_remaining = 0.55
	var was_killed := current_health <= 0.0
	if was_killed:
		_reset_remaining = reset_delay_sec
		killed.emit(event)
	_update_visuals()
	return was_killed

func is_headshot_position(world_position: Vector3) -> bool:
	var local_position := to_local(world_position)
	var head_center := Vector3(0.0, HEAD_CENTER_Y, 0.0)
	return local_position.y >= HEAD_CENTER_Y - HEAD_RADIUS and local_position.distance_to(head_center) <= HEAD_RADIUS + 0.08

func apply_stun(duration_sec: float) -> bool:
	if _reset_remaining > 0.0:
		return false
	_stun_remaining_sec = maxf(_stun_remaining_sec, duration_sec)
	_update_visuals()
	return true

func get_stun_remaining_sec() -> float:
	return _stun_remaining_sec

func reset_target() -> void:
	current_health = max_health
	_reset_remaining = 0.0
	_stun_remaining_sec = 0.0
	_hit_feedback_remaining = 0.0
	_last_damage_amount = 0.0
	_last_hit_was_headshot = false
	_update_visuals()

func _build_visuals() -> void:
	var body_collision := CollisionShape3D.new()
	body_collision.name = "BodyHitbox"
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = BODY_RADIUS
	body_shape.height = BODY_HEIGHT
	body_collision.shape = body_shape
	body_collision.position.y = BODY_CENTER_Y
	add_child(body_collision)

	var head_collision := CollisionShape3D.new()
	head_collision.name = "HeadHitbox"
	var head_shape := SphereShape3D.new()
	head_shape.radius = HEAD_RADIUS
	head_collision.shape = head_shape
	head_collision.position.y = HEAD_CENTER_Y
	add_child(head_collision)

	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BodyVisual"
	var body_capsule := CapsuleMesh.new()
	body_capsule.radius = BODY_RADIUS
	body_capsule.height = BODY_HEIGHT
	body_mesh.mesh = body_capsule
	body_mesh.position.y = BODY_CENTER_Y
	_body_material.albedo_color = Color(0.95, 0.46, 0.28)
	_body_material.roughness = 0.85
	body_mesh.material_override = _body_material
	add_child(body_mesh)

	var head_mesh := MeshInstance3D.new()
	head_mesh.name = "HeadVisual"
	var head_sphere := SphereMesh.new()
	head_sphere.radius = HEAD_RADIUS
	head_sphere.height = HEAD_RADIUS * 2.0
	head_mesh.mesh = head_sphere
	head_mesh.position.y = HEAD_CENTER_Y
	_head_material.albedo_color = Color(1.0, 0.80, 0.26)
	_head_material.roughness = 0.76
	head_mesh.material_override = _head_material
	add_child(head_mesh)

	_label = Label3D.new()
	_label.position = Vector3(0.0, 2.12, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.004
	add_child(_label)

func _update_visuals() -> void:
	var stun_text := "\nSTUN %.1fs" % _stun_remaining_sec if _stun_remaining_sec > 0.0 else ""
	var hit_text := ""
	if _hit_feedback_remaining > 0.0:
		hit_text = "\n%s -%d" % ["HEAD" if _last_hit_was_headshot else "BODY", roundi(_last_damage_amount)]
	_label.text = "%s\n%d HP%s%s" % [display_name, roundi(current_health), hit_text, stun_text]
	if current_health <= 0.0:
		_body_material.albedo_color = Color(0.16, 0.16, 0.16)
		_head_material.albedo_color = Color(0.10, 0.10, 0.10)
	elif _stun_remaining_sec > 0.0:
		_body_material.albedo_color = Color(0.12, 0.62, 1.0)
		_head_material.albedo_color = Color(0.20, 0.78, 1.0)
	elif _hit_feedback_remaining > 0.0 and _last_hit_was_headshot:
		_body_material.albedo_color = Color(0.95, 0.46, 0.28)
		_head_material.albedo_color = Color(1.0, 0.12, 0.08)
	elif _hit_feedback_remaining > 0.0:
		_body_material.albedo_color = Color(1.0, 0.12, 0.08)
		_head_material.albedo_color = Color(1.0, 0.80, 0.26)
	else:
		_body_material.albedo_color = Color(0.95, 0.46, 0.28)
		_head_material.albedo_color = Color(1.0, 0.80, 0.26)
