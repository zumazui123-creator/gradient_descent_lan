extends RefCounted

const GameManagerModel = preload("res://scripts/autoload/GameManager.gd")
const ClientSessionModel = preload("res://scripts/autoload/ClientSession.gd")


static func run() -> Array[String]:
	var failures: Array[String] = []
	var authority = GameManagerModel.new()
	var replica = GameManagerModel.new()
	var session = ClientSessionModel.new()

	authority.add_player(1, "Ada")
	authority.add_player(27, "Ben")
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

	var malformed := public_snapshot.duplicate(true)
	malformed["phase"] = "cheating"
	_expect(not replica.apply_public_snapshot(malformed), "Ungültige Netzwerkphase wurde akzeptiert", failures)

	var private_probe := {
		"type": "probe_result",
		"x": 500.0,
		"y": 450.0,
		"slope": 0.2,
		"patch": [Vector2(495, 449), Vector2(500, 450)],
		"probes_left": 39,
		"found": false,
	}
	session.store_private_measurement(private_probe)
	_expect(session.measurements.size() == 1, "Private Messung wurde nicht gespeichert", failures)
	_expect(session.last_measurement.get("x") == 500.0, "Letzte Messung ist falsch", failures)

	var terrain := [Vector2(72, 420), Vector2(76, 421)]
	session.release_round_result(27, terrain, 76)
	_expect(session.released_winner_id == 27, "Freigegebener Gewinner ist falsch", failures)
	_expect(session.released_terrain.size() == 2, "Freigegebenes Terrain ist unvollständig", failures)
	_expect(session.released_treasure_x == 76, "Freigegebene Schatzposition ist falsch", failures)

	session.reset_round()
	_expect(session.measurements.is_empty(), "Rundenreset behält Messungen", failures)
	_expect(session.released_terrain.is_empty(), "Rundenreset behält Terrain", failures)

	authority.free()
	replica.free()
	session.free()
	return failures


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
