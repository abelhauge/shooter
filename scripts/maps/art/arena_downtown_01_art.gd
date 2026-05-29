@tool
extends Node3D

const BLOCKOUT_SCENE := preload("res://scenes/maps/blockout/arena_downtown_01_blockout.tscn")
const ROOFTOP_CONFIG := preload("res://data/maps/arena_downtown_01_rooftop_config.tres")
const DOWNTOWN_ROOT := "res://assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/"
const GENERATED_EDITOR_NODE_META := "arena_downtown_editor_generated"
const GENERATED_EDITOR_ROOT_NAMES := [
	"GameplayBlockout",
	"RooftopMist",
	"RooftopSpawnPoints",
	"DowntownCityMegaKitDressing",
	"P03DowntownAssetProof",
	"WarmContainerYardFill",
	"CoolSkylineRim",
	"BlueSpawnPerimeterFill",
	"OrangeSpawnPerimeterFill",
	"NorthYardEdgeFill",
	"SouthYardEdgeFill",
	"HighRouteFill",
]

const P03_PROOF_ASSETS := [
	{"file": "Building_Large_2.gltf", "pos": Vector3(-10, 0.0, 2), "rot": Vector3(0, 20, 0), "scale": Vector3(0.65, 0.65, 0.65)},
	{"file": "Building_Small_1.gltf", "pos": Vector3(10, 0.0, 2), "rot": Vector3(0, -25, 0), "scale": Vector3(0.9, 0.9, 0.9)},
	{"file": "Street_4Lane.gltf", "pos": Vector3(0, 0.03, 9), "rot": Vector3(0, 90, 0), "scale": Vector3(1.8, 1.8, 1.8)},
	{"file": "Street_2Lane.gltf", "pos": Vector3(0, 0.04, 4), "rot": Vector3(0, 90, 0), "scale": Vector3(1.8, 1.8, 1.8)},
	{"file": "Sidewalk_Straight_3m.gltf", "pos": Vector3(-8, 0.08, 10), "rot": Vector3(0, 0, 0), "scale": Vector3(1.4, 1.4, 1.4)},
	{"file": "Stairs_Rails_Metal.gltf", "pos": Vector3(8, 0.08, 10), "rot": Vector3(0, 180, 0), "scale": Vector3(1.0, 1.0, 1.0)},
	{"file": "Prop_ACUnit.gltf", "pos": Vector3(-5, 0.1, 13), "rot": Vector3(0, 25, 0), "scale": Vector3(1.2, 1.2, 1.2)},
	{"file": "Prop_Bollard.gltf", "pos": Vector3(-2, 0.08, 13), "rot": Vector3(0, 0, 0), "scale": Vector3(1.4, 1.4, 1.4)},
	{"file": "Prop_ManholeCover.gltf", "pos": Vector3(2, 0.08, 13), "rot": Vector3(0, 0, 0), "scale": Vector3(1.4, 1.4, 1.4)},
	{"file": "Prop_Planter_Single.gltf", "pos": Vector3(5, 0.08, 13), "rot": Vector3(0, -20, 0), "scale": Vector3(1.2, 1.2, 1.2)},
]

var _blockout: Node3D
var _art_root: Node3D
var _p03_proof_root: Node3D
var _rooftop_spawn_root: Node3D
var _loaded_asset_sources: Array[String] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		_clear_editor_generated_nodes()
	_loaded_asset_sources.clear()
	_blockout = null
	_art_root = null
	_p03_proof_root = null
	_blockout = BLOCKOUT_SCENE.instantiate()
	_blockout.name = "GameplayBlockout"
	_add_generated_child(self, _blockout)
	_hide_blockout_layer_meshes("SkylineBackdrop")
	_hide_blockout_layer_meshes("GameplayCore")
	_hide_blockout_layer_meshes("TraversalRoutes")
	_hide_blockout_static_body_meshes("CombatCover")
	_hide_blockout_layer_meshes("PerimeterClosure")
	_art_root = _get_or_create_city_dressing_root()
	_make_visual_only(_art_root)
	_create_rooftop_spawn_points()

func get_spawn_points() -> Array[SpawnPoint]:
	if _rooftop_spawn_root != null:
		var rooftop_spawns: Array[SpawnPoint] = []
		for child in _rooftop_spawn_root.get_children():
			if child is SpawnPoint:
				rooftop_spawns.append(child)
		if not rooftop_spawns.is_empty():
			return rooftop_spawns
	if _blockout != null and _blockout.has_method("get_spawn_points"):
		return _blockout.get_spawn_points()
	return []

func get_rooftop_map_config() -> Resource:
	return ROOFTOP_CONFIG

func get_runtime_smoke_summary() -> Dictionary:
	return {
		"has_blockout": _blockout != null,
		"has_art_root": _art_root != null,
		"art_children": _art_root.get_child_count() if _art_root != null else 0,
		"loaded_asset_sources": _collect_loaded_asset_sources(),
		"p04_dressing_report": get_p04_dressing_report(),
		"p23_level_designer_report": get_p23_level_designer_report(),
		"map_closure_report": _blockout.get_map_closure_report() if _blockout != null and _blockout.has_method("get_map_closure_report") else {},
		"p03_proof_children": _p03_proof_root.get_child_count() if _p03_proof_root != null else 0,
		"spawn_points": get_spawn_points().size(),
	}

func get_p03_asset_manifest() -> Array[Dictionary]:
	var manifest: Array[Dictionary] = []
	_ensure_p03_proof_assets()
	if _p03_proof_root == null:
		return manifest
	for child in _p03_proof_root.get_children():
		manifest.append({
			"source_file": child.get_meta("source_file", ""),
			"node_path": str(child.get_path()),
		})
	return manifest

func get_p03_capture_pose() -> Dictionary:
	_ensure_p03_proof_assets()
	return {
		"position": Vector3(0.0, 8.0, 28.0),
		"yaw": 0.0,
		"pitch": deg_to_rad(-24.0),
	}

func get_p04_dressing_manifest() -> Array[Dictionary]:
	var manifest: Array[Dictionary] = []
	if _art_root == null:
		return manifest
	for item in _collect_city_asset_summaries(_art_root):
		if String(item.get("node_name", "")).begins_with("P23_"):
			continue
		manifest.append(item)
	return manifest

func get_p04_dressing_report() -> Dictionary:
	var manifest := get_p04_dressing_manifest()
	var landmark_count := 0
	var playable_support_count := 0
	var route_names: Array[String] = []
	for item in manifest:
		var tags: Array = item.get("tags", [])
		if tags.has("landmark"):
			landmark_count += 1
		if tags.has("playable_space"):
			playable_support_count += 1
		var route_name := String(item.get("route", ""))
		if route_name != "" and not route_names.has(route_name):
			route_names.append(route_name)
	return {
		"instance_count": manifest.size(),
		"landmark_count": landmark_count,
		"playable_support_count": playable_support_count,
		"traversal_route_count": route_names.size(),
		"traversal_routes": route_names,
		"enabled_art_collision_objects": _count_enabled_collision_objects(_art_root),
	}

func get_p04_capture_pose(view_name: String) -> Dictionary:
	var poses := {
		"blue_spawn": {"position": Vector3(-32.0, 0.3, 22.0), "target": Vector3(-12.0, 1.6, 7.0)},
		"orange_spawn": {"position": Vector3(32.0, 0.3, -22.0), "target": Vector3(12.0, 1.6, -7.0)},
		"mid_map": {"position": Vector3(0.0, 8.0, 28.0), "target": Vector3(0.0, 1.0, 0.0)},
		"traversal_route": {"position": Vector3(-25.0, 6.0, -25.0), "target": Vector3(-8.0, 5.6, -10.0)},
	}
	return poses.get(view_name, {})

func get_p23_level_designer_manifest() -> Array[Dictionary]:
	var manifest: Array[Dictionary] = []
	if _art_root == null:
		return manifest
	for item in _collect_city_asset_summaries(_art_root):
		if String(item.get("node_name", "")).begins_with("P23_"):
			manifest.append(item)
	return manifest

func get_p23_level_designer_report() -> Dictionary:
	var manifest := get_p23_level_designer_manifest()
	var layer_names: Array[String] = []
	var missing_sources: Array[String] = []
	var source_pack_paths: Array[String] = []
	var invalid_transforms: Array[String] = []
	var stable_name_count := 0
	for item in manifest:
		var parent_layer := String(item.get("parent_layer", ""))
		if parent_layer != "" and not layer_names.has(parent_layer):
			layer_names.append(parent_layer)
		if not bool(item.get("source_exists", false)):
			missing_sources.append(String(item.get("source_path", "")))
		if bool(item.get("uses_source_packs", false)):
			source_pack_paths.append(String(item.get("source_path", "")))
		var scale_value: Vector3 = item.get("scale", Vector3.ONE)
		if scale_value.x <= 0.0 or scale_value.y <= 0.0 or scale_value.z <= 0.0:
			invalid_transforms.append(String(item.get("node_name", "")))
		if String(item.get("node_name", "")).begins_with("P23_"):
			stable_name_count += 1
	return {
		"ok": missing_sources.is_empty() and source_pack_paths.is_empty() and invalid_transforms.is_empty(),
		"placement_count": manifest.size(),
		"stable_name_count": stable_name_count,
		"layer_names": layer_names,
		"missing_sources": missing_sources,
		"source_pack_paths": source_pack_paths,
		"invalid_transforms": invalid_transforms,
		"manifest": manifest,
	}

func get_p23_capture_pose(view_name: String) -> Dictionary:
	var poses := {
		"game_view": {"position": Vector3(-30.0, 7.0, 25.0), "target": Vector3(0.0, 2.2, -12.0)},
		"traversal_check": {"position": Vector3(-23.0, 8.2, -23.0), "target": Vector3(-4.0, 6.1, -7.0)},
	}
	return poses.get(view_name, {})

func _create_rooftop_spawn_points() -> void:
	if _rooftop_spawn_root != null:
		_rooftop_spawn_root.queue_free()
	_rooftop_spawn_root = Node3D.new()
	_rooftop_spawn_root.name = "RooftopSpawnPoints"
	_add_generated_child(self, _rooftop_spawn_root)

	var candidates := _collect_rooftop_spawn_candidates()
	if candidates.is_empty():
		candidates = _fallback_rooftop_spawn_candidates()
	var blue_candidates := _select_team_rooftop_candidates(candidates, 1)
	var orange_candidates := _select_team_rooftop_candidates(candidates, 2)
	var suffixes := ["A", "B", "C", "D"]
	for index in range(4):
		_create_runtime_rooftop_spawn(_rooftop_spawn_root, "BlueRooftopSpawn%s" % suffixes[index], 1, blue_candidates[index % blue_candidates.size()], Vector3.ZERO)
		_create_runtime_rooftop_spawn(_rooftop_spawn_root, "OrangeRooftopSpawn%s" % suffixes[index], 2, orange_candidates[index % orange_candidates.size()], Vector3.ZERO)

func _collect_rooftop_spawn_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	_collect_rooftop_spawn_candidates_recursive(_art_root, candidates)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("area", 0.0)) > float(b.get("area", 0.0))
	)
	return candidates

func _collect_rooftop_spawn_candidates_recursive(node: Node, candidates: Array[Dictionary]) -> void:
	if node == null:
		return
	if node.has_method("get_runtime_summary"):
		var summary: Dictionary = node.get_runtime_summary()
		var category := String(summary.get("category", "")).to_lower()
		var tags: Array = summary.get("tags", [])
		if category == "building" or tags.has("rooftop_spawn"):
			var bounds := _collect_active_collision_bounds(node)
			if bounds.size.y > 0.01 and bounds.end.y >= ROOFTOP_CONFIG.rooftop_spawn_min_y:
				candidates.append({
					"position": Vector3(bounds.get_center().x, bounds.end.y + ROOFTOP_CONFIG.rooftop_spawn_clearance, bounds.get_center().z),
					"area": bounds.size.x * bounds.size.z,
					"bounds": bounds,
					"source": node.name,
				})
	for child in node.get_children():
		_collect_rooftop_spawn_candidates_recursive(child, candidates)

func _collect_active_collision_bounds(root: Node) -> AABB:
	var state := {
		"has_bounds": false,
		"bounds": AABB(),
	}
	_collect_active_collision_bounds_recursive(root, state)
	return state["bounds"] if bool(state["has_bounds"]) else AABB()

func _collect_active_collision_bounds_recursive(node: Node, state: Dictionary) -> void:
	if node is CollisionShape3D:
		var shape_node := node as CollisionShape3D
		if not shape_node.disabled and shape_node.shape is BoxShape3D:
			_expand_bounds_with_box_shape(shape_node, state)
	for child in node.get_children():
		_collect_active_collision_bounds_recursive(child, state)

func _expand_bounds_with_box_shape(shape_node: CollisionShape3D, state: Dictionary) -> void:
	var box := shape_node.shape as BoxShape3D
	var half := box.size * 0.5
	var transform := shape_node.global_transform
	for x in [-half.x, half.x]:
		for y in [-half.y, half.y]:
			for z in [-half.z, half.z]:
				var point := transform * Vector3(x, y, z)
				if not bool(state["has_bounds"]):
					state["bounds"] = AABB(point, Vector3.ZERO)
					state["has_bounds"] = true
				else:
					state["bounds"] = (state["bounds"] as AABB).expand(point)

func _fallback_rooftop_spawn_candidates() -> Array[Dictionary]:
	var fallback_positions := [
		Vector3(-28.0, 11.0, 18.0),
		Vector3(-20.0, 12.0, -18.0),
		Vector3(-8.0, 10.5, 16.0),
		Vector3(-34.0, 10.5, -4.0),
		Vector3(28.0, 11.0, -18.0),
		Vector3(20.0, 12.0, 18.0),
		Vector3(8.0, 10.5, -16.0),
		Vector3(34.0, 10.5, 4.0),
	]
	var candidates: Array[Dictionary] = []
	for position in fallback_positions:
		candidates.append({"position": position, "area": 1.0, "source": "fallback"})
	return candidates

func _select_team_rooftop_candidates(candidates: Array[Dictionary], team_id: int) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for candidate in candidates:
		var position: Vector3 = candidate.get("position", Vector3.ZERO)
		if (team_id == 1 and position.x <= 0.0) or (team_id == 2 and position.x >= 0.0):
			selected.append(candidate)
	if selected.size() < 4:
		selected = candidates.duplicate()
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ax := (a.get("position", Vector3.ZERO) as Vector3).x
		var bx := (b.get("position", Vector3.ZERO) as Vector3).x
		return ax < bx if team_id == 1 else ax > bx
	)
	return selected.slice(0, mini(4, selected.size()))

func _create_runtime_rooftop_spawn(parent: Node3D, node_name: String, team_id: int, candidate: Dictionary, look_target: Vector3) -> SpawnPoint:
	var spawn := SpawnPoint.new()
	spawn.name = node_name
	spawn.team_id = team_id
	spawn.spawn_group = &"arena_downtown_01_rooftop"
	spawn.position = candidate.get("position", Vector3.ZERO)
	spawn.yaw_degrees = _yaw_degrees_toward(spawn.position, look_target)
	spawn.set_meta("source_rooftop", candidate.get("source", ""))
	parent.add_child(spawn)
	return spawn

func _yaw_degrees_toward(from_position: Vector3, target_position: Vector3) -> float:
	var direction := target_position - from_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return 0.0
	direction = direction.normalized()
	return rad_to_deg(atan2(-direction.x, -direction.z))

func _get_or_create_city_dressing_root() -> Node3D:
	var existing := get_node_or_null("DowntownCityMegaKitDressing") as Node3D
	if existing != null:
		return existing
	var scene_root := Node3D.new()
	scene_root.name = "DowntownCityMegaKitDressing"
	_add_generated_child(self, scene_root)
	return scene_root

func _collect_loaded_asset_sources() -> Array[String]:
	var sources: Array[String] = []
	for item in _collect_city_asset_summaries(_art_root):
		var path := String(item.get("source_path", ""))
		if path != "" and not sources.has(path):
			sources.append(path)
	for path in _loaded_asset_sources:
		if not sources.has(path):
			sources.append(path)
	return sources

func _collect_city_asset_summaries(root: Node) -> Array[Dictionary]:
	var manifest: Array[Dictionary] = []
	if root == null:
		return manifest
	if root.has_method("get_runtime_summary"):
		var summary: Dictionary = root.get_runtime_summary()
		summary["node_path"] = str(root.get_path())
		summary["node_name"] = root.name
		if root.get_parent() != null:
			summary["parent_layer"] = root.get_parent().name
		manifest.append(summary)
	for child in root.get_children():
		manifest.append_array(_collect_city_asset_summaries(child))
	return manifest

func _add_p03_proof_assets() -> void:
	if _p03_proof_root != null:
		return
	_p03_proof_root = Node3D.new()
	_p03_proof_root.name = "P03DowntownAssetProof"
	_add_generated_child(self, _p03_proof_root)
	for entry in P03_PROOF_ASSETS:
		var asset := _instantiate_downtown_asset(entry)
		if asset == null:
			continue
		asset.name = "P03_%s" % String(entry["file"]).get_basename()
		_p03_proof_root.add_child(asset)

func _ensure_p03_proof_assets() -> void:
	if _p03_proof_root == null:
		_add_p03_proof_assets()

func _instantiate_downtown_asset(entry: Dictionary) -> Node3D:
	var file_name := String(entry["file"])
	var path := DOWNTOWN_ROOT + file_name
	var asset := _instantiate_scene_asset(path)
	if asset == null:
		return null
	asset.name = String(entry.get("name", file_name.get_basename()))
	asset.position = entry["pos"]
	asset.rotation_degrees = entry["rot"]
	asset.scale = entry["scale"]
	asset.set_meta("source_file", path)
	asset.set_meta("tags", entry.get("tags", []))
	asset.set_meta("route", entry.get("route", ""))
	_make_visual_only(asset)
	if not _loaded_asset_sources.has(path):
		_loaded_asset_sources.append(path)
	return asset

func _load_packed_scene_if_available(path: String) -> PackedScene:
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	return ResourceLoader.load(path, "PackedScene") as PackedScene

func _instantiate_scene_asset(path: String) -> Node3D:
	var scene := _load_packed_scene_if_available(path)
	if scene != null:
		return scene.instantiate() as Node3D
	var gltf_document := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var error := gltf_document.append_from_file(path, gltf_state)
	if error != OK:
		return null
	return gltf_document.generate_scene(gltf_state) as Node3D

func _make_visual_only(root: Node) -> void:
	if root.name == "CollisionProxy":
		return
	if root is CollisionObject3D:
		var collision_object := root as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	for child in root.get_children():
		_make_visual_only(child)

func _count_enabled_collision_objects(root: Node) -> int:
	if root == null:
		return 0
	var count := 0
	if root is CollisionObject3D:
		var collision_object := root as CollisionObject3D
		if collision_object.collision_layer != 0 or collision_object.collision_mask != 0:
			count += 1
	if root is CollisionShape3D and not (root as CollisionShape3D).disabled:
		count += 1
	for child in root.get_children():
		count += _count_enabled_collision_objects(child)
	return count

func _hide_blockout_layer_meshes(layer_name: String) -> void:
	if _blockout == null:
		return
	var layer := _blockout.get_node_or_null(layer_name)
	if layer == null:
		return
	_set_meshes_visible(layer, false)

func _hide_blockout_static_body_meshes(layer_name: String) -> void:
	if _blockout == null:
		return
	var layer := _blockout.get_node_or_null(layer_name)
	if layer == null:
		return
	for child in layer.get_children():
		if child is StaticBody3D:
			_set_meshes_visible(child, false)

func _set_meshes_visible(root: Node, is_visible: bool) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).visible = is_visible
	for child in root.get_children():
		_set_meshes_visible(child, is_visible)

func _add_atmosphere() -> void:
	var fill := OmniLight3D.new()
	fill.name = "WarmContainerYardFill"
	fill.position = Vector3(0, 8, 0)
	fill.light_color = Color(1.0, 0.68, 0.42)
	fill.light_energy = 1.9
	fill.omni_range = 58.0
	_add_generated_child(self, fill)

	var rim := DirectionalLight3D.new()
	rim.name = "CoolSkylineRim"
	rim.rotation_degrees = Vector3(-45, 135, 0)
	rim.light_color = Color(0.55, 0.70, 1.0)
	rim.light_energy = 0.75
	rim.shadow_enabled = true
	_add_generated_child(self, rim)

	_add_yard_light("BlueSpawnPerimeterFill", Vector3(-32, 6.0, 22), Color(0.45, 0.72, 1.0), 1.55, 28.0)
	_add_yard_light("OrangeSpawnPerimeterFill", Vector3(32, 6.0, -22), Color(1.0, 0.62, 0.34), 1.55, 28.0)
	_add_yard_light("NorthYardEdgeFill", Vector3(0, 6.5, -25), Color(1.0, 0.76, 0.46), 1.25, 30.0)
	_add_yard_light("SouthYardEdgeFill", Vector3(0, 6.5, 25), Color(0.64, 0.78, 1.0), 1.25, 30.0)
	_add_yard_light("HighRouteFill", Vector3(0, 9.0, 0), Color(0.78, 0.86, 1.0), 1.15, 34.0)

func _add_yard_light(node_name: String, position: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	_add_generated_child(self, light)

func _add_generated_child(parent: Node, child: Node) -> void:
	if Engine.is_editor_hint():
		child.set_meta(GENERATED_EDITOR_NODE_META, true)
	parent.add_child(child)

func _clear_editor_generated_nodes() -> void:
	for child in get_children():
		if child.owner != null:
			continue
		if not child.has_meta(GENERATED_EDITOR_NODE_META) and not GENERATED_EDITOR_ROOT_NAMES.has(String(child.name)):
			continue
		remove_child(child)
		child.free()
