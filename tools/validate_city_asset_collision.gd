extends SceneTree

const INSTANCE_SCRIPT := preload("res://scripts/maps/downtown_city_asset_instance.gd")

const BUILDING_ENTRY := {
	"asset_id": "building_medium_2_001",
	"display_name": "Medium Corner Building",
	"category": "building",
	"source_path": "res://assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Building_Medium_2_001.gltf",
	"expects_collision": true,
}
const WALL_ENTRY := {
	"asset_id": "trim_wall_guard",
	"display_name": "Wall Guard Trim",
	"category": "trim",
	"source_path": "res://assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Trim_Wall_Guard.gltf",
	"expects_collision": true,
}
const STREET_ENTRY := {
	"asset_id": "street_4lane",
	"display_name": "Street 4 Lane",
	"category": "street",
	"source_path": "res://assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Street_4Lane.gltf",
	"expects_collision": true,
}

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	for entry in [BUILDING_ENTRY, WALL_ENTRY, STREET_ENTRY]:
		var result := await _validate_entry(entry)
		if not bool(result.get("ok", false)):
			push_error("City asset collision validation failed: %s" % str(result))
			quit(1)
			return
	print("CITY_ASSET_COLLISION_VALIDATION_PASS building_wall_and_street_auto_collision=true")
	quit(0)

func _validate_entry(entry: Dictionary) -> Dictionary:
	var node := Node3D.new()
	node.name = String(entry["asset_id"])
	node.set_script(INSTANCE_SCRIPT)
	node.set("asset_id", String(entry["asset_id"]))
	node.set("display_name", String(entry["display_name"]))
	node.set("category", String(entry["category"]))
	node.set("source_path", String(entry["source_path"]))
	node.set("collision_mode", &"auto")
	root.add_child(node)
	await process_frame
	await process_frame

	var proxy := node.get_node_or_null("CollisionProxy") as StaticBody3D
	var has_proxy := proxy != null
	var expects_collision := bool(entry["expects_collision"])
	var result := {
		"ok": has_proxy == expects_collision,
		"asset_id": entry["asset_id"],
		"expects_collision": expects_collision,
		"has_proxy": has_proxy,
	}
	if proxy != null:
		var shape_node := proxy.get_child(0) as CollisionShape3D if proxy.get_child_count() > 0 else null
		result["proxy_layer"] = proxy.collision_layer
		result["proxy_mask"] = proxy.collision_mask
		result["shape_enabled"] = shape_node != null and not shape_node.disabled
		result["ok"] = bool(result["ok"]) and proxy.collision_layer == 1 and proxy.collision_mask == 1 and bool(result["shape_enabled"])
	node.queue_free()
	return result
