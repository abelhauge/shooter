extends CanvasLayer

const SNIPER_SCOPE_OVERLAY_SCRIPT := preload("res://scripts/ui/sniper_scope_overlay.gd")
const HUD_MINIMAP_SCRIPT := preload("res://scripts/ui/hud_minimap.gd")

var _player: PlayerController
var _map_provider: Node
var _root: Control
var _debug_label: Label
var _combat_label: Label
var _feedback_label: Label
var _match_label: Label
var _perf_label: Label
var _crosshair_root: Control
var _sniper_scope_overlay: Control
var _mini_map
var _feedback_timer := 0.0
var _match_director: MatchDirector

func _ready() -> void:
	_build_ui()

func bind_player(player: PlayerController) -> void:
	_player = player
	if not is_node_ready():
		await ready
	player.get_weapon_controller().hit_confirmed.connect(_on_hit_confirmed)

func bind_match_director(match_director: MatchDirector) -> void:
	_match_director = match_director

func bind_map_provider(map_provider: Node) -> void:
	_map_provider = map_provider

func get_runtime_smoke_summary() -> Dictionary:
	_update_debug()
	_update_combat()
	_update_match()
	_update_perf()
	_update_minimap()
	_update_sniper_scope_overlay()
	return {
		"debug_text": _debug_label.text,
		"combat_text": _combat_label.text,
		"match_text": _match_label.text,
		"perf_text": _perf_label.text,
		"has_feedback_label": _feedback_label != null,
		"crosshair_visible": _crosshair_root.visible if _crosshair_root != null else false,
		"has_minimap": _mini_map != null,
		"minimap_target_count": _mini_map.get_target_count() if _mini_map != null else 0,
		"minimap_range_m": _mini_map.get_range_m() if _mini_map != null else 0.0,
		"sniper_scope_visible": _sniper_scope_overlay.visible if _sniper_scope_overlay != null else false,
		"sniper_scope_progress": _sniper_scope_overlay.call("get_scope_progress") if _sniper_scope_overlay != null else 0.0,
	}

func _process(delta: float) -> void:
	_update_responsive_layout()
	if _player == null:
		return
	_feedback_timer = maxf(0.0, _feedback_timer - delta)
	_update_debug()
	_update_combat()
	_update_match()
	_update_perf()
	_update_minimap()
	_update_sniper_scope_overlay()
	_feedback_label.visible = _feedback_timer > 0.0

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "HudRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_debug_label = _add_readout_panel(
		Vector2(16, 14),
		Vector2(246, 84),
		Color(0.015, 0.025, 0.035, 0.72),
		Color(0.20, 0.54, 0.92, 0.72),
		15
	)

	_combat_label = _add_readout_panel(
		Vector2(18, 520),
		Vector2(286, 182),
		Color(0.018, 0.024, 0.030, 0.82),
		Color(0.96, 0.44, 0.16, 0.75),
		18
	)

	_match_label = _add_readout_panel(
		Vector2(472, 14),
		Vector2(336, 76),
		Color(0.012, 0.018, 0.026, 0.78),
		Color(0.92, 0.82, 0.42, 0.82),
		20
	)
	_match_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_perf_label = _add_readout_panel(
		Vector2(1068, 14),
		Vector2(194, 74),
		Color(0.015, 0.025, 0.035, 0.70),
		Color(0.28, 0.78, 0.68, 0.72),
		15
	)

	_mini_map = HUD_MINIMAP_SCRIPT.new()
	_mini_map.name = "EnemyMiniMap"
	_mini_map.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_mini_map.custom_minimum_size = Vector2(164.0, 164.0)
	_mini_map.size = Vector2(164.0, 164.0)
	_root.add_child(_mini_map)

	_feedback_label = Label.new()
	_feedback_label.name = "FeedbackLabel"
	_feedback_label.text = "HIT"
	_feedback_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feedback_label.add_theme_font_size_override("font_size", 34)
	_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.22, 1.0))
	_feedback_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_feedback_label.add_theme_constant_override("shadow_offset_x", 2)
	_feedback_label.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_feedback_label)

	_sniper_scope_overlay = SNIPER_SCOPE_OVERLAY_SCRIPT.new()
	_sniper_scope_overlay.name = "SniperScopeOverlay"
	_sniper_scope_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.add_child(_sniper_scope_overlay)

	_crosshair_root = Control.new()
	_crosshair_root.name = "CrosshairRoot"
	_crosshair_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair_root)
	_add_crosshair_segment(Vector2(-24, -1), Vector2(12, 2), Color(0.0, 0.0, 0.0, 0.70))
	_add_crosshair_segment(Vector2(12, -1), Vector2(12, 2), Color(0.0, 0.0, 0.0, 0.70))
	_add_crosshair_segment(Vector2(-1, -24), Vector2(2, 12), Color(0.0, 0.0, 0.0, 0.70))
	_add_crosshair_segment(Vector2(-1, 12), Vector2(2, 12), Color(0.0, 0.0, 0.0, 0.70))
	_add_crosshair_segment(Vector2(-22, -1), Vector2(10, 2), Color(0.88, 0.95, 1.0, 0.92))
	_add_crosshair_segment(Vector2(12, -1), Vector2(10, 2), Color(1.0, 0.54, 0.24, 0.92))
	_add_crosshair_segment(Vector2(-1, -22), Vector2(2, 10), Color(0.88, 0.95, 1.0, 0.92))
	_add_crosshair_segment(Vector2(-1, 12), Vector2(2, 10), Color(1.0, 0.54, 0.24, 0.92))
	_add_crosshair_segment(Vector2(-2, -2), Vector2(4, 4), Color(0.96, 0.84, 0.32, 0.95))
	_update_responsive_layout()

func _update_responsive_layout() -> void:
	if _root == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_root.offset_left = 0.0
	_root.offset_top = 0.0
	_root.offset_right = 0.0
	_root.offset_bottom = 0.0
	if _crosshair_root != null:
		_crosshair_root.position = viewport_size * 0.5
	if _sniper_scope_overlay != null:
		_sniper_scope_overlay.position = Vector2.ZERO
		_sniper_scope_overlay.size = viewport_size
	if _feedback_label != null:
		_feedback_label.position = viewport_size * 0.5 + Vector2(-120.0, -62.0)
		_feedback_label.size = Vector2(240.0, 44.0)
	if _mini_map != null:
		var map_size := clampf(viewport_size.x * 0.13, 136.0, 172.0)
		_mini_map.size = Vector2(map_size, map_size)
		_mini_map.position = Vector2(
			maxf(18.0, viewport_size.x - map_size - 18.0),
			102.0 if viewport_size.y >= 640.0 else 92.0
		)

func _add_readout_panel(position: Vector2, size: Vector2, color: Color, border_color: Color, font_size: int) -> Label:
	var panel := PanelContainer.new()
	panel.position = position
	panel.custom_minimum_size = size
	panel.add_theme_stylebox_override("panel", _panel_style(color, border_color))
	_root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var label := Label.new()
	label.custom_minimum_size = size - Vector2(24, 18)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	margin.add_child(label)
	return label

func _panel_style(color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 8
	return style

func _add_crosshair_segment(position: Vector2, size: Vector2, color: Color) -> void:
	var segment := ColorRect.new()
	segment.position = position
	segment.size = size
	segment.color = color
	_crosshair_root.add_child(segment)

func _update_debug() -> void:
	_debug_label.text = "Speed: %.1f m/s\nGrounded: %s\nState: %s" % [
		_player.get_speed_mps(),
		str(_player.is_on_floor()),
		String(_player.movement_state),
	]

func _update_combat() -> void:
	var health := _player.get_health_component()
	var weapon_summary := _player.get_weapon_controller().get_active_summary()
	var ammo_text := "%d / %d" % [weapon_summary["ammo_in_mag"], weapon_summary["reserve_ammo"]]
	if weapon_summary["charges_max"] > 0:
		ammo_text = "%d charges" % weapon_summary["charges_current"]
	var buff_text := ""
	if float(weapon_summary.get("speed_buff_remaining_sec", 0.0)) > 0.0:
		buff_text = "\nSpeed Buff: x%.2f %.1fs" % [
			float(weapon_summary.get("speed_multiplier", 1.0)),
			float(weapon_summary.get("speed_buff_remaining_sec", 0.0)),
		]
	_combat_label.text = "HP: %d\nSlot: %s\nWeapon: %s\nAmmo: %s\nCooldown: %.2f%s%s" % [
		roundi(health.current_health),
		String(weapon_summary["slot"]),
		weapon_summary["display_name"],
		ammo_text,
		weapon_summary["cooldown_remaining_sec"],
		" RELOADING" if weapon_summary["is_reloading"] else "",
		buff_text,
	]

func _update_match() -> void:
	if _match_director == null:
		_match_label.text = ""
		return
	var summary := _match_director.get_summary()
	var remaining: float = summary["remaining_time_sec"]
	var minutes := floori(remaining / 60.0)
	var seconds := floori(fmod(remaining, 60.0))
	var phase_text := String(summary["phase"]).to_upper()
	_match_label.text = "%s  %02d:%02d\nBlue %d  Orange %d  / %d" % [
		phase_text,
		minutes,
		seconds,
		summary["blue_score"],
		summary["orange_score"],
		summary["score_limit"],
	]

func _update_perf() -> void:
	_perf_label.text = "FPS: %d\nNodes: %d" % [
		Engine.get_frames_per_second(),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	]

func _update_minimap() -> void:
	if _mini_map == null:
		return
	var snapshot := {}
	if _map_provider != null and is_instance_valid(_map_provider) and _map_provider.has_method("get_hud_map_snapshot"):
		snapshot = _map_provider.call("get_hud_map_snapshot")
	_mini_map.set_snapshot(snapshot)

func _update_sniper_scope_overlay() -> void:
	if _sniper_scope_overlay == null or _crosshair_root == null:
		return
	if _player == null:
		_sniper_scope_overlay.call("set_scope_progress", 0.0)
		_crosshair_root.visible = true
		return
	var scope_summary := _player.get_weapon_controller().get_sniper_scope_summary()
	var scope_visible := bool(scope_summary.get("scope_visible", false))
	_sniper_scope_overlay.call("set_scope_progress", float(scope_summary.get("scope_progress", 0.0)) if scope_visible else 0.0)
	_crosshair_root.visible = not scope_visible

func _on_hit_confirmed(damage: float, killed: bool) -> void:
	_feedback_label.text = "KILL" if killed else "HIT %.0f" % damage
	_feedback_timer = 0.35
