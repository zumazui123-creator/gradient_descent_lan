extends RefCounted

const Constants = preload("res://scripts/model/GameConstants.gd")
const GameManagerModel = preload("res://scripts/autoload/GameManager.gd")


static func run() -> Array[String]:
	var failures: Array[String] = []
	var manager = GameManagerModel.new()
	_expect(Constants.PROBE_COOLDOWN_SECONDS == 3.0, "Sondenzeit ist nicht 3 Sekunden", failures)
	_expect(Constants.MEASUREMENT_CURVE_LENGTH == 110, "Messkurvenlänge ist falsch", failures)
	_expect(Constants.MEASUREMENT_TANGENT_LENGTH == 48.0, "Tangentenlänge ist falsch", failures)

	_expect(not manager.start_round(10), "Runde startet ohne Spieler", failures)
	_expect(manager.add_player(1, "Ada") != null, "Host konnte nicht angelegt werden", failures)
	_expect(not manager.start_round(10), "Runde startet mit nur einem Spieler", failures)
	_expect(manager.add_player(17, "Ben") != null, "Zweiter Spieler konnte nicht angelegt werden", failures)
	_expect(manager.add_player(17, "Doppelt") == null, "Doppelte Peer-ID wurde akzeptiert", failures)
	_expect(manager.players[1].color != manager.players[17].color, "Spielerfarben sind nicht eindeutig", failures)

	_expect(manager.start_round(123456), "Runde startet trotz zwei Spielern nicht", failures)
	_expect(manager.phase == manager.PHASE_PLAYING, "Phase ist nach Start nicht playing", failures)
	_expect(manager.round_number == 1, "Rundennummer wurde nicht erhöht", failures)
	_expect(manager.add_player(23, "Zu spät") == null, "Beitritt während einer Runde wurde akzeptiert", failures)

	var expected_start_x := Constants.WORLD_LEFT + (
		(Constants.WORLD_RIGHT - Constants.WORLD_LEFT) / 3.0
	)
	_expect(is_equal_approx(manager.players[1].x, expected_start_x), "Startposition ist falsch", failures)

	manager.set_axis(1, 1)
	manager.tick(1.0)
	var expected_x := expected_start_x + Constants.SHIP_SPEED * 0.12
	_expect(is_equal_approx(manager.players[1].x, expected_x), "Tick begrenzt delta nicht auf 0,12 s", failures)
	manager.set_axis(1, 9)
	_expect(manager.players[1].axis == 1, "Ungültige Achse wurde akzeptiert", failures)

	var first_probe := manager.probe(1, 100.0)
	_expect(not first_probe.is_empty(), "Erste Sonde wurde abgewiesen", failures)
	_expect(first_probe.has("patch"), "Sondenergebnis enthält keinen Patch", failures)
	_expect(not first_probe.has("terrain"), "Sondenergebnis verrät das Gesamtterrain", failures)
	_expect(not first_probe.has("treasure_x"), "Sondenergebnis verrät den Schatz", failures)
	_expect(manager.players[1].probes_left == Constants.PROBES_PER_PLAYER - 1, "Sonde wurde nicht abgezogen", failures)
	var anchored_x := manager.players[1].x
	manager.tick(0.12)
	_expect(is_equal_approx(manager.players[1].x, anchored_x), "Schiff bewegt sich während der Messung", failures)
	for _step in range(24):
		manager.tick(0.12)
	manager.tick(0.1)
	_expect(manager.players[1].x > anchored_x, "Schiff bleibt nach Ablauf der Messzeit verankert", failures)

	var blocked_probe := manager.probe(1, 100.2)
	_expect(blocked_probe.is_empty(), "Sonden-Cooldown wurde nicht eingehalten", failures)
	_expect(manager.players[1].probes_left == Constants.PROBES_PER_PLAYER - 1, "Blockierte Sonde wurde abgezogen", failures)
	_expect(manager.round_result().is_empty(), "Terrain wurde vor Rundenende veröffentlicht", failures)

	var public_state := manager.snapshot()
	_expect(not public_state.has("terrain"), "Snapshot verrät das Gesamtterrain", failures)
	_expect(not public_state.has("treasure_x"), "Snapshot verrät den Schatz", failures)
	_expect(not public_state.has("seed"), "Snapshot verrät den Seed", failures)

	manager.players[1].x = manager.seabed.treasure_x
	var winning_probe := manager.probe(1, 104.0)
	_expect(winning_probe.get("found", false), "Sonde am Schatz gewinnt nicht", failures)
	_expect(manager.phase == manager.PHASE_FINISHED, "Gewinn beendet die Runde nicht", failures)
	_expect(manager.winner_id == 1, "Gewinner-ID ist falsch", failures)

	var result := manager.round_result()
	_expect(not result.is_empty(), "Rundenergebnis fehlt nach Rundenende", failures)
	_expect(result.has("terrain"), "Rundenergebnis enthält kein Terrain", failures)
	_expect(result.get("treasure_x") == manager.seabed.treasure_x, "Rundenergebnis enthält falschen Schatz", failures)

	var capacity_manager = GameManagerModel.new()
	for player_id in range(1, Constants.MAX_PLAYERS + 1):
		_expect(
			capacity_manager.add_player(player_id, "Spieler %d" % player_id) != null,
			"Einer der sechs Spielerplätze wurde abgewiesen",
			failures
		)
	_expect(
		capacity_manager.add_player(Constants.MAX_PLAYERS + 1, "Zu viel") == null,
		"Ein siebter Spieler wurde zugelassen",
		failures
	)
	var used_colors: Dictionary = {}
	for player in capacity_manager.players.values():
		used_colors[player.color] = true
	_expect(used_colors.size() == Constants.MAX_PLAYERS, "Sechs Spielerfarben sind nicht eindeutig", failures)

	var team_manager = GameManagerModel.new()
	for player_id in range(1, 7):
		team_manager.add_player(player_id, "Teamspieler %d" % player_id)
	_expect(team_manager.set_show_all_measurements(true), "Messfreigabe ließ sich nicht aktivieren", failures)
	_expect(team_manager.set_team_mode(true), "Teammodus ließ sich nicht aktivieren", failures)
	for player_id in range(1, 7):
		team_manager.set_player_team(player_id, 1)
	_expect(not team_manager.can_start_round(), "Teamrunde mit nur einem Team wurde zugelassen", failures)
	for player_id in [1, 2]:
		team_manager.set_player_team(player_id, 1)
	team_manager.set_player_team(3, 2)
	for player_id in [4, 5, 6]:
		team_manager.set_player_team(player_id, 3)
	_expect(team_manager.can_start_round(), "Teamaufteilung 2 gegen 1 gegen 3 ist ungültig", failures)

	var team_snapshot := team_manager.snapshot()
	_expect(team_snapshot.get("show_all_measurements") == true, "Messfreigabe fehlt im Snapshot", failures)
	_expect(team_snapshot.get("team_mode") == true, "Teammodus fehlt im Snapshot", failures)
	_expect(team_manager.start_round(654321), "Teamrunde startet nicht", failures)
	_expect(not team_manager.set_player_team(1, 2), "Team wurde während der Runde geändert", failures)
	team_manager.players[4].x = team_manager.seabed.treasure_x
	var team_probe := team_manager.probe(4, 200.0)
	_expect(team_probe.get("player_id") == 4, "Messung enthält keine Spieler-ID", failures)
	_expect(team_probe.get("team_id") == 3, "Messung enthält das falsche Team", failures)
	_expect(team_manager.winner_team_id == 3, "Gewinnerteam ist falsch", failures)
	_expect(team_manager.round_result().get("winner_team") == 3, "Gewinnerteam fehlt im Ergebnis", failures)

	manager.free()
	capacity_manager.free()
	team_manager.free()
	return failures


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
