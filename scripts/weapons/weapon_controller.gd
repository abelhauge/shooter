class_name WeaponController
extends Node

signal weapon_state_changed(summary: Dictionary)
signal hit_confirmed(damage: float, killed: bool)
signal network_fire_requested(weapon_id: StringName, origin: Vector3, direction: Vector3, shooter_velocity: Vector3)
signal network_reload_requested(weapon_id: StringName)
signal network_slot_changed(slot: StringName)

const FLAME_BURST_SCENE := preload("res://scenes/fx/flame_burst.tscn")
const SLOT_ORDER: Array[StringName] = [&"primary", &"secondary", &"melee", &"artillery"]
const WEAPON_PATHS := {
	&"assault_rifle": "res://data/weapons/assault_rifle.tres",
	&"shotgun": "res://data/weapons/shotgun.tres",
	&"sniper": "res://data/weapons/sniper.tres",
	&"flamethrower": "res://data/weapons/flamethrower.tres",
	&"handgun": "res://data/weapons/handgun.tres",
	&"portal_gun": "res://data/weapons/portal_gun.tres",
	&"lasso": "res://data/weapons/lasso.tres",
	&"taser_gun": "res://data/weapons/taser_gun.tres",
	&"knife": "res://data/weapons/knife.tres",
	&"smoke_bomb": "res://data/weapons/smoke_bomb.tres",
	&"grenade": "res://data/weapons/grenade.tres",
	&"redbull": "res://data/weapons/redbull.tres",
}

const VIEW_MODEL_PATHS := {
	&"assault_rifle": "res://scenes/weapons/viewmodels/rifle_viewmodel.tscn",
	&"handgun": "res://scenes/weapons/viewmodels/handgun_viewmodel.tscn",
	&"shotgun": "res://scenes/weapons/viewmodels/shotgun_viewmodel.tscn",
	&"sniper": "res://scenes/weapons/viewmodels/sniper_viewmodel.tscn",
	&"flamethrower": "res://scenes/weapons/viewmodels/flamethrower_viewmodel.tscn",
	&"lasso": "res://scenes/weapons/viewmodels/revolver_viewmodel.tscn",
	&"taser_gun": "res://scenes/weapons/viewmodels/taser_gun_viewmodel.tscn",
	&"knife": "res://scenes/weapons/viewmodels/knife_viewmodel.tscn",
	&"smoke_bomb": "res://scenes/weapons/viewmodels/smoke_bomb_viewmodel.tscn",
	&"grenade": "res://scenes/weapons/viewmodels/grenade_viewmodel.tscn",
	&"redbull": "res://scenes/weapons/viewmodels/redbull_viewmodel.tscn",
	&"portal_gun": "res://scenes/weapons/viewmodels/p90_viewmodel.tscn",
}

@export var loadout: LoadoutDefinition = preload("res://data/loadouts/default_v1_loadout.tres")

var active_slot: StringName = &"primary"
var _definitions: Dictionary = {}
var _runtime_states: Dictionary = {}
var _slot_weapon_ids: Dictionary = {}
var _owner_body: CharacterBody3D
var _projectiles_root: Node3D
var _effects_root: Node3D
var _view_model_root: Node3D
var _current_view_model: Node3D
var _impact_scene := preload("res://scenes/fx/impact_spark.tscn")
var _multiplayer_combat_enabled := false
var _speed_buff_remaining_sec := 0.0
var _speed_buff_multiplier := 1.0
var _rocket_fuel_remaining_sec := 0.0
var _portal_a_position := Vector3.ZERO
var _portal_b_position := Vector3.ZERO
var _portal_a_active := false
var _portal_b_active := false
var _portal_cooldown_sec := 0.0
var _portal_lifetime_remaining_sec := 0.0
var _portal_transport_cooldown_sec := 0.0
var _input_locked := false
var _sniper_scope_progress := 0.0
var _camera_default_fov := 0.0

func _ready() -> void:
	_load_definitions()
	reset_loadout()

func set_owner_body(owner_body: CharacterBody3D) -> void:
	_owner_body = owner_body

func set_effect_roots(projectiles_root: Node3D, effects_root: Node3D) -> void:
	_projectiles_root = projectiles_root
	_effects_root = effects_root

func set_view_model_root(view_model_root: Node3D) -> void:
	_view_model_root = view_model_root
	_refresh_view_model()

func set_multiplayer_combat_enabled(enabled: bool) -> void:
	_multiplayer_combat_enabled = enabled

func set_input_locked(locked: bool) -> void:
	_input_locked = locked

func physics_update(delta: float, camera: Camera3D, projectiles_root: Node3D, effects_root: Node3D) -> void:
	if projectiles_root != null:
		_projectiles_root = projectiles_root
	if effects_root != null:
		_effects_root = effects_root
	_tick_runtime_states(delta)
	_tick_special_states(delta)
	_update_sniper_scope(delta, camera)
	if _input_locked:
		_emit_summary()
		return
	_handle_slot_input()
	_handle_reload_input()
	_handle_fire_input(camera)
	_handle_alt_fire_input(camera, delta)
	_emit_summary()

func reset_loadout() -> void:
	_slot_weapon_ids = {
		&"primary": loadout.primary_weapon_id,
		&"secondary": loadout.secondary_weapon_id,
		&"melee": loadout.melee_weapon_id,
		&"artillery": loadout.artillery_weapon_id,
	}
	_runtime_states.clear()
	for weapon_id in _slot_weapon_ids.values():
		var definition: WeaponDefinition = _definitions[weapon_id]
		_runtime_states[weapon_id] = WeaponRuntimeState.from_definition(definition)
	active_slot = &"primary"
	_speed_buff_remaining_sec = 0.0
	_speed_buff_multiplier = 1.0
	_rocket_fuel_remaining_sec = 0.0
	_clear_portals()
	_refresh_view_model()
	_emit_summary()

func set_loadout_definition(definition: LoadoutDefinition) -> void:
	loadout = definition
	if is_node_ready():
		reset_loadout()

func get_weapon_options_for_slot(slot_type: StringName) -> Array[WeaponDefinition]:
	var options: Array[WeaponDefinition] = []
	for definition in _definitions.values():
		if definition.slot_type == slot_type:
			options.append(definition)
	options.sort_custom(func(a: WeaponDefinition, b: WeaponDefinition) -> bool: return a.display_name < b.display_name)
	return options

func get_movement_speed_multiplier() -> float:
	return _speed_buff_multiplier

func get_look_sensitivity_multiplier() -> float:
	var scoped_multiplier := 1.0
	if _is_active_weapon(&"sniper"):
		scoped_multiplier = get_active_definition().scope_sensitivity_multiplier
	return lerpf(1.0, scoped_multiplier, _sniper_scope_progress)

func get_active_definition() -> WeaponDefinition:
	return _definitions[_slot_weapon_ids[active_slot]]

func get_active_state() -> WeaponRuntimeState:
	return _runtime_states[_slot_weapon_ids[active_slot]]

func get_active_summary() -> Dictionary:
	var definition := get_active_definition()
	var state := get_active_state()
	return {
		"slot": active_slot,
		"weapon_id": definition.weapon_id,
		"display_name": definition.display_name,
		"ammo_in_mag": state.ammo_in_mag,
		"reserve_ammo": state.reserve_ammo,
		"charges_current": state.charges_current,
		"charges_max": definition.charges_max,
		"is_reloading": state.is_reloading,
		"cooldown_remaining_sec": state.cooldown_remaining_sec,
		"speed_buff_remaining_sec": _speed_buff_remaining_sec,
		"speed_multiplier": get_movement_speed_multiplier(),
		"rocket_fuel_remaining_sec": _rocket_fuel_remaining_sec,
		"scope_progress": _sniper_scope_progress,
		"scope_visible": _is_active_weapon(&"sniper") and definition.scope_enabled and _sniper_scope_progress > 0.02,
		"scope_sensitivity_multiplier": get_look_sensitivity_multiplier(),
	}

func get_sniper_scope_summary() -> Dictionary:
	var is_sniper := _is_active_weapon(&"sniper")
	var scope_enabled := is_sniper and get_active_definition().scope_enabled
	return {
		"is_sniper_active": is_sniper,
		"scope_progress": _sniper_scope_progress,
		"scope_visible": scope_enabled and _sniper_scope_progress > 0.02,
		"is_scoped": scope_enabled and _sniper_scope_progress >= 0.98,
		"sensitivity_multiplier": get_look_sensitivity_multiplier(),
	}

func get_weapon_tuning_snapshot(weapon_ids: Array[StringName]) -> Dictionary:
	var snapshot := {}
	for weapon_id in weapon_ids:
		if not _definitions.has(weapon_id):
			continue
		var definition: WeaponDefinition = _definitions[weapon_id]
		snapshot[String(weapon_id)] = {
			"magazine_size": definition.magazine_size,
			"reserve_ammo_max": definition.reserve_ammo_max,
			"reload_time_sec": definition.reload_time_sec,
			"shot_cooldown_sec": definition.shot_cooldown_sec,
			"pellets_per_shot": definition.pellets_per_shot,
			"body_damage": definition.body_damage,
			"head_damage": definition.head_damage,
			"charges_max": definition.charges_max,
			"effect_duration_sec": definition.effect_duration_sec,
			"alt_action_type": definition.alt_action_type,
		}
	return snapshot

func run_runtime_smoke_check(camera: Camera3D, include_fire: bool) -> Dictionary:
	if camera == null:
		return {"ok": false, "error": "weapon smoke missing camera"}
	if _definitions.is_empty():
		return {"ok": false, "error": "weapon definitions are not loaded"}
	var original_slot := active_slot
	var checked_weapons := []
	for slot in SLOT_ORDER:
		if not _slot_weapon_ids.has(slot):
			return {"ok": false, "error": "loadout missing slot %s" % String(slot)}
		active_slot = slot
		var definition := get_active_definition()
		if not _runtime_states.has(definition.weapon_id):
			return {"ok": false, "error": "runtime state missing for %s" % String(definition.weapon_id)}
		_refresh_view_model()
		checked_weapons.append(String(definition.weapon_id))
		if include_fire:
			var validation := _validate_weapon_runtime_assets(definition)
			if not bool(validation.get("ok", false)):
				active_slot = original_slot
				_refresh_view_model()
				return validation
			_fire_active_weapon_for_smoke(definition, camera)
	active_slot = original_slot
	_refresh_view_model()
	return {
		"ok": true,
		"checked_weapons": checked_weapons,
		"loaded_definition_count": _definitions.size(),
	}

func run_all_weapons_runtime_smoke_check(camera: Camera3D, include_fire: bool) -> Dictionary:
	if camera == null:
		return {"ok": false, "error": "all-weapons smoke missing camera"}
	if _definitions.is_empty():
		return {"ok": false, "error": "weapon definitions are not loaded"}
	var original_loadout := loadout
	var original_slot := active_slot
	var checked_weapons := []
	for weapon_id in WEAPON_PATHS.keys():
		if not _definitions.has(weapon_id):
			return {"ok": false, "error": "definition not loaded for %s" % String(weapon_id)}
		var definition: WeaponDefinition = _definitions[weapon_id]
		var validation := _validate_weapon_runtime_assets(definition)
		if not bool(validation.get("ok", false)):
			return validation
		loadout = _build_smoke_loadout_for_weapon(definition)
		reset_loadout()
		active_slot = definition.slot_type
		if not _runtime_states.has(definition.weapon_id):
			return {"ok": false, "error": "runtime state missing for %s" % String(definition.weapon_id)}
		_refresh_view_model()
		checked_weapons.append(String(definition.weapon_id))
		if include_fire:
			_fire_active_weapon_for_smoke(definition, camera)
	loadout = original_loadout
	reset_loadout()
	active_slot = original_slot
	_refresh_view_model()
	return {
		"ok": true,
		"checked_weapons": checked_weapons,
		"loaded_definition_count": _definitions.size(),
	}

func run_reload_interrupt_smoke_check() -> Dictionary:
	if not _slot_weapon_ids.has(&"primary") or not _slot_weapon_ids.has(&"secondary"):
		return {"ok": false, "error": "reload smoke requires primary and secondary slots"}
	var original_slot := active_slot
	active_slot = &"primary"
	var definition := get_active_definition()
	var state := get_active_state()
	if definition.magazine_size <= 0 or definition.reload_time_sec <= 0.0:
		active_slot = original_slot
		return {"ok": false, "error": "primary weapon cannot exercise reload"}
	state.ammo_in_mag = maxi(0, definition.magazine_size - 1)
	state.reserve_ammo = maxi(1, state.reserve_ammo)
	state.is_reloading = true
	state.reload_elapsed_sec = definition.reload_time_sec * 0.5
	_switch_active_slot(&"secondary")
	var cancelled := not state.is_reloading and is_equal_approx(state.reload_elapsed_sec, 0.0)
	active_slot = original_slot
	_refresh_view_model()
	if not cancelled:
		return {"ok": false, "error": "reload was not cancelled by weapon switch"}
	return {"ok": true}

func select_slot_for_verification(slot: StringName) -> Dictionary:
	if not _slot_weapon_ids.has(slot):
		return {"ok": false, "error": "unknown slot %s" % String(slot)}
	active_slot = slot
	_refresh_view_model()
	return {"ok": true, "view_model": get_view_model_runtime_summary()}

func select_weapon_for_verification(weapon_id: StringName) -> Dictionary:
	if not _definitions.has(weapon_id):
		return {"ok": false, "error": "unknown weapon %s" % String(weapon_id)}
	var definition: WeaponDefinition = _definitions[weapon_id]
	loadout = _build_smoke_loadout_for_weapon(definition)
	reset_loadout()
	active_slot = definition.slot_type
	_refresh_view_model()
	return {
		"ok": true,
		"weapon_id": weapon_id,
		"slot": definition.slot_type,
		"definition_display_name": definition.display_name,
		"view_model": get_view_model_runtime_summary(),
		"active_summary": get_active_summary(),
	}

func fire_active_weapon_for_verification(camera: Camera3D, consume_state := false) -> Dictionary:
	if camera == null:
		return {"ok": false, "error": "missing camera"}
	var definition := get_active_definition()
	var state := get_active_state()
	if consume_state:
		if state.is_reloading or state.cooldown_remaining_sec > 0.0:
			return {"ok": false, "error": "active weapon cannot fire", "weapon_id": definition.weapon_id}
		if definition.magazine_size > 0:
			if state.ammo_in_mag <= 0:
				return {"ok": false, "error": "active weapon has no ammo", "weapon_id": definition.weapon_id}
			state.ammo_in_mag -= 1
		elif definition.charges_max > 0:
			if state.charges_current <= 0:
				return {"ok": false, "error": "active weapon has no charges", "weapon_id": definition.weapon_id}
			state.charges_current -= 1
		state.cooldown_remaining_sec = definition.shot_cooldown_sec
	else:
		state.is_reloading = false
		state.cooldown_remaining_sec = 0.0
		if definition.magazine_size > 0 and state.ammo_in_mag <= 0:
			state.ammo_in_mag = definition.magazine_size
	_spawn_first_person_fire_feedback(definition, 0.62, 0.14)
	var propulsion := _apply_primary_fire_propulsion(definition, _get_base_fire_direction(camera)) if consume_state else {}
	_fire_active_weapon_for_smoke(definition, camera)
	return {
		"ok": true,
		"weapon_id": definition.weapon_id,
		"view_model": get_view_model_runtime_summary(),
		"active_summary": get_active_summary(),
		"primary_fire_propulsion": propulsion,
	}

func apply_alt_fire_for_verification(delta: float) -> Dictionary:
	var definition := get_active_definition()
	if definition.alt_action_type == &"":
		return {"ok": false, "error": "active weapon has no alt action", "weapon_id": definition.weapon_id}
	if _owner_body == null:
		return {"ok": false, "error": "missing owner body", "weapon_id": definition.weapon_id}
	var velocity_before := _owner_body.velocity
	if definition.alt_action_type == &"propel":
		_owner_body.velocity += (-_owner_body.global_transform.basis.z + Vector3.UP * 0.55).normalized() * definition.propulsion_force * delta
	elif definition.alt_action_type == &"vault":
		_owner_body.velocity.y = maxf(_owner_body.velocity.y, definition.propulsion_force)
	elif definition.alt_action_type == &"rocket_lift":
		if _rocket_fuel_remaining_sec <= 0.0:
			_rocket_fuel_remaining_sec = definition.effect_duration_sec
		_owner_body.velocity.y += definition.propulsion_force * delta
	else:
		return {"ok": false, "error": "unsupported verification alt action %s" % String(definition.alt_action_type), "weapon_id": definition.weapon_id}
	return {
		"ok": _owner_body.velocity.length() > velocity_before.length() and _owner_body.velocity.y >= velocity_before.y,
		"weapon_id": definition.weapon_id,
		"alt_action_type": definition.alt_action_type,
		"propulsion_force": definition.propulsion_force,
		"rocket_fuel_remaining_sec": _rocket_fuel_remaining_sec,
		"velocity_before": velocity_before,
		"velocity_after": _owner_body.velocity,
	}

func get_view_model_runtime_summary() -> Dictionary:
	if _current_view_model == null or not is_instance_valid(_current_view_model):
		return {"has_view_model": false}
	var loader_summary := {}
	if _current_view_model.has_method("get_runtime_summary"):
		loader_summary = _current_view_model.get_runtime_summary()
	return {
		"has_view_model": true,
		"node_name": _current_view_model.name,
		"is_fallback": _current_view_model.name.begins_with("FallbackViewModel"),
		"summary": loader_summary,
	}

func reset_portals_for_verification() -> void:
	_clear_portals()

func get_portal_runtime_summary() -> Dictionary:
	var marker_count := 0
	if _effects_root != null:
		for child in _effects_root.get_children():
			if _is_portal_marker(child):
				marker_count += 1
	var radius := 0.0
	var duration := 0.0
	if _definitions.has(&"portal_gun"):
		var definition: WeaponDefinition = _definitions[&"portal_gun"]
		radius = definition.effect_radius_m
		duration = definition.effect_duration_sec
	return {
		"a_active": _portal_a_active,
		"b_active": _portal_b_active,
		"both_active": _portal_a_active and _portal_b_active,
		"a_position": _portal_a_position,
		"b_position": _portal_b_position,
		"distance_between": _portal_a_position.distance_to(_portal_b_position) if _portal_a_active and _portal_b_active else 0.0,
		"marker_count": marker_count,
		"effect_radius_m": radius,
		"effect_duration_sec": duration,
		"lifetime_remaining_sec": _portal_lifetime_remaining_sec,
		"fire_cooldown_sec": _portal_cooldown_sec,
		"transport_cooldown_sec": _portal_transport_cooldown_sec,
	}

func _is_active_weapon(weapon_id: StringName) -> bool:
	return _slot_weapon_ids.has(active_slot) and _slot_weapon_ids[active_slot] == weapon_id

func apply_authoritative_weapon_states(authoritative_states: Dictionary) -> void:
	for weapon_id_key in authoritative_states.keys():
		var weapon_id := StringName(weapon_id_key)
		if not _runtime_states.has(weapon_id):
			continue
		var authoritative_state: Dictionary = authoritative_states[weapon_id_key]
		var state: WeaponRuntimeState = _runtime_states[weapon_id]
		state.ammo_in_mag = int(authoritative_state.get("ammo_in_mag", state.ammo_in_mag))
		state.reserve_ammo = int(authoritative_state.get("reserve_ammo", state.reserve_ammo))
		state.charges_current = int(authoritative_state.get("charges_current", state.charges_current))
		state.is_reloading = bool(authoritative_state.get("is_reloading", state.is_reloading))
		state.reload_elapsed_sec = float(authoritative_state.get("reload_elapsed_sec", state.reload_elapsed_sec))
		state.cooldown_remaining_sec = float(authoritative_state.get("cooldown_remaining_sec", state.cooldown_remaining_sec))
	_emit_summary()

func _load_definitions() -> void:
	for weapon_id in WEAPON_PATHS.keys():
		var definition: WeaponDefinition = load(WEAPON_PATHS[weapon_id])
		_definitions[weapon_id] = definition

func _tick_runtime_states(delta: float) -> void:
	for weapon_id in _runtime_states.keys():
		var state: WeaponRuntimeState = _runtime_states[weapon_id]
		state.cooldown_remaining_sec = maxf(0.0, state.cooldown_remaining_sec - delta)
		if state.is_reloading:
			var definition: WeaponDefinition = _definitions[weapon_id]
			state.reload_elapsed_sec += delta
			if state.reload_elapsed_sec >= definition.reload_time_sec:
				var missing := definition.magazine_size - state.ammo_in_mag
				var loaded := mini(missing, state.reserve_ammo)
				state.ammo_in_mag += loaded
				state.reserve_ammo -= loaded
				state.cancel_reload()

func _tick_special_states(delta: float) -> void:
	_speed_buff_remaining_sec = maxf(0.0, _speed_buff_remaining_sec - delta)
	if _speed_buff_remaining_sec <= 0.0:
		_speed_buff_multiplier = 1.0
	_rocket_fuel_remaining_sec = maxf(0.0, _rocket_fuel_remaining_sec - delta)
	_portal_cooldown_sec = maxf(0.0, _portal_cooldown_sec - delta)
	_portal_transport_cooldown_sec = maxf(0.0, _portal_transport_cooldown_sec - delta)
	if _portal_a_active or _portal_b_active:
		_portal_lifetime_remaining_sec = maxf(0.0, _portal_lifetime_remaining_sec - delta)
		if _portal_lifetime_remaining_sec <= 0.0:
			_clear_portals()

func _update_sniper_scope(delta: float, camera: Camera3D) -> void:
	if camera != null and _camera_default_fov <= 0.0:
		_camera_default_fov = camera.fov
	var definition := get_active_definition()
	var sniper_active := definition.weapon_id == &"sniper" and definition.scope_enabled and not _input_locked
	var wants_scope := sniper_active and Input.is_action_pressed(FpsInputActions.FIRE_SECONDARY)
	var target_progress := 1.0 if wants_scope else 0.0
	var transition_step := delta / maxf(definition.scope_transition_sec, 0.001)
	_sniper_scope_progress = move_toward(_sniper_scope_progress, target_progress, transition_step)
	if camera != null and _camera_default_fov > 0.0:
		camera.fov = lerpf(_camera_default_fov, definition.scope_fov, _sniper_scope_progress)
	_apply_sniper_scope_view_model(sniper_active, definition)

func _apply_sniper_scope_view_model(sniper_active: bool, definition: WeaponDefinition) -> void:
	if _current_view_model == null or not is_instance_valid(_current_view_model) or not sniper_active:
		return
	var eased := _sniper_scope_progress * _sniper_scope_progress * (3.0 - 2.0 * _sniper_scope_progress)
	_current_view_model.position = Vector3.ZERO.lerp(definition.scope_viewmodel_position, eased)
	_current_view_model.rotation_degrees = Vector3.ZERO.lerp(definition.scope_viewmodel_rotation_degrees, eased)

func _handle_slot_input() -> void:
	var requested_slot := active_slot
	if Input.is_action_just_pressed(FpsInputActions.SLOT_PRIMARY):
		requested_slot = &"primary"
	elif Input.is_action_just_pressed(FpsInputActions.SLOT_SECONDARY):
		requested_slot = &"secondary"
	elif Input.is_action_just_pressed(FpsInputActions.SLOT_MELEE):
		requested_slot = &"melee"
	elif Input.is_action_just_pressed(FpsInputActions.SLOT_ARTILLERY):
		requested_slot = &"artillery"
	if requested_slot == active_slot:
		return
	_switch_active_slot(requested_slot)

func _switch_active_slot(requested_slot: StringName) -> void:
	if requested_slot == active_slot:
		return
	get_active_state().cancel_reload()
	active_slot = requested_slot
	_refresh_view_model()
	network_slot_changed.emit(active_slot)

func _handle_reload_input() -> void:
	if not Input.is_action_just_pressed(FpsInputActions.RELOAD):
		return
	var definition := get_active_definition()
	var state := get_active_state()
	if definition.magazine_size <= 0 or state.reserve_ammo <= 0 or state.ammo_in_mag >= definition.magazine_size:
		return
	if _multiplayer_combat_enabled:
		network_reload_requested.emit(definition.weapon_id)
	state.is_reloading = true
	state.reload_elapsed_sec = 0.0

func _handle_fire_input(camera: Camera3D) -> void:
	var definition := get_active_definition()
	var state := get_active_state()
	var wants_fire := Input.is_action_pressed(FpsInputActions.FIRE_PRIMARY) if definition.supports_hold_fire else Input.is_action_just_pressed(FpsInputActions.FIRE_PRIMARY)
	if not wants_fire:
		return
	_try_fire_active_weapon(definition, state, camera)

func _try_fire_active_weapon(definition: WeaponDefinition, state: WeaponRuntimeState, camera: Camera3D) -> bool:
	if camera == null or state.is_reloading or state.cooldown_remaining_sec > 0.0:
		return false
	if definition.magazine_size > 0:
		if state.ammo_in_mag <= 0:
			_try_auto_reload(definition, state)
			return false
		state.ammo_in_mag -= 1
	elif definition.charges_max > 0:
		if state.charges_current <= 0:
			return false
		state.charges_current -= 1
	state.cooldown_remaining_sec = definition.shot_cooldown_sec
	var origin := camera.global_position
	var direction := _get_base_fire_direction(camera)
	_spawn_first_person_fire_feedback(definition)
	_apply_primary_fire_propulsion(definition, direction)
	if _multiplayer_combat_enabled:
		if definition.fire_mode == &"self_buff":
			_apply_self_buff(definition)
		elif definition.fire_mode == &"portal":
			_place_portal(definition, origin, direction, camera)
		var shooter_velocity := Vector3.ZERO
		if _owner_body != null:
			shooter_velocity = _owner_body.velocity
		network_fire_requested.emit(definition.weapon_id, origin, direction, shooter_velocity)
		return true
	if definition.is_hitscan or definition.fire_mode == &"melee":
		_fire_trace_weapon(definition, origin, direction, camera)
	elif definition.uses_projectile:
		_fire_projectile(definition, origin, direction, camera)
	elif definition.fire_mode == &"self_buff":
		_apply_self_buff(definition)
	elif definition.fire_mode == &"portal":
		_place_portal(definition, origin, direction, camera)
	return true

func _fire_active_weapon_for_smoke(definition: WeaponDefinition, camera: Camera3D) -> void:
	var origin := camera.global_position
	var direction := _get_base_fire_direction(camera)
	if definition.is_hitscan or definition.fire_mode == &"melee":
		_fire_trace_weapon(definition, origin, direction, camera)
	elif definition.uses_projectile:
		_fire_projectile(definition, origin, direction, camera)
	elif definition.fire_mode == &"self_buff":
		_apply_self_buff(definition)
	elif definition.fire_mode == &"portal":
		_place_portal(definition, origin, direction, camera)

func _validate_weapon_runtime_assets(definition: WeaponDefinition) -> Dictionary:
	if definition.uses_projectile:
		if definition.projectile_scene_path == "":
			return {"ok": false, "error": "projectile weapon %s has no projectile scene" % String(definition.weapon_id)}
		if not ResourceLoader.exists(definition.projectile_scene_path, "PackedScene"):
			return {"ok": false, "error": "projectile scene missing for %s: %s" % [String(definition.weapon_id), definition.projectile_scene_path]}
	return {"ok": true}

func _build_smoke_loadout_for_weapon(definition: WeaponDefinition) -> LoadoutDefinition:
	var primary_id := loadout.primary_weapon_id
	var secondary_id := loadout.secondary_weapon_id
	var melee_id := loadout.melee_weapon_id
	var artillery_id := loadout.artillery_weapon_id
	if definition.slot_type == &"primary":
		primary_id = definition.weapon_id
	elif definition.slot_type == &"secondary":
		secondary_id = definition.weapon_id
	elif definition.slot_type == &"melee":
		melee_id = definition.weapon_id
	elif definition.slot_type == &"artillery":
		artillery_id = definition.weapon_id
	return loadout.duplicate_with_slots(primary_id, secondary_id, melee_id, artillery_id)

func _try_auto_reload(definition: WeaponDefinition, state: WeaponRuntimeState) -> void:
	if definition.reload_time_sec > 0.0 and state.reserve_ammo > 0:
		state.is_reloading = true
		state.reload_elapsed_sec = 0.0

func _handle_alt_fire_input(_camera: Camera3D, delta: float) -> void:
	var definition := get_active_definition()
	if definition.alt_action_type == &"" or not Input.is_action_pressed(FpsInputActions.FIRE_SECONDARY):
		return
	if definition.alt_action_type == &"propel" and _owner_body != null:
		_owner_body.velocity += (-_owner_body.global_transform.basis.z + Vector3.UP * 0.55).normalized() * definition.propulsion_force * delta
	elif definition.alt_action_type == &"vault" and _owner_body != null and Input.is_action_just_pressed(FpsInputActions.FIRE_SECONDARY):
		_owner_body.velocity.y = maxf(_owner_body.velocity.y, definition.propulsion_force)
	elif definition.alt_action_type == &"rocket_lift" and _owner_body != null:
		if _rocket_fuel_remaining_sec <= 0.0:
			_rocket_fuel_remaining_sec = definition.effect_duration_sec
		if _rocket_fuel_remaining_sec > 0.0:
			_owner_body.velocity.y += definition.propulsion_force * delta

func _apply_primary_fire_propulsion(definition: WeaponDefinition, direction: Vector3) -> Dictionary:
	if definition.weapon_id != &"flamethrower" or _owner_body == null:
		return {}
	var velocity_before := _owner_body.velocity
	var fuel_tick := maxf(definition.shot_cooldown_sec, 1.0 / 30.0)
	var fire_dir := direction.normalized()
	var horizontal_recoil := Vector3(-fire_dir.x, 0.0, -fire_dir.z)
	if horizontal_recoil.length_squared() <= 0.0001:
		horizontal_recoil = _owner_body.global_transform.basis.z
		horizontal_recoil.y = 0.0
	horizontal_recoil = horizontal_recoil.normalized()
	var thrust_dir := (horizontal_recoil + Vector3.UP * 1.25).normalized()
	var impulse := definition.propulsion_force * fuel_tick
	_owner_body.velocity += thrust_dir * impulse
	_owner_body.velocity.y = maxf(_owner_body.velocity.y, velocity_before.y + impulse * 0.80)
	return {
		"ok": _owner_body.velocity.y > velocity_before.y,
		"weapon_id": definition.weapon_id,
		"uses_primary_fire_fuel": true,
		"fire_direction": fire_dir,
		"recoil_direction": thrust_dir,
		"propulsion_force": definition.propulsion_force,
		"impulse": impulse,
		"velocity_before": velocity_before,
		"velocity_after": _owner_body.velocity,
	}

func _get_base_fire_direction(camera: Camera3D) -> Vector3:
	return (-camera.global_transform.basis.z).normalized()

func _fire_trace_weapon(definition: WeaponDefinition, origin: Vector3, direction: Vector3, camera: Camera3D) -> void:
	if definition.fire_mode == &"portal":
		_place_portal(definition, origin, direction, camera)
		return
	var pellets := maxi(1, definition.pellets_per_shot)
	for _index in range(pellets):
		var pellet_direction := direction
		if definition.is_hitscan and definition.spread_degrees > 0.0:
			pellet_direction = _apply_spread(direction, definition.spread_degrees)
		_fire_single_trace(definition, origin, pellet_direction, camera)

func _fire_single_trace(definition: WeaponDefinition, origin: Vector3, direction: Vector3, camera: Camera3D) -> void:
	var max_range := definition.max_range_m
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_range)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	if _owner_body != null:
		query.exclude = [_owner_body.get_rid()]
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_spawn_impact(hit["position"], hit["normal"])
	var collider: Object = hit["collider"]
	if collider == null:
		return
	if definition.fire_mode == &"utility":
		_apply_utility_effect(definition, collider)
		return
	if not collider.has_method("apply_damage"):
		return
	var event := DamageEvent.new()
	event.weapon_id = definition.weapon_id
	event.hit_position = hit["position"]
	event.hit_normal = hit["normal"]
	if collider.has_method("is_headshot_position") and collider.is_headshot_position(event.hit_position):
		event.is_headshot = true
	event.amount = definition.head_damage if event.is_headshot else definition.body_damage
	var killed: bool = collider.apply_damage(event)
	hit_confirmed.emit(event.amount, killed)

func _fire_projectile(definition: WeaponDefinition, origin: Vector3, direction: Vector3, _camera: Camera3D) -> void:
	if _projectiles_root == null:
		return
	var projectile_scene: PackedScene = load(definition.projectile_scene_path)
	var projectile := projectile_scene.instantiate()
	_projectiles_root.add_child(projectile)
	projectile.global_position = origin + direction * 0.65
	var inherited_velocity := Vector3.ZERO
	if _owner_body != null:
		inherited_velocity = _owner_body.velocity * 0.35
	if projectile.has_method("setup"):
		projectile.setup(direction * definition.projectile_speed_mps + inherited_velocity, definition, _effects_root)

func _apply_self_buff(definition: WeaponDefinition) -> void:
	if definition.alt_action_type != &"speed_buff":
		return
	_speed_buff_remaining_sec = definition.effect_duration_sec
	_speed_buff_multiplier = definition.move_speed_multiplier

func _apply_lasso_pull(collider: Object) -> void:
	if _owner_body == null or not (collider is Node3D):
		return
	var target := collider as Node3D
	var pull_direction := (_owner_body.global_position - target.global_position).normalized()
	if target is CharacterBody3D:
		var target_body := target as CharacterBody3D
		target_body.velocity += pull_direction * get_active_definition().propulsion_force

func _apply_utility_effect(definition: WeaponDefinition, collider: Object) -> void:
	if definition.alt_action_type == &"pull":
		_apply_lasso_pull(collider)
		hit_confirmed.emit(0.0, false)
	elif definition.alt_action_type == &"stun":
		if collider.has_method("apply_stun"):
			collider.apply_stun(definition.effect_duration_sec)
			hit_confirmed.emit(0.0, false)

func _place_portal(definition: WeaponDefinition, origin: Vector3, direction: Vector3, camera: Camera3D) -> void:
	if _portal_cooldown_sec > 0.0:
		return
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * definition.max_range_m)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if _owner_body != null:
		query.exclude = [_owner_body.get_rid()]
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	if not _portal_a_active:
		_portal_a_position = hit["position"]
		_portal_a_active = true
		_spawn_portal_marker(&"A", hit["position"], hit["normal"], Color(0.10, 0.50, 1.0, 1.0))
	else:
		_portal_b_position = hit["position"]
		_portal_b_active = true
		_spawn_portal_marker(&"B", hit["position"], hit["normal"], Color(1.0, 0.48, 0.06, 1.0))
	_portal_cooldown_sec = definition.shot_cooldown_sec
	_portal_lifetime_remaining_sec = definition.effect_duration_sec
	_spawn_impact(hit["position"], hit["normal"])

func try_apply_portal_transport(body: CharacterBody3D) -> bool:
	if not _portal_a_active or not _portal_b_active:
		return false
	if _portal_transport_cooldown_sec > 0.0:
		return false
	var radius: float = _definitions[&"portal_gun"].effect_radius_m
	if body.global_position.distance_to(_portal_a_position) <= radius:
		body.global_position = _portal_b_position + _portal_exit_direction(body.velocity, _portal_a_position, _portal_b_position) * radius
		_portal_transport_cooldown_sec = _definitions[&"portal_gun"].shot_cooldown_sec
		return true
	elif body.global_position.distance_to(_portal_b_position) <= radius:
		body.global_position = _portal_a_position + _portal_exit_direction(body.velocity, _portal_b_position, _portal_a_position) * radius
		_portal_transport_cooldown_sec = _definitions[&"portal_gun"].shot_cooldown_sec
		return true
	return false

func _portal_exit_direction(velocity: Vector3, from_position: Vector3, to_position: Vector3) -> Vector3:
	if velocity.length() > 0.01:
		return velocity.normalized()
	var fallback := (to_position - from_position).normalized()
	return fallback if fallback.length_squared() > 0.001 else Vector3.FORWARD

func _spawn_portal_marker(portal_id: StringName, position: Vector3, normal: Vector3, color: Color) -> void:
	if _effects_root == null:
		return
	_remove_portal_marker(portal_id)
	var marker := Node3D.new()
	marker.name = "PortalMarker%s_%d" % [String(portal_id), marker.get_instance_id()]
	marker.set_meta("portal_marker", true)
	marker.set_meta("portal_id", portal_id)
	_effects_root.add_child(marker)
	var safe_normal := normal.normalized()
	if safe_normal.length_squared() <= 0.001:
		safe_normal = Vector3.UP
	marker.global_position = position + safe_normal * 0.035

	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = _definitions[&"portal_gun"].effect_radius_m * 0.32
	glow_mesh.height = _definitions[&"portal_gun"].effect_radius_m * 0.12
	glow.mesh = glow_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.material_override = material
	marker.add_child(glow)

	var core := MeshInstance3D.new()
	core.name = "Core"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = _definitions[&"portal_gun"].effect_radius_m * 0.14
	core_mesh.height = _definitions[&"portal_gun"].effect_radius_m * 0.06
	core.mesh = core_mesh
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color(0.95, 0.98, 1.0, 1.0)
	core_material.emission_enabled = true
	core_material.emission = color.lightened(0.35)
	core_material.emission_energy_multiplier = 4.0
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = core_material
	marker.add_child(core)

func _remove_portal_marker(portal_id: StringName) -> void:
	if _effects_root == null:
		return
	for child in _effects_root.get_children():
		if _is_portal_marker(child) and StringName(str(child.get_meta("portal_id", &""))) == portal_id:
			child.queue_free()

func _clear_portals() -> void:
	_portal_a_position = Vector3.ZERO
	_portal_b_position = Vector3.ZERO
	_portal_a_active = false
	_portal_b_active = false
	_portal_cooldown_sec = 0.0
	_portal_lifetime_remaining_sec = 0.0
	_portal_transport_cooldown_sec = 0.0
	if _effects_root == null:
		return
	for child in _effects_root.get_children():
		if _is_portal_marker(child):
			child.queue_free()

func _is_portal_marker(node: Node) -> bool:
	return bool(node.get_meta("portal_marker", false)) or String(node.name).begins_with("PortalMarker")

func _apply_spread(direction: Vector3, spread_degrees: float) -> Vector3:
	var spread := deg_to_rad(spread_degrees)
	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(direction).normalized()
	var offset := right * randf_range(-spread, spread) + up * randf_range(-spread, spread)
	return (direction + offset).normalized()

func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	if _effects_root == null:
		return
	var impact := _impact_scene.instantiate()
	_effects_root.add_child(impact)
	impact.global_position = position + normal * 0.02
	if impact.has_method("align_to_normal"):
		impact.align_to_normal(normal)

func _spawn_muzzle_flash(lifetime_sec := 0.08, visual_scale := 1.0) -> void:
	if _view_model_root == null:
		return
	var flash := OmniLight3D.new()
	flash.name = "MuzzleFlash"
	flash.position = Vector3(0.18, -0.03, -1.05)
	flash.light_color = Color(1.0, 0.66, 0.30)
	flash.light_energy = 2.6 * visual_scale
	flash.omni_range = 1.8 * visual_scale
	_view_model_root.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, lifetime_sec)
	tween.tween_callback(flash.queue_free)

func _spawn_first_person_fire_feedback(definition: WeaponDefinition, visual_scale := 1.0, lifetime_sec := 0.08) -> void:
	_play_view_model_recoil(definition)
	if [&"assault_rifle", &"handgun"].has(definition.weapon_id):
		return
	if definition.weapon_id == &"flamethrower":
		_spawn_flame_burst(visual_scale)
	else:
		_spawn_muzzle_flash(lifetime_sec, visual_scale)

func _play_view_model_recoil(definition: WeaponDefinition) -> void:
	if _current_view_model == null or not is_instance_valid(_current_view_model):
		return
	var kick_scale := 1.0
	if definition.weapon_id == &"assault_rifle":
		kick_scale = 0.62
	elif definition.weapon_id == &"handgun":
		kick_scale = 0.88
	elif definition.weapon_id == &"shotgun" or definition.weapon_id == &"sniper":
		kick_scale = 1.18
	var recoil_offset := Vector3(0.0, -0.012, 0.075) * kick_scale
	var recoil_rotation := Vector3(-4.5, randf_range(-0.7, 0.7), randf_range(-0.8, 0.8)) * kick_scale
	_current_view_model.position = recoil_offset
	_current_view_model.rotation_degrees = recoil_rotation
	var tween := _current_view_model.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_current_view_model, "position", Vector3.ZERO, 0.105)
	tween.tween_property(_current_view_model, "rotation_degrees", Vector3.ZERO, 0.105)

func _spawn_flame_burst(visual_scale := 1.0) -> void:
	if _view_model_root == null:
		return
	var burst := FLAME_BURST_SCENE.instantiate()
	burst.name = "FlameBurst"
	burst.position = Vector3(0.12, -0.06, -1.00)
	burst.scale = Vector3.ONE * visual_scale
	_view_model_root.add_child(burst)

func _emit_summary() -> void:
	weapon_state_changed.emit(get_active_summary())

func _refresh_view_model() -> void:
	if _view_model_root == null or _slot_weapon_ids.is_empty():
		return
	if _current_view_model != null and is_instance_valid(_current_view_model):
		_current_view_model.queue_free()
	for child in _view_model_root.get_children():
		child.visible = false
	var weapon_id: StringName = _slot_weapon_ids[active_slot]
	if VIEW_MODEL_PATHS.has(weapon_id):
		var scene := _load_view_model_scene(VIEW_MODEL_PATHS[weapon_id])
		if scene != null:
			_current_view_model = scene.instantiate()
			_current_view_model.name = "AssetViewModel_%s" % String(weapon_id)
			_current_view_model.position = Vector3.ZERO
			_current_view_model.rotation_degrees = Vector3.ZERO
			_current_view_model.scale = Vector3.ONE
			_view_model_root.add_child(_current_view_model)
			return
	var fallback := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.12, 0.58)
	fallback.mesh = mesh
	fallback.name = "FallbackViewModel_%s" % String(weapon_id)
	_view_model_root.add_child(fallback)
	_current_view_model = fallback

func _load_view_model_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	return ResourceLoader.load(path, "PackedScene") as PackedScene
