class_name WeaponDefinition
extends Resource

@export var weapon_id: StringName
@export var slot_type: StringName
@export var display_name := ""
@export var fire_mode: StringName
@export var is_hitscan := false
@export var uses_projectile := false
@export var supports_hold_fire := false
@export var magazine_size := 0
@export var reserve_ammo_max := 0
@export var reload_time_sec := 0.0
@export var shot_cooldown_sec := 0.0
@export var pellets_per_shot := 1
@export var body_damage := 0.0
@export var head_damage := 0.0
@export var spread_degrees := 0.0
@export var max_range_m := 0.0
@export var projectile_scene_path := ""
@export var projectile_speed_mps := 0.0
@export var projectile_gravity_scale := 1.0
@export var charges_max := 0
@export var effect_duration_sec := 0.0
@export var effect_radius_m := 0.0
@export var alt_action_type: StringName
@export var move_speed_multiplier := 1.0
@export var propulsion_force := 0.0
@export var scope_enabled := false
@export var scope_fov := 26.0
@export var scope_transition_sec := 0.20
@export var scope_sensitivity_multiplier := 0.34
@export var scope_viewmodel_position := Vector3(-0.18, 0.08, -0.26)
@export var scope_viewmodel_rotation_degrees := Vector3(-1.5, -3.0, 0.0)
