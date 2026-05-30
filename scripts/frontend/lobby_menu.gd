class_name LobbyMenu
extends Control

signal offline_requested(loadout: Dictionary)
signal host_requested(port: int, loadout: Dictionary)
signal join_requested(address: String, port: int, loadout: Dictionary)
signal ready_requested()
signal start_requested()

const ABEL_PUBLIC_JOIN_ADDRESS := "203.0.113.77"
const PUBLIC_IP_LOOKUP_URLS := [
	"https://api.ipify.org?format=json",
	"https://api64.ipify.org?format=json",
	"https://checkip.amazonaws.com",
	"http://api.ipify.org?format=json",
]
const ITCH_TARGET := "abelhauge/shooter"
const ITCH_PAGE_URL := "https://abelhauge.itch.io/shooter"
const ITCH_LATEST_URL_TEMPLATE := "https://itch.io/api/1/x/wharf/latest?target=%s&channel_name=%s"
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
var _name_edit: LineEdit
var _address_edit: LineEdit
var _port_edit: LineEdit
var _lan_hosts_option: OptionButton
var _join_lan_button: Button
var _public_action_button: Button
var _ready_button: Button
var _start_button: Button
var _public_ip_request: HTTPRequest
var _update_request: HTTPRequest
var _update_banner: PanelContainer
var _update_label: Label
var _update_button: Button
var _lan_hosts: Array[Dictionary] = []
var _public_network_mode := PublicNetworkMode.DETECTING
var _detected_public_ip := ""
var _latest_itch_version := ""
var _public_ip_lookup_url_index := 0
var _public_ip_lookup_failures: Array[String] = []
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
	_begin_update_check()
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

func smoke_set_player_name(player_name: String) -> void:
	if _name_edit != null:
		_name_edit.text = player_name

func smoke_press_join_abel() -> void:
	_public_network_mode = PublicNetworkMode.JOIN
	_on_public_action_pressed()

func smoke_press_public_action() -> void:
	_on_public_action_pressed()

func smoke_force_public_ip(public_ip: String) -> void:
	_apply_detected_public_ip(public_ip, "smoke")

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

func smoke_get_public_ip_lookup_debug() -> String:
	return " | ".join(_public_ip_lookup_failures)

func smoke_get_lan_host_count() -> int:
	return _lan_hosts.size()

func smoke_force_latest_itch_version(latest_version: String) -> void:
	_apply_latest_itch_version(latest_version)

func smoke_is_update_banner_visible() -> bool:
	return _update_banner != null and _update_banner.visible

func smoke_get_update_text() -> String:
	return _update_label.text if _update_label != null else ""

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
	_add_background_rect(Vector2(954, 86), Vector2(180, 546), Color(0.10, 0.08, 0.06, 0.34))
	_add_background_rect(Vector2(1098, 148), Vector2(76, 484), Color(0.76, 0.48, 0.16, 0.18))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(930, 594)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = panel.custom_minimum_size
	panel.position = -panel.custom_minimum_size * 0.5
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.018, 0.026, 0.030, 0.94), Color(0.22, 0.62, 0.82, 0.72), 3, 14))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)

	var title := Label.new()
	title.text = "DOWNTOWN MOVEMENT FPS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(title)

	_create_update_banner(box)

	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 10)
	box.add_child(identity_row)

	var identity_label := Label.new()
	identity_label.text = "HANDLE"
	identity_label.custom_minimum_size = Vector2(82, 34)
	identity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity_label.add_theme_font_size_override("font_size", 13)
	identity_label.add_theme_color_override("font_color", Color(0.72, 0.86, 0.92, 1.0))
	identity_row.add_child(identity_label)

	_name_edit = LineEdit.new()
	_name_edit.text = _default_player_name()
	_name_edit.placeholder_text = "Your name"
	_name_edit.max_length = 18
	_name_edit.custom_minimum_size = Vector2(260, 34)
	_style_line_edit(_name_edit)
	identity_row.add_child(_name_edit)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.86, 0.94, 0.92, 1.0))
	_status_label.visible = false
	add_child(_status_label)

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

func _create_update_banner(parent: VBoxContainer) -> void:
	_update_banner = PanelContainer.new()
	_update_banner.visible = false
	_update_banner.add_theme_stylebox_override("panel", _style_box(Color(0.15, 0.08, 0.025, 0.94), Color(1.0, 0.64, 0.25, 0.82), 1, 8))
	parent.add_child(_update_banner)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	_update_banner.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	_update_label = Label.new()
	_update_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_label.add_theme_font_size_override("font_size", 15)
	_update_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72, 1.0))
	row.add_child(_update_label)

	_update_button = Button.new()
	_update_button.text = "Update"
	_update_button.tooltip_text = "Open the itch.io page to install the latest build."
	_style_button(_update_button, Color(0.78, 0.42, 0.12, 1.0))
	_update_button.custom_minimum_size = Vector2(126, 30)
	_update_button.pressed.connect(_on_update_pressed)
	row.add_child(_update_button)

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
		"player_name": _read_player_name(),
		"primary": _selected_weapon(&"primary"),
		"secondary": _selected_weapon(&"secondary"),
		"melee": _selected_weapon(&"melee"),
		"artillery": _selected_weapon(&"artillery"),
	}

func _read_player_name() -> String:
	var raw := _name_edit.text if _name_edit != null else _default_player_name()
	var sanitized := ""
	for index in range(raw.length()):
		var character := raw.substr(index, 1)
		if character >= "a" and character <= "z":
			sanitized += character
		elif character >= "A" and character <= "Z":
			sanitized += character
		elif character >= "0" and character <= "9":
			sanitized += character
		elif character == "_" or character == "-":
			sanitized += character
		elif character == " " and sanitized.length() > 0 and not sanitized.ends_with(" "):
			sanitized += character
		if sanitized.length() >= 18:
			break
	sanitized = sanitized.strip_edges()
	return sanitized if sanitized != "" else "Player"

func _default_player_name() -> String:
	var user := OS.get_environment("USER")
	if user == "":
		user = OS.get_environment("USERNAME")
	user = user.strip_edges()
	return user if user != "" else "Player"

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
		return Vector2(812, 72)
	return Vector2(194, 72)

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
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.disable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var card_size := _weapon_card_size(definition.slot_type)
	viewport.size = Vector2i(maxi(48, int(card_size.x - 12.0)), maxi(40, int(card_size.y - 10.0)))
	viewport_container.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color(0.005, 0.008, 0.010, 1.0)
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.32, 0.38, 0.42, 1.0)
	environment_resource.ambient_light_energy = 2.8
	environment.environment = environment_resource
	world.add_child(environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	key_light.light_energy = 1.25
	world.add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-0.65, 0.55, 1.1)
	fill_light.light_energy = 1.8
	fill_light.omni_range = 4.0
	world.add_child(fill_light)

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
		if model is GltfViewModelLoader:
			(model as GltfViewModelLoader).apply_material_override = false
		model.position = _preview_model_position(definition)
		model.rotation_degrees = _preview_model_rotation(definition)
		model.scale *= _preview_model_scale(definition)
		model_holder.add_child(model)
	else:
		model_holder.add_child(_create_fallback_preview_mesh(definition))

	var camera := Camera3D.new()
	camera.look_at_from_position(Vector3(0.0, 0.05, 1.2), Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.62
	camera.current = true
	camera.visible = false
	world.add_child(camera)
	_preview_entries.append({
		"holder": model_holder,
		"camera": camera,
		"viewport": viewport,
		"color": _weapon_color(definition),
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
	if size.x <= 0.001 or size.y <= 0.001:
		return
	var camera := entry.get("camera") as Camera3D
	var viewport := entry.get("viewport") as SubViewport
	var camera_size := 0.62 if camera == null else camera.size
	var viewport_size := Vector2(220.0, 78.0) if viewport == null else Vector2(viewport.size)
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var target_width := camera_size * aspect * 0.76
	var target_height := camera_size * 0.70
	var fit_scale := minf(target_width / size.x, target_height / size.y)
	holder.scale *= fit_scale
	holder.position = -center * fit_scale
	entry["fitted"] = true

func _apply_preview_material_override(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color.lightened(0.24)
		material.metallic = 0.0
		material.roughness = 0.45
		mesh_instance.material_override = material
	for child in node.get_children():
		_apply_preview_material_override(child, color)

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
	_lan_hosts = []
	for host in hosts:
		if String((host as Dictionary).get("state", "lobby")) == "in_game":
			_lan_hosts.append((host as Dictionary).duplicate(true))
	if _lan_hosts_option == null:
		return
	_lan_hosts_option.clear()
	if _lan_hosts.is_empty():
		_lan_hosts_option.add_item("No ready LAN matches found")
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

func _begin_update_check() -> void:
	var channel_name := _itch_channel_name()
	if channel_name == "":
		return
	_update_request = HTTPRequest.new()
	_update_request.name = "ItchLatestVersionLookup"
	_update_request.timeout = 5.0
	add_child(_update_request)
	_update_request.request_completed.connect(_on_update_request_completed)
	var url := ITCH_LATEST_URL_TEMPLATE % [ITCH_TARGET, channel_name]
	var error := _update_request.request(url)
	if error != OK:
		push_warning("Could not start itch update check: %s" % error_string(error))

func _on_update_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var latest := String((parsed as Dictionary).get("latest", "")).strip_edges()
	if latest == "":
		return
	_apply_latest_itch_version(latest)

func _apply_latest_itch_version(latest_version: String) -> void:
	_latest_itch_version = latest_version.strip_edges()
	if _latest_itch_version == "":
		return
	var current_version := _current_app_version()
	if not _is_version_newer(_latest_itch_version, current_version):
		return
	if _update_label != null:
		_update_label.text = "New build available: %s  |  Current: %s" % [_latest_itch_version, current_version]
	if _update_banner != null:
		_update_banner.visible = true

func _on_update_pressed() -> void:
	var error := OS.shell_open(ITCH_PAGE_URL)
	if error != OK:
		push_warning("Could not open itch update page: %s" % error_string(error))

func _current_app_version() -> String:
	var version := String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	return version if version != "" else "0.0.0-dev"

func _itch_channel_name() -> String:
	var os_name := OS.get_name()
	if os_name == "macOS":
		return "mac"
	if os_name == "Windows":
		return "windows"
	return ""

func _is_version_newer(candidate: String, current: String) -> bool:
	var candidate_parts := _version_number_parts(candidate)
	var current_parts := _version_number_parts(current)
	var count := maxi(candidate_parts.size(), current_parts.size())
	for index in range(count):
		var candidate_value := int(candidate_parts[index]) if index < candidate_parts.size() else 0
		var current_value := int(current_parts[index]) if index < current_parts.size() else 0
		if candidate_value > current_value:
			return true
		if candidate_value < current_value:
			return false
	return false

func _version_number_parts(version: String) -> Array[int]:
	var parts: Array[int] = []
	for token in version.split("."):
		var digits := ""
		for index in range(token.length()):
			var character := token.substr(index, 1)
			if character >= "0" and character <= "9":
				digits += character
			else:
				break
		parts.append(int(digits) if digits != "" else 0)
	return parts

func _begin_public_ip_detection() -> void:
	_set_public_action_state(PublicNetworkMode.DETECTING)
	_public_ip_request = HTTPRequest.new()
	_public_ip_request.name = "PublicIpLookup"
	_public_ip_request.timeout = 4.0
	add_child(_public_ip_request)
	_public_ip_request.request_completed.connect(_on_public_ip_request_completed)
	_public_ip_lookup_url_index = 0
	_public_ip_lookup_failures.clear()
	_request_current_public_ip_lookup_url()

func _request_current_public_ip_lookup_url() -> void:
	if _public_ip_request == null or _public_ip_lookup_url_index >= PUBLIC_IP_LOOKUP_URLS.size():
		_apply_public_ip_detection_failure("Public IP check failed. Join will use Abel's saved IP.")
		return
	var url := String(PUBLIC_IP_LOOKUP_URLS[_public_ip_lookup_url_index])
	var error := _public_ip_request.request(url)
	if error != OK:
		_public_ip_lookup_failures.append("%s start=%s" % [url, error_string(error)])
		_try_next_public_ip_lookup_url()

func _on_public_ip_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_public_ip_lookup_failures.append("%s result=%d http=%d" % [
			String(PUBLIC_IP_LOOKUP_URLS[_public_ip_lookup_url_index]),
			result,
			response_code,
		])
		_try_next_public_ip_lookup_url()
		return
	var public_ip := _parse_public_ip_response(body)
	if public_ip == "":
		_public_ip_lookup_failures.append("%s invalid-body" % String(PUBLIC_IP_LOOKUP_URLS[_public_ip_lookup_url_index]))
		_try_next_public_ip_lookup_url()
		return
	_apply_detected_public_ip(public_ip, String(PUBLIC_IP_LOOKUP_URLS[_public_ip_lookup_url_index]))

func _try_next_public_ip_lookup_url() -> void:
	_public_ip_lookup_url_index += 1
	if _public_ip_lookup_url_index < PUBLIC_IP_LOOKUP_URLS.size():
		_request_current_public_ip_lookup_url.call_deferred()
		return
	push_warning("Public IP lookup failed: %s" % " | ".join(_public_ip_lookup_failures))
	_apply_public_ip_detection_failure("Public IP check failed. Join will use Abel's saved IP.")

func _parse_public_ip_response(body: PackedByteArray) -> String:
	var text := body.get_string_from_utf8().strip_edges()
	if text.begins_with("{") or text.begins_with("["):
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			var ip := String((parsed as Dictionary).get("ip", "")).strip_edges()
			return ip if ip.is_valid_ip_address() else ""
	return text if text.is_valid_ip_address() else ""

func _apply_detected_public_ip(public_ip: String, lookup_source := "") -> void:
	_detected_public_ip = public_ip.strip_edges()
	if lookup_source != "smoke":
		var source := lookup_source if lookup_source != "" else "unknown"
		print("Public IP detected via %s: %s" % [source, _detected_public_ip])
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
