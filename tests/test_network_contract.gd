extends RefCounted

const GameManagerModel = preload("res://scripts/autoload/GameManager.gd")
const ClientSessionModel = preload("res://scripts/autoload/ClientSession.gd")
const NetworkManagerModel = preload("res://scripts/autoload/NetworkManager.gd")


static func run() -> Array[String]:
	var failures: Array[String] = []
	var authority = GameManagerModel.new()
	var replica = GameManagerModel.new()
	var session = ClientSessionModel.new()

	authority.add_player(1, "Ada")
	authority.add_player(27, "Ben")
	authority.set_show_all_measurements(true)
	authority.set_team_mode(true)
	authority.set_player_team(1, 1)
	authority.set_player_team(27, 2)
	authority.start_round(123456)
	authority.set_axis(27, 1)
	authority.tick(0.05)

	var public_snapshot := authority.snapshot()
	_expect(replica.apply_public_snapshot(public_snapshot), "Öffentlicher Snapshot wurde abgewiesen", failures)
	_expect(replica.phase == authority.phase, "Client-Phase stimmt nicht mit Host überein", failures)
	_expect(replica.round_number == authority.round_number, "Client-Rundennummer ist falsch", failures)
	_expect(replica.players.size() == authority.players.size(), "Client-Spielerliste ist unvollständig", failures)
	_expect(replica.seabed == null, "Client erhielt ein autoritatives Seabed", failures)
	_expect(replica.players[27].axis == 0, "Private Eingabeachse wurde repliziert", failures)
	_expect(replica.players[27].last_probe_time == -10.0, "Privater Cooldown wurde repliziert", failures)
	_expect(replica.show_all_measurements, "Messfreigabe wurde nicht repliziert", failures)
	_expect(replica.team_mode, "Teammodus wurde nicht repliziert", failures)
	_expect(replica.players[27].team_id == 2, "Teamzuweisung wurde nicht repliziert", failures)

	var malformed := public_snapshot.duplicate(true)
	malformed["phase"] = "cheating"
	_expect(not replica.apply_public_snapshot(malformed), "Ungültige Netzwerkphase wurde akzeptiert", failures)

	session.local_player_id = 27
	var remote_probe := {
		"type": "probe_result",
		"player_id": 1,
		"team_id": 1,
		"x": 500.0,
		"y": 450.0,
		"slope": 0.2,
		"patch": [Vector2(495, 449), Vector2(500, 450)],
		"probes_left": 39,
		"found": false,
	}
	session.store_measurement(remote_probe)
	_expect(session.last_measurement.is_empty(), "Fremde Messung ersetzte die eigene letzte Messung", failures)
	var local_probe := remote_probe.duplicate(true)
	local_probe["player_id"] = 27
	local_probe["team_id"] = 2
	session.store_measurement(local_probe)
	_expect(session.measurements.size() == 2, "Sichtbare Messungen wurden nicht gespeichert", failures)
	_expect(session.last_measurement.get("x") == 500.0, "Letzte Messung ist falsch", failures)

	var terrain := [Vector2(72, 420), Vector2(76, 421)]
	session.release_round_result(27, terrain, 76)
	_expect(session.released_winner_id == 27, "Freigegebener Gewinner ist falsch", failures)
	_expect(session.released_terrain.size() == 2, "Freigegebenes Terrain ist unvollständig", failures)
	_expect(session.released_treasure_x == 76, "Freigegebene Schatzposition ist falsch", failures)

	session.reset_round()
	_expect(session.measurements.is_empty(), "Rundenreset behält Messungen", failures)
	_expect(session.released_terrain.is_empty(), "Rundenreset behält Terrain", failures)

	var transport = NetworkManagerModel.new()
	_expect(transport.DEFAULT_PORT == 3131, "Godot-Standardport ist nicht 3131", failures)
	_expect(transport.has_method("request_set_measurement_visibility"), "Netzwerk-API für Messsichtbarkeit fehlt", failures)
	_expect(transport.has_method("request_set_team_mode"), "Netzwerk-API für Teammodus fehlt", failures)
	_expect(transport.has_method("request_set_player_team"), "Netzwerk-API für Teamzuweisung fehlt", failures)

	authority.free()
	replica.free()
	session.free()
	transport.free()
	return failures


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
