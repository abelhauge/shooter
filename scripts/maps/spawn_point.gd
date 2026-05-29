class_name SpawnPoint
extends Marker3D

@export var team_id := 1
@export var spawn_group: StringName = &"default"
@export var yaw_degrees := 0.0
@export var is_enabled := true

func apply_to_player(player: PlayerController) -> void:
	player.global_position = global_position
	player.rotation.y = deg_to_rad(yaw_degrees)
	player.yaw = player.rotation.y
	player.pitch = 0.0
	player.head_pivot.rotation.x = 0.0
	player.velocity = Vector3.ZERO
