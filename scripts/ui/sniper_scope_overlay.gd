class_name SniperScopeOverlay
extends Control

var _scope_progress := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func set_scope_progress(progress: float) -> void:
	_scope_progress = clampf(progress, 0.0, 1.0)
	visible = _scope_progress > 0.02
	queue_redraw()

func get_scope_progress() -> float:
	return _scope_progress

func _draw() -> void:
	if _scope_progress <= 0.02:
		return
	var viewport_size := size
	var center := viewport_size * 0.5
	var radius := minf(viewport_size.x, viewport_size.y) * lerpf(0.24, 0.38, _scope_progress)
	var shade := Color(0.0, 0.0, 0.0, 0.80 * _scope_progress)
	var edge := Color(0.0, 0.0, 0.0, 0.92 * _scope_progress)
	var top_left := center + Vector2(-radius, -radius)
	var top_right := center + Vector2(radius, -radius)
	var bottom_right := center + Vector2(radius, radius)
	var bottom_left := center + Vector2(-radius, radius)
	draw_rect(Rect2(Vector2.ZERO, Vector2(viewport_size.x, center.y - radius)), shade)
	draw_rect(Rect2(Vector2(0.0, center.y + radius), Vector2(viewport_size.x, viewport_size.y - center.y - radius)), shade)
	draw_rect(Rect2(Vector2(0.0, center.y - radius), Vector2(center.x - radius, radius * 2.0)), shade)
	draw_rect(Rect2(Vector2(center.x + radius, center.y - radius), Vector2(viewport_size.x - center.x - radius, radius * 2.0)), shade)
	_draw_scope_corner(center, radius, -PI * 0.5, -PI, top_left, shade)
	_draw_scope_corner(center, radius, -PI * 0.5, 0.0, top_right, shade)
	_draw_scope_corner(center, radius, 0.0, PI * 0.5, bottom_right, shade)
	_draw_scope_corner(center, radius, PI * 0.5, PI, bottom_left, shade)
	draw_arc(center, radius, 0.0, TAU, 128, edge, 5.0, true)
	draw_arc(center, radius - 7.0, 0.0, TAU, 128, Color(0.08, 0.11, 0.12, 0.70 * _scope_progress), 1.5, true)
	var reticle_color := Color(0.0, 0.0, 0.0, 0.72 * _scope_progress)
	draw_line(center + Vector2(-26.0, 0.0), center + Vector2(-7.0, 0.0), reticle_color, 1.5)
	draw_line(center + Vector2(7.0, 0.0), center + Vector2(26.0, 0.0), reticle_color, 1.5)
	draw_line(center + Vector2(0.0, -26.0), center + Vector2(0.0, -7.0), reticle_color, 1.5)
	draw_line(center + Vector2(0.0, 7.0), center + Vector2(0.0, 26.0), reticle_color, 1.5)
	draw_circle(center, lerpf(2.0, 4.0, _scope_progress), Color(1.0, 0.04, 0.02, _scope_progress))

func _draw_scope_corner(center: Vector2, radius: float, start_angle: float, end_angle: float, corner: Vector2, color: Color) -> void:
	var points: PackedVector2Array = [corner]
	var steps := 24
	for index in range(steps + 1):
		var weight := float(index) / float(steps)
		var angle := lerpf(start_angle, end_angle, weight)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
