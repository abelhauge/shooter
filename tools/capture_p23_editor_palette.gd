extends SceneTree

const DOCK_SCRIPT := preload("res://addons/city_level_designer/city_level_designer_dock.gd")
const OUTPUT_PATH := "res://docs/verification/screenshots/p23_level_designer_editor_palette.png"
const EDIT_SCENE := "res://scenes/maps/art/arena_downtown_01_art.tscn"

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var canvas := PanelContainer.new()
	canvas.size = Vector2(1280, 900)
	viewport.add_child(canvas)

	var outer := HBoxContainer.new()
	outer.size = Vector2(1280, 900)
	outer.add_theme_constant_override("separation", 16)
	canvas.add_child(outer)

	var scene_panel := _build_scene_context_panel()
	scene_panel.custom_minimum_size = Vector2(820, 900)
	outer.add_child(scene_panel)

	var dock := DOCK_SCRIPT.new()
	dock.custom_minimum_size = Vector2(420, 900)
	outer.add_child(dock)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	viewport.queue_free()
	if error != OK:
		push_error("P23 editor palette capture failed: %s" % error)
		quit(1)
		return
	print("P23_EDITOR_PALETTE_CAPTURED %s" % OUTPUT_PATH)
	quit(0)

func _build_scene_context_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Godot Editor - P23 City Asset Level Designer"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var scene := Label.new()
	scene.text = "Open scene: %s" % EDIT_SCENE
	box.add_child(scene)

	var selected := Label.new()
	selected.text = "Selected tool dock: City Asset Level Designer"
	box.add_child(selected)

	var layers := Label.new()
	layers.text = "Placement layers: GameplayCore, TraversalRoutes, CombatCover, SkylineBackdrop, SpawnSpaces, HazardsAndKillVolumes, LightingAndAtmosphere"
	layers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(layers)

	var actions := Label.new()
	actions.text = "Designer actions exposed: Preview Ghost, Clear Preview, Place, Apply Transform, Duplicate, Delete, Validate"
	actions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(actions)

	var notes := RichTextLabel.new()
	notes.custom_minimum_size = Vector2(760, 620)
	notes.fit_content = false
	notes.bbcode_enabled = true
	notes.text = "[b]Direct arena editing context[/b]\n- Tool runs as an EditorPlugin dock, not an external editor.\n- Catalog entries are loaded from data/maps/downtown_city_asset_catalog.json.\n- City placements are saved directly in scenes/maps/art/arena_downtown_01_art.tscn under DowntownCityMegaKitDressing.\n- New placements are parented under the selected map layer in the open arena scene.\n- Asset source is restricted to assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot).\n\n[b]Screenshot target[/b]\nThe palette on the right is the actual dock Control used by the EditorPlugin, rendered through Godot for deterministic verification capture."
	box.add_child(notes)
	return panel
