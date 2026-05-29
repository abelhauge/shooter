@tool
extends VBoxContainer

const CATALOG_PATH := "res://data/maps/downtown_city_asset_catalog.json"
const PLACEMENT_SCRIPT := preload("res://scripts/maps/downtown_city_asset_instance.gd")
const MAP_LAYERS := [
	"GameplayCore",
	"TraversalRoutes",
	"CombatCover",
	"SkylineBackdrop",
	"SpawnSpaces",
	"HazardsAndKillVolumes",
	"LightingAndAtmosphere",
]

var _editor_interface: EditorInterface
var _undo_redo: EditorUndoRedoManager
var _catalog: Array[Dictionary] = []
var _filtered_entries: Array[Dictionary] = []
var _selected_entry: Dictionary = {}
var _preview_node: Node3D

var _category_filter: OptionButton
var _asset_list: ItemList
var _layer_select: OptionButton
var _snap_select: OptionButton
var _rotation_step_select: OptionButton
var _position_spin: Array[SpinBox] = []
var _rotation_spin: Array[SpinBox] = []
var _scale_spin: SpinBox
var _status_label: Label
var _selected_label: Label

func setup(editor_interface: EditorInterface, undo_redo: EditorUndoRedoManager) -> void:
	_editor_interface = editor_interface
	_undo_redo = undo_redo

func _ready() -> void:
	_load_catalog()
	_build_ui()
	_refresh_category_filter()
	_apply_filter()
	_update_status("Loaded %d curated Downtown City MegaKit assets." % _catalog.size())

func _build_ui() -> void:
	custom_minimum_size = Vector2(320, 520)
	var title := Label.new()
	title.text = "P23 City Asset Level Designer"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	_selected_label = Label.new()
	_selected_label.text = "Select an asset from the palette."
	_selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_selected_label)

	_category_filter = OptionButton.new()
	_category_filter.item_selected.connect(_on_category_selected)
	add_child(_category_filter)

	_asset_list = ItemList.new()
	_asset_list.custom_minimum_size = Vector2(280, 170)
	_asset_list.item_selected.connect(_on_asset_selected)
	add_child(_asset_list)

	_layer_select = OptionButton.new()
	for layer_name in MAP_LAYERS:
		_layer_select.add_item(layer_name)
		if layer_name == "SkylineBackdrop":
			_layer_select.select(_layer_select.get_item_count() - 1)
	add_child(_labeled_control("Map layer", _layer_select))

	var transform_grid := GridContainer.new()
	transform_grid.columns = 2
	add_child(transform_grid)
	for axis in ["X", "Y", "Z"]:
		transform_grid.add_child(_small_label("Move %s" % axis))
		var spin := _new_spin(-200.0, 200.0, 0.5, 0.0)
		_position_spin.append(spin)
		transform_grid.add_child(spin)
	for axis in ["Pitch", "Yaw", "Roll"]:
		transform_grid.add_child(_small_label("Rot %s" % axis))
		var spin := _new_spin(-360.0, 360.0, 15.0, 0.0)
		_rotation_spin.append(spin)
		transform_grid.add_child(spin)
	transform_grid.add_child(_small_label("Scale"))
	_scale_spin = _new_spin(0.05, 20.0, 0.05, 1.0)
	transform_grid.add_child(_scale_spin)

	_snap_select = OptionButton.new()
	for snap in ["0.5m", "1m", "5m"]:
		_snap_select.add_item(snap)
	_snap_select.select(0)
	add_child(_labeled_control("Snap preset", _snap_select))

	_rotation_step_select = OptionButton.new()
	for step in ["15 deg", "90 deg"]:
		_rotation_step_select.add_item(step)
	_rotation_step_select.select(0)
	add_child(_labeled_control("Rotation preset", _rotation_step_select))

	var action_grid := GridContainer.new()
	action_grid.columns = 2
	add_child(action_grid)
	_add_button(action_grid, "Preview Ghost", _on_preview_pressed)
	_add_button(action_grid, "Clear Preview", _on_clear_preview_pressed)
	_add_button(action_grid, "Place", _on_place_pressed)
	_add_button(action_grid, "Apply Transform", _on_apply_transform_pressed)
	_add_button(action_grid, "Duplicate", _on_duplicate_pressed)
	_add_button(action_grid, "Delete", _on_delete_pressed)
	_add_button(action_grid, "Validate", _on_validate_pressed)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

func _load_catalog() -> void:
	_catalog.clear()
	if not FileAccess.file_exists(CATALOG_PATH):
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	for entry in parsed.get("entries", []):
		if entry is Dictionary:
			_catalog.append(entry)

func _refresh_category_filter() -> void:
	_category_filter.clear()
	_category_filter.add_item("all")
	var categories: Array[String] = []
	for entry in _catalog:
		var category := String(entry.get("category", "uncategorized"))
		if not categories.has(category):
			categories.append(category)
	categories.sort()
	for category in categories:
		_category_filter.add_item(category)

func _apply_filter() -> void:
	var selected_category := _category_filter.get_item_text(_category_filter.selected)
	_filtered_entries.clear()
	_asset_list.clear()
	for entry in _catalog:
		if selected_category != "all" and String(entry.get("category", "")) != selected_category:
			continue
		_filtered_entries.append(entry)
		_asset_list.add_item("%s  [%s]" % [String(entry.get("display_name", "")), String(entry.get("category", ""))])
	if not _filtered_entries.is_empty():
		_asset_list.select(0)
		_select_entry(0)

func _on_category_selected(_index: int) -> void:
	_apply_filter()

func _on_asset_selected(index: int) -> void:
	_select_entry(index)

func _select_entry(index: int) -> void:
	if index < 0 or index >= _filtered_entries.size():
		_selected_entry = {}
		_selected_label.text = "No asset selected."
		return
	_selected_entry = _filtered_entries[index]
	_selected_label.text = "%s\n%s" % [
		String(_selected_entry.get("asset_id", "")),
		String(_selected_entry.get("source_path", "")),
	]
	var rotation := _array_to_vector3(_selected_entry.get("default_rotation_degrees", [0.0, 0.0, 0.0]))
	var scale := _array_to_vector3(_selected_entry.get("default_scale", [1.0, 1.0, 1.0]))
	_rotation_spin[0].value = rotation.x
	_rotation_spin[1].value = rotation.y
	_rotation_spin[2].value = rotation.z
	_scale_spin.value = scale.x

func _on_preview_pressed() -> void:
	var layer := _target_layer()
	if layer == null or _selected_entry.is_empty():
		_update_status("Open the P23 dressing scene or arena art scene before previewing.")
		return
	_clear_preview()
	_preview_node = _create_placement_node(_selected_entry, "P23PlacementPreview", 0)
	_preview_node.set_meta("p23_preview", true)
	layer.add_child(_preview_node)
	_update_status("Preview ghost added under %s. It is not owned by the scene and will not save." % layer.name)

func _on_clear_preview_pressed() -> void:
	_clear_preview()
	_update_status("Preview ghost cleared.")

func _on_place_pressed() -> void:
	var layer := _target_layer()
	var root := _edited_root()
	if layer == null or root == null or _selected_entry.is_empty():
		_update_status("Open the P23 dressing scene or arena art scene before placing.")
		return
	var node_name := _next_stable_node_name(layer, String(_selected_entry.get("asset_id", "asset")))
	var index := int(node_name.get_slice("_", node_name.get_slice_count("_") - 1))
	var node := _create_placement_node(_selected_entry, node_name, index)
	_undo_redo.create_action("P23 Place City Asset")
	_undo_redo.add_do_method(self, "_do_add_node", layer, node, root)
	_undo_redo.add_undo_method(self, "_do_remove_node", node)
	_undo_redo.commit_action()
	_update_status("Placed %s under %s." % [node_name, layer.name])

func _on_apply_transform_pressed() -> void:
	var node := _selected_placement_node()
	if node == null:
		_update_status("Select a P23 placement node to transform.")
		return
	var snap := _snap_value()
	var rotation_step := _rotation_step_value()
	var new_position := Vector3(
		snappedf(float(_position_spin[0].value), snap),
		snappedf(float(_position_spin[1].value), snap),
		snappedf(float(_position_spin[2].value), snap)
	)
	var new_rotation := Vector3(
		snappedf(float(_rotation_spin[0].value), rotation_step),
		snappedf(float(_rotation_spin[1].value), rotation_step),
		snappedf(float(_rotation_spin[2].value), rotation_step)
	)
	var uniform_scale := float(_scale_spin.value)
	_undo_redo.create_action("P23 Transform City Asset")
	_undo_redo.add_do_property(node, "position", new_position)
	_undo_redo.add_do_property(node, "rotation_degrees", new_rotation)
	_undo_redo.add_do_property(node, "scale", Vector3(uniform_scale, uniform_scale, uniform_scale))
	_undo_redo.add_undo_property(node, "position", node.position)
	_undo_redo.add_undo_property(node, "rotation_degrees", node.rotation_degrees)
	_undo_redo.add_undo_property(node, "scale", node.scale)
	_undo_redo.commit_action()
	_update_status("Applied snapped transform to %s." % node.name)

func _on_duplicate_pressed() -> void:
	var source := _selected_placement_node()
	var layer := _target_layer()
	var root := _edited_root()
	if source == null or layer == null or root == null:
		_update_status("Select a P23 placement node before duplicating.")
		return
	var duplicate := source.duplicate()
	duplicate.name = _next_stable_node_name(layer, String(source.get("asset_id")))
	duplicate.position += Vector3(_snap_value(), 0.0, _snap_value())
	_undo_redo.create_action("P23 Duplicate City Asset")
	_undo_redo.add_do_method(self, "_do_add_node", layer, duplicate, root)
	_undo_redo.add_undo_method(self, "_do_remove_node", duplicate)
	_undo_redo.commit_action()
	_update_status("Duplicated %s." % source.name)

func _on_delete_pressed() -> void:
	var node := _selected_placement_node()
	if node == null:
		_update_status("Select a P23 placement node before deleting.")
		return
	var parent := node.get_parent()
	_undo_redo.create_action("P23 Delete City Asset")
	_undo_redo.add_do_method(self, "_do_remove_node", node)
	_undo_redo.add_undo_method(self, "_do_add_node", parent, node, _edited_root())
	_undo_redo.commit_action()
	_update_status("Deleted %s through undo stack." % node.name)

func _on_validate_pressed() -> void:
	var report := _build_validation_report()
	_update_status("Catalog=%d, placements=%d, missing=%d, source_packs=%d, off_layer=%d." % [
		int(report.get("catalog_count", 0)),
		int(report.get("placement_count", 0)),
		int(report.get("missing_sources", 0)),
		int(report.get("source_pack_paths", 0)),
		int(report.get("off_layer", 0)),
	])

func _do_add_node(parent: Node, node: Node, root: Node) -> void:
	if node.get_parent() != parent:
		parent.add_child(node)
	node.owner = root

func _do_remove_node(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)

func _create_placement_node(entry: Dictionary, node_name: String, placement_index: int) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.set_script(PLACEMENT_SCRIPT)
	node.set("asset_id", String(entry.get("asset_id", "")))
	node.set("display_name", String(entry.get("display_name", "")))
	node.set("category", String(entry.get("category", "")))
	node.set("source_path", String(entry.get("source_path", "")))
	node.set("map_layer", StringName(_selected_layer_name()))
	node.set("placement_index", placement_index)
	node.set("collision_mode", &"auto")
	node.position = Vector3(float(_position_spin[0].value), float(_position_spin[1].value), float(_position_spin[2].value))
	node.rotation_degrees = Vector3(float(_rotation_spin[0].value), float(_rotation_spin[1].value), float(_rotation_spin[2].value))
	var uniform_scale := float(_scale_spin.value)
	node.scale = Vector3(uniform_scale, uniform_scale, uniform_scale)
	return node

func _target_layer() -> Node3D:
	var root := _edited_root()
	if root == null:
		return null
	var layer_name := _selected_layer_name()
	var city_root := _find_city_dressing_root(root)
	if city_root == null:
		city_root = Node3D.new()
		city_root.name = "DowntownCityMegaKitDressing"
		root.add_child(city_root)
		city_root.owner = root
	if not city_root.has_node(layer_name):
		var layer := Node3D.new()
		layer.name = layer_name
		city_root.add_child(layer)
		layer.owner = root
		return layer
	return city_root.get_node(layer_name) as Node3D

func _find_city_dressing_root(root: Node) -> Node3D:
	if root.name == "DowntownCityMegaKitDressing":
		return root as Node3D
	if root.has_node("DowntownCityMegaKitDressing"):
		return root.get_node("DowntownCityMegaKitDressing") as Node3D
	return null

func _edited_root() -> Node:
	if _editor_interface == null:
		return null
	return _editor_interface.get_edited_scene_root()

func _selected_layer_name() -> String:
	return _layer_select.get_item_text(_layer_select.selected)

func _selected_placement_node() -> Node3D:
	if _editor_interface == null:
		return null
	for node in _editor_interface.get_selection().get_selected_nodes():
		if node is Node3D and node.has_method("get_runtime_summary"):
			return node as Node3D
	return null

func _next_stable_node_name(layer: Node, asset_id: String) -> String:
	var prefix := "P23_%s_" % asset_id
	var highest := 0
	for child in layer.get_children():
		if not String(child.name).begins_with(prefix):
			continue
		highest = maxi(highest, int(String(child.name).trim_prefix(prefix)))
	return "%s%03d" % [prefix, highest + 1]

func _build_validation_report() -> Dictionary:
	var missing := 0
	var source_packs := 0
	for entry in _catalog:
		var path := String(entry.get("source_path", ""))
		if path.contains("/source_packs/"):
			source_packs += 1
		if not ResourceLoader.exists(path, "PackedScene") and not FileAccess.file_exists(path):
			missing += 1
	var placements := 0
	var off_layer := 0
	var root := _edited_root()
	if root != null:
		for node in _collect_nodes(root):
			if not String(node.name).begins_with("P23_"):
				continue
			placements += 1
			if node.get_parent() == null or not MAP_LAYERS.has(String(node.get_parent().name)):
				off_layer += 1
	return {
		"catalog_count": _catalog.size(),
		"placement_count": placements,
		"missing_sources": missing,
		"source_pack_paths": source_packs,
		"off_layer": off_layer,
	}

func _collect_nodes(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	for child in root.get_children():
		nodes.append_array(_collect_nodes(child))
	return nodes

func _clear_preview() -> void:
	if _preview_node != null and is_instance_valid(_preview_node):
		_preview_node.queue_free()
	_preview_node = null

func _snap_value() -> float:
	return [0.5, 1.0, 5.0][_snap_select.selected]

func _rotation_step_value() -> float:
	return [15.0, 90.0][_rotation_step_select.selected]

func _array_to_vector3(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

func _new_spin(min_value: float, max_value: float, step: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	return spin

func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _labeled_control(label_text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	box.add_child(control)
	return box

func _add_button(parent: Node, text: String, callable: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callable)
	parent.add_child(button)

func _update_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
