extends Node

## ENet-Transport und einzige RPC-Grenze des Spiels.

signal connection_succeeded(is_host: bool)
signal connection_failed(message: String)
signal server_disconnected
signal state_received(snapshot: Dictionary)
signal private_probe_received(result: Dictionary)
signal round_started(round_number: int)
signal round_finished(winner_id: Variant, terrain: Array, treasure_x: int)
signal notice_received(message: String)

const DEFAULT_PORT := 50415
const SERVER_PEER_ID := 1
const SNAPSHOT_INTERVAL := 0.08
const CHANNEL_COUNT := 3

var peer: ENetMultiplayerPeer = null
var is_host := false
var player_name := "Spieler"
var port := DEFAULT_PORT

var _snapshot_elapsed := 0.0
var _announced_result_round := 0
var _closing_connection := false


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(delta: float) -> void:
	if not is_host or peer == null or GameManager.phase != GameManager.PHASE_PLAYING:
		return

	GameManager.tick(delta)
	_snapshot_elapsed += maxf(delta, 0.0)
	if _snapshot_elapsed >= SNAPSHOT_INTERVAL:
		_snapshot_elapsed = 0.0
		_broadcast_state()


func host_game(requested_name: String, requested_port: int = DEFAULT_PORT) -> Error:
	disconnect_network()
	if requested_port < 1 or requested_port > 65535:
		return ERR_INVALID_PARAMETER

	var new_peer := ENetMultiplayerPeer.new()
	var error := new_peer.create_server(
		requested_port,
		GameConstants.MAX_PLAYERS - 1,
		CHANNEL_COUNT
	)
	if error != OK:
		return error

	GameManager.reset()
	ClientSession.reset_all()
	peer = new_peer
	port = requested_port
	player_name = _clean_player_name(requested_name)
	is_host = true
	_snapshot_elapsed = 0.0
	_announced_result_round = 0
	multiplayer.multiplayer_peer = peer

	GameManager.add_player(SERVER_PEER_ID, player_name)
	ClientSession.local_player_id = SERVER_PEER_ID
	connection_succeeded.emit(true)
	_broadcast_state()
	return OK


func join_game(address: String, requested_name: String, requested_port: int = DEFAULT_PORT) -> Error:
	disconnect_network()
	if requested_port < 1 or requested_port > 65535:
		return ERR_INVALID_PARAMETER

	var clean_address := address.strip_edges()
	if clean_address.is_empty():
		clean_address = "127.0.0.1"

	var new_peer := ENetMultiplayerPeer.new()
	var error := new_peer.create_client(
		clean_address,
		requested_port,
		CHANNEL_COUNT
	)
	if error != OK:
		return error

	GameManager.reset()
	ClientSession.reset_all()
	peer = new_peer
	port = requested_port
	player_name = _clean_player_name(requested_name)
	is_host = false
	_snapshot_elapsed = 0.0
	_announced_result_round = 0
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_network() -> void:
	_closing_connection = true
	var previous_peer := peer
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if previous_peer != null:
		previous_peer.close()

	is_host = false
	port = DEFAULT_PORT
	_snapshot_elapsed = 0.0
	_announced_result_round = 0
	GameManager.reset()
	ClientSession.reset_all()
	_closing_connection = false


func local_ip() -> String:
	for address: String in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address == "0.0.0.0":
			continue
		return address
	return "127.0.0.1"


func submit_axis(axis: int) -> void:
	if peer == null:
		return
	if is_host:
		_server_submit_axis(SERVER_PEER_ID, axis)
	else:
		_rpc_submit_axis.rpc_id(SERVER_PEER_ID, axis)


func request_probe() -> void:
	if peer == null:
		return
	if is_host:
		_server_probe(SERVER_PEER_ID)
	else:
		_rpc_request_probe.rpc_id(SERVER_PEER_ID)


func request_start_round() -> void:
	if peer == null:
		return
	if is_host:
		_server_start_round(SERVER_PEER_ID, false)
	else:
		_rpc_request_start_round.rpc_id(SERVER_PEER_ID)


func request_restart_round() -> void:
	if peer == null:
		return
	if is_host:
		_server_start_round(SERVER_PEER_ID, true)
	else:
		_rpc_request_restart_round.rpc_id(SERVER_PEER_ID)


func _on_connected_to_server() -> void:
	if peer == null or is_host:
		return
	_rpc_register_player.rpc_id(SERVER_PEER_ID, player_name)


func _on_connection_failed() -> void:
	if _closing_connection:
		return
	disconnect_network()
	connection_failed.emit("Verbindung zum Host fehlgeschlagen.")


func _on_server_disconnected() -> void:
	if _closing_connection:
		return
	disconnect_network()
	server_disconnected.emit()


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host or not GameManager.players.has(peer_id):
		return

	GameManager.remove_player(peer_id)
	_broadcast_state()
	_announce_round_result_if_needed()


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_register_player(requested_name: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if GameManager.players.has(sender_id):
		_rpc_registration_accepted.rpc_id(sender_id, sender_id)
		_rpc_receive_state.rpc_id(sender_id, GameManager.snapshot())
		if GameManager.phase == GameManager.PHASE_FINISHED:
			_send_round_result_to_peer(sender_id)
		return

	var player := GameManager.add_player(sender_id, _clean_player_name(requested_name))
	if player == null:
		_rpc_registration_rejected.rpc_id(
			sender_id,
			"Runde läuft oder Lobby ist voll."
		)
		call_deferred("_disconnect_rejected_peer", sender_id)
		return

	_rpc_registration_accepted.rpc_id(sender_id, sender_id)
	_broadcast_state()
	if GameManager.phase == GameManager.PHASE_FINISHED:
		_send_round_result_to_peer(sender_id)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_registration_accepted(player_id: int) -> void:
	if is_host or player_id <= SERVER_PEER_ID:
		return
	ClientSession.local_player_id = player_id
	connection_succeeded.emit(false)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_registration_rejected(message: String) -> void:
	if is_host:
		return
	disconnect_network()
	connection_failed.emit(message.substr(0, 160))


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_submit_axis(axis: int) -> void:
	if multiplayer.is_server():
		_server_submit_axis(multiplayer.get_remote_sender_id(), axis)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_request_probe() -> void:
	if multiplayer.is_server():
		_server_probe(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_request_start_round() -> void:
	if multiplayer.is_server():
		_server_start_round(multiplayer.get_remote_sender_id(), false)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_request_restart_round() -> void:
	if multiplayer.is_server():
		_server_start_round(multiplayer.get_remote_sender_id(), true)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_receive_state(snapshot: Dictionary) -> void:
	_accept_state(snapshot)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_receive_probe_result(result: Dictionary) -> void:
	_accept_private_probe(result)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_round_started(round_number: int, initial_snapshot: Dictionary) -> void:
	_accept_round_started(round_number, initial_snapshot)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_round_finished(
	winner_id: Variant,
	terrain: Array,
	treasure_x: int,
	final_snapshot: Dictionary
) -> void:
	_accept_round_finished(winner_id, terrain, treasure_x, final_snapshot)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_receive_notice(message: String) -> void:
	notice_received.emit(message.substr(0, 160))


func _server_submit_axis(player_id: int, axis: int) -> void:
	GameManager.set_axis(player_id, axis)


func _server_probe(player_id: int) -> void:
	var result := GameManager.probe(player_id)
	if result.is_empty():
		return

	if player_id == SERVER_PEER_ID:
		_accept_private_probe(result)
	else:
		_rpc_receive_probe_result.rpc_id(player_id, result)

	_broadcast_state()
	_announce_round_result_if_needed()


func _server_start_round(requester_id: int, restart: bool) -> void:
	if requester_id != SERVER_PEER_ID:
		_send_notice(requester_id, "Nur der Host darf eine Runde starten.")
		return
	if restart and GameManager.phase != GameManager.PHASE_FINISHED:
		_send_notice(requester_id, "Eine neue Runde ist erst nach Rundenende möglich.")
		return
	if not restart and GameManager.phase != GameManager.PHASE_LOBBY:
		_send_notice(requester_id, "Die Runde kann aus diesem Zustand nicht gestartet werden.")
		return
	if not GameManager.start_round():
		_send_notice(requester_id, "Mindestens zwei Spieler werden benötigt.")
		return

	_announced_result_round = 0
	var initial_snapshot := GameManager.snapshot()
	_rpc_round_started.rpc(GameManager.round_number, initial_snapshot)
	_accept_round_started(GameManager.round_number, initial_snapshot)


func _broadcast_state() -> void:
	if not is_host or peer == null:
		return

	var current_snapshot := GameManager.snapshot()
	_rpc_receive_state.rpc(current_snapshot)
	_accept_state(current_snapshot)


func _announce_round_result_if_needed() -> void:
	if GameManager.phase != GameManager.PHASE_FINISHED:
		return
	if _announced_result_round == GameManager.round_number:
		return

	var result := GameManager.round_result()
	if result.is_empty():
		return

	_announced_result_round = GameManager.round_number
	var final_snapshot := GameManager.snapshot()
	_rpc_round_finished.rpc(
		result["winner"],
		result["terrain"],
		result["treasure_x"],
		final_snapshot
	)
	_accept_round_finished(
		result["winner"],
		result["terrain"],
		result["treasure_x"],
		final_snapshot
	)


func _send_round_result_to_peer(peer_id: int) -> void:
	var result := GameManager.round_result()
	if result.is_empty():
		return
	_rpc_round_finished.rpc_id(
		peer_id,
		result["winner"],
		result["terrain"],
		result["treasure_x"],
		GameManager.snapshot()
	)


func _accept_state(snapshot: Dictionary) -> void:
	if not is_host and not GameManager.apply_public_snapshot(snapshot):
		return
	ClientSession.apply_public_state(snapshot)
	state_received.emit(snapshot)


func _accept_private_probe(result: Dictionary) -> void:
	if result.has("terrain") or result.has("treasure_x") or result.has("seed"):
		return
	ClientSession.store_private_measurement(result)
	private_probe_received.emit(result)


func _accept_round_started(new_round_number: int, initial_snapshot: Dictionary) -> void:
	ClientSession.reset_round()
	_accept_state(initial_snapshot)
	round_started.emit(new_round_number)


func _accept_round_finished(
	winner_id: Variant,
	terrain: Array,
	treasure_x: int,
	final_snapshot: Dictionary
) -> void:
	_accept_state(final_snapshot)
	ClientSession.release_round_result(winner_id, terrain, treasure_x)
	round_finished.emit(winner_id, terrain, treasure_x)


func _send_notice(peer_id: int, message: String) -> void:
	if peer_id == SERVER_PEER_ID:
		notice_received.emit(message)
	else:
		_rpc_receive_notice.rpc_id(peer_id, message)


func _disconnect_rejected_peer(peer_id: int) -> void:
	if is_host and peer != null and peer.get_peer(peer_id) != null:
		peer.disconnect_peer(peer_id, false)


func _clean_player_name(raw_name: String) -> String:
	var filtered := ""
	for index in range(raw_name.length()):
		var codepoint := raw_name.unicode_at(index)
		if codepoint >= 32 and codepoint != 127:
			filtered += raw_name.substr(index, 1)

	filtered = filtered.strip_edges().substr(0, 18)
	return filtered if not filtered.is_empty() else "Spieler"
