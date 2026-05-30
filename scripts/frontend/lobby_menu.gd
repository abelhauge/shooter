class_name LobbyMenu
extends Control

signal offline_requested(loadout: Dictionary)
signal host_requested(port: int, loadout: Dictionary)
signal join_requested(address: String, port: int, loadout: Dictionary)
signal ready_requested()
signal start_requested()

const ABEL_PUBLIC_JOIN_ADDRESS := "203.0.113.77"
const PUBLIC_IP_LOOKUP_URL := "https://api.ipify.org?format=json"
const SLOT_WEAPON_ORDER := {
	&"primary": [&"assault_rifle", &"shotgun", &"sniper", &"flamethrower"],
	&"secondary": [&"handgun", &"portal_gun", &"lasso", &"taser_gun"],
	&"melee": [&"knife"],
	&"artillery": [&"smoke_bomb", &"grenade", &"redbull"],
}

enum PublicNetworkMode {
	DETECTING,
	HOST,
	JOIN,
}

var _status_label: Label
var _address_edit: LineEdit
var _port_edit: LineEdit
var _lan_hosts_option: OptionButton
var _join_lan_button: Button
var _public_action_button: Button
var _ready_button: Button
var _start_button: Button
var _public_ip_request: HTTPRequest
var _lan_hosts: Array[Dictionary] = []
var _public_network_mode := PublicNetworkMode.DETECTING
var _detected_public_ip := ""
var _selected_weapon_by_slot: Dictionary = {}
var _slot_buttons_by_weapon: Dictionary = {}
var _slot_weapon_ids_by_slot: Dictionary = {}
var _slot_summary_labels: Dictionary = {}
var _preview_roots: Array[Node3D] = []
var _preview_entries: Array[Dictionary] = []

func _ready() -> void:
	_build_ui()
	set_status("Checking public IP...")
	set_network_controls(false, false)
	_begin_public_ip_detection()
	set_process(true)

func _process(delta: float) -> void:
	for entry in _preview_entries:
		_fit_preview_entry(entry)
	for preview_root in _preview_roots:
		if is_instance_valid(preview_root):
			preview_root.rotate_y(delta * 0.72)

func set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text

func set_network_controls(show_ready: bool, show_start: bool) -> void:
	if _ready_button != null:
		_ready_button.visible = show_ready
	if _start_button != null:
		_start_button.visible = show_start

func smoke_press_offline() -> void:
	_on_offline_pressed()

func smoke_press_host(port: int) -> void:
	_port_edit.text = str(port)
	_on_host_pressed()

func smoke_press_join(address: String, port: int) -> void:
	_address_edit.text = address
	_port_edit.text = str(port)
	_on_join_pressed()

func smoke_press_join_abel() -> void:
	_public_network_mode = PublicNetworkMode.JOIN
	_on_public_action_pressed()

func smoke_press_public_action() -> void:
	_on_public_action_pressed()

func smoke_force_public_ip(public_ip: String) -> void:
	_apply_detected_public_ip(public_ip)

func smoke_get_public_action_label() -> String:
	return _public_action_button.text if _public_action_button != null else ""

func smoke_press_join_lan(index := 0) -> bool:
	if _lan_hosts.is_empty() or index < 0 or index >= _lan_hosts.size():
		return false
	_lan_hosts_option.select(index)
	_on_join_lan_pressed()
	return true

func smoke_press_ready() -> void:
	_on_ready_pressed()

func smoke_press_start() -> void:
	_on_start_pressed()

func smoke_get_status() -> String:
	return _status_label.text if _status_label != null else ""

func smoke_get_lan_host_count() -> int:
	return _lan_hosts.size()

func smoke_get_slot_weapon_ids() -> Dictionary:
	return {
		"primary": _slot_weapon_ids(&"primary"),
		"secondary": _slot_weapon_ids(&"secondary"),
		"melee": _slot_weapon_ids(&"melee"),
		"artillery": _slot_weapon_ids(&"artillery"),
	}

func smoke_select_loadout(primary_id: StringName, secondary_id: StringName, melee_id: StringName, artillery_id: StringName) -> bool:
	return (
		_select_weapon_for_slot(&"primary", primary_id)
		and _select_weapon_for_slot(&"secondary", secondary_id)
		and _select_weapon_for_slot(&"melee", melee_id)
		and _select_weapon_for_slot(&"artillery", artillery_id)
	)

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.035, 0.055, 0.060, 1.0)
	add_child(background)

	_add_background_rect(Vector2(0, 0), Vector2(1280, 86), Color(0.73, 0.28, 0.12, 0.35))
	_add_background_rect(Vector2(0, 636), Vector2(1280, 84), Color(0.05, 0.20, 0.30, 0.48))
	_add_background_rect(Vector2(76, 118), Vector2(190, 500), Color(0.08, 0.14, 0.15, 0.70))
	_add_background_rect(Vector2(954, 86), Vector2(180, 546), Color(0.10, 0.08, 0.06, 0.62))
	_add_background_rect(Vector2(1098, 148), Vector2(76, 484), Color(0.76, 0.48, 0.16, 0.30))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 560)
	panel.position = Vector2(72, 82)
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.018, 0.026, 0.030, 0.94), Color(0.22, 0.62, 0.82, 0.72), 3, 14))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)

	var title := Label.new()
	title.text = "DOWNTOWN MOVEMENT FPS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(560, 54)
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.86, 0.94, 0.92, 1.0))
	box.add_child(_status_label)

	var network_label := Label.new()
	network_label.text = "NETWORK TARGET"
	network_label.add_theme_font_size_override("font_size", 13)
	network_label.add_theme_color_override("font_color", Color(0.96, 0.58, 0.28, 1.0))
	network_label.visible = false
	box.add_child(network_label)

	var network_row := HBoxContainer.new()
	network_row.add_theme_constant_override("separation", 10)
	network_row.visible = false
	box.add_child(network_row)
	_address_edit = LineEdit.new()
	_address_edit.placeholder_text = "Host IP / LAN target"
	_address_edit.text = "127.0.0.1"
	_address_edit.custom_minimum_size = Vector2(410, 36)
	_style_line_edit(_address_edit)
	network_row.add_child(_address_edit)

	_port_edit = LineEdit.new()
	_port_edit.placeholder_text = "Port"
	_port_edit.text = str(NetworkConstants.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(140, 36)
	_style_line_edit(_port_edit)
	network_row.add_child(_port_edit)

	var lan_row := HBoxContainer.new()
	lan_row.add_theme_constant_override("separation", 10)
	lan_row.visible = false
	box.add_child(lan_row)
	_lan_hosts_option = OptionButton.new()
	_lan_hosts_option.custom_minimum_size = Vector2(374, 34)
	_style_option_button(_lan_hosts_option)
	lan_row.add_child(_lan_hosts_option)

	_join_lan_button = Button.new()
	_join_lan_button.text = "Join LAN"
	_join_lan_button.custom_minimum_size = Vector2(176, 34)
	_style_button(_join_lan_button, Color(0.24, 0.44, 0.36, 1.0))
	_join_lan_button.pressed.connect(_on_join_lan_pressed)
	lan_row.add_child(_join_lan_button)
	set_lan_hosts([])

	_create_slot_selector(box, "Primary", &"primary")
	_create_slot_selector(box, "Secondary", &"secondary")
	_create_slot_selector(box, "Melee", &"melee")
	_create_slot_selector(box, "Artillery", &"artillery")

	var action_row := GridContainer.new()
	action_row.columns = 2
	action_row.add_theme_constant_override("h_separation", 10)
	action_row.add_theme_constant_override("v_separation", 8)
	box.add_child(action_row)

	var offline_button := Button.new()
	offline_button.text = "Offline Dev Match"
	_style_button(offline_button, Color(0.16, 0.48, 0.68, 1.0))
	offline_button.pressed.connect(_on_offline_pressed)
	action_row.add_child(offline_button)

	_public_action_button = Button.new()
	_public_action_button.text = "Detecting..."
	_public_action_button.disabled = true
	_style_button(_public_action_button, Color(0.32, 0.42, 0.70, 1.0))
	_public_action_button.pressed.connect(_on_public_action_pressed)
	action_row.add_child(_public_action_button)

	var ready_row := HBoxContainer.new()
	ready_row.add_theme_constant_override("separation", 10)
	box.add_child(ready_row)

	_ready_button = Button.new()
	_ready_button.text = "Ready"
	_style_button(_ready_button, Color(0.18, 0.56, 0.32, 1.0))
	_ready_button.pressed.connect(_on_ready_pressed)
	ready_row.add_child(_ready_button)

	_start_button = Button.new()
	_start_button.text = "Host Start Match"
	_style_button(_start_button, Color(0.88, 0.58, 0.18, 1.0))
	_start_button.pressed.connect(_on_start_pressed)
	ready_row.add_child(_start_button)

	var briefing := PanelContainer.new()
	briefing.custom_minimum_size = Vector2(420, 360)
	briefing.position = Vector2(760, 152)
	briefing.add_theme_stylebox_override("panel", _style_box(Color(0.035, 0.045, 0.046, 0.88), Color(0.92, 0.52, 0.20, 0.62), 2, 12))
	add_child(briefing)
	var briefing_margin := MarginContainer.new()
	briefing_margin.add_theme_constant_override("margin_left", 24)
	briefing_margin.add_theme_constant_override("margin_top", 22)
	briefing_margin.add_theme_constant_override("margin_right", 24)
	briefing_margin.add_theme_constant_override("margin_bottom", 22)
	briefing.add_child(briefing_margin)
	var briefing_box := VBoxContainer.new()
	briefing_box.add_theme_constant_override("separation", 12)
	briefing_margin.add_child(briefing_box)
	var briefing_title := Label.new()
	briefing_title.text = "LOADOUT CHECK"
	briefing_title.add_theme_font_size_override("font_size", 28)
	briefing_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42, 1.0))
	briefing_box.add_child(briefing_title)
	var briefing_text := Label.new()
	briefing_text.text = "Fast routes, readable team colors, and LAN listen-server matches are the current vertical-slice contract.\n\nUse Offline for local movement/combat QA. Host and Join share the same arena and selected loadout."
	briefing_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing_text.add_theme_font_size_override("font_size", 18)
	briefing_text.add_theme_color_override("font_color", Color(0.86, 0.93, 0.90, 1.0))
	briefing_box.add_child(briefing_text)

func _read_port() -> int:
	var port := int(_port_edit.text)
	return NetworkConstants.DEFAULT_PORT if port <= 0 else port

func _create_slot_selector(parent: VBoxContainer, label_text: String, slot_type: StringName) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	parent.add_child(header)

	var label := Label.new()
	label.text = label_text.to_upper()
	label.custom_minimum_size = Vector2(82, 18)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.72, 0.86, 0.92, 1.0))
	header.add_child(label)

	var summary := Label.new()
	summary.text = ""
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_font_size_override("font_size", 13)
	summary.add_theme_color_override("font_color", Color(0.94, 0.97, 0.92, 1.0))
	header.add_child(summary)
	_slot_summary_labels[slot_type] = summary

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var slot_ids: Array[StringName] = []
	_slot_buttons_by_weapon[slot_type] = {}
	for weapon_id in SLOT_WEAPON_ORDER.get(slot_type, []):
		if not WeaponController.WEAPON_PATHS.has(weapon_id):
			continue
		var definition: WeaponDefinition = load(WeaponController.WEAPON_PATHS[weapon_id])
		if definition.slot_type != slot_type:
			continue
		slot_ids.append(definition.weapon_id)
		var button := _create_weapon_preview_button(definition)
		button.set_meta("weapon_id", definition.weapon_id)
		button.set_meta("slot_type", slot_type)
		button.pressed.connect(_on_weapon_card_pressed.bind(slot_type, definition.weapon_id))
		row.add_child(button)
		(_slot_buttons_by_weapon[slot_type] as Dictionary)[definition.weapon_id] = button
	_selected_weapon_by_slot[slot_type] = _default_weapon_for_slot(slot_type)
	_slot_weapon_ids_by_slot[slot_type] = slot_ids
	_refresh_slot_buttons(slot_type)

func _add_background_rect(position: Vector2, size: Vector2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.position = position
	rect.size = size
	rect.color = color
	add_child(rect)

func _style_box(color: Color, border_color: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 14
	return style

func _style_line_edit(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", _style_box(Color(0.010, 0.014, 0.016, 0.94), Color(0.22, 0.40, 0.48, 0.70), 1, 6))
	edit.add_theme_stylebox_override("focus", _style_box(Color(0.012, 0.026, 0.032, 0.96), Color(0.42, 0.76, 0.92, 0.92), 2, 6))
	edit.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	edit.add_theme_font_size_override("font_size", 16)

func _style_option_button(option: OptionButton) -> void:
	option.add_theme_stylebox_override("normal", _style_box(Color(0.014, 0.019, 0.022, 0.94), Color(0.22, 0.40, 0.48, 0.70), 1, 6))
	option.add_theme_stylebox_override("hover", _style_box(Color(0.030, 0.052, 0.060, 0.96), Color(0.50, 0.76, 0.86, 0.82), 1, 6))
	option.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	option.add_theme_font_size_override("font_size", 16)

func _style_weapon_button(button: Button, definition: WeaponDefinition, selected: bool) -> void:
	var color := _weapon_color(definition)
	var base_color := color.darkened(0.18) if selected else Color(0.012, 0.017, 0.020, 0.96)
	var border_color := Color(1.0, 0.82, 0.42, 0.92) if selected else color.darkened(0.10)
	var border_width := 2 if selected else 1
	button.add_theme_stylebox_override("normal", _style_box(base_color, border_color, border_width, 7))
	button.add_theme_stylebox_override("hover", _style_box(base_color.lightened(0.08), Color(1.0, 0.86, 0.52, 0.82), 2, 7))
	button.add_theme_stylebox_override("pressed", _style_box(base_color.darkened(0.18), Color(1.0, 0.70, 0.32, 0.92), 2, 7))
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	button.add_theme_font_size_override("font_size", 1)

func _style_button(button: Button, color: Color) -> void:
	button.custom_minimum_size = Vector2(176, 38)
	button.add_theme_stylebox_override("normal", _style_box(color.darkened(0.12), Color(0.92, 0.96, 1.0, 0.28), 1, 7))
	button.add_theme_stylebox_override("hover", _style_box(color.lightened(0.08), Color(1.0, 0.86, 0.52, 0.72), 2, 7))
	button.add_theme_stylebox_override("pressed", _style_box(color.darkened(0.24), Color(1.0, 0.70, 0.32, 0.92), 2, 7))
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	button.add_theme_font_size_override("font_size", 15)

func _default_weapon_for_slot(slot_type: StringName) -> StringName:
	if slot_type == &"primary":
		return &"assault_rifle"
	if slot_type == &"secondary":
		return &"handgun"
	if slot_type == &"melee":
		return &"knife"
	return &"smoke_bomb"

func _selected_weapon(slot_type: StringName) -> StringName:
	return StringName(str(_selected_weapon_by_slot.get(slot_type, _default_weapon_for_slot(slot_type))))

func _slot_weapon_ids(slot_type: StringName) -> Array[StringName]:
	var weapon_ids: Array[StringName] = []
	for weapon_id in _slot_weapon_ids_by_slot.get(slot_type, []):
		weapon_ids.append(StringName(str(weapon_id)))
	return weapon_ids

func _select_weapon_for_slot(slot_type: StringName, weapon_id: StringName) -> bool:
	var buttons: Dictionary = _slot_buttons_by_weapon.get(slot_type, {})
	if not buttons.has(weapon_id):
		return false
	_selected_weapon_by_slot[slot_type] = weapon_id
	_refresh_slot_buttons(slot_type)
	return true

func _selected_loadout() -> Dictionary:
	return {
		"primary": _selected_weapon(&"primary"),
		"secondary": _selected_weapon(&"secondary"),
		"melee": _selected_weapon(&"melee"),
		"artillery": _selected_weapon(&"artillery"),
	}

func _on_weapon_card_pressed(slot_type: StringName, weapon_id: StringName) -> void:
	_select_weapon_for_slot(slot_type, weapon_id)

func _refresh_slot_buttons(slot_type: StringName) -> void:
	var buttons: Dictionary = _slot_buttons_by_weapon.get(slot_type, {})
	var selected_id := _selected_weapon(slot_type)
	for weapon_id in buttons.keys():
		var button := buttons[weapon_id] as Button
		var definition: WeaponDefinition = load(WeaponController.WEAPON_PATHS[StringName(str(weapon_id))])
		var selected := StringName(str(weapon_id)) == selected_id
		button.button_pressed = selected
		_style_weapon_button(button, definition, selected)
	var selected_definition: WeaponDefinition = load(WeaponController.WEAPON_PATHS[selected_id])
	if _slot_summary_labels.has(slot_type):
		(_slot_summary_labels[slot_type] as Label).text = _selected_weapon_summary(selected_definition)

func _weapon_card_size(slot_type: StringName) -> Vector2:
	if slot_type == &"melee":
		return Vector2(560, 58)
	return Vector2(134, 58)

func _create_weapon_preview_button(definition: WeaponDefinition) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.text = ""
	button.tooltip_text = definition.display_name
	button.custom_minimum_size = _weapon_card_size(definition.slot_type)

	var viewport_container := SubViewportContainer.new()
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_container.stretch = true
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.offset_left = 6
	viewport_container.offset_top = 5
	viewport_container.offset_right = -6
	viewport_container.offset_bottom = -5
	button.add_child(viewport_container)

	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.disable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(160, 72)
	viewport_container.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color(0.005, 0.008, 0.010, 1.0)
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.32, 0.38, 0.42, 1.0)
	environment_resource.ambient_light_energy = 2.4
	environment.environment = environment_resource
	world.add_child(environment)

	var preview_root := Node3D.new()
	preview_root.name = "%sPreview" % String(definition.weapon_id)
	world.add_child(preview_root)
	_preview_roots.append(preview_root)

	var model_holder := Node3D.new()
	model_holder.name = "ModelHolder"
	preview_root.add_child(model_holder)

	var view_model_path := String(WeaponController.VIEW_MODEL_PATHS.get(definition.weapon_id, ""))
	if view_model_path != "" and ResourceLoader.exists(view_model_path, "PackedScene"):
		var packed := load(view_model_path) as PackedScene
		var model := packed.instantiate() as Node3D
		model.position = _preview_model_position(definition)
		model.rotation_degrees = _preview_model_rotation(definition)
		model.scale *= _preview_model_scale(definition)
		model_holder.add_child(model)
	else:
		model_holder.add_child(_create_fallback_preview_mesh(definition))

	var camera := Camera3D.new()
	camera.look_at_from_position(Vector3(0.0, 0.05, 1.2), Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.82
	camera.current = true
	camera.visible = false
	world.add_child(camera)
	_preview_entries.append({
		"holder": model_holder,
		"fitted": false,
	})
	return button

func _create_fallback_preview_mesh(definition: WeaponDefinition) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.48, 0.16, 0.18)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _create_preview_material(_weapon_color(definition))
	return mesh_instance

func _create_preview_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.lightened(0.18)
	material.metallic = 0.15
	material.roughness = 0.42
	return material

func _preview_model_position(definition: WeaponDefinition) -> Vector3:
	if definition.slot_type == &"melee":
		return Vector3(-0.08, 0.00, 0.0)
	if definition.slot_type == &"artillery":
		return Vector3(-0.04, 0.02, 0.0)
	return Vector3(-0.12, 0.00, 0.0)

func _preview_model_rotation(definition: WeaponDefinition) -> Vector3:
	if definition.slot_type == &"melee":
		return Vector3(-8, -44, 4)
	if definition.slot_type == &"artillery":
		return Vector3(-12, -34, 0)
	return Vector3(-8, -62, 0)

func _preview_model_scale(definition: WeaponDefinition) -> Vector3:
	if definition.slot_type == &"melee":
		return Vector3(0.78, 0.78, 0.78)
	if definition.slot_type == &"artillery":
		return Vector3(0.85, 0.85, 0.85)
	return Vector3(1.15, 1.15, 1.15)

func _selected_weapon_summary(definition: WeaponDefinition) -> String:
	var features: Array[String] = []
	features.append(String(definition.fire_mode).to_upper())
	if definition.magazine_size > 0:
		features.append("%d mag" % definition.magazine_size)
	elif definition.charges_max > 0:
		features.append("%d charges" % definition.charges_max)
	if definition.body_damage > 0.0:
		features.append("%.0f body / %.0f head" % [definition.body_damage, definition.head_damage])
	elif definition.effect_duration_sec > 0.0:
		features.append("%.0fs effect" % definition.effect_duration_sec)
	if definition.max_range_m > 0.0:
		features.append("%.0fm" % definition.max_range_m)
	if definition.reload_time_sec > 0.0:
		features.append("%.1fs reload" % definition.reload_time_sec)
	return "%s  -  %s" % [definition.display_name, "  |  ".join(features)]

func _fit_preview_entry(entry: Dictionary) -> void:
	if bool(entry.get("fitted", false)):
		return
	var holder := entry.get("holder") as Node3D
	if holder == null or not is_instance_valid(holder):
		return
	var bounds := _calculate_mesh_bounds(holder)
	if bounds.is_empty():
		return
	var min_point: Vector3 = bounds["min"]
	var max_point: Vector3 = bounds["max"]
	var center := (min_point + max_point) * 0.5
	var size := max_point - min_point
	var max_dimension := maxf(size.x, maxf(size.y, size.z))
	if max_dimension <= 0.001:
		return
	var fit_scale := 0.60 / max_dimension
	holder.scale *= fit_scale
	holder.position = -center * fit_scale
	entry["fitted"] = true

func _calculate_mesh_bounds(root_node: Node) -> Dictionary:
	var state := {
		"has_bounds": false,
		"min": Vector3(1000000.0, 1000000.0, 1000000.0),
		"max": Vector3(-1000000.0, -1000000.0, -1000000.0),
	}
	_collect_mesh_bounds(root_node, state)
	if not bool(state["has_bounds"]):
		return {}
	return {
		"min": state["min"],
		"max": state["max"],
	}

func _collect_mesh_bounds(node: Node, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var aabb := mesh_instance.get_aabb()
			var min_corner := aabb.position
			var max_corner := aabb.position + aabb.size
			for x in [min_corner.x, max_corner.x]:
				for y in [min_corner.y, max_corner.y]:
					for z in [min_corner.z, max_corner.z]:
						var point := mesh_instance.global_transform * Vector3(x, y, z)
						state["min"] = (state["min"] as Vector3).min(point)
						state["max"] = (state["max"] as Vector3).max(point)
						state["has_bounds"] = true
	for child in node.get_children():
		_collect_mesh_bounds(child, state)

func _weapon_color(definition: WeaponDefinition) -> Color:
	if definition.scope_enabled:
		return Color(0.30, 0.44, 0.72, 1.0)
	if definition.alt_action_type == &"stun":
		return Color(0.18, 0.58, 0.70, 1.0)
	if definition.alt_action_type == &"portal":
		return Color(0.38, 0.32, 0.70, 1.0)
	if definition.alt_action_type == &"speed_buff":
		return Color(0.72, 0.40, 0.18, 1.0)
	if definition.fire_mode == &"throwable":
		return Color(0.38, 0.50, 0.32, 1.0)
	if definition.fire_mode == &"beam":
		return Color(0.72, 0.28, 0.16, 1.0)
	if definition.fire_mode == &"melee":
		return Color(0.52, 0.52, 0.58, 1.0)
	return Color(0.24, 0.42, 0.50, 1.0)

func set_lan_hosts(hosts: Array[Dictionary]) -> void:
	_lan_hosts = hosts.duplicate(true)
	if _lan_hosts_option == null:
		return
	_lan_hosts_option.clear()
	if _lan_hosts.is_empty():
		_lan_hosts_option.add_item("No LAN matches found")
		_lan_hosts_option.disabled = true
		if _join_lan_button != null:
			_join_lan_button.disabled = true
		return
	_lan_hosts_option.disabled = false
	if _join_lan_button != null:
		_join_lan_button.disabled = false
	for host in _lan_hosts:
		var label := "%s  %s:%d" % [
			String(host.get("name", "LAN Host")),
			String(host.get("address", "")),
			int(host.get("port", NetworkConstants.DEFAULT_PORT)),
		]
		_lan_hosts_option.add_item(label)
		_lan_hosts_option.set_item_metadata(_lan_hosts_option.get_item_count() - 1, host)

func _on_offline_pressed() -> void:
	offline_requested.emit(_selected_loadout())

func _on_host_pressed() -> void:
	host_requested.emit(_read_port(), _selected_loadout())

func _on_join_pressed() -> void:
	join_requested.emit(_address_edit.text.strip_edges(), _read_port(), _selected_loadout())

func _on_public_action_pressed() -> void:
	if _public_network_mode == PublicNetworkMode.HOST:
		_on_host_pressed()
		return
	_address_edit.text = ABEL_PUBLIC_JOIN_ADDRESS
	_port_edit.text = str(NetworkConstants.DEFAULT_PORT)
	join_requested.emit(ABEL_PUBLIC_JOIN_ADDRESS, NetworkConstants.DEFAULT_PORT, _selected_loadout())

func _on_join_lan_pressed() -> void:
	if _lan_hosts.is_empty() or _lan_hosts_option == null:
		set_status("No LAN match found yet.")
		return
	var index := _lan_hosts_option.selected
	if index < 0 or index >= _lan_hosts.size():
		set_status("No LAN match selected.")
		return
	var host: Dictionary = _lan_hosts[index]
	var address := String(host.get("address", ""))
	var port := int(host.get("port", NetworkConstants.DEFAULT_PORT))
	if address == "" or port <= 0:
		set_status("LAN match has no valid address.")
		return
	_address_edit.text = address
	_port_edit.text = str(port)
	join_requested.emit(address, port, _selected_loadout())

func _on_ready_pressed() -> void:
	ready_requested.emit()
	set_status("Ready sent. Waiting for host start.")

func _on_start_pressed() -> void:
	start_requested.emit()

func _begin_public_ip_detection() -> void:
	_set_public_action_state(PublicNetworkMode.DETECTING)
	_public_ip_request = HTTPRequest.new()
	_public_ip_request.name = "PublicIpLookup"
	_public_ip_request.timeout = 4.0
	add_child(_public_ip_request)
	_public_ip_request.request_completed.connect(_on_public_ip_request_completed)
	var error := _public_ip_request.request(PUBLIC_IP_LOOKUP_URL)
	if error != OK:
		_apply_public_ip_detection_failure("Could not start public IP check: %s" % error_string(error))

func _on_public_ip_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_apply_public_ip_detection_failure("Public IP check failed. Join will use Abel's saved IP.")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_apply_public_ip_detection_failure("Public IP check returned invalid data. Join will use Abel's saved IP.")
		return
	var public_ip := String((parsed as Dictionary).get("ip", "")).strip_edges()
	if public_ip == "":
		_apply_public_ip_detection_failure("Public IP check returned no address. Join will use Abel's saved IP.")
		return
	_apply_detected_public_ip(public_ip)

func _apply_detected_public_ip(public_ip: String) -> void:
	_detected_public_ip = public_ip.strip_edges()
	if _detected_public_ip == ABEL_PUBLIC_JOIN_ADDRESS:
		_set_public_action_state(PublicNetworkMode.HOST)
		set_status("Public IP %s matches Abel's host. Press Host game." % _detected_public_ip)
	else:
		_set_public_action_state(PublicNetworkMode.JOIN)
		set_status("Public IP %s is a client. Press Join to connect to Abel." % _detected_public_ip)

func _apply_public_ip_detection_failure(message: String) -> void:
	_set_public_action_state(PublicNetworkMode.JOIN)
	set_status(message)

func _set_public_action_state(mode: int) -> void:
	_public_network_mode = mode
	if _public_action_button == null:
		return
	_public_action_button.disabled = false
	if mode == PublicNetworkMode.HOST:
		_public_action_button.text = "Host game"
		_style_button(_public_action_button, Color(0.76, 0.38, 0.14, 1.0))
	elif mode == PublicNetworkMode.JOIN:
		_public_action_button.text = "Join"
		_style_button(_public_action_button, Color(0.32, 0.42, 0.70, 1.0))
	else:
		_public_action_button.text = "Detecting..."
		_public_action_button.disabled = true
		_style_button(_public_action_button, Color(0.20, 0.30, 0.34, 1.0))
