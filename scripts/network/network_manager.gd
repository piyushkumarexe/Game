extends Node
## Expedition crew networking. One transport abstraction, two interchangeable
## SceneMultiplayer backends, host-authoritative world state.
##
##  • Transport.WEBSOCKET — TCP. Internet-friendly: one port, works behind a
##    reverse proxy (nginx/caddy `wss://`), survives networks that drop UDP.
##    Godot's WebSocket peer has no unreliable mode, so voice and RV state are
##    reliable; the payload is tiny (~8 KB/s per talker, ~7 KB/s of RV state).
##  • Transport.ENET      — UDP. Lower latency and real unreliable channels, so
##    it is the better choice for four phones on the same Wi-Fi.
##
## The host (or a headless dedicated server) owns the RV physics, the mission
## chain and the crew roster. Clients send input; they never mutate authority
## state directly. Voice is relayed by the host and only to nearby crew.

signal host_ready(address: String, port: int)
signal joined_server
signal connection_failed(reason: String)
signal peer_roster_changed(roster: Dictionary)
signal disconnected
signal crew_spoken(from_peer: int)

enum Transport { WEBSOCKET, ENET }

const DEFAULT_PORT := 24817
const MAX_PLAYERS := 4
const ROLES: Array[String] = ["DRIVER", "MECHANIC", "SCOUT", "NAVIGATOR"]
## How close two crew members must be before their voice reaches each other.
const VOICE_RANGE_M := 26.0
## Per-talker relay budget, so a buggy or hostile client cannot flood a session.
const VOICE_CREDIT_MAX := 24.0
## Packets are coalesced while this timer is still running.
const VOICE_MIN_SEND_INTERVAL := 0.045
const JOIN_ANSWER_SECONDS := 8.0
## Highest rpc channel this session uses (see `_make_peer`); ENet needs a count.
const VOICE_CHANNEL := 2

var transport: Transport = Transport.WEBSOCKET
var peer: MultiplayerPeer
var world: Node
var roster: Dictionary = {}
var is_online := false
var is_dedicated := false
var port := DEFAULT_PORT
var pending_name := "Rover"
var pending_role := 0

## Crew that asked to join while the host was still building the valley. The
## world spawns them once its collision surface exists, so nobody can land on
## an unfinished terrain chunk.
var _queued_crew: Array[Dictionary] = []
var _voice_send_left := 0.0
var _voice_credit: Dictionary = {}
var _join_timeout_left := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	_voice_send_left = maxf(0.0, _voice_send_left - delta)
	if is_online and multiplayer.is_server():
		# Refill the per-peer voice budget instead of counting wall-clock windows.
		for peer_id: int in _voice_credit.keys():
			_voice_credit[peer_id] = minf(VOICE_CREDIT_MAX, float(_voice_credit[peer_id]) + delta * 18.0)
	if _join_timeout_left > 0.0:
		_join_timeout_left -= delta
		if _join_timeout_left <= 0.0 and is_online and not multiplayer.is_server() and roster.size() <= 1:
			connection_failed.emit("HOST DID NOT ANSWER — CHECK ADDRESS, PORT AND FIREWALL.")
			shutdown()


# --- session lifecycle ----------------------------------------------------

func start_solo() -> void:
	shutdown()
	transport = Transport.WEBSOCKET
	roster = {1: _crew_entry(GameSession.player_name, GameSession.selected_role)}


func host_game(player_name: String, role: int, use_websocket := true, requested_port := DEFAULT_PORT) -> Error:
	return _open_session(player_name, role, Transport.WEBSOCKET if use_websocket else Transport.ENET, requested_port, false)


func start_dedicated_server(requested_port := DEFAULT_PORT, use_websocket := true) -> Error:
	## A rendering-free host that runs only physics, mission state and the roster.
	## Launched with `godot --headless -- --server [--port 24817] [--enet]`.
	var error := _open_session("Expedition Server", 0, Transport.WEBSOCKET if use_websocket else Transport.ENET,
		requested_port, true)
	if error == OK:
		print("SERVER_READY transport=%s port=%d max_players=%d" % [transport_name(), port, MAX_PLAYERS])
	return error


func _open_session(player_name: String, role: int, chosen: Transport, requested_port: int, dedicated: bool) -> Error:
	shutdown()
	transport = chosen
	port = maxi(1024, requested_port)
	is_dedicated = dedicated
	pending_name = _clean_name(player_name, "Expedition Server" if dedicated else "Trail Boss")
	pending_role = clampi(role, 0, ROLES.size() - 1)
	var error := _make_peer(true)
	if error != OK:
		connection_failed.emit("COULD NOT OPEN %s PORT %d." % [transport_name().to_upper(), port])
		return error
	multiplayer.multiplayer_peer = peer
	is_online = true
	roster = {}
	if not dedicated:
		roster[1] = _crew_entry(pending_name, pending_role)
	host_ready.emit(join_address_for_display(), port)
	return OK


func join_game(address: String, player_name: String, role: int, requested_port := DEFAULT_PORT) -> Error:
	shutdown()
	pending_name = _clean_name(player_name, "Passenger")
	pending_role = clampi(role, 0, ROLES.size() - 1)
	var target := parse_join_target(address, requested_port)
	transport = Transport.WEBSOCKET if bool(target["websocket"]) else Transport.ENET
	port = int(target["port"])
	var error := _make_peer(false, str(target["host"]))
	if error != OK:
		connection_failed.emit("COULD NOT OPEN A SOCKET TO %s." % str(target["host"]))
		return error
	multiplayer.multiplayer_peer = peer
	is_online = true
	roster = {1: _crew_entry(pending_name, pending_role)}
	_join_timeout_left = JOIN_ANSWER_SECONDS
	return OK


func _make_peer(as_host: bool, target := "") -> Error:
	if transport == Transport.ENET:
		var enet := ENetMultiplayerPeer.new()
		# Three channels: 0 for driver input, 1 for RV and crew transforms, 2 for
		# voice. ENet's default channel count is 0, which silently drops every
		# rpc sent on a numbered channel, so it must be raised explicitly.
		if as_host:
			var bind_error := enet.create_server(port, MAX_PLAYERS, VOICE_CHANNEL + 1)
			if bind_error != OK:
				return bind_error
		else:
			var connect_error := enet.create_client(target, port, VOICE_CHANNEL + 1)
			if connect_error != OK:
				return connect_error
		peer = enet
		return OK
	var websocket := WebSocketMultiplayerPeer.new()
	# A little more headroom than the defaults: voice, RV state and player
	# transforms share one TCP connection, so a stalled buffer is audible.
	websocket.inbound_buffer_size = 131072
	websocket.outbound_buffer_size = 131072
	if as_host:
		# "*" so a phone on the same network can reach the host, and a fronting
		# reverse proxy can terminate wss:// in front of this port.
		var listen_error := websocket.create_server(port, "*")
		if listen_error != OK:
			return listen_error
	else:
		var connect_error := websocket.create_client(target)
		if connect_error != OK:
			return connect_error
	peer = websocket
	return OK


func shutdown() -> void:
	world = null
	roster.clear()
	_queued_crew.clear()
	_voice_credit.clear()
	_voice_send_left = 0.0
	is_online = false
	is_dedicated = false
	_join_timeout_left = 0.0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null


func transport_name() -> String:
	return "websocket" if transport == Transport.WEBSOCKET else "enet"


func is_host() -> bool:
	return not is_online or multiplayer.is_server()


func crew_count() -> int:
	return roster.size()


func local_peer_id() -> int:
	return multiplayer.get_unique_id()


# --- world registration ---------------------------------------------------

func register_world(node: Node) -> void:
	world = node
	if not is_online:
		node.spawn_network_player(1, GameSession.player_name, GameSession.selected_role)
		return
	if multiplayer.is_server():
		if not is_dedicated:
			node.spawn_network_player(1, pending_name, pending_role)
		# Anyone who asked to join during world construction lands now, once the
		# terrain and the RV collider exist.
		for entry: Dictionary in _queued_crew:
			_spawn_and_announce(int(entry["peer_id"]), str(entry["name"]), int(entry["role"]))
		_queued_crew.clear()
		_broadcast_roster()
	else:
		_request_join.rpc_id(1, pending_name, pending_role)


func set_role(role: int) -> void:
	pending_role = clampi(role, 0, ROLES.size() - 1)
	GameSession.selected_role = pending_role
	if not is_online or roster.is_empty():
		roster = {1: _crew_entry(GameSession.player_name, pending_role)}
		peer_roster_changed.emit(roster)
		return
	if multiplayer.is_server():
		roster[1] = _crew_entry(str(roster.get(1, {}).get("name", pending_name)), pending_role)
		_broadcast_roster()
	else:
		_request_role.rpc_id(1, pending_role)


@rpc("any_peer", "call_remote", "reliable")
func _request_role(role: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not roster.has(sender):
		return
	var entry: Dictionary = roster[sender]
	entry["role"] = clampi(role, 0, ROLES.size() - 1)
	roster[sender] = entry
	_broadcast_roster()


# --- roster ---------------------------------------------------------------

func _crew_entry(display_name: String, role: int) -> Dictionary:
	return {
		"name": display_name,
		"role": clampi(role, 0, ROLES.size() - 1),
		"local": false,
	}


func _clean_name(raw_name: String, fallback: String) -> String:
	var cleaned := raw_name.strip_edges().left(18)
	return cleaned if not cleaned.is_empty() else fallback


@rpc("any_peer", "call_remote", "reliable")
func _request_join(player_name: String, role: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if roster.has(sender):
		return
	if roster.size() >= MAX_PLAYERS:
		_reject_full.rpc_id(sender)
		return
	var entry := _crew_entry(_clean_name(player_name, "Passenger"), role)
	roster[sender] = entry
	_voice_credit[sender] = VOICE_CREDIT_MAX
	if world == null or not is_instance_valid(world):
		# The host is still building Redmesa Valley. Queue, then spawn on ready.
		_queued_crew.append({"peer_id": sender, "name": entry["name"], "role": entry["role"]})
		_sync_roster.rpc_id(sender, roster)
		return
	_spawn_and_announce(sender, str(entry["name"]), int(entry["role"]))
	# Late crew need the mission board too, not just a body in the world.
	_sync_progress.rpc_id(sender, GameSession.mission_index, GameSession.checkpoint_index,
		GameSession.supplies_loaded, GameSession.planks_placed)
	_broadcast_roster()


@rpc("authority", "call_remote", "reliable")
func _reject_full() -> void:
	connection_failed.emit("CREW IS FULL — %d OF %d SEATS TAKEN" % [roster.size(), MAX_PLAYERS])
	shutdown()


func _spawn_and_announce(peer_id: int, player_name: String, role: int) -> void:
	if world and is_instance_valid(world):
		world.spawn_network_player(peer_id, player_name, role)
		if peer_id != 1:
			GameSession.toast_requested.emit("CREW IN RANGE",
				"%s joined as %s at the campfire." % [player_name, role_name(role)])
	# Every other peer needs the new body as well; the newcomer needs the rest
	# of the crew, which is why the loop excludes them and the last rpc does not.
	for listener: int in roster:
		if listener != peer_id:
			_spawn_player.rpc_id(listener, peer_id, player_name, role)
	_spawn_player.rpc_id(peer_id, peer_id, player_name, role)


@rpc("authority", "call_local", "reliable")
func _spawn_player(peer_id: int, player_name: String, role: int) -> void:
	if world and is_instance_valid(world):
		world.spawn_network_player(peer_id, player_name, role)


@rpc("authority", "call_remote", "reliable")
func _sync_roster(data: Dictionary) -> void:
	roster = data.duplicate(true)
	_mark_local()
	peer_roster_changed.emit(roster)


func _broadcast_roster() -> void:
	_mark_local()
	for listener: int in roster:
		if listener != 1:
			_sync_roster.rpc_id(listener, roster)
	peer_roster_changed.emit(roster)


func _mark_local() -> void:
	var local_id := multiplayer.get_unique_id()
	for peer_id: int in roster.keys():
		var entry: Dictionary = roster[peer_id]
		entry["local"] = peer_id == local_id
		roster[peer_id] = entry


func role_name(role: int) -> String:
	return ROLES[clampi(role, 0, ROLES.size() - 1)]


func roster_lines(driving_peer: int) -> Array[String]:
	var lines: Array[String] = []
	for peer_id: int in roster.keys():
		var entry: Dictionary = roster[peer_id]
		var tags: Array[String] = []
		if peer_id == 1:
			tags.append("HOST")
		if peer_id == driving_peer:
			tags.append("DRIVING")
		if bool(entry.get("local", false)):
			tags.append("YOU")
		lines.append("%d  %s · %s%s" % [peer_id, str(entry.get("name", "?")),
			role_name(int(entry.get("role", 0))),
			("  ·  " + " ".join(tags)) if not tags.is_empty() else ""])
	return lines


# --- mission progress -----------------------------------------------------

func broadcast_progress() -> void:
	if is_online and multiplayer.is_server():
		_sync_progress.rpc(GameSession.mission_index, GameSession.checkpoint_index,
			GameSession.supplies_loaded, GameSession.planks_placed)


@rpc("authority", "call_remote", "reliable")
func _sync_progress(mission: int, checkpoint: int, supplies: int, planks: int) -> void:
	GameSession.mission_index = mission
	GameSession.checkpoint_index = checkpoint
	GameSession.supplies_loaded = supplies
	GameSession.planks_placed = planks
	if mission < GameSession.MISSIONS.size():
		var info: Dictionary = GameSession.MISSIONS[mission]
		GameSession.mission_changed.emit(str(info["title"]), str(info["detail"]), mission + 1, GameSession.MISSIONS.size())


# --- crew chatter ---------------------------------------------------------

## Toasts raised by host-side logic (an interactable applied on the authority,
## a winch that found no anchor, a crew member joining) would otherwise only be
## visible on the host's screen. Sharing them is what makes a four-person run
## feel like one trip instead of four separate games.
func broadcast_toast(title: String, detail: String) -> void:
	if is_online and multiplayer.is_server():
		_show_toast.rpc(title, detail)


@rpc("authority", "call_remote", "reliable")
func _show_toast(title: String, detail: String) -> void:
	GameSession.toast_requested.emit(title, detail)


# --- proximity voice ------------------------------------------------------

func voice_out(packet: PackedByteArray) -> void:
	## Called by the local mic capture. The host decides who hears it, so no
	## client can spoof another peer's voice.
	if not is_online or packet.size() < 2:
		return
	if _voice_send_left > 0.0:
		return
	_voice_send_left = VOICE_MIN_SEND_INTERVAL
	if is_host():
		_relay_to_nearby(multiplayer.get_unique_id(), packet)
	else:
		_relay_voice.rpc_id(1, packet)


@rpc("any_peer", "call_remote", "reliable")
func _relay_voice(packet: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not roster.has(sender) or packet.size() < 2:
		return
	var credit := float(_voice_credit.get(sender, 0.0))
	if credit < 1.0:
		return
	_voice_credit[sender] = credit - 1.0
	_relay_to_nearby(sender, packet)


func _relay_to_nearby(sender: int, packet: PackedByteArray) -> void:
	if world == null or not is_instance_valid(world):
		return
	var source: Node = world.get_player(sender)
	if source == null:
		return
	for listener: int in roster:
		if listener == sender:
			continue
		var target: Node = world.get_player(listener)
		if target == null:
			continue
		if source.global_position.distance_to(target.global_position) > VOICE_RANGE_M:
			continue
		if listener == 1:
			_hear_locally(sender, packet)
		else:
			_hear_voice.rpc_id(listener, sender, packet)


func _hear_locally(from_peer: int, packet: PackedByteArray) -> void:
	if world == null or not is_instance_valid(world):
		return
	var listener: Node = world.get_player(1)
	if listener:
		deliver_voice_to(listener, from_peer, packet)


@rpc("authority", "call_remote", "reliable")
func _hear_voice(from_peer: int, packet: PackedByteArray) -> void:
	if world == null or not is_instance_valid(world):
		return
	var listener: Node = world.get_player(multiplayer.get_unique_id())
	if listener:
		deliver_voice_to(listener, from_peer, packet)


func deliver_voice_to(listener: Node, from_peer: int, packet: PackedByteArray) -> void:
	var voice: Node = listener.get("voice")
	if voice and voice.has_method("push_samples"):
		voice.call("push_samples", from_peer, packet)
		crew_spoken.emit(from_peer)


# --- connection callbacks -------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		# Grant the newcomer a full voice budget up front; the join handshake
		# arrives on a later frame.
		_voice_credit[id] = VOICE_CREDIT_MAX


func _on_connected() -> void:
	_join_timeout_left = 0.0
	joined_server.emit()


func _on_connection_failed() -> void:
	connection_failed.emit("CONNECTION FAILED — THE HOST CLOSED THE SESSION OR IS UNREACHABLE.")
	shutdown()


func _on_server_disconnected() -> void:
	disconnected.emit()
	shutdown()


func _on_peer_disconnected(id: int) -> void:
	_voice_credit.erase(id)
	if not is_online:
		return
	var was_driver := false
	if world and is_instance_valid(world) and world.rv:
		was_driver = int(world.rv.driver_peer_id) == id
	roster.erase(id)
	if world and is_instance_valid(world):
		world.remove_network_player(id)
	if multiplayer.is_server():
		# An abandoned driver seat would freeze the rig forever, so the seat and
		# any ride slot are released before the roster is rebroadcast.
		if was_driver and world.rv.has_method("force_release_driver"):
			world.rv.call("force_release_driver", id)
		if world.has_method("release_riders_for"):
			world.call("release_riders_for", id)
		_remove_player.rpc(id)
		_broadcast_roster()
		GameSession.toast_requested.emit("CREW OFFLINE", "A crew member dropped from the session.")


@rpc("authority", "call_local", "reliable")
func _remove_player(id: int) -> void:
	if world and is_instance_valid(world):
		world.remove_network_player(id)


# --- addresses ------------------------------------------------------------

func parse_join_target(raw_address: String, fallback_port: int) -> Dictionary:
	## Accepts everything a player is likely to paste into the join field:
	##   192.168.1.24   192.168.1.24:24817   ws://host:24817/
	##   wss://trip.example.com   enet:203.0.113.9:24817
	var text := raw_address.strip_edges().to_lower()
	var use_websocket := true
	if text.begins_with("enet:") or text.begins_with("udp:"):
		use_websocket = false
		text = text.substr(text.find(":") + 1)
	var scheme := ""
	if text.begins_with("wss://") or text.begins_with("ws://"):
		scheme = text.substr(0, text.find("://"))
		text = text.substr(text.find("://") + 3)
	while text.ends_with("/"):
		text = text.substr(0, text.length() - 1)
	text = text.get_slice("@", 1) if text.contains("@") else text
	var host := text
	var resolved_port := fallback_port
	if text.contains(":"):
		host = text.get_slice(":", 0)
		resolved_port = int(text.get_slice(":", 1))
	if host.is_empty():
		host = "127.0.0.1"
	if use_websocket:
		var prefix := scheme if not scheme.is_empty() else "ws"
		return {"websocket": true, "host": "%s://%s:%d/" % [prefix, host, resolved_port], "port": resolved_port}
	return {"websocket": false, "host": host, "port": resolved_port}


func join_address_for_display() -> String:
	var local := best_local_address()
	if transport == Transport.ENET:
		return "enet:%s:%d" % [local, port]
	return "ws://%s:%d/" % [local, port]


func best_local_address() -> String:
	for address: String in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254"):
			continue
		return address
	return "127.0.0.1"
