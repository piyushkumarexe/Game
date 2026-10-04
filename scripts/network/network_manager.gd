extends Node
## ENet co-op session layer. Host authoritative for mission and RV state.

signal host_ready(address: String, port: int)
signal joined_server
signal connection_failed(reason: String)
signal peer_roster_changed(roster: Dictionary)
signal disconnected

const PORT := 24817
const MAX_PLAYERS := 4

var peer: ENetMultiplayerPeer
var world: Node
var roster: Dictionary = {}
var is_online := false
var pending_name := "Rover"
var pending_role := 0

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func start_solo() -> void:
	shutdown()
	is_online = false
	roster = {1: {"name": GameSession.player_name, "role": GameSession.selected_role}}

func host_game(player_name: String, role: int) -> Error:
	shutdown()
	pending_name = player_name.strip_edges().left(18) if not player_name.strip_edges().is_empty() else "Trail Boss"
	pending_role = role
	peer = ENetMultiplayerPeer.new()
	var result := peer.create_server(PORT, MAX_PLAYERS)
	if result != OK:
		connection_failed.emit("Could not open UDP port %d." % PORT)
		return result
	multiplayer.multiplayer_peer = peer
	is_online = true
	roster = {1: {"name": pending_name, "role": pending_role}}
	host_ready.emit(_best_local_address(), PORT)
	return OK

func join_game(address: String, player_name: String, role: int) -> Error:
	shutdown()
	pending_name = player_name.strip_edges().left(18) if not player_name.strip_edges().is_empty() else "Passenger"
	pending_role = role
	peer = ENetMultiplayerPeer.new()
	var clean_address := address.strip_edges()
	if clean_address.is_empty():
		clean_address = "127.0.0.1"
	var result := peer.create_client(clean_address, PORT)
	if result != OK:
		connection_failed.emit("Could not connect to %s:%d." % [clean_address, PORT])
		return result
	multiplayer.multiplayer_peer = peer
	is_online = true
	return OK

func register_world(node: Node) -> void:
	world = node
	if not is_online:
		world.spawn_network_player(1, GameSession.player_name, GameSession.selected_role)
		return
	if multiplayer.is_server():
		world.spawn_network_player(1, pending_name, pending_role)
		_broadcast_roster()
	else:
		_request_join.rpc_id(1, pending_name, pending_role)

func shutdown() -> void:
	world = null
	roster.clear()
	is_online = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null

@rpc("any_peer", "call_remote", "reliable")
func _request_join(player_name: String, role: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if roster.size() >= MAX_PLAYERS or roster.has(sender):
		return
	roster[sender] = {"name": player_name.left(18), "role": clampi(role, 0, 3)}
	for id: int in roster:
		var info: Dictionary = roster[id]
		_spawn_player.rpc_id(sender, id, str(info["name"]), int(info["role"]))
	_spawn_player.rpc(sender, player_name.left(18), clampi(role, 0, 3))
	_sync_progress.rpc_id(sender, GameSession.mission_index, GameSession.checkpoint_index,
		GameSession.supplies_loaded, GameSession.planks_placed)
	_broadcast_roster()

@rpc("authority", "call_local", "reliable")
func _spawn_player(peer_id: int, player_name: String, role: int) -> void:
	if world and is_instance_valid(world):
		world.spawn_network_player(peer_id, player_name, role)

@rpc("authority", "call_remote", "reliable")
func _sync_roster(data: Dictionary) -> void:
	roster = data.duplicate(true)
	peer_roster_changed.emit(roster)

func _broadcast_roster() -> void:
	_sync_roster.rpc(roster)
	peer_roster_changed.emit(roster)

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

func _on_connected() -> void:
	joined_server.emit()

func _on_connection_failed() -> void:
	connection_failed.emit("Connection failed. Check the host address and network.")
	shutdown()

func _on_server_disconnected() -> void:
	disconnected.emit()
	shutdown()

func _on_peer_disconnected(id: int) -> void:
	roster.erase(id)
	if world and is_instance_valid(world):
		world.remove_network_player(id)
	if multiplayer.is_server():
		_remove_player.rpc(id)
		_broadcast_roster()

@rpc("authority", "call_local", "reliable")
func _remove_player(id: int) -> void:
	if world and is_instance_valid(world):
		world.remove_network_player(id)

func _best_local_address() -> String:
	for address: String in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254"):
			continue
		return address
	return "127.0.0.1"
