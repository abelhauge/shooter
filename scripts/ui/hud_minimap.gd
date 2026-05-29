class_name HudMiniMap
extends Control

const BLUE_COLOR := Color(0.30, 0.62, 1.0, 1.0)
const ORANGE_COLOR := Color(1.0, 0.43, 0.13, 1.0)
const SELF_COLOR := Color(0.88, 0.96, 1.0, 1.0)
const MAP_BG := Color(0.012, 0.018, 0.026, 0.82)
const MAP_GRID := Color(0.62, 0.78, 0.92, 0.18)
const MAP_BORDER := Color(0.28, 0.78, 0.68, 0.70)

@export var fallback_range_m := 80.0

var _snapshot := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	queue_redraw()

func get_target_count() -> int:
	return (_snapshot.get("enemies", []) as Array).size()

func get_range_m() -> float:
	return maxf(1.0, float(_snapshot.get("range_m", fallback_range_m)))

func _draw() -> void:
	var map_size := minf(size.x, size.y)
	if map_size <= 2.0:
		return
	var center := size * 0.5
	var radius := map_size * 0.44
	var range_m := get_range_m()
	draw_circle(center, radius + 6.0, Color(0.0, 0.0, 0.0, 0.38))
	draw_circle(center, radius + 2.0, MAP_BG)
	for ring_scale in [0.33, 0.66, 1.0]:
		draw_arc(center, radius * ring_scale, 0.0, TAU, 96, MAP_GRID, 1.0, true)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), MAP_GRID, 1.0, true)
	draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), MAP_GRID, 1.0, true)
	draw_arc(center, radius + 2.0, 0.0, TAU, 96, MAP_BORDER, 2.0, true)

	var local_position: Vector3 = _snapshot.get("local_position", Vector3.ZERO)
	var local_yaw := float(_snapshot.get("local_yaw", 0.0))
	var enemies: Array = _snapshot.get("enemies", [])
	for enemy in enemies:
		if not (enemy is Dictionary):
			continue
		var enemy_position: Vector3 = enemy.get("position", Vector3.ZERO)
		var relative := Vector2(enemy_position.x - local_position.x, enemy_position.z - local_position.z)
		var distance_m := relative.length()
		if distance_m <= 0.01:
			continue
		var local_relative := relative.rotated(local_yaw)
		var clamped := local_relative
		if clamped.length() > range_m:
			clamped = clamped.normalized() * range_m
		var dot_position := center + clamped * (radius / range_m)
		var alpha := 1.0 if distance_m <= range_m else 0.58
		var team_id := int(enemy.get("team_id", 2))
		var dot_color := ORANGE_COLOR if team_id != 1 else BLUE_COLOR
		dot_color.a = alpha
		draw_circle(dot_position, 6.5, Color(0.0, 0.0, 0.0, 0.60 * alpha))
		draw_circle(dot_position, 4.5, dot_color)
		draw_arc(dot_position, 7.5, 0.0, TAU, 24, Color(dot_color.r, dot_color.g, dot_color.b, 0.45 * alpha), 1.5, true)

	_draw_player_marker(center)

func _draw_player_marker(center: Vector2) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -10.0),
		center + Vector2(7.0, 8.0),
		center + Vector2(0.0, 4.5),
		center + Vector2(-7.0, 8.0),
	])
	draw_colored_polygon(points, SELF_COLOR)
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.72), 1.5, true)
