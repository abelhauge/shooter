class_name LanDiscovery
extends Node

signal hosts_changed(hosts: Array)

const MESSAGE_TYPE := "shooter_lan_host"

var _advertiser := PacketPeerUDP.new()
var _listener := PacketPeerUDP.new()
var _is_advertising := false
var _is_listening := false
var _advertise_elapsed := 0.0
var _host_id := ""
var _host_name := ""
var _host_port := 0
var _joined_interfaces: Array[String] = []
var _hosts_by_id: Dictionary = {}

func _process(delta: float) -> void:
	if _is_advertising:
		_advertise_elapsed += delta
		if _advertise_elapsed >= NetworkConstants.LAN_DISCOVERY_ADVERTISE_INTERVAL_SEC:
			_advertise_elapsed = 0.0
			_send_advertisement()
	if _is_listening:
		_poll_listener()
		_expire_hosts()

func start_advertising(port: int, host_name: String) -> void:
	stop()
	_host_port = port
	_host_name = host_name
	_host_id = "%s-%d-%d" % [OS.get_unique_id(), Time.get_ticks_usec(), randi()]
	_advertiser = PacketPeerUDP.new()
	_advertiser.set_broadcast_enabled(true)
	_is_advertising = true
	_advertise_elapsed = NetworkConstants.LAN_DISCOVERY_ADVERTISE_INTERVAL_SEC

func start_listening() -> Error:
	stop()
	_listener = PacketPeerUDP.new()
	var error := _listener.bind(NetworkConstants.LAN_DISCOVERY_PORT, "0.0.0.0")
	if error != OK:
		_is_listening = false
		_emit_hosts_if_changed({})
		return error
	_join_multicast_groups()
	_is_listening = true
	_emit_hosts_if_changed({})
	return OK

func stop() -> void:
	if _is_listening:
		_leave_multicast_groups()
		_listener.close()
	if _is_advertising:
		_advertiser.close()
	_is_advertising = false
	_is_listening = false
	_advertise_elapsed = 0.0
	_joined_interfaces.clear()
	_emit_hosts_if_changed({})

func is_advertising() -> bool:
	return _is_advertising

func is_listening() -> bool:
	return _is_listening

func get_hosts() -> Array[Dictionary]:
	var hosts: Array[Dictionary] = []
	for host in _hosts_by_id.values():
		hosts.append((host as Dictionary).duplicate(true))
	hosts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	return hosts

func _send_advertisement() -> void:
	var payload := {
		"type": MESSAGE_TYPE,
		"protocol": NetworkConstants.LAN_DISCOVERY_PROTOCOL_VERSION,
		"game": NetworkConstants.LAN_DISCOVERY_GAME_ID,
		"host_id": _host_id,
		"name": _host_name,
		"port": _host_port,
		"max_players": NetworkConstants.MAX_PLAYERS,
		"state": "lobby",
	}
	var bytes := JSON.stringify(payload).to_utf8_buffer()
	_send_packet(bytes, NetworkConstants.LAN_DISCOVERY_MULTICAST_GROUP)
	_send_packet(bytes, NetworkConstants.LAN_DISCOVERY_BROADCAST_ADDRESS)

func _send_packet(bytes: PackedByteArray, address: String) -> void:
	var error := _advertiser.set_dest_address(address, NetworkConstants.LAN_DISCOVERY_PORT)
	if error == OK:
		_advertiser.put_packet(bytes)

func _poll_listener() -> void:
	while _listener.get_available_packet_count() > 0:
		var packet := _listener.get_packet()
		var source_ip := _listener.get_packet_ip()
		_apply_packet(packet, source_ip)

func _apply_packet(packet: PackedByteArray, source_ip: String) -> void:
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	if String(data.get("type", "")) != MESSAGE_TYPE:
		return
	if String(data.get("game", "")) != NetworkConstants.LAN_DISCOVERY_GAME_ID:
		return
	if int(data.get("protocol", -1)) != NetworkConstants.LAN_DISCOVERY_PROTOCOL_VERSION:
		return
	var host_id := String(data.get("host_id", ""))
	var port := int(data.get("port", 0))
	if host_id == "" or port <= 0:
		return
	var host := {
		"id": host_id,
		"name": String(data.get("name", "LAN Host")),
		"address": source_ip,
		"port": port,
		"max_players": int(data.get("max_players", NetworkConstants.MAX_PLAYERS)),
		"state": String(data.get("state", "lobby")),
		"last_seen_msec": Time.get_ticks_msec(),
	}
	_hosts_by_id[host_id] = host
	hosts_changed.emit(get_hosts())

func _expire_hosts() -> void:
	if _hosts_by_id.is_empty():
		return
	var now := Time.get_ticks_msec()
	var timeout_msec := int(NetworkConstants.LAN_DISCOVERY_HOST_TIMEOUT_SEC * 1000.0)
	var changed := false
	for host_id in _hosts_by_id.keys():
		var host: Dictionary = _hosts_by_id[host_id]
		if now - int(host.get("last_seen_msec", 0)) > timeout_msec:
			_hosts_by_id.erase(host_id)
			changed = true
	if changed:
		hosts_changed.emit(get_hosts())

func _emit_hosts_if_changed(hosts: Dictionary) -> void:
	var had_hosts := not _hosts_by_id.is_empty()
	_hosts_by_id = hosts
	if had_hosts or not hosts.is_empty():
		hosts_changed.emit(get_hosts())

func _join_multicast_groups() -> void:
	_joined_interfaces.clear()
	for interface_info in IP.get_local_interfaces():
		if not (interface_info is Dictionary):
			continue
		var info: Dictionary = interface_info
		if not _interface_has_ipv4(info):
			continue
		var interface_name := String(info.get("name", ""))
		if interface_name == "":
			continue
		var error := _listener.join_multicast_group(NetworkConstants.LAN_DISCOVERY_MULTICAST_GROUP, interface_name)
		if error == OK:
			_joined_interfaces.append(interface_name)

func _leave_multicast_groups() -> void:
	for interface_name in _joined_interfaces:
		_listener.leave_multicast_group(NetworkConstants.LAN_DISCOVERY_MULTICAST_GROUP, interface_name)
	_joined_interfaces.clear()

func _interface_has_ipv4(info: Dictionary) -> bool:
	for address in info.get("addresses", []):
		if String(address).contains("."):
			return true
	return false
