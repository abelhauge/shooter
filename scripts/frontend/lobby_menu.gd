class_name LobbyMenu
extends Control

signal offline_requested(loadout: Dictionary)
signal host_requested(port: int, loadout: Dictionary)
signal join_requested(address: String, port: int, loadout: Dictionary)
signal ready_requested()
signal start_requested()

const ABEL_PUBLIC_JOIN_ADDRESS := "203.0.113.77"

var _status_label: Label
var _address_edit: LineEdit
var _port_edit: LineEdit
var _lan_hosts_option: OptionButton
var _join_lan_button: Button
var _ready_button: Button
var _start_button: Button
var _primary_option: OptionButton
var _secondary_option: OptionButton
var _melee_option: OptionButton
var _artillery_option: OptionButton
var _lan_hosts: Array[Dictionary] = []

func _ready() -> void:
	_build_ui()
	set_status("Choose Offline, Host, or Join.")
	set_network_controls(false, false)

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
	_on_join_abel_pressed()

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
		"primary": _option_weapon_ids(_primary_option),
		"secondary": _option_weapon_ids(_secondary_option),
		"melee": _option_weapon_ids(_melee_option),
		"artillery": _option_weapon_ids(_artillery_option),
	}

func smoke_select_loadout(primary_id: StringName, secondary_id: StringName, melee_id: StringName, artillery_id: StringName) -> bool:
	return (
		_select_option_by_weapon_id(_primary_option, primary_id)
		and _select_option_by_weapon_id(_secondary_option, secondary_id)
		and _select_option_by_weapon_id(_melee_option, melee_id)
		and _select_option_by_weapon_id(_artillery_option, artillery_id)
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
	box.add_child(network_label)

	var network_row := HBoxContainer.new()
	network_row.add_theme_constant_override("separation", 10)
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

	_primary_option = _create_slot_option(box, "Primary", &"primary")
	_secondary_option = _create_slot_option(box, "Secondary", &"secondary")
	_melee_option = _create_slot_option(box, "Melee", &"melee")
	_artillery_option = _create_slot_option(box, "Artillery", &"artillery")

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

	var host_button := Button.new()
	host_button.text = "Host Private Match"
	_style_button(host_button, Color(0.76, 0.38, 0.14, 1.0))
	host_button.pressed.connect(_on_host_pressed)
	action_row.add_child(host_button)

	var join_button := Button.new()
	join_button.text = "Join By IP"
	_style_button(join_button, Color(0.20, 0.30, 0.34, 1.0))
	join_button.pressed.connect(_on_join_pressed)
	action_row.add_child(join_button)

	var join_abel_button := Button.new()
	join_abel_button.text = "Join Abel"
	_style_button(join_abel_button, Color(0.32, 0.42, 0.70, 1.0))
	join_abel_button.pressed.connect(_on_join_abel_pressed)
	action_row.add_child(join_abel_button)

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

func _create_slot_option(parent: VBoxContainer, label_text: String, slot_type: StringName) -> OptionButton:
	var label := Label.new()
	label.text = label_text.to_upper()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.72, 0.86, 0.92, 1.0))
	parent.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(560, 34)
	_style_option_button(option)
	parent.add_child(option)
	for weapon_id in WeaponController.WEAPON_PATHS.keys():
		var definition: WeaponDefinition = load(WeaponController.WEAPON_PATHS[weapon_id])
		if definition.slot_type != slot_type:
			continue
		option.add_item(definition.display_name)
		var item_index := option.get_item_count() - 1
		option.set_item_metadata(item_index, definition.weapon_id)
		if _default_weapon_for_slot(slot_type) == definition.weapon_id:
			option.select(item_index)
	return option

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

func _selected_weapon(option: OptionButton) -> StringName:
	return StringName(str(option.get_item_metadata(option.selected)))

func _option_weapon_ids(option: OptionButton) -> Array[StringName]:
	var weapon_ids: Array[StringName] = []
	if option == null:
		return weapon_ids
	for index in range(option.get_item_count()):
		weapon_ids.append(StringName(str(option.get_item_metadata(index))))
	return weapon_ids

func _select_option_by_weapon_id(option: OptionButton, weapon_id: StringName) -> bool:
	if option == null:
		return false
	for index in range(option.get_item_count()):
		if StringName(str(option.get_item_metadata(index))) == weapon_id:
			option.select(index)
			return true
	return false

func _selected_loadout() -> Dictionary:
	return {
		"primary": _selected_weapon(_primary_option),
		"secondary": _selected_weapon(_secondary_option),
		"melee": _selected_weapon(_melee_option),
		"artillery": _selected_weapon(_artillery_option),
	}

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

func _on_join_abel_pressed() -> void:
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
