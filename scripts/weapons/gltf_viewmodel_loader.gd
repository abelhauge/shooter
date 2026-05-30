class_name GltfViewModelLoader
extends Node3D

@export var source_fbx_path := ""
@export var generated_glb_path := ""
@export var viewmodel_kind := ""
@export var asset_pack := ""
@export var model_position := Vector3.ZERO
@export var model_rotation_degrees := Vector3.ZERO
@export var model_scale := Vector3.ONE
@export var apply_material_override := false
@export var material_color := Color(0.62, 0.66, 0.70, 1.0)
@export var material_metallic := 0.25
@export var material_roughness := 0.55
@export var use_named_material_palette := true

var model_root: Node3D
var vertex_count := 0

func _ready() -> void:
	model_root = _load_glb_scene(generated_glb_path)
	if model_root == null:
		push_error("Could not load GLTF/GLB viewmodel: %s" % generated_glb_path)
		return
	model_root.name = "ImportedAssetModel"
	model_root.position = model_position
	model_root.rotation_degrees = model_rotation_degrees
	model_root.scale = model_scale
	add_child(model_root)
	if apply_material_override:
		_apply_material_override(model_root)
	vertex_count = _count_mesh_vertices(model_root)

func get_runtime_summary() -> Dictionary:
	return {
		"source_fbx_path": source_fbx_path,
		"generated_glb_path": generated_glb_path,
		"source_asset_path": generated_glb_path,
		"viewmodel_kind": viewmodel_kind,
		"asset_pack": asset_pack,
		"has_mesh": model_root != null and vertex_count > 0,
		"vertex_count": vertex_count,
		"material_override": apply_material_override,
		"uses_source_materials": not apply_material_override,
		"uses_named_material_palette": apply_material_override and use_named_material_palette,
		"has_curated_materials": not apply_material_override or use_named_material_palette,
	}

func _load_glb_scene(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		push_error("GLB viewmodel import failed for %s: %s" % [path, error_string(error)])
		return null
	return document.generate_scene(state) as Node3D

func _count_mesh_vertices(root: Node) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mesh := (root as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				count += vertices.size()
	for child in root.get_children():
		count += _count_mesh_vertices(child)
	return count

func _apply_material_override(root: Node) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null and use_named_material_palette:
			for surface_index in range(mesh.get_surface_count()):
				var source_material := mesh.surface_get_material(surface_index)
				var surface_name := source_material.resource_name if source_material != null else ""
				mesh_instance.set_surface_override_material(surface_index, _create_viewmodel_material(surface_name))
		else:
			mesh_instance.material_override = _create_viewmodel_material("")
	for child in root.get_children():
		_apply_material_override(child)

func _create_viewmodel_material(source_name: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var normalized := source_name.to_lower()
	material.albedo_color = _color_for_source_material(normalized)
	material.metallic = material_metallic
	material.roughness = material_roughness
	if normalized.contains("metal") or normalized.contains("barrel") or normalized.contains("black"):
		material.metallic = maxf(material.metallic, 0.35)
		material.roughness = minf(material.roughness, 0.42)
	return material

func _color_for_source_material(normalized_name: String) -> Color:
	if normalized_name.contains("bulletred"):
		return Color(0.82, 0.12, 0.08, 1.0)
	if normalized_name.contains("bulletyellow"):
		return Color(0.96, 0.68, 0.18, 1.0)
	if normalized_name.contains("orange"):
		return Color(0.90, 0.38, 0.12, 1.0)
	if normalized_name.contains("wood"):
		return Color(0.46, 0.27, 0.13, 1.0)
	if normalized_name.contains("darkmetal"):
		return Color(0.34, 0.37, 0.40, 1.0)
	if normalized_name.contains("barrel"):
		return Color(0.50, 0.55, 0.61, 1.0)
	if normalized_name.contains("black"):
		return Color(0.08, 0.09, 0.10, 1.0)
	if normalized_name.contains("trigger"):
		return Color(0.06, 0.055, 0.05, 1.0)
	if normalized_name.contains("magazine"):
		return Color(0.10, 0.11, 0.12, 1.0)
	if normalized_name.contains("green"):
		return Color(0.24, 0.38, 0.22, 1.0)
	return material_color
