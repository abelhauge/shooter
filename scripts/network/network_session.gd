class_name NetworkSession
extends Node

const LAN_DISCOVERY_SCRIPT := preload("res://scripts/network/lan_discovery.gd")

signal hosting_started(port: int)
signal connected_to_host()
signal connection_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal session_closed()
signal lan_hosts_changed(hosts: Array)

var is_hosting := false
var is_client := false
var is_connected_to_host := false
var listen_port := NetworkConstants.DEFAULT_PORT
var _lan_discovery: Node

func _ready() -> void:
	_lan_discovery = LAN_DISCOVERY_SCRIPT.new()
	_lan_discovery.name = "LanDiscovery"
	add_child(_lan_discovery)
	_lan_discovery.hosts_changed.connect(_on_lan_hosts_changed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port := NetworkConstants.DEFAULT_PORT, max_players := NetworkConstants.MAX_PLAYERS) -> Error:
	close()
	stop_lan_discovery()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_players - 1)
	if error != OK:
		connection_failed.emit("Could not host ENet server on port %d: %s" % [port, error_string(error)])
		return error
	multiplayer.multiplayer_peer = peer
	is_hosting = true
	is_client = false
	is_connected_to_host = false
	listen_port = port
	start_lan_advertising(port)
	hosting_started.emit(port)
	return OK

func join(address: String, port := NetworkConstants.DEFAULT_PORT) -> Error:
	close()
	stop_lan_discovery()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		connection_failed.emit("Could not connect to %s:%d: %s" % [address, port, error_string(error)])
		return error
	multiplayer.multiplayer_peer = peer
	is_hosting = false
	is_client = true
	is_connected_to_host = false
	listen_port = port
	return OK

func close() -> void:
	var was_active := is_active()
	if multiplayer.multiplayer_peer != null and was_active:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	stop_lan_discovery()
	is_hosting = false
	is_client = false
	is_connected_to_host = false
	if was_active:
		session_closed.emit()

func start_lan_discovery() -> Error:
	if is_active() or _lan_discovery == null:
		return ERR_BUSY
	var error: Error = _lan_discovery.start_listening()
	lan_hosts_changed.emit(_lan_discovery.get_hosts())
	return error

func start_lan_advertising(port := NetworkConstants.DEFAULT_PORT) -> void:
	if _lan_discovery == null:
		return
	_lan_discovery.start_advertising(port, _build_lan_host_name())

func stop_lan_discovery() -> void:
	if _lan_discovery == null:
		return
	_lan_discovery.stop()
	lan_hosts_changed.emit([])

func get_lan_hosts() -> Array[Dictionary]:
	if _lan_discovery == null:
		return []
	return _lan_discovery.get_hosts()

func is_active() -> bool:
	return is_hosting or is_client

func local_peer_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 1

func is_connection_ready() -> bool:
	if is_hosting:
		return true
	if not is_client or multiplayer.multiplayer_peer == null:
		return false
	return is_connected_to_host or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)

func _on_connected_to_server() -> void:
	is_connected_to_host = true
	connected_to_host.emit()

func _on_connection_failed() -> void:
	connection_failed.emit("Connection failed")
	close()

func _on_server_disconnected() -> void:
	connection_failed.emit("Server disconnected")
	close()

func _on_lan_hosts_changed(hosts: Array) -> void:
	lan_hosts_changed.emit(hosts)

func _build_lan_host_name() -> String:
	var user := OS.get_environment("USER")
	if user == "":
		user = OS.get_environment("USERNAME")
	if user == "":
		user = "LAN"
	return "%s's Match" % user
