extends SceneTree

const ARENA_SCENE := preload("res://scenes/maps/art/arena_downtown_01_art.tscn")
const GENERATED_ATMOSPHERE_NAMES := [
	"WarmContainerYardFill",
	"CoolSkylineRim",
	"BlueSpawnPerimeterFill",
	"OrangeSpawnPerimeterFill",
	"NorthYardEdgeFill",
	"SouthYardEdgeFill",
	"HighRouteFill",
]

func _initialize() -> void:
	_validate.call_deferred()

func _validate() -> void:
	var arena := ARENA_SCENE.instantiate()
	root.add_child(arena)
	await process_frame
	await process_frame

	var blockout := arena.get_node_or_null("GameplayBlockout")
	if blockout == null:
		_fail("missing generated gameplay collision blockout")
		return

	var visible_generated := _collect_visible_visuals(blockout)
	if not visible_generated.is_empty():
		_fail("generated blockout visuals are visible in normal runtime: %s" % str(visible_generated))
		return

	var blocking_generated := _collect_blocking_collision(blockout)
	if not blocking_generated.is_empty():
		_fail("generated blockout collision is active outside ArenaFloor: %s" % str(blocking_generated))
		return

	var dummies := get_nodes_in_group("combat_dummies")
	if not dummies.is_empty():
		_fail("normal runtime should not spawn dev combat dummies: %d" % dummies.size())
		return

	var disabled_art_proxies := _collect_disabled_collision_proxies(arena.get_node_or_null("DowntownCityMegaKitDressing"))
	if not disabled_art_proxies.is_empty():
		_fail("city asset collision proxies should stay active: %s" % str(disabled_art_proxies))
		return

	for node_name in GENERATED_ATMOSPHERE_NAMES:
		if arena.has_node(node_name):
			_fail("normal runtime should not create generated atmosphere node %s" % node_name)
			return

	print("RUNTIME_SCENE_CONTRACT_PASS no_generated_visual_artifacts=true")
	quit(0)

func _collect_visible_visuals(root_node: Node) -> Array[String]:
	var visible_nodes: Array[String] = []
	if root_node is VisualInstance3D and (root_node as VisualInstance3D).visible:
		visible_nodes.append(str(root_node.get_path()))
	for child in root_node.get_children():
		visible_nodes.append_array(_collect_visible_visuals(child))
	return visible_nodes

func _collect_blocking_collision(root_node: Node) -> Array[String]:
	var blocking_nodes: Array[String] = []
	if _is_arena_floor_branch(root_node):
		return blocking_nodes
	if root_node is CollisionObject3D:
		var collision_object := root_node as CollisionObject3D
		if collision_object.collision_layer != 0 or collision_object.collision_mask != 0:
			blocking_nodes.append(str(root_node.get_path()))
	if root_node is CollisionShape3D and not (root_node as CollisionShape3D).disabled:
		blocking_nodes.append(str(root_node.get_path()))
	for child in root_node.get_children():
		blocking_nodes.append_array(_collect_blocking_collision(child))
	return blocking_nodes

func _is_arena_floor_branch(node: Node) -> bool:
	var current := node
	while current != null:
		if current.name == "ArenaFloor":
			return true
		current = current.get_parent()
	return false

func _collect_disabled_collision_proxies(root_node: Node) -> Array[String]:
	var disabled_nodes: Array[String] = []
	if root_node == null:
		return disabled_nodes
	if root_node.name == "CollisionProxy":
		if root_node is CollisionObject3D:
			var collision_object := root_node as CollisionObject3D
			if collision_object.collision_layer == 0 or collision_object.collision_mask == 0:
				disabled_nodes.append(str(root_node.get_path()))
		var has_enabled_shape := false
		for child in root_node.get_children():
			if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
				has_enabled_shape = true
		if not has_enabled_shape:
			disabled_nodes.append("%s/no_enabled_shape" % str(root_node.get_path()))
	for child in root_node.get_children():
		disabled_nodes.append_array(_collect_disabled_collision_proxies(child))
	return disabled_nodes

func _fail(message: String) -> void:
	push_error("Runtime scene contract failed: %s" % message)
	quit(1)
