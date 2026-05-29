@tool
extends Node3D

@export var asset_id := ""
@export var display_name := ""
@export var category := ""
@export_file("*.gltf", "*.glb", "*.tscn") var source_path := ""
@export var map_layer: StringName = &"SkylineBackdrop"
@export var placement_index := 0
@export var collision_mode: StringName = &"auto"
@export var source_tags: Array[String] = []
@export var route: StringName = &""

const VISUAL_ROOT_NAME := "AssetVisual"
const COLLISION_PROXY_NAME := "CollisionProxy"
const SOLID_AUTO_CATEGORIES := [&"building", &"facade", &"landmark", &"backdrop", &"street"]

var _last_loaded_source_path := ""

func _ready() -> void:
	_refresh_visual()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and source_path != _last_loaded_source_path:
		_refresh_visual()

func get_runtime_summary() -> Dictionary:
	return {
		"asset_id": asset_id,
		"display_name": display_name,
		"category": category,
		"source_path": source_path,
		"source_exists": _source_exists(source_path),
		"uses_source_packs": source_path.contains("/source_packs/"),
		"map_layer": map_layer,
		"placement_index": placement_index,
		"collision_mode": collision_mode,
		"has_collision_proxy": get_node_or_null(COLLISION_PROXY_NAME) != null,
		"source_file": source_path,
		"tags": source_tags,
		"route": route,
		"visual_loaded": get_node_or_null(VISUAL_ROOT_NAME) != null,
		"position": position,
		"rotation_degrees": rotation_degrees,
		"scale": scale,
	}

func _refresh_visual() -> void:
	_last_loaded_source_path = source_path
	var existing := get_node_or_null(VISUAL_ROOT_NAME)
	if existing != null:
		existing.queue_free()
	var existing_proxy := get_node_or_null(COLLISION_PROXY_NAME)
	if existing_proxy != null:
		existing_proxy.queue_free()
	if source_path == "" or not _source_exists(source_path):
		return
	var asset := _instantiate_scene_asset(source_path)
	if asset == null:
		return
	asset.name = VISUAL_ROOT_NAME
	asset.set_meta("p23_source_path", source_path)
	asset.set_meta("p23_asset_id", asset_id)
	add_child(asset)
	_make_visual_only(asset)
	if _should_add_collision_proxy():
		_add_collision_proxy(asset)

func _source_exists(path: String) -> bool:
	return ResourceLoader.exists(path, "PackedScene") or FileAccess.file_exists(path)

func _instantiate_scene_asset(path: String) -> Node3D:
	if ResourceLoader.exists(path, "PackedScene"):
		var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
		if scene != null:
			return scene.instantiate() as Node3D
	if not FileAccess.file_exists(path):
		return null
	var gltf_document := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var error := gltf_document.append_from_file(path, gltf_state)
	if error != OK:
		push_warning("P23 could not import city asset %s: %s" % [path, error_string(error)])
		return null
	return gltf_document.generate_scene(gltf_state) as Node3D

func _make_visual_only(root: Node) -> void:
	if root is CollisionObject3D:
		var collision_object := root as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	for child in root.get_children():
		_make_visual_only(child)

func _should_add_collision_proxy() -> bool:
	if collision_mode == &"visual_only" or collision_mode == &"none":
		return false
	if collision_mode == &"solid_proxy":
		return true
	if collision_mode != &"auto":
		return false
	return (
		SOLID_AUTO_CATEGORIES.has(StringName(category))
		or asset_id.to_lower().contains("wall")
		or display_name.to_lower().contains("wall")
	)

func _add_collision_proxy(asset: Node3D) -> void:
	var visual_bounds := _collect_visual_bounds(asset)
	if visual_bounds.size.x <= 0.01 or visual_bounds.size.y <= 0.01 or visual_bounds.size.z <= 0.01:
		return
	var body := StaticBody3D.new()
	body.name = COLLISION_PROXY_NAME
	body.collision_layer = 1
	body.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = visual_bounds.size
	shape_node.shape = shape
	shape_node.position = visual_bounds.get_center()
	body.add_child(shape_node)
	add_child(body)

func _collect_visual_bounds(root_node: Node3D) -> AABB:
	var state := {
		"has_bounds": false,
		"bounds": AABB(),
	}
	_collect_visual_bounds_recursive(root_node, root_node.transform, state)
	return state["bounds"] if bool(state["has_bounds"]) else AABB()

func _collect_visual_bounds_recursive(node: Node, local_transform: Transform3D, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			_expand_bounds_with_aabb(mesh_instance.get_aabb(), local_transform, state)
	for child in node.get_children():
		if child is Node3D:
			var child_node := child as Node3D
			_collect_visual_bounds_recursive(child_node, local_transform * child_node.transform, state)

func _expand_bounds_with_aabb(source_bounds: AABB, local_transform: Transform3D, state: Dictionary) -> void:
	for x in [source_bounds.position.x, source_bounds.position.x + source_bounds.size.x]:
		for y in [source_bounds.position.y, source_bounds.position.y + source_bounds.size.y]:
			for z in [source_bounds.position.z, source_bounds.position.z + source_bounds.size.z]:
				var point := local_transform * Vector3(x, y, z)
				if not bool(state["has_bounds"]):
					state["bounds"] = AABB(point, Vector3.ZERO)
					state["has_bounds"] = true
				else:
					state["bounds"] = (state["bounds"] as AABB).expand(point)
