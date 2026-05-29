class_name WeaponRuntimeState
extends RefCounted

var weapon_id: StringName
var ammo_in_mag := 0
var reserve_ammo := 0
var charges_current := 0
var is_reloading := false
var reload_elapsed_sec := 0.0
var cooldown_remaining_sec := 0.0
var is_trigger_held := false

static func from_definition(definition: WeaponDefinition) -> WeaponRuntimeState:
	var state := WeaponRuntimeState.new()
	state.weapon_id = definition.weapon_id
	state.ammo_in_mag = definition.magazine_size
	state.reserve_ammo = definition.reserve_ammo_max
	state.charges_current = definition.charges_max
	return state

func cancel_reload() -> void:
	is_reloading = false
	reload_elapsed_sec = 0.0

