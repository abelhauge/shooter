class_name MovementConfig
extends Resource

@export_group("Body")
@export var capsule_radius := 0.35
@export var capsule_height := 1.8
@export var eye_height := 1.62
@export var step_offset_target := 0.35

@export_group("Ground")
@export var ground_move_speed := 9.5
@export var ground_acceleration := 28.0
@export var ground_deceleration := 22.0
@export var ground_friction := 8.0
@export var ground_counter_deceleration := 140.0
@export var ground_counter_friction := 34.0
@export var ground_lateral_deceleration := 105.0
@export var ground_lateral_friction := 26.0
@export var air_acceleration := 9.0
@export var air_control_max_speed_contribution := 2.5
@export var gravity := 24.0
@export var terminal_fall_speed := 40.0

@export_group("Jump")
@export var jump_velocity := 8.75
@export var coyote_time := 0.12
@export var jump_buffer := 0.12
@export var landing_grace_before_reslide := 0.08

@export_group("Slide")
@export var slide_min_entry_speed := 7.0
@export var slide_start_boost := 2.25
@export var slide_max_duration := 1.15
@export var slide_friction := 3.25
@export var slide_steering_factor := 0.35
@export var slide_jump_horizontal_bonus_multiplier := 1.10
@export var target_max_flat_slide_distance := 11.0
@export var slide_capsule_height := 1.05
@export var slide_eye_height := 0.95
@export var slide_height_lerp_speed := 18.0

@export_group("Wallrun")
@export var wallrun_min_speed := 7.5
@export var wallrun_max_duration := 1.2
@export var wallrun_gravity_multiplier := 0.22
@export var wall_stick_force := 6.0
@export var wall_jump_vertical_velocity := 8.25
@export var wall_jump_lateral_push := 5.5
@export var wall_jump_look_speed_bonus := 1.5
@export var wall_jump_min_outward_speed := 7.5
@export var wall_reattach_lockout_after_jump := 0.25
@export var wall_same_surface_reattach_lockout_after_jump := 0.55
@export var wall_same_surface_normal_dot := 0.82

@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var pitch_limit_degrees := 86.0
