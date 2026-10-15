extends SceneTree

const TEST_TIMEOUT_SECONDS := 12.0

var _role := ""
var _port := 50416
var _done := false
var _round_requested := false


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	_read_arguments()
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.state_received.connect(_on_state_received)
	NetworkManager.round_started.connect(_on_round_started)
	NetworkManager.private_probe_received.connect(_on_private_probe_received)
	create_timer(TEST_TIMEOUT_SECONDS).timeout.connect(_on_timeout)

	var error: Error
	if _role == "host":
		error = NetworkManager.host_game("TestHost", _port)
	elif _role == "client":
		error = NetworkManager.join_game("127.0.0.1", "TestClient", _port)
	else:
		_fail("Argument --role=host oder --role=client fehlt.")
		return

	if error != OK:
		_fail("Netzwerkstart fehlgeschlagen: %s" % error_string(error))


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			_role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))


func _on_state_received(snapshot: Dictionary) -> void:
	if _done or _role != "host":
		return

	var players: Array = snapshot.get("players", [])
	if snapshot.get("phase") == GameManager.PHASE_LOBBY and players.size() >= 2:
		if not _round_requested:
			_round_requested = true
			NetworkManager.request_start_round()
		return

	if snapshot.get("phase") == GameManager.PHASE_PLAYING:
		for player: Dictionary in players:
			var is_remote_player := int(player.get("id", 0)) != NetworkManager.SERVER_PEER_ID
			var has_measured := int(player.get("measurements", 0)) > 0
			if is_remote_player and has_measured:
				if GameManager.seabed == null:
					_fail("Host besitzt kein autoritatives Terrain.")
				else:
					_succeed("Host empfing Registrierung, Start und Sondenstatus.")
				return


func _on_round_started(_round_number: int) -> void:
	if _done or _role != "client":
		return
	if GameManager.seabed != null:
		_fail("Client besitzt vor Rundenende ein Terrain.")
		return
	NetworkManager.submit_axis(1)
	NetworkManager.request_probe()


func _on_private_probe_received(result: Dictionary) -> void:
	if _done or _role != "client":
		return
	if result.has("terrain") or result.has("treasure_x") or result.has("seed"):
		_fail("Privates Sondenergebnis enthält geheime Rundendaten.")
		return
	if GameManager.seabed != null:
		_fail("Client besitzt nach der Sonde ein autoritatives Terrain.")
		return
	_succeed("Client empfing ausschließlich sein privates Sondenergebnis.")


func _on_connection_failed(message: String) -> void:
	_fail(message)


func _on_server_disconnected() -> void:
	if not _done:
		_fail("Server wurde während des Smoke-Tests getrennt.")


func _on_timeout() -> void:
	if not _done:
		_fail("Netzwerk-Smoke-Test hat das Zeitlimit überschritten.")


func _succeed(message: String) -> void:
	if _done:
		return
	_done = true
	print("Phase 3 OK: " + message)
	create_timer(0.5).timeout.connect(func() -> void:
		NetworkManager.disconnect_network()
		quit(0)
	)


func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	push_error("Phase 3 FEHLER: " + message)
	NetworkManager.disconnect_network()
	quit(1)
