@tool
extends EditorPlugin

const DOCK_SCRIPT := preload("res://addons/city_level_designer/city_level_designer_dock.gd")
const RUNNER_START_SCENE_ENV := "SHOOTER_EDITOR_START_SCENE"

var _dock: Control

func _enter_tree() -> void:
	_dock = DOCK_SCRIPT.new()
	_dock.name = "City Asset Level Designer"
	if _dock.has_method("setup"):
		_dock.setup(get_editor_interface(), get_undo_redo())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	call_deferred("_open_runner_start_scene")

func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

func _open_runner_start_scene() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var scene_path := OS.get_environment(RUNNER_START_SCENE_ENV)
	if scene_path == "":
		return
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		push_warning("Requested editor start scene does not exist: %s" % scene_path)
		return
	var editor_interface := get_editor_interface()
	var edited_scene_root := editor_interface.get_edited_scene_root()
	if edited_scene_root != null and edited_scene_root.scene_file_path == scene_path:
		return
	editor_interface.open_scene_from_path(scene_path)
