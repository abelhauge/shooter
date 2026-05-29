class_name PlayerController
extends CharacterBody3D

const STATE_GROUNDED := &"grounded"
const STATE_AIRBORNE := &"airborne"
const STATE_SLIDING := &"sliding"
const STATE_WALLRUNNING := &"wallrunning"
const STATE_STUNNED := &"stunned"
const STATE_DEAD := &"dead"

@export var movement_config: MovementConfig = preload("res://data/movement/movement_default.tres")

@onready var head_pivot: Node3D = $HeadPivot
@onready var camera: Camera3D = $HeadPivot/Camera3D
@onready var view_model_root: Node3D = $HeadPivot/ViewModelRoot
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var wall_check_left: RayCast3D = $WallCheckLeft
@onready var wall_check_right: RayCast3D = $WallCheckRight
@onready var health_component: HealthComponent = $HealthComponent
@onready var weapon_controller: WeaponController = $WeaponController

var movement_state: StringName = STATE_AIRBORNE
var yaw := 0.0
var pitch := 0.0
var _jump_buffer_remaining := 0.0
var _coyote_remaining := 0.0
var _slide_elapsed := 0.0
var _wallrun_elapsed := 0.0
var _wallrun_lockout_remaining := 0.0
var _wall_normal := Vector3.ZERO
var _wallrun_direction := Vector3.ZERO
var _last_wall_jump_normal := Vector3.ZERO
var _same_wall_reattach_lockout_remaining := 0.0
var _standing_capsule_height := 1.8
var _standing_collision_center_y := 0.9
var _standing_eye_height := 1.62
var _projectiles_root: Node3D
var _effects_root: Node3D
var _stun_remaining_sec := 0.0

func _ready() -> void:
	_make_collision_shape_unique()
	_cache_standing_height()
	health_component.died.connect(_on_died)
	health_component.reset.connect(_on_health_reset)
	weapon_controller.set_owner_body(self)
	weapon_controller.set_view_model_root(view_model_root)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and health_component.is_alive:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	if _handle_mouse_look_event(event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _handle_mouse_look_event(event):
		get_viewport().set_input_as_handled()

func _handle_mouse_look_event(event: InputEvent) -> bool:
	if not (event is InputEventMouseMotion):
		return false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not health_component.is_alive or is_stunned():
		return false
	var mouse_motion := event as InputEventMouseMotion
	_apply_mouse_look_delta(mouse_motion.relative)
	return true

func _apply_mouse_look_delta(relative: Vector2) -> void:
	var sensitivity_multiplier := weapon_controller.get_look_sensitivity_multiplier() if weapon_controller != null else 1.0
	var effective_sensitivity := movement_config.mouse_sensitivity * sensitivity_multiplier
	yaw -= relative.x * effective_sensitivity
	pitch = clampf(
		pitch - relative.y * effective_sensitivity,
		-deg_to_rad(movement_config.pitch_limit_degrees),
		deg_to_rad(movement_config.pitch_limit_degrees)
	)
	rotation.y = yaw
	head_pivot.rotation.x = pitch

func _physics_process(delta: float) -> void:
	_update_common_timers(delta)
	if not health_component.is_alive:
		weapon_controller.set_input_locked(true)
		_simulate_dead_body(delta)
		return
	weapon_controller.set_input_locked(is_stunned())
	if is_stunned():
		_simulate_stunned_body(delta)
		weapon_controller.physics_update(delta, camera, _projectiles_root, _effects_root)
		return

	var grounded := is_on_floor()
	if grounded:
		_coyote_remaining = movement_config.coyote_time
		if movement_state != STATE_SLIDING:
			movement_state = STATE_GROUNDED
	else:
		if movement_state != STATE_WALLRUNNING:
			movement_state = STATE_AIRBORNE

	if Input.is_action_just_pressed(FpsInputActions.JUMP):
		_jump_buffer_remaining = movement_config.jump_buffer

	var wish_dir := _get_wish_direction()
	_try_start_slide(grounded)
	_try_start_wallrun(grounded)

	if movement_state == STATE_SLIDING:
		_process_slide(delta, wish_dir)
	elif movement_state == STATE_WALLRUNNING:
		_process_wallrun(delta, wish_dir)
	else:
		_process_standard_movement(delta, wish_dir, grounded)

	_update_slide_height(delta)
	move_and_slide()
	weapon_controller.try_apply_portal_transport(self)
	weapon_controller.physics_update(delta, camera, _projectiles_root, _effects_root)

func configure_gameplay_roots(projectiles_root: Node3D, effects_root: Node3D) -> void:
	_projectiles_root = projectiles_root
	_effects_root = effects_root
	if is_node_ready():
		weapon_controller.set_effect_roots(projectiles_root, effects_root)

func get_speed_mps() -> float:
	return Vector2(velocity.x, velocity.z).length()

func get_health_component() -> HealthComponent:
	return health_component

func get_weapon_controller() -> WeaponController:
	return weapon_controller

func apply_stun(duration_sec: float) -> bool:
	if not health_component.is_alive:
		return false
	_stun_remaining_sec = maxf(_stun_remaining_sec, duration_sec)
	_jump_buffer_remaining = 0.0
	_slide_elapsed = 0.0
	_wallrun_elapsed = 0.0
	_wallrun_direction = Vector3.ZERO
	movement_state = STATE_STUNNED
	return true

func set_stun_remaining_sec(duration_sec: float) -> void:
	_stun_remaining_sec = maxf(0.0, duration_sec)
	if _stun_remaining_sec > 0.0 and health_component.is_alive:
		movement_state = STATE_STUNNED

func get_stun_remaining_sec() -> float:
	return _stun_remaining_sec

func is_stunned() -> bool:
	return _stun_remaining_sec > 0.0

func run_runtime_movement_smoke_check() -> Dictionary:
	var original_transform := global_transform
	var original_velocity := velocity
	var original_state := movement_state
	var original_yaw := yaw
	var original_pitch := pitch
	var original_mouse_mode := Input.mouse_mode
	var original_jump_buffer := _jump_buffer_remaining
	var original_coyote := _coyote_remaining
	var original_slide_elapsed := _slide_elapsed
	var original_wallrun_elapsed := _wallrun_elapsed
	var original_wallrun_lockout := _wallrun_lockout_remaining
	var original_wall_normal := _wall_normal
	var original_wallrun_direction := _wallrun_direction
	var original_last_wall_jump_normal := _last_wall_jump_normal
	var original_same_wall_lockout := _same_wall_reattach_lockout_remaining
	var original_head_y := head_pivot.position.y
	var original_collision_y := collision_shape.position.y
	var original_capsule_height := _capsule_shape().height if _capsule_shape() != null else 0.0

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var click_event := InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.pressed = true
	_input(click_event)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return {"ok": false, "error": "mouse click did not capture input for aim"}
	var mouse_event := InputEventMouseMotion.new()
	mouse_event.relative = Vector2(18.0, -10.0)
	_input(mouse_event)
	if is_equal_approx(yaw, original_yaw) or is_equal_approx(pitch, original_pitch):
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return {"ok": false, "error": "mouse look did not update yaw/pitch"}

	velocity = Vector3.ZERO
	_process_standard_movement(1.0 / 60.0, Vector3.FORWARD, true)
	if Vector2(velocity.x, velocity.z).length() <= 0.01:
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return {"ok": false, "error": "ground movement did not accelerate"}

	velocity = Vector3(0.0, 0.0, -24.0)
	for _index in range(10):
		_process_standard_movement(1.0 / 60.0, Vector3.ZERO, true)
	if Vector2(velocity.x, velocity.z).length() > 1.0:
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return {"ok": false, "error": "high-speed ground stop slides too far", "speed_after": Vector2(velocity.x, velocity.z).length()}

	velocity = Vector3(0.0, 0.0, -24.0)
	for _index in range(10):
		_process_standard_movement(1.0 / 60.0, Vector3.BACK, true)
	if velocity.z < -0.25 or Vector2(velocity.x, velocity.z).length() > 5.5:
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return {"ok": false, "error": "high-speed reverse input did not brake old momentum", "velocity_after": velocity}

	velocity = Vector3(24.0, 0.0, 0.0)
	for _index in range(10):
		_process_standard_movement(1.0 / 60.0, Vector3.FORWARD, true)
	if absf(velocity.x) > 1.0 or Vector2(velocity.x, velocity.z).length() > 5.5:
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return {"ok": false, "error": "high-speed sideways input did not brake lateral momentum", "velocity_after": velocity}

	velocity = Vector3.ZERO
	_jump_buffer_remaining = movement_config.jump_buffer
	_coyote_remaining = movement_config.coyote_time
	_process_standard_movement(1.0 / 60.0, Vector3.ZERO, true)
	if velocity.y <= 0.0 or movement_state != STATE_AIRBORNE:
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return {"ok": false, "error": "jump did not launch player"}

	movement_state = STATE_SLIDING
	velocity = Vector3(0.0, 0.0, -movement_config.slide_min_entry_speed)
	_jump_buffer_remaining = 0.0
	_process_slide(1.0 / 60.0, Vector3.ZERO)
	_update_slide_height(1.0 / 60.0)
	if head_pivot.position.y >= _standing_eye_height:
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return {"ok": false, "error": "slide did not lower camera height"}
	_jump_buffer_remaining = movement_config.jump_buffer
	_process_slide(1.0 / 60.0, Vector3.ZERO)
	if movement_state != STATE_AIRBORNE or velocity.y <= 0.0:
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return {"ok": false, "error": "slide jump did not transition airborne"}

	var wall_result := _run_wallrun_smoke_check()
	if not bool(wall_result.get("ok", false)):
		_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
		_last_wall_jump_normal = original_last_wall_jump_normal
		_same_wall_reattach_lockout_remaining = original_same_wall_lockout
		_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
		return wall_result

	_restore_movement_smoke_state(original_transform, original_velocity, original_state, original_yaw, original_pitch, original_mouse_mode, original_jump_buffer, original_coyote, original_slide_elapsed, original_wallrun_elapsed, original_wallrun_lockout, original_wall_normal, original_wallrun_direction)
	_last_wall_jump_normal = original_last_wall_jump_normal
	_same_wall_reattach_lockout_remaining = original_same_wall_lockout
	_restore_slide_height(original_head_y, original_collision_y, original_capsule_height)
	return {"ok": true}

func _restore_movement_smoke_state(original_transform: Transform3D, original_velocity: Vector3, original_state: StringName, original_yaw: float, original_pitch: float, original_mouse_mode: Input.MouseMode, original_jump_buffer: float, original_coyote: float, original_slide_elapsed: float, original_wallrun_elapsed: float, original_wallrun_lockout: float, original_wall_normal: Vector3, original_wallrun_direction: Vector3) -> void:
	global_transform = original_transform
	velocity = original_velocity
	movement_state = original_state
	yaw = original_yaw
	pitch = original_pitch
	rotation.y = yaw
	head_pivot.rotation.x = pitch
	Input.mouse_mode = original_mouse_mode
	_jump_buffer_remaining = original_jump_buffer
	_coyote_remaining = original_coyote
	_slide_elapsed = original_slide_elapsed
	_wallrun_elapsed = original_wallrun_elapsed
	_wallrun_lockout_remaining = original_wallrun_lockout
	_wall_normal = original_wall_normal
	_wallrun_direction = original_wallrun_direction

func _cache_standing_height() -> void:
	var capsule := _capsule_shape()
	if capsule != null:
		_standing_capsule_height = capsule.height
	_standing_collision_center_y = collision_shape.position.y
	_standing_eye_height = head_pivot.position.y

func _make_collision_shape_unique() -> void:
	if collision_shape != null and collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()

func _capsule_shape() -> CapsuleShape3D:
	if collision_shape == null:
		return null
	return collision_shape.shape as CapsuleShape3D

func _update_slide_height(delta: float) -> void:
	var capsule := _capsule_shape()
	if capsule == null:
		return
	var slide_active := movement_state == STATE_SLIDING
	var target_capsule_height := movement_config.slide_capsule_height if slide_active else _standing_capsule_height
	var target_center_y := target_capsule_height * 0.5 if slide_active else _standing_collision_center_y
	var target_eye_height := movement_config.slide_eye_height if slide_active else _standing_eye_height
	var t := clampf(movement_config.slide_height_lerp_speed * delta, 0.0, 1.0)
	capsule.height = lerpf(capsule.height, target_capsule_height, t)
	collision_shape.position.y = lerpf(collision_shape.position.y, target_center_y, t)
	head_pivot.position.y = lerpf(head_pivot.position.y, target_eye_height, t)

func _restore_slide_height(head_y: float, collision_y: float, capsule_height: float) -> void:
	head_pivot.position.y = head_y
	collision_shape.position.y = collision_y
	var capsule := _capsule_shape()
	if capsule != null and capsule_height > 0.0:
		capsule.height = capsule_height

func _run_wallrun_smoke_check() -> Dictionary:
	if wall_check_left == null or wall_check_right == null:
		return {"ok": false, "error": "wallrun raycasts are missing"}
	global_position = Vector3(-15.1, 2.6, -7.0)
	rotation.y = 0.0
	var ray_start := global_position + wall_check_left.position
	var ray_end := ray_start + Vector3.LEFT * 2.0
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"ok": false, "error": "wallrun smoke ray did not hit arena wall panel"}
	var hit_normal: Vector3 = hit["normal"]
	if absf(hit_normal.y) >= 0.25:
		return {"ok": false, "error": "wallrun smoke hit was not a vertical wall"}
	movement_state = STATE_AIRBORNE
	velocity = -global_transform.basis.z * movement_config.wallrun_min_speed
	_wallrun_lockout_remaining = 0.0
	_wall_normal = hit_normal
	_wallrun_direction = _calculate_wallrun_direction(hit_normal)
	movement_state = STATE_WALLRUNNING
	_process_wallrun(0.25, -_wallrun_direction)
	if _wallrun_direction.dot(Vector3.FORWARD) < 0.95:
		return {"ok": false, "error": "wallrun direction changed from reverse wish input"}
	if velocity.y < -movement_config.gravity * 0.35 * 0.25:
		return {"ok": false, "error": "wallrun gravity did not slow the fall enough"}
	yaw = deg_to_rad(90.0)
	rotation.y = yaw
	_jump_buffer_remaining = movement_config.jump_buffer
	_perform_wall_jump()
	if movement_state != STATE_AIRBORNE or velocity.y <= 0.0:
		return {"ok": false, "error": "wall jump did not launch player"}
	var jump_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if jump_horizontal.dot(Vector3(hit_normal.x, 0.0, hit_normal.z).normalized()) < movement_config.wall_jump_min_outward_speed - 0.01:
		return {"ok": false, "error": "wall jump did not push far enough away from wall", "velocity": velocity, "wall_normal": hit_normal}
	var old_state := movement_state
	_try_start_wallrun(false)
	if movement_state == STATE_WALLRUNNING:
		return {"ok": false, "error": "same wall reattached immediately after wall jump"}
	movement_state = old_state
	return {"ok": true}

func _update_common_timers(delta: float) -> void:
	_jump_buffer_remaining = maxf(0.0, _jump_buffer_remaining - delta)
	_coyote_remaining = maxf(0.0, _coyote_remaining - delta)
	_wallrun_lockout_remaining = maxf(0.0, _wallrun_lockout_remaining - delta)
	_same_wall_reattach_lockout_remaining = maxf(0.0, _same_wall_reattach_lockout_remaining - delta)
	_stun_remaining_sec = maxf(0.0, _stun_remaining_sec - delta)
	if _same_wall_reattach_lockout_remaining <= 0.0:
		_last_wall_jump_normal = Vector3.ZERO

func _simulate_stunned_body(delta: float) -> void:
	movement_state = STATE_STUNNED
	_jump_buffer_remaining = 0.0
	_wallrun_direction = Vector3.ZERO
	_update_slide_height(delta)
	velocity.x = move_toward(velocity.x, 0.0, movement_config.ground_deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, movement_config.ground_deceleration * delta)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - movement_config.gravity * delta, -movement_config.terminal_fall_speed)
	elif velocity.y < 0.0:
		velocity.y = -0.05
	move_and_slide()

func _simulate_dead_body(delta: float) -> void:
	movement_state = STATE_DEAD
	_update_slide_height(delta)
	velocity.x = move_toward(velocity.x, 0.0, movement_config.ground_deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, movement_config.ground_deceleration * delta)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - movement_config.gravity * delta, -movement_config.terminal_fall_speed)
	move_and_slide()

func _get_wish_direction() -> Vector3:
	var input_vec := Vector2(
		Input.get_action_strength(FpsInputActions.MOVE_RIGHT) - Input.get_action_strength(FpsInputActions.MOVE_LEFT),
		Input.get_action_strength(FpsInputActions.MOVE_BACK) - Input.get_action_strength(FpsInputActions.MOVE_FORWARD)
	)
	if input_vec.length_squared() > 1.0:
		input_vec = input_vec.normalized()
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	return (right * input_vec.x + forward * -input_vec.y).normalized()

func _process_standard_movement(delta: float, wish_dir: Vector3, grounded: bool) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_ground_speed := movement_config.ground_move_speed * weapon_controller.get_movement_speed_multiplier()
	if grounded:
		if wish_dir == Vector3.ZERO:
			var speed := horizontal.length()
			var braking := maxf(movement_config.ground_deceleration, speed * movement_config.ground_friction)
			horizontal = horizontal.move_toward(Vector3.ZERO, braking * delta)
		else:
			horizontal = _apply_ground_directional_braking(horizontal, wish_dir, delta)
			horizontal = horizontal.move_toward(wish_dir * target_ground_speed, movement_config.ground_acceleration * delta)
		if velocity.y < 0.0:
			velocity.y = -0.05
	else:
		if wish_dir != Vector3.ZERO:
			var desired_air := horizontal + wish_dir * movement_config.air_control_max_speed_contribution
			horizontal = horizontal.move_toward(desired_air, movement_config.air_acceleration * delta)
		velocity.y = maxf(velocity.y - movement_config.gravity * delta, -movement_config.terminal_fall_speed)

	if _jump_buffer_remaining > 0.0 and _coyote_remaining > 0.0:
		velocity.y = movement_config.jump_velocity
		_jump_buffer_remaining = 0.0
		_coyote_remaining = 0.0
		movement_state = STATE_AIRBORNE

	velocity.x = horizontal.x
	velocity.z = horizontal.z

func _apply_ground_directional_braking(horizontal: Vector3, wish_dir: Vector3, delta: float) -> Vector3:
	var speed := horizontal.length()
	if speed <= 0.01 or wish_dir == Vector3.ZERO:
		return horizontal
	var forward_speed := horizontal.dot(wish_dir)
	var along := wish_dir * forward_speed
	var lateral := horizontal - along
	if forward_speed < 0.0:
		var counter_braking := maxf(
			movement_config.ground_counter_deceleration,
			speed * movement_config.ground_counter_friction
		)
		along = along.move_toward(Vector3.ZERO, counter_braking * delta)
	if lateral.length_squared() > 0.0001:
		var lateral_braking := maxf(
			movement_config.ground_lateral_deceleration,
			speed * movement_config.ground_lateral_friction
		)
		lateral = lateral.move_toward(Vector3.ZERO, lateral_braking * delta)
	return along + lateral

func _try_start_slide(grounded: bool) -> void:
	if movement_state == STATE_SLIDING:
		return
	if not grounded or not Input.is_action_just_pressed(FpsInputActions.SLIDE):
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < movement_config.slide_min_entry_speed:
		return
	var boost_dir := horizontal.normalized()
	horizontal += boost_dir * movement_config.slide_start_boost
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_slide_elapsed = 0.0
	movement_state = STATE_SLIDING

func _process_slide(delta: float, wish_dir: Vector3) -> void:
	_slide_elapsed += delta
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir != Vector3.ZERO:
		var steer_target := wish_dir * maxf(horizontal.length(), movement_config.slide_min_entry_speed)
		horizontal = horizontal.lerp(steer_target, movement_config.slide_steering_factor * delta)
	horizontal = horizontal.move_toward(Vector3.ZERO, movement_config.slide_friction * delta)

	if _jump_buffer_remaining > 0.0:
		horizontal *= movement_config.slide_jump_horizontal_bonus_multiplier
		velocity.y = movement_config.jump_velocity
		_jump_buffer_remaining = 0.0
		movement_state = STATE_AIRBORNE
	elif _slide_elapsed >= movement_config.slide_max_duration or horizontal.length() < movement_config.slide_min_entry_speed * 0.55:
		movement_state = STATE_GROUNDED

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if velocity.y < 0.0:
		velocity.y = -0.05

func _try_start_wallrun(grounded: bool) -> void:
	if grounded or movement_state == STATE_WALLRUNNING or _wallrun_lockout_remaining > 0.0:
		return
	var horizontal_speed := get_speed_mps()
	if horizontal_speed < movement_config.wallrun_min_speed:
		return
	var found_normal := _find_wall_normal()
	if found_normal == Vector3.ZERO:
		return
	if _is_same_wall_reattach_blocked(found_normal):
		return
	_wall_normal = found_normal
	_wallrun_elapsed = 0.0
	_wallrun_direction = _calculate_wallrun_direction(found_normal)
	movement_state = STATE_WALLRUNNING

func _process_wallrun(delta: float, _wish_dir: Vector3) -> void:
	_wallrun_elapsed += delta
	var found_normal := _find_wall_normal()
	if found_normal == Vector3.ZERO:
		movement_state = STATE_AIRBORNE
		return
	_wall_normal = found_normal
	var along_wall := _project_wallrun_direction_onto_wall(_wallrun_direction, _wall_normal)
	if along_wall == Vector3.ZERO:
		movement_state = STATE_AIRBORNE
		return
	_wallrun_direction = along_wall
	var horizontal_speed := maxf(get_speed_mps(), movement_config.wallrun_min_speed)
	velocity.x = along_wall.x * horizontal_speed - _wall_normal.x * movement_config.wall_stick_force
	velocity.z = along_wall.z * horizontal_speed - _wall_normal.z * movement_config.wall_stick_force
	velocity.y = maxf(velocity.y - movement_config.gravity * movement_config.wallrun_gravity_multiplier * delta, -movement_config.terminal_fall_speed)

	if _jump_buffer_remaining > 0.0:
		_perform_wall_jump()
	elif _wallrun_elapsed >= movement_config.wallrun_max_duration:
		_wallrun_lockout_remaining = movement_config.wall_reattach_lockout_after_jump
		movement_state = STATE_AIRBORNE

func _perform_wall_jump() -> void:
	var look_dir := -camera.global_transform.basis.z
	var horizontal_look := Vector3(look_dir.x, 0.0, look_dir.z)
	if horizontal_look.length_squared() < 0.001:
		horizontal_look = -global_transform.basis.z
	horizontal_look = horizontal_look.normalized()
	var jump_speed := maxf(get_speed_mps(), movement_config.wallrun_min_speed) + movement_config.wall_jump_look_speed_bonus
	var wall_normal := Vector3(_wall_normal.x, 0.0, _wall_normal.z).normalized()
	var horizontal_jump := horizontal_look * jump_speed
	var outward_speed := horizontal_jump.dot(wall_normal)
	if outward_speed < movement_config.wall_jump_min_outward_speed:
		horizontal_jump += wall_normal * (movement_config.wall_jump_min_outward_speed - outward_speed)
	velocity.x = horizontal_jump.x
	velocity.z = horizontal_jump.z
	velocity.y = movement_config.wall_jump_vertical_velocity + maxf(look_dir.y, 0.0) * movement_config.wall_jump_lateral_push
	_jump_buffer_remaining = 0.0
	_wallrun_lockout_remaining = movement_config.wall_reattach_lockout_after_jump
	_same_wall_reattach_lockout_remaining = movement_config.wall_same_surface_reattach_lockout_after_jump
	_last_wall_jump_normal = wall_normal
	_wallrun_direction = Vector3.ZERO
	movement_state = STATE_AIRBORNE

func _is_same_wall_reattach_blocked(candidate_normal: Vector3) -> bool:
	if _same_wall_reattach_lockout_remaining <= 0.0 or _last_wall_jump_normal == Vector3.ZERO:
		return false
	var horizontal_candidate := Vector3(candidate_normal.x, 0.0, candidate_normal.z)
	if horizontal_candidate.length_squared() <= 0.001:
		return false
	horizontal_candidate = horizontal_candidate.normalized()
	return horizontal_candidate.dot(_last_wall_jump_normal) >= movement_config.wall_same_surface_normal_dot

func _calculate_wallrun_direction(normal: Vector3) -> Vector3:
	var along_wall := normal.cross(Vector3.UP).normalized()
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() > 0.001 and along_wall.dot(horizontal_velocity) < 0.0:
		along_wall = -along_wall
	elif horizontal_velocity.length_squared() <= 0.001 and along_wall.dot(-global_transform.basis.z) < 0.0:
		along_wall = -along_wall
	return along_wall

func _project_wallrun_direction_onto_wall(direction: Vector3, normal: Vector3) -> Vector3:
	if direction == Vector3.ZERO:
		return _calculate_wallrun_direction(normal)
	var projected := direction - normal * direction.dot(normal)
	projected.y = 0.0
	return projected.normalized() if projected.length_squared() > 0.001 else Vector3.ZERO

func _find_wall_normal() -> Vector3:
	wall_check_left.force_raycast_update()
	wall_check_right.force_raycast_update()
	if wall_check_left.is_colliding():
		var left_normal := wall_check_left.get_collision_normal()
		if absf(left_normal.y) < 0.25:
			return left_normal
	if wall_check_right.is_colliding():
		var right_normal := wall_check_right.get_collision_normal()
		if absf(right_normal.y) < 0.25:
			return right_normal
	return Vector3.ZERO

func _on_died(_event: DamageEvent) -> void:
	movement_state = STATE_DEAD
	_same_wall_reattach_lockout_remaining = 0.0
	_last_wall_jump_normal = Vector3.ZERO
	_stun_remaining_sec = 0.0

func _on_health_reset(_current_health: float) -> void:
	movement_state = STATE_AIRBORNE
	_same_wall_reattach_lockout_remaining = 0.0
	_last_wall_jump_normal = Vector3.ZERO
	_stun_remaining_sec = 0.0
	weapon_controller.set_input_locked(false)
