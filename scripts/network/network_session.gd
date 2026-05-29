class_name NetworkSession
extends Node

signal hosting_started(port: int)
signal connected_to_host()
signal connection_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal session_closed()

var is_hosting := false
var is_client := false
var is_connected_to_host := false
var listen_port := NetworkConstants.DEFAULT_PORT

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port := NetworkConstants.DEFAULT_PORT, max_players := NetworkConstants.MAX_PLAYERS) -> Error:
	close()
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
	hosting_started.emit(port)
	return OK

func join(address: String, port := NetworkConstants.DEFAULT_PORT) -> Error:
	close()
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
	is_hosting = false
	is_client = false
	is_connected_to_host = false
	if was_active:
		session_closed.emit()

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
