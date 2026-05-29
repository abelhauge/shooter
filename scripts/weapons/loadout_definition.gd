class_name LoadoutDefinition
extends Resource

@export var loadout_id: StringName = &"default_v1"
@export var display_name := "Default V1"
@export var primary_weapon_id: StringName = &"assault_rifle"
@export var secondary_weapon_id: StringName = &"handgun"
@export var melee_weapon_id: StringName = &"knife"
@export var artillery_weapon_id: StringName = &"smoke_bomb"

func duplicate_with_slots(primary_id: StringName, secondary_id: StringName, melee_id: StringName, artillery_id: StringName) -> LoadoutDefinition:
	var copy := LoadoutDefinition.new()
	copy.loadout_id = &"custom_v1"
	copy.display_name = "Custom V1"
	copy.primary_weapon_id = primary_id
	copy.secondary_weapon_id = secondary_id
	copy.melee_weapon_id = melee_id
	copy.artillery_weapon_id = artillery_id
	return copy
